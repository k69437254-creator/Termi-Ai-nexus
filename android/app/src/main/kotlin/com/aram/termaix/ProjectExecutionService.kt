package com.aram.termaix

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap

class ProjectExecutionService : Service() {

    private var flutterEngine: FlutterEngine? = null
    private var serviceChannel: MethodChannel? = null
    private var activeProjectId: String? = null
    private var dartReady = false
    private var wakeLock: PowerManager.WakeLock? = null
    private val pendingProjectIds = ArrayDeque<String>()

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val projectId = intent?.getStringExtra(EXTRA_PROJECT_ID)
            ?.trim()?.takeIf { it.isNotEmpty() }

        if (projectId == null) {
            if (activeProjectId == null) stopSelf(startId)
            return START_NOT_STICKY
        }

        try {
            startForegroundCompat()
            acquireWakeLock()
        } catch (error: Throwable) {
            pendingCancellationProjectIds.remove(projectId)
            stopSelf(startId)
            return START_NOT_STICKY
        }

        when {
            activeProjectId == null -> startProject(projectId)
            activeProjectId == projectId -> Unit
            !pendingProjectIds.contains(projectId) ->
                pendingProjectIds.addLast(projectId)
        }

        return START_NOT_STICKY
    }

    private fun startProject(projectId: String) {
        activeProjectId = projectId
        dartReady = false
        updateNotification("يجري تنفيذ المشروع $projectId")

        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)

            val engine = FlutterEngine(applicationContext)
            flutterEngine = engine

            AramEngineChannel.register(engine, applicationContext, null)

            val channel = MethodChannel(
                engine.dartExecutor.binaryMessenger,
                SERVICE_CHANNEL
            )
            serviceChannel = channel

            channel.setMethodCallHandler { call, result ->
                if (call.method == "ready") {
                    val readyId = call.argument<String>("projectId")?.trim()
                    if (readyId.isNullOrEmpty() || readyId != activeProjectId) {
                        result.error(
                            "PROJECT_ID_MISMATCH",
                            "معرف المشروع لا يطابق المهمة النشطة.",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    dartReady = true
                    result.success(pendingCancellationProjectIds.remove(readyId))
                    return@setMethodCallHandler
                }

                if (call.method == "taskUpdate") {
                    val data = call.arguments as? Map<*, *>
                    val updateProjectId = data?.get("projectId") as? String
                    if (updateProjectId != activeProjectId) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    val taskTitle = data?.get("taskTitle")
                        ?.toString()?.take(80).orEmpty()
                    val taskNumber =
                        (data?.get("taskNumber") as? Number)?.toInt() ?: 0
                    val taskCount =
                        (data?.get("taskCount") as? Number)?.toInt() ?: 0
                    val status = data?.get("status")?.toString().orEmpty()
                    val taskResult = data?.get("result")
                        ?.toString()?.take(110).orEmpty()

                    val statusLabel = when (status) {
                        "pending" -> "بانتظار التنفيذ"
                        "running" -> "قيد التنفيذ"
                        "completed" -> "اكتملت"
                        "failed" -> "فشلت"
                        "rolledBack" -> "تم التراجع"
                        "interrupted" -> "توقفت"
                        else -> "تحديث المهمة"
                    }

                    val detail = buildString {
                        if (taskNumber > 0 && taskCount > 0) {
                            append("$taskNumber/$taskCount • ")
                        }
                        append(statusLabel)
                        if (taskTitle.isNotBlank()) {
                            append(" • $taskTitle")
                        }
                        if (
                            status in setOf("failed", "rolledBack", "interrupted") &&
                            taskResult.isNotBlank()
                        ) {
                            append(" • $taskResult")
                        }
                    }

                    updateNotification(detail)
                    result.success(true)
                    return@setMethodCallHandler
                }

                if (call.method != "complete") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val data = call.arguments as? Map<*, *>
                val completedId = data?.get("projectId") as? String

                if (completedId != activeProjectId) {
                    result.error(
                        "PROJECT_ID_MISMATCH",
                        "معرف المشروع لا يطابق المهمة النشطة.",
                        null
                    )
                    return@setMethodCallHandler
                }

                val success = data["success"] as? Boolean ?: false
                val error = data["error"]?.toString()
                result.success(true)
                finishProject(projectId, success, error)
            }

            val entrypoint = DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                DART_ENTRYPOINT
            )

            engine.dartExecutor.executeDartEntrypoint(
                entrypoint,
                listOf(projectId)
            )
        } catch (error: Throwable) {
            finishProject(
                projectId,
                false,
                error.message ?: error.javaClass.simpleName
            )
        }
    }

    private fun cancelProject(
        projectId: String,
        result: MethodChannel.Result
    ) {
        if (activeProjectId != projectId) {
            if (pendingProjectIds.remove(projectId)) {
                pendingCancellationProjectIds.remove(projectId)
                result.success(true)
            } else if (activeProjectId == null) {
                pendingCancellationProjectIds.add(projectId)
                result.success(true)
            } else {
                result.success(false)
            }
            return
        }

        val channel = serviceChannel
        if (!dartReady || channel == null) {
            pendingCancellationProjectIds.add(projectId)
            result.success(true)
            return
        }

        channel.invokeMethod(
            "cancel",
            mapOf("projectId" to projectId),
            object : MethodChannel.Result {
                override fun success(value: Any?) {
                    result.success(value == true)
                }

                override fun error(
                    errorCode: String,
                    errorMessage: String?,
                    errorDetails: Any?
                ) {
                    result.error(errorCode, errorMessage, errorDetails)
                }

                override fun notImplemented() {
                    result.success(false)
                }
            }
        )
    }

    private fun finishProject(
        projectId: String,
        success: Boolean,
        error: String?
    ) {
        if (activeProjectId != projectId) return

        pendingCancellationProjectIds.remove(projectId)
        dartReady = false
        updateNotification(
            if (success) "اكتمل تنفيذ المشروع $projectId"
            else "تعذر إكمال المشروع $projectId: ${error ?: "خطأ غير معروف"}"
        )

        val oldEngine = flutterEngine
        flutterEngine = null
        serviceChannel = null
        activeProjectId = null
        runCatching { oldEngine?.destroy() }

        if (pendingProjectIds.isNotEmpty()) {
            startProject(pendingProjectIds.removeFirst())
        } else {
            stopForeground(STOP_FOREGROUND_REMOVE)
            releaseWakeLock()
            stopSelf()
        }
    }

    private fun startForegroundCompat() {
        val manager = getSystemService(NotificationManager::class.java)

        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "تنفيذ المشاريع",
                NotificationManager.IMPORTANCE_LOW
            )
        )

        val notification = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("TermiAI-Nexus")
            .setContentText("تهيئة تنفيذ المشروع في الخلفية…")
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()

        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification(message: String) {
        runCatching {
            val notification = Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle("TermiAI-Nexus · تنفيذ المشاريع")
                .setContentText(message.take(180))
                .setOngoing(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                .build()

            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, notification)
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return

        wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "$packageName:ProjectExecution"
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
    }

    private fun releaseWakeLock() {
        runCatching { wakeLock?.takeIf { it.isHeld }?.release() }
        wakeLock = null
    }

    override fun onDestroy() {
        pendingProjectIds.clear()
        runCatching { flutterEngine?.destroy() }
        flutterEngine = null
        serviceChannel = null
        activeProjectId?.let { pendingCancellationProjectIds.remove(it) }
        activeProjectId = null
        dartReady = false
        releaseWakeLock()
        if (instance === this) instance = null
        super.onDestroy()
    }

    companion object {
        const val EXTRA_PROJECT_ID =
            "com.aram.termaix.extra.PROJECT_ID"

        private const val SERVICE_CHANNEL =
            "termai/project-execution-service"
        private const val DART_ENTRYPOINT =
            "projectExecutionEntrypoint"
        private const val CHANNEL_ID =
            "termi_project_execution"
        private const val NOTIFICATION_ID = 9201

        @Volatile
        private var instance: ProjectExecutionService? = null

        private val pendingCancellationProjectIds =
            ConcurrentHashMap.newKeySet<String>()

        fun isExecuting(projectId: String): Boolean =
            instance?.let { service ->
                service.activeProjectId == projectId ||
                    service.pendingProjectIds.contains(projectId)
            } == true

        fun requestCancellation(
            projectId: String,
            result: MethodChannel.Result
        ) {
            val service = instance
            if (service == null) {
                pendingCancellationProjectIds.add(projectId)
                result.success(true)
            } else {
                service.cancelProject(projectId, result)
            }
        }
    }
}
