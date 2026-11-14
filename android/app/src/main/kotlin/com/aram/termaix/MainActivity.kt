package com.aram.termaix

import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "termai/pty"
        private const val EVENT_CHANNEL = "termai/pty-events"
    }

    private data class Session(val handle: Long, @Volatile var active: Boolean = true)
    private val sessions = ConcurrentHashMap<Long, Session>()
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AramEngineChannel.register(flutterEngine, applicationContext, this)
        AgentCommandChannel.register(flutterEngine, applicationContext)
        LinuxRuntimeChannel.register(flutterEngine, applicationContext)
        NexusDeviceChannel.register(flutterEngine, this)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
            override fun onCancel(arguments: Any?) { eventSink = null }
        })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        if (!LinuxRuntimeChannel.isInstalled(applicationContext)) {
                            result.error("LINUX_NOT_INSTALLED", "يجب تهيئة Ubuntu من شاشة الطرفية أولاً.", null)
                            return@setMethodCallHandler
                        }
                        val directory = call.argument<String>("workingDirectory")?.takeIf { it.isNotBlank() } ?: filesDir.absolutePath
                        val rows = call.argument<Int>("rows") ?: 28
                        val columns = call.argument<Int>("columns") ?: 100
                        val githubToken = call.argument<String>("githubToken").orEmpty()
                        val workspacePath = call.argument<String>("workspacePath")
                            ?: error("Missing project workspace path.")
                        val bootstrap = LinuxRuntimeChannel.terminalBootstrap(applicationContext, workspacePath)
                        val handle = PtyNative.nativeSpawn(directory, rows, columns, githubToken)
                        if (handle == 0L) throw IllegalStateException("Native PTY allocation failed")
                        sessions[handle] = Session(handle)
                        startReader(handle)
                        thread(name = "termai-linux-bootstrap-$handle", isDaemon = true) {
                            try {
                                Thread.sleep(500)
                                if (sessions[handle]?.active == true) {
                                    val written = PtyNative.nativeWrite(handle, (bootstrap + "\n").toByteArray(StandardCharsets.UTF_8))
                                    if (written <= 0) {
                                        mainHandler.post {
                                            eventSink?.success(mapOf("id" to handle, "data" to "\r\n[Linux bootstrap failed]\r\n"))
                                        }
                                    }
                                }
                            } catch (_: Throwable) {
                                mainHandler.post {
                                    eventSink?.success(mapOf("id" to handle, "data" to "\r\n[Linux bootstrap failed]\r\n"))
                                }
                            }
                        }
                        result.success(handle)
                    }
                    "write" -> {
                        val id = call.argument<Number>("id")?.toLong() ?: error("Missing session id")
                        val data = call.argument<String>("data") ?: ""
                        val session = sessions[id] ?: error("PTY session is not active")
                        val count = PtyNative.nativeWrite(session.handle, data.toByteArray(StandardCharsets.UTF_8))
                        if (count < 0) throw IllegalStateException("PTY write failed")
                        result.success(null)
                    }
                    "resize" -> {
                        val id = call.argument<Number>("id")?.toLong() ?: error("Missing session id")
                        val session = sessions[id] ?: error("PTY session is not active")
                        PtyNative.nativeResize(session.handle, call.argument<Int>("rows") ?: 28, call.argument<Int>("columns") ?: 100)
                        result.success(null)
                    }
                    "close" -> {
                        val id = call.argument<Number>("id")?.toLong() ?: error("Missing session id")
                        val session = sessions.remove(id)
                        if (session != null) {
                            session.active = false
                            PtyNative.nativeClose(session.handle)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Throwable) {
                result.error("PTY_ERROR", error.message ?: "PTY operation failed", null)
            }
        }
    }

    private fun startReader(handle: Long) {
        val session = sessions[handle] ?: return
        thread(name = "termai-pty-$handle", isDaemon = true) {
            val buffer = ByteArray(4096)
            val decoder = StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPLACE)
                .onUnmappableCharacter(CodingErrorAction.REPLACE)
            var carry = ByteArray(0)
            try {
                while (session.active) {
                    val count = PtyNative.nativeRead(session.handle, buffer)
                    if (count <= 0) break
                    val combined = ByteArray(carry.size + count)
                    System.arraycopy(carry, 0, combined, 0, carry.size)
                    System.arraycopy(buffer, 0, combined, carry.size, count)
                    val input = ByteBuffer.wrap(combined)
                    val chars = CharBuffer.allocate(combined.size * 2 + 4)
                    decoder.decode(input, chars, false)
                    carry = ByteArray(input.remaining())
                    input.get(carry)
                    chars.flip()
                    val decoded = chars.toString()
                    if (decoded.isNotEmpty()) {
                        mainHandler.post { eventSink?.success(mapOf("id" to handle, "data" to decoded)) }
                    }
                }
            } catch (_: Throwable) {
                // A closed PTY normally ends the blocking read with EIO.
            } finally {
                sessions.remove(handle)
                try { PtyNative.nativeRelease(handle) } catch (_: Throwable) { }
                mainHandler.post { eventSink?.success(mapOf("id" to handle, "data" to "\r\n[PTY session closed]\r\n")) }
            }
        }
    }

    @Deprecated("Deprecated in Android API; retained for Flutter document-picker compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (!NexusDeviceChannel.onActivityResult(requestCode, resultCode, data)) {
            AramEngineChannel.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        sessions.values.forEach { session ->
            session.active = false
            try { PtyNative.nativeClose(session.handle) } catch (_: Throwable) { }
        }
        sessions.clear()
        super.onDestroy()
    }
}
