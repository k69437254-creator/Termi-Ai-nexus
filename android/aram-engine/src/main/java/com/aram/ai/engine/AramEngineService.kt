package com.aram.ai.engine

import android.app.DownloadManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import com.aram.ai.data.ApiKeyStore
import com.aram.ai.data.AppPrefs
import com.aram.ai.data.ModelFiles
import fi.iki.elonen.NanoHTTPD
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.withLock

/** Runs Aram's single native model instance inside the TermiAI-Nexus app process. */
class AramEngineService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lifecycleMutex = ModelOperationLock.mutex
    @Volatile private var server: com.aram.ai.server.ApiHttpServer? = null
    @Volatile private var starting = false
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopEngine()
            return START_NOT_STICKY
        }
        try {
            startForegroundCompat()
            acquireWakeLock()
        } catch (error: Throwable) {
            AppPrefs.setEngineState(this, "ERROR", "تعذر بدء خدمة Aram AI: ${error.message ?: error.javaClass.simpleName}")
            stopSelf(startId)
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_DOWNLOAD_MODEL) {
            startModelDownload()
        } else {
            startEngine()
        }
        return START_STICKY
    }

    private fun downloadStatus(id: Long): Int? {
        if (id < 0L) return null
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val cursor = runCatching { manager.query(DownloadManager.Query().setFilterById(id)) }.getOrNull() ?: return null
        cursor.use {
            if (!it.moveToFirst()) return null
            return it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
        }
    }

    private fun startModelDownload() {
        scope.launch {
            var shouldStart = false
            var shouldStop = false
            var failure: String? = null
            lifecycleMutex.withLock {
                try {
                    if (ModelRuntime.isLoaded() && server != null) {
                        AppPrefs.setEngineState(this@AramEngineService, "READY", "محرك Aram AI يعمل بالفعل")
                    } else if (ModelFiles.isModelReady(this@AramEngineService)) {
                        AppPrefs.setEngineState(this@AramEngineService, "STOPPED", "ملف النموذج موجود وصالح؛ لا حاجة إلى تنزيل نسخة أخرى")
                        shouldStart = true
                    } else {
                        val currentId = AppPrefs.downloadId(this@AramEngineService)
                        when (downloadStatus(currentId)) {
                            DownloadManager.STATUS_PENDING,
                            DownloadManager.STATUS_RUNNING,
                            DownloadManager.STATUS_PAUSED -> {
                                AppPrefs.setEngineState(this@AramEngineService, "DOWNLOADING_MODEL", "تنزيل نموذج Spark-X2.6-1.7B جارٍ بالفعل؛ لن يبدأ تنزيل مكرر")
                                updateNotification("تنزيل نموذج Spark-X2.6-1.7B جارٍ بالفعل")
                                shouldStop = true
                            }
                            DownloadManager.STATUS_SUCCESSFUL -> {
                                if (ModelFiles.finalizeDownload(this@AramEngineService) || ModelFiles.isModelReady(this@AramEngineService)) {
                                    AppPrefs.setDownloadId(this@AramEngineService, -1L)
                                    AppPrefs.setEngineState(this@AramEngineService, "STOPPED", "اكتمل تنزيل النموذج والتحقق منه")
                                    shouldStart = true
                                } else {
                                    failure = "اكتمل تنزيل Android لكن ملف GGUF لم يجتز التحقق؛ أعد اختيار الملف أو أعد التنزيل بعد حذف التنزيل غير الصالح"
                                }
                            }
                            else -> {
                                val newId = ModelFiles.enqueueDownload(this@AramEngineService)
                                AppPrefs.setDownloadId(this@AramEngineService, newId)
                                AppPrefs.setEngineState(this@AramEngineService, "DOWNLOADING_MODEL", "بدأ تنزيل نموذج Spark-X2.6-1.7B؛ سيجري التحقق منه قبل تشغيله")
                                updateNotification("تنزيل نموذج Spark-X2.6-1.7B جارٍ عبر Download Manager")
                                shouldStop = true
                            }
                        }
                    }
                } catch (error: Throwable) {
                    failure = error.message ?: error.javaClass.simpleName
                }
                if (failure != null) {
                    AppPrefs.setEngineState(this@AramEngineService, "ERROR", "تعذر تنزيل أو تجهيز النموذج: $failure")
                    shouldStop = true
                }
            }
            if (shouldStart) {
                startEngine()
            } else if (shouldStop) {
                stopForeground(STOP_FOREGROUND_REMOVE)
                releaseWakeLock()
                stopSelf()
            }
        }
    }

    private fun startEngine() {
        scope.launch {
            lifecycleMutex.withLock {
                if (starting || server != null) return@withLock

                starting = true
                AppPrefs.setEngineState(
                    this@AramEngineService,
                    "STARTING",
                    "تهيئة محرك Aram AI الداخلي…"
                )

                try {
                    if (!ModelFiles.isModelReady(this@AramEngineService)) {
                        val currentId = AppPrefs.downloadId(this@AramEngineService)
                        val currentDownloadStatus = downloadStatus(currentId)
                        if (currentDownloadStatus == DownloadManager.STATUS_PENDING ||
                            currentDownloadStatus == DownloadManager.STATUS_RUNNING ||
                            currentDownloadStatus == DownloadManager.STATUS_PAUSED) {
                            AppPrefs.setEngineState(this@AramEngineService, "DOWNLOADING_MODEL", "تنزيل النموذج لم يكتمل بعد؛ لن يبدأ المحرك أو تنزيل نسخة مكررة")
                            updateNotification("تنزيل نموذج Spark-X2.6-1.7B جارٍ")
                            stopForeground(STOP_FOREGROUND_REMOVE)
                            releaseWakeLock()
                            stopSelf()
                            return@withLock
                        }
                        if (currentDownloadStatus == DownloadManager.STATUS_SUCCESSFUL) {
                            if (!ModelFiles.finalizeDownload(this@AramEngineService)) {
                                throw IllegalStateException("اكتمل التنزيل لكن ملف GGUF المؤقت غير صالح أو غير موجود")
                            }
                            AppPrefs.setDownloadId(this@AramEngineService, -1L)
                        } else {
                            throw IllegalStateException("ملف النموذج غير موجود في مساحة التطبيق. استخدم تنزيل النموذج أو استيراده من الهاتف أولًا")
                        }
                    }

                    AppPrefs.setEngineState(
                        this@AramEngineService,
                        "LOADING_MODEL",
                        "يجري تحميل النموذج في ذاكرة TermiAI-Nexus…"
                    )
                    updateNotification("تحميل نموذج Spark-X2.6-1.7B…")

                    ModelRuntime.load(
                        this@AramEngineService,
                        ModelFiles.modelFile(this@AramEngineService)
                    )
                    acquireWakeLock()

                    AppPrefs.setEngineState(
                        this@AramEngineService,
                        "STARTING_SERVER",
                        "تم تحميل النموذج؛ تشغيل API المحلي على المنفذ 8766…"
                    )

                    val localServer = com.aram.ai.server.ApiHttpServer(
                        "127.0.0.1",
                        ApiKeyStore(this@AramEngineService),
                        8766
                    )

                    localServer.start(NanoHTTPD.SOCKET_READ_TIMEOUT, false)
                    server = localServer

                    AppPrefs.setEngineState(
                        this@AramEngineService,
                        "READY",
                        "محرك Aram AI جاهز داخل TermiAI-Nexus · API على 127.0.0.1:8766"
                    )
                    updateNotification("Aram AI جاهز داخل TermiAI-Nexus · المنفذ 8766")

                } catch (error: Throwable) {
                    runCatching { server?.stop() }
                    server = null
                    runCatching { ModelRuntime.unload("startup_failure:${error.javaClass.simpleName}") }

                    AppPrefs.setEngineState(
                        this@AramEngineService,
                        "ERROR",
                        "فشل تشغيل محرك Aram AI: ${error.message ?: error.javaClass.simpleName}"
                    )
                    updateNotification("فشل تشغيل محرك Aram AI · افتح TermiAI-Nexus للتفاصيل")
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    releaseWakeLock()
                    stopSelf()
                } finally {
                    starting = false
                }
            }
        }
    }

    private fun stopEngine() {
        scope.launch {
            lifecycleMutex.withLock {
                AppPrefs.setEngineState(
                    this@AramEngineService,
                    "STOPPING",
                    "يجري إيقاف محرك Aram AI وتحرير موارده…"
                )

                runCatching { server?.stop() }
                server = null
                runCatching { ModelRuntime.unload("user_requested_stop") }

                AppPrefs.setEngineState(
                    this@AramEngineService,
                    "STOPPED",
                    "تم إيقاف محرك Aram AI وتحرير موارده"
                )

                releaseWakeLock()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:AramAI-engine").apply {
                setReferenceCounted(false)
                acquire()
            }
    }

    private fun releaseWakeLock() {
        runCatching { wakeLock?.takeIf { it.isHeld }?.release() }
        wakeLock = null
    }

    private fun startForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "محرك Aram AI الداخلي", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        val stopIntent = PendingIntent.getService(
            this, 8806, Intent(this, AramEngineService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle("TermiAI-Nexus · Aram AI")
                .setContentText("تهيئة المحرك المحلي…")
                .setOngoing(true)
                .addAction(android.R.drawable.ic_media_pause, "إيقاف", stopIntent)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle("TermiAI-Nexus · Aram AI")
                .setContentText("تهيئة المحرك المحلي…")
                .setOngoing(true)
                .addAction(android.R.drawable.ic_media_pause, "إيقاف", stopIntent)
                .build()
        }
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification(message: String) {
        runCatching {
            val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.stat_sys_download_done)
                    .setContentTitle("TermiAI-Nexus · Aram AI")
                    .setContentText(message)
                    .setOngoing(true)
                    .build()
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
                    .setSmallIcon(android.R.drawable.stat_sys_download_done)
                    .setContentTitle("TermiAI-Nexus · Aram AI")
                    .setContentText(message)
                    .setOngoing(true)
                    .build()
            }
            getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification)
        }
    }

    override fun onDestroy() {
        runCatching { server?.stop() }
        server = null
        releaseWakeLock()
        val state = AppPrefs.engineStatus(this)
        if (state.state == "READY" || state.state == "STARTING" || state.state == "LOADING_MODEL" || state.state == "STARTING_SERVER") {
            AppPrefs.setEngineState(this, "STOPPED", "توقفت خدمة محرك Aram AI")
        }
        scope.cancel()
        super.onDestroy()
    }

    companion object {
        const val ACTION_START = "com.aram.termaix.aram.START"
        const val ACTION_DOWNLOAD_MODEL = "com.aram.termaix.aram.DOWNLOAD_MODEL"
        const val ACTION_STOP = "com.aram.termaix.aram.STOP"
        private const val CHANNEL_ID = "termi_aram_engine"
        private const val NOTIFICATION_ID = 8806
    }
}
