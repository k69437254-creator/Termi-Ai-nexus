package com.aram.termaix

import android.app.Activity
import android.app.ActivityManager
import android.content.Intent
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.speech.RecognizerIntent
import android.util.Base64
import android.net.Uri
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

object NexusDeviceChannel {
    private const val CHANNEL = "termai/nexus-device"
    private const val REQUEST_SPEECH = 7811
    private const val REQUEST_IMAGE = 7812
    private const val MAX_IMAGE_BYTES = 8 * 1024 * 1024

    private var activity: Activity? = null
    private var pendingResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "nexus-media-reader").apply { isDaemon = true }
    }

    fun register(engine: FlutterEngine, host: Activity) {
        activity = host
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "metrics" -> runCatching { deviceMetrics(host) }
                        .onSuccess(result::success)
                        .onFailure { result.error("METRICS_FAILED", it.message, null) }

                    "recognizeSpeech" -> startSpeechRecognition(host, result)
                    "pickImage" -> startImagePicker(host, result)
                    "openHtmlPreview" -> {
                        val path = call.argument<String>("path")?.trim()
                        if (path.isNullOrEmpty()) {
                            result.error("INVALID_PREVIEW_PATH", "Missing HTML path.", null)
                        } else {
                            runCatching {
                                host.startActivity(
                                    Intent(host, ProjectPreviewActivity::class.java)
                                        .putExtra(ProjectPreviewActivity.EXTRA_PATH, path)
                                )
                            }.onSuccess { result.success(true) }
                                .onFailure { result.error("PREVIEW_FAILED", it.message, null) }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_SPEECH && requestCode != REQUEST_IMAGE) return false
        val callback = pendingResult ?: return true
        pendingResult = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            callback.success(null)
            return true
        }

        val host = activity
        if (host == null) {
            callback.error("ACTIVITY_GONE", "Android activity is no longer available.", null)
            return true
        }

        if (requestCode == REQUEST_SPEECH) {
            val matches = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
            callback.success(matches?.firstOrNull()?.trim()?.takeIf { it.isNotEmpty() })
            return true
        }

        val uri = data.data
        if (uri == null) {
            callback.success(null)
            return true
        }

        ioExecutor.execute {
            try {
                val image = readImage(host, uri)
                mainHandler.post { callback.success(image) }
            } catch (error: Throwable) {
                mainHandler.post {
                    callback.error("IMAGE_READ_FAILED", error.message, null)
                }
            }
        }
        return true
    }

    private fun startSpeechRecognition(host: Activity, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("MEDIA_BUSY", "هناك طلب وسائط آخر قيد التنفيذ.", null)
            return
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ar-IQ")
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "ar-IQ")
            putExtra(RecognizerIntent.EXTRA_PROMPT, "تحدث لوصف المهمة التي تريد تنفيذها")
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        try {
            pendingResult = result
            host.startActivityForResult(intent, REQUEST_SPEECH)
        } catch (error: Throwable) {
            pendingResult = null
                result.error("SPEECH_UNAVAILABLE", "خدمة التعرف الصوتي غير متاحة: ${error.message}", null)
        }
    }

    private fun startImagePicker(host: Activity, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("MEDIA_BUSY", "هناك طلب وسائط آخر قيد التنفيذ.", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            pendingResult = result
            host.startActivityForResult(intent, REQUEST_IMAGE)
        } catch (error: Throwable) {
            pendingResult = null
                result.error("IMAGE_PICKER_UNAVAILABLE", "تعذر فتح منتقي الصور: ${error.message}", null)
        }
    }

    private fun readImage(host: Activity, uri: Uri): Map<String, Any> {
        val mime = host.contentResolver.getType(uri)
            ?: throw IllegalArgumentException("تعذر تحديد نوع الصورة.")
        require(mime in setOf("image/jpeg", "image/png", "image/webp", "image/gif")) {
            "صيغة الصورة غير مدعومة: $mime"
        }
        val output = ByteArrayOutputStream()
        host.contentResolver.openInputStream(uri)?.use { input ->
            val buffer = ByteArray(16 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                require(output.size() + count <= MAX_IMAGE_BYTES) {
                    "حجم الصورة يتجاوز الحد المسموح (8 MB)."
                }
                output.write(buffer, 0, count)
            }
        } ?: throw IllegalStateException("تعذر قراءة ملف الصورة.")
        val bytes = output.toByteArray()
        require(bytes.isNotEmpty()) { "ملف الصورة فارغ." }
        return mapOf(
            "base64" to Base64.encodeToString(bytes, Base64.NO_WRAP),
            "mimeType" to mime,
            "sizeBytes" to bytes.size
        )
    }

    private fun deviceMetrics(host: Activity): Map<String, Any> {
        val manager = host.getSystemService(Activity.ACTIVITY_SERVICE) as ActivityManager
        val memory = ActivityManager.MemoryInfo()
        manager.getMemoryInfo(memory)
        val debug = Debug.MemoryInfo()
        Debug.getMemoryInfo(debug)
        val runtime = Runtime.getRuntime()
        val javaUsed = runtime.totalMemory() - runtime.freeMemory()
        return mapOf(
            "deviceTotalRamBytes" to memory.totalMem,
            "deviceAvailableRamBytes" to memory.availMem,
            "deviceLowMemory" to memory.lowMemory,
            "appPssKb" to debug.totalPss,
            "appJavaHeapUsedBytes" to javaUsed,
            "appJavaHeapMaxBytes" to runtime.maxMemory(),
            "sampledAtEpochMs" to System.currentTimeMillis()
        )
    }
}
