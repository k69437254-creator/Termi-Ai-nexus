package com.aram.termaix

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.aram.ai.data.ApiKeyStore
import com.aram.ai.data.AppPrefs
import com.aram.ai.engine.AramEngineService
import com.aram.ai.engine.ModelRuntime
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

object AramEngineChannel {
    private const val CHANNEL = "termai/aram-engine"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val main = Handler(Looper.getMainLooper())

    fun register(engine: FlutterEngine, activity: Activity) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val context = activity.applicationContext
            val keyStore by lazy { ApiKeyStore(context) }
            try {
                when (call.method) {
                    "start", "downloadModel" -> {
                        context.startForegroundService(Intent(context, AramEngineService::class.java).setAction(AramEngineService.ACTION_START))
                        result.success(true)
                    }
                    "stop" -> {
                        context.startService(Intent(context, AramEngineService::class.java).setAction(AramEngineService.ACTION_STOP))
                        result.success(true)
                    }
                    "status" -> {
                        val status = AppPrefs.engineStatus(context)
                        result.success(mapOf(
                            "state" to status.state,
                            "message" to status.message,
                            "updatedAt" to status.updatedAt,
                            "startedAt" to status.startedAt,
                            "loaded" to ModelRuntime.isLoaded(),
                            "queuedRequests" to ModelRuntime.pendingRequestCount(),
                            "apiBaseUrl" to "http://127.0.0.1:8766/v1"
                        ))
                    }
                    "generate" -> {
                        val user = call.argument<String>("user")?.takeIf { it.isNotBlank() }
                            ?: throw IllegalArgumentException("نص الطلب فارغ")
                        val system = call.argument<String>("system") ?: "أنت مساعد Aram AI. أجب بدقة ووضوح."
                        val maxTokens = call.argument<Int>("maxTokens") ?: 512
                        if (!ModelRuntime.isLoaded()) {
                            context.startForegroundService(Intent(context, AramEngineService::class.java).setAction(AramEngineService.ACTION_START))
                        }
                        scope.launch {
                            try {
                                var attempts = 0
                                while (!ModelRuntime.isLoaded() && attempts < 240) {
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
                        val issued = keyStore.issueClientKey(name, quota)
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
}
