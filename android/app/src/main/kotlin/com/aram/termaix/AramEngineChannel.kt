package com.aram.termaix

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.aram.ai.data.ApiKeyStore
import com.aram.ai.data.ModelFiles
import com.aram.ai.data.AppPrefs
import com.aram.ai.engine.AramEngineService
import com.aram.ai.engine.ModelRuntime
import com.aram.ai.engine.ModelOperationLock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.withLock

object AramEngineChannel {
    private const val CHANNEL = "termai/aram-engine"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val main = Handler(Looper.getMainLooper())
    private const val IMPORT_REQUEST_CODE = 0x4152
    @Volatile private var pendingImportResult: MethodChannel.Result? = null
    @Volatile private var pendingImportContext: android.content.Context? = null

    fun register(engine: FlutterEngine, activity: Activity) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val context = activity.applicationContext
            val keyStore by lazy { ApiKeyStore(context) }
            try {
                when (call.method) {
                    "start" -> {
                        context.startForegroundService(Intent(context, AramEngineService::class.java).setAction(AramEngineService.ACTION_START))
                        result.success(true)
                    }
                    "downloadModel" -> {
                        context.startForegroundService(Intent(context, AramEngineService::class.java).setAction(AramEngineService.ACTION_DOWNLOAD_MODEL))
                        result.success(true)
                    }
                    "cancelDownload" -> {
                        val id = AppPrefs.downloadId(context)
                        if (id < 0L) throw IllegalStateException("لا يوجد تنزيل نشط لإلغائه")
                        val manager = context.getSystemService(android.app.DownloadManager::class.java)
                        val removed = manager.remove(id)
                        AppPrefs.setDownloadId(context, -1L)
                        AppPrefs.clearTransferProgress(context)
                        AppPrefs.setEngineState(context, "STOPPED", "أُلغي تنزيل نموذج Aram AI بناءً على طلب المستخدم")
                        result.success(removed > 0)
                    }
                    "importModel" -> {
                        if (pendingImportResult != null) throw IllegalStateException("منتقي ملف النموذج مفتوح بالفعل")
                        val current = AppPrefs.engineStatus(context)
                        if (ModelRuntime.isLoaded() || current.state in setOf("STARTING", "DOWNLOADING_MODEL", "LOADING_MODEL", "STARTING_SERVER", "STOPPING", "READY")) {
                            throw IllegalStateException("أوقف المحرك أو انتظر انتهاء التنزيل قبل استيراد نموذج آخر")
                        }
                        pendingImportResult = result
                        pendingImportContext = context
                        val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        activity.startActivityForResult(picker, IMPORT_REQUEST_CODE)
                    }
                    "stop" -> {
                        context.startService(Intent(context, AramEngineService::class.java).setAction(AramEngineService.ACTION_STOP))
                        result.success(true)
                    }
                    "status" -> {
                        val status = AppPrefs.engineStatus(context)
                        val payload = mutableMapOf<String, Any?>(
                            "state" to status.state,
                            "message" to status.message,
                            "updatedAt" to status.updatedAt,
                            "startedAt" to status.startedAt,
                            "loaded" to ModelRuntime.isLoaded(),
                            "modelAvailable" to runCatching { ModelFiles.isModelReady(context) }.getOrDefault(false),
                            "modelSizeBytes" to runCatching { ModelFiles.modelFile(context).takeIf { it.isFile }?.length() ?: 0L }.getOrDefault(0L),
                            "queuedRequests" to ModelRuntime.pendingRequestCount(),
                            "apiBaseUrl" to "http://127.0.0.1:8766/v1"
                        )
                        payload.putAll(AppPrefs.transferProgress(context))
                        payload.putAll(ModelFiles.downloadProgress(context))
                        result.success(payload)
                    }
                    "generate" -> {
                        val user = call.argument<String>("user")?.takeIf { it.isNotBlank() }
                            ?: throw IllegalArgumentException("نص الطلب فارغ")
                        val system = call.argument<String>("system") ?: "أنت مساعد Aram AI. أجب بدقة ووضوح."
                        val maxTokens = call.argument<Int>("maxTokens") ?: 512
                        if (!ModelRuntime.isLoaded()) {
                            if (!runCatching { ModelFiles.isModelReady(context) }.getOrDefault(false)) {
                                throw IllegalStateException("نموذج Spark-X2.6-1.7B غير مثبت بعد. افتح مركز محرك Aram AI ونزّل النموذج أو استورده أولاً.")
                            }
                            context.startForegroundService(Intent(context, AramEngineService::class.java).setAction(AramEngineService.ACTION_START))
                        }
                        scope.launch {
                            try {
                                var attempts = 0
                                while (!ModelRuntime.isLoaded() && attempts < 900) {
                                    val current = AppPrefs.engineStatus(context)
                                    if (current.state == "DOWNLOADING_MODEL" || current.state == "ERROR") {
                                        throw IllegalStateException(current.message)
                                    }
                                    delay(500)
                                    attempts++
                                }
                                if (!ModelRuntime.isLoaded()) {
                                    throw IllegalStateException(AppPrefs.engineStatus(context).message.ifBlank { "محرك Aram AI لم يصبح جاهزًا بعد." })
                                }
                                val answer = ModelRuntime.generate(
                                    prompt = user,
                                    systemPrompt = system,
                                    maxTokens = maxTokens,
                                    priority = 0
                                ) { }
                                main.post { result.success(answer) }
                            } catch (error: Throwable) {
                                main.post { result.error("ARAM_GENERATION_FAILED", error.message ?: error.javaClass.simpleName, null) }
                            }
                        }
                    }
                    "issueOwnerKey" -> {
                        val issued = keyStore.issueOwnerKey(call.argument<String>("name") ?: "مفتاح المالك")
                        result.success(mapOf("secret" to issued.secret, "id" to issued.record.id, "prefix" to issued.record.prefix, "role" to issued.record.role, "dailyQuota" to issued.record.dailyQuota))
                    }
                    "issueClientKey" -> {
                        val name = call.argument<String>("name") ?: "مفتاح عميل"
                        val quota = call.argument<Int>("dailyQuota") ?: 100
                        val issued = keyStore.issueClient(name, quota)
                        result.success(mapOf("secret" to issued.secret, "id" to issued.record.id, "prefix" to issued.record.prefix, "role" to issued.record.role, "dailyQuota" to issued.record.dailyQuota))
                    }
                    "listApiKeys" -> {
                        result.success(keyStore.list().map { item -> mapOf(
                            "id" to item.id, "name" to item.name, "prefix" to item.prefix,
                            "createdAt" to item.createdAt, "requests" to item.requests,
                            "revoked" to item.revoked, "role" to item.role,
                            "dailyQuota" to item.dailyQuota, "requestsToday" to item.requestsToday
                        ) })
                    }
                    "revokeApiKey" -> {
                        val id = call.argument<String>("id") ?: throw IllegalArgumentException("معرف المفتاح مفقود")
                        keyStore.revoke(id)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Throwable) {
                result.error("ARAM_ENGINE_CHANNEL_ERROR", error.message ?: error.javaClass.simpleName, null)
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != IMPORT_REQUEST_CODE) return false
        val pending = pendingImportResult
        val context = pendingImportContext
        pendingImportResult = null
        pendingImportContext = null
        if (pending == null || context == null) return true

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            main.post { pending.success(false) }
            return true
        }

        scope.launch {
            try {
                ModelOperationLock.mutex.withLock {
                    val current = AppPrefs.engineStatus(context)
                    if (ModelRuntime.isLoaded() || current.state in setOf("STARTING", "DOWNLOADING_MODEL", "LOADING_MODEL", "STARTING_SERVER", "STOPPING", "READY")) {
                        throw IllegalStateException("تغيرت حالة المحرك أثناء اختيار الملف؛ أوقف المحرك ثم أعد الاستيراد")
                    }
                    AppPrefs.setEngineState(context, "IMPORTING_MODEL", "يجري نسخ ملف GGUF والتحقق من سلامته…")
                    AppPrefs.setTransferProgress(context, "IMPORT", "COPYING", 0L, -1L)
                    ModelFiles.importModel(context, uri) { stage, bytes, total ->
                        AppPrefs.setTransferProgress(context, "IMPORT", stage, bytes, total)
                    }
                    AppPrefs.clearTransferProgress(context)
                    AppPrefs.setEngineState(context, "STOPPED", "تم استيراد ملف GGUF والتحقق من ترويسة النموذج وحجمه")
                }
                main.post { pending.success(true) }
            } catch (error: Throwable) {
                AppPrefs.clearTransferProgress(context)
                val message = error.message ?: error.javaClass.simpleName
                AppPrefs.setEngineState(context, "ERROR", "فشل استيراد نموذج Aram AI: $message")
                main.post { pending.error("MODEL_IMPORT_FAILED", message, null) }
            }
        }
        return true
    }
}
