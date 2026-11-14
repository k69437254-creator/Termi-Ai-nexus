package com.aram.ai.engine

import android.content.Context
import android.os.Process
import android.util.Log
import com.arm.aichat.AiChat
import com.arm.aichat.InferenceEngine
import com.arm.aichat.gguf.GgufMetadataReader
import com.aram.ai.data.ModelFiles
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.io.File
import java.io.IOException
import java.util.PriorityQueue
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.ConcurrentHashMap
import java.util.UUID

class GenerationQueueFullException(message: String = "طابور التوليد ممتلئ؛ أعد المحاولة بعد اكتمال الطلبات الحالية.") : IllegalStateException(message)

/** Process-wide owner for the single native model instance and its prioritized serial queue. */
object ModelRuntime {
    private val initLock = Mutex()
    private val generationLock = Mutex()
    @Volatile private var engine: InferenceEngine? = null
    @Volatile private var loaded: Boolean = false
    @Volatile private var acceptingRequests: Boolean = false
    // SYSTEM_PROMPT_REUSE_FIX_V1: upstream accepts setSystemPrompt only once after load.
    @Volatile private var systemPromptConfigured: Boolean = false

    private class QueuedGeneration(
        val requestId: String,
        val priority: Int,
        val sequence: Long,
        val prompt: String,
        val systemPrompt: String,
        val maxTokens: Int,
        val onToken: (String) -> Unit
    ) {
        val result = CompletableDeferred<String>()
        @Volatile var activeJob: Job? = null
        @Volatile var cancelRequested: Boolean = false
        @Volatile var nativeStarted: Boolean = false
    }

    private val sequence = AtomicLong(0L)
    private val executionLeases = AtomicInteger(0)
    private val requestsById = ConcurrentHashMap<String, QueuedGeneration>()
    private val cancelledBeforeStart = ConcurrentHashMap<String, Long>()

    private companion object {
        const val CANCEL_TOMBSTONE_TTL_MS = 5 * 60 * 1000L
        const val MAX_CANCEL_TOMBSTONES = 256
    }

    private fun rememberEarlyCancellation(requestId: String) {
        val now = System.currentTimeMillis()
        cancelledBeforeStart[requestId] = now

        cancelledBeforeStart.entries.removeIf {
            now - it.value > CANCEL_TOMBSTONE_TTL_MS
        }

        while (cancelledBeforeStart.size > MAX_CANCEL_TOMBSTONES) {
            val oldest = cancelledBeforeStart.entries.minByOrNull { it.value } ?: break
            cancelledBeforeStart.remove(oldest.key, oldest.value)
        }
    }

    private fun consumeEarlyCancellation(requestId: String): Boolean {
        val timestamp = cancelledBeforeStart.remove(requestId) ?: return false
        return System.currentTimeMillis() - timestamp <= CANCEL_TOMBSTONE_TTL_MS
    }

    /**
     * Prevents model unloading while a project execution owns the runtime.
     * The lease is acquired only while the model is loaded and accepting requests.
     */
    suspend fun acquireExecutionLease(): AutoCloseable = initLock.withLock {
        check(loaded && acceptingRequests) {
            "لا يمكن بدء تنفيذ المشروع قبل جاهزية نموذج Spark"
        }
        executionLeases.incrementAndGet()
        val released = AtomicBoolean(false)
        AutoCloseable {
            if (released.compareAndSet(false, true)) {
                executionLeases.decrementAndGet()
            }
        }
    }

    fun activeExecutionLeaseCount(): Int = executionLeases.get()

    private val queueMonitor = Any()
    private val pending = PriorityQueue<QueuedGeneration>(
        compareBy<QueuedGeneration> { it.priority }.thenBy { it.sequence }
    )
    private val schedulerScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val schedulerWake = Channel<Unit>(Channel.CONFLATED)

    init {
        schedulerScope.launch {
            for (ignored in schedulerWake) drainQueue()
        }
    }

    suspend fun load(context: Context, modelFile: File) = initLock.withLock {
        require(modelFile.isFile && modelFile.length() >= ModelFiles.MIN_MODEL_BYTES) {
            "ملف النموذج غير موجود أو تنزيله غير مكتمل"
        }
        if (loaded) {
            Log.i(TAG, "MODEL_LOAD_SKIPPED pid=${Process.myPid()} reason=already_loaded")
            return@withLock
        }
        Log.i(TAG, "MODEL_LOAD_BEGIN pid=${Process.myPid()} enginePresent=${engine != null}")
        // GGUF_ARCHITECTURE_PREFLIGHT_V1: validate model metadata before entering JNI.
        val metadata = withContext(Dispatchers.IO) {
            modelFile.inputStream().buffered().use { input ->
                GgufMetadataReader.create().readStructuredMetadata(input)
            }
        }
        val architecture = metadata.architecture?.architecture
            ?: throw IOException("ملف GGUF لا يحتوي على بيانات المعمارية general.architecture")
        if (architecture != "spark2_5") {
            throw IOException("معمارية ملف GGUF هي '$architecture'، بينما يتطلب محركنا spark2_5 الخاص بنموذج Spark-X2.6-1.7B")
        }
        if (metadata.tensorCount <= 0L) {
            throw IOException("ملف GGUF لا يحتوي على أي أوزان (tensorCount=${metadata.tensorCount})")
        }
        Log.i(TAG, "GGUF_PREFLIGHT_OK architecture=$architecture version=${metadata.version.code} tensors=${metadata.tensorCount} metadataKeys=${metadata.kvCount} layers=${metadata.dimensions?.blockCount ?: -1} bytes=${modelFile.length()}")
        val instance = engine ?: withContext(Dispatchers.Default) {
            AiChat.getInferenceEngine(context.applicationContext)
        }.also { engine = it }
        try {
            val initializedState = withTimeout(30_000L) {
                instance.state.first { state ->
                    state is InferenceEngine.State.Initialized || state is InferenceEngine.State.Error
                }
            }
            if (initializedState is InferenceEngine.State.Error) throw initializedState.exception
            withContext(Dispatchers.IO) { instance.loadModel(modelFile.absolutePath) }
            systemPromptConfigured = false
            loaded = true
            acceptingRequests = true
            Log.i(TAG, "MODEL_LOAD_SUCCESS pid=${Process.myPid()} engine=${System.identityHashCode(instance)}")
        } catch (failure: Throwable) {
            acceptingRequests = false
            loaded = false
            systemPromptConfigured = false
            Log.e(TAG, "MODEL_LOAD_FAILED pid=${Process.myPid()}", failure)
            throw failure
        }
    }

    /** Lower priority number runs first. Owner and on-device chat use 0; customer API uses 10. */
    suspend fun generate(
        prompt: String,
        systemPrompt: String = "أنت مساعد Aram AI. أجب بدقة ووضوح.",
        maxTokens: Int = 256,
        priority: Int = 10,
        requestId: String = UUID.randomUUID().toString(),
        onToken: (String) -> Unit
    ): String {
        check(loaded && acceptingRequests) { "النموذج غير جاهز لاستقبال الطلبات" }
        val request = QueuedGeneration(
            requestId = requestId,
            priority = priority.coerceIn(0, 1000),
            sequence = sequence.getAndIncrement(),
            prompt = prompt,
            systemPrompt = systemPrompt,
            maxTokens = maxTokens.coerceIn(32, MAX_SAFE_OUTPUT_TOKENS),
            onToken = onToken
        )
        val cancelledBeforeQueue = synchronized(queueMonitor) {
            check(loaded && acceptingRequests) { "المحرك يتوقف ولا يقبل طلبات جديدة" }

            if (consumeEarlyCancellation(request.requestId)) {
                request.cancelRequested = true
                request.result.cancel(
                    CancellationException("تم إلغاء الطلب قبل تسجيله في طابور التوليد")
                )
                true
            } else {
                check(!requestsById.containsKey(request.requestId)) {
                    "معرف طلب التوليد مستخدم بالفعل: ${request.requestId}"
                }
                if (pending.size >= MAX_PENDING_REQUESTS) {
                    // Priority 0 (device owner/local chat) may displace the lowest-priority
                    // waiting customer request. A request already running is never preempted.
                    val lowestPriority = pending.maxByOrNull { it.priority }
                    if (request.priority == OWNER_PRIORITY && lowestPriority != null && lowestPriority.priority > OWNER_PRIORITY) {
                        pending.remove(lowestPriority)
                        requestsById.remove(lowestPriority.requestId, lowestPriority)
                        lowestPriority.result.completeExceptionally(
                            GenerationQueueFullException("تمت إزاحة هذا الطلب من الطابور لإعطاء أولوية لطلب المالك.")
                        )
                    } else {
                        throw GenerationQueueFullException()
                    }
                }
                requestsById[request.requestId] = request
                pending.add(request)
                false
            }
        }

        if (cancelledBeforeQueue) {
            return request.result.await()
        }

        schedulerWake.trySend(Unit)
        return try {
            request.result.await()
        } catch (cancelled: CancellationException) {
            synchronized(request) {
                request.cancelRequested = true
                if (request.nativeStarted) engine?.cancelGeneration()
            }
            request.result.cancel(cancelled)
            throw cancelled
        } finally {
            requestsById.remove(request.requestId, request)
        }
    }

    /** Cancels only the queued or active generation with this exact ID. */
    fun cancelRequest(requestId: String): Boolean {
        val request = synchronized(queueMonitor) {
            val active = requestsById[requestId]
            if (active == null) {
                rememberEarlyCancellation(requestId)
                null
            } else {
                active
            }
        } ?: return true

        synchronized(request) {
            if (request.result.isCompleted) return false
            request.cancelRequested = true
            request.result.cancel(
                CancellationException("تم إلغاء طلب التوليد المحدد")
            )
        }
        return true
    }

    private suspend fun drainQueue() {
        while (true) {
            val request = synchronized(queueMonitor) {
                while (pending.peek()?.result?.isCancelled == true) pending.poll()
                pending.poll()
            } ?: return
            if (request.result.isCancelled) continue

            val task = schedulerScope.async {
                try {
                    request.result.complete(runGeneration(request))
                } catch (cancelled: CancellationException) {
                    if (!request.result.isCancelled) request.result.completeExceptionally(cancelled)
                } catch (failure: Throwable) {
                    request.result.completeExceptionally(failure)
                }
            }
            request.activeJob = task
            if (request.cancelRequested || request.result.isCancelled) {
                synchronized(request) {
                    request.cancelRequested = true
                    if (request.nativeStarted) engine?.cancelGeneration()
                }
                task.cancel()
            }
            request.result.invokeOnCompletion {
                if (request.result.isCancelled) {
                    synchronized(request) {
                        request.cancelRequested = true
                        if (request.nativeStarted && request.activeJob === task) engine?.cancelGeneration()
                    }
                    task.cancel()
                }
            }
            task.join()
            request.activeJob = null
        }
    }

    private suspend fun runGeneration(request: QueuedGeneration): String = generationLock.withLock {
        val instance = engine ?: error("لم يتم تحميل النموذج بعد")
        check(loaded) { "النموذج غير جاهز" }
        val output = StringBuilder()
        if (!systemPromptConfigured) {
            instance.setSystemPrompt(DEFAULT_NATIVE_SYSTEM_PROMPT)
            systemPromptConfigured = true
            Log.i(TAG, "NATIVE_SYSTEM_PROMPT_SET pid=${Process.myPid()}")
        }
        val effectivePrompt = buildString {
            append("تعليمات هذه الرسالة:\n")
            append(request.systemPrompt.ifBlank { DEFAULT_NATIVE_SYSTEM_PROMPT })
            append("\n\nرسالة المستخدم:\n")
            append(request.prompt)
        }
        synchronized(request) {
            if (request.cancelRequested || request.result.isCancelled) {
                throw CancellationException("تم إلغاء الطلب قبل بدء التوليد")
            }
            instance.beginGeneration()
            request.nativeStarted = true
        }
        withContext(Dispatchers.Default) {
            instance.sendUserPrompt(effectivePrompt, request.maxTokens).collect { token ->
                output.append(token)
                request.onToken(token)
            }
        }
        output.toString()
    }

    fun pendingRequestCount(): Int = synchronized(queueMonitor) { pending.count { !it.result.isCancelled } }

    private const val DEFAULT_NATIVE_SYSTEM_PROMPT = "أنت مساعد Aram AI. أجب بدقة ووضوح."
    private const val MAX_PENDING_REQUESTS = 12
    private const val OWNER_PRIORITY = 0
    private const val MAX_SAFE_OUTPUT_TOKENS = 512

    suspend fun benchmark(): String = generationLock.withLock {
        val instance = engine ?: error("لم يتم إنشاء محرك الاستدلال بعد")
        check(loaded) { "النموذج غير جاهز لإجراء اختبار الأداء" }
        withContext(Dispatchers.IO) { instance.bench(pp = 256, tg = 64, pl = 1, nr = 1) }
    }

    suspend fun unload(reason: String = "unspecified") {
        Log.w(TAG, "MODEL_UNLOAD_REQUEST pid=${Process.myPid()} reason=$reason loaded=$loaded")

        val mayUnload = initLock.withLock {
            if (executionLeases.get() > 0) {
                Log.w(TAG, "MODEL_UNLOAD_DEFERRED reason=$reason activeProjectLeases=${executionLeases.get()}")
                false
            } else {
                acceptingRequests = false
                true
            }
        }
        if (!mayUnload) return

        synchronized(queueMonitor) {
            while (pending.isNotEmpty()) {
                pending.poll().result.completeExceptionally(
                    IllegalStateException("تم إيقاف المحرك قبل تنفيذ الطلب.")
                )
            }
        }

        // Let the active native call finish cleanly before releasing the singleton.
        generationLock.withLock {
            initLock.withLock {
                // Recheck under the lifecycle lock before destroying native resources.
                if (executionLeases.get() > 0) {
                    acceptingRequests = true
                    Log.w(TAG, "MODEL_UNLOAD_ABORTED activeProjectLeases=${executionLeases.get()}")
                    return@withLock
                }
                val current = engine
                engine = null
                loaded = false
                acceptingRequests = false
                systemPromptConfigured = false
                if (current != null) withContext(Dispatchers.IO) { current.cleanUp() }
                Log.i(TAG, "MODEL_UNLOAD_COMPLETE pid=${Process.myPid()} reason=$reason")
            }
        }
    }

    private const val TAG = "AramModelRuntime"

    fun isLoaded(): Boolean = loaded && acceptingRequests
}
