package com.aram.termaix

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

object AgentCommandChannel {
    private const val CHANNEL = "termai/agent-command"
    private const val TOYBOX = "/system/bin/toybox"
    private const val TIMEOUT_MS = 8000L
    private const val MAX_OUTPUT = 32 * 1024
    private const val MAX_FILE = 512 * 1024

    private val main = Handler(Looper.getMainLooper())
    private val busy = AtomicBoolean(false)

    private val allowed = setOf(
        "pwd", "ls", "grep", "wc", "head",
        "tail", "stat", "uname", "id"
    )

    private val secretName = Regex(
        """(^|[._-])(secret|secrets|credential|credentials|token|password|private|apikey|api_key|auth|service-account)([._-]|$)""",
        RegexOption.IGNORE_CASE
    )

    private val secretLine = Regex(
        """(api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|passwd|secret|private[_-]?key)\s*[:=]\s*\S+|authorization\s*:\s*bearer\s+\S+|-----BEGIN [^-]*PRIVATE KEY-----""",
        RegexOption.IGNORE_CASE
    )

    fun register(engine: FlutterEngine, context: Context) {
        val app = context.applicationContext
        MethodChannel(
            engine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method != "run") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            if (!busy.compareAndSet(false, true)) {
                result.error("AGENT_COMMAND_BUSY", "هناك أمر آخر قيد التنفيذ.", null)
                return@setMethodCallHandler
            }

            try {
                val data = call.arguments as? Map<*, *>
                    ?: error("Invalid command payload.")
                val workspace = data["workspacePath"] as? String
                    ?: error("Missing workspace path.")
                val command = data["command"] as? String
                    ?: error("Missing command.")
                val rawArgs = data["args"] as? List<*> ?: emptyList<Any>()
                val args = rawArgs.map {
                    it as? String ?: error("Command arguments must be text.")
                }
                val workingDirectory =
                    data["workingDirectory"] as? String ?: "."

                thread(name = "termai-agent-command", isDaemon = true) {
                    try {
                        val output = execute(
                            app, workspace, command, args, workingDirectory
                        )
                        main.post { result.success(output) }
                    } catch (error: Throwable) {
                        main.post {
                            result.error(
                                "AGENT_COMMAND_FAILED",
                                error.message ?: error.javaClass.simpleName,
                                null
                            )
                        }
                    } finally {
                        busy.set(false)
                    }
                }
            } catch (error: Throwable) {
                busy.set(false)
                result.error(
                    "AGENT_COMMAND_REJECTED",
                    error.message ?: "Invalid command request.",
                    null
                )
            }
        }
    }

    private fun execute(
        context: Context,
        workspacePath: String,
        command: String,
        args: List<String>,
        workingDirectory: String
    ): Map<String, Any> {
        require(command in allowed) { "Command is not allowed: $command" }
        require(args.size <= 2) { "Too many command arguments." }

        val appData = File(context.applicationInfo.dataDir).canonicalFile
        val root = File(workspacePath).canonicalFile
        require(within(appData, root) && root != appData) {
            "Workspace is outside application storage."
        }
        require(
            root.parentFile?.name == "workspaces" &&
            root.parentFile?.parentFile?.name == "TermiAI-Nexus"
        ) { "Invalid project workspace location." }
        require(root.isDirectory) { "Workspace directory does not exist." }

        val cwd = resolvePath(root, root, workingDirectory, true)
        require(cwd.isDirectory) { "Working directory does not exist." }

        when (command) {
            "pwd", "uname", "id" ->
                require(args.isEmpty()) { "$command does not accept arguments." }

            "ls" -> {
                require(args.size <= 1) { "ls accepts at most one path." }
                if (args.isNotEmpty()) {
                    resolvePath(root, cwd, args[0], true)
                }
            }

            "grep" -> {
                require(args.size == 2) { "grep requires a pattern and file." }
                val pattern = args[0]
                require(
                    pattern.isNotBlank() && pattern.length <= 128 &&
                    !pattern.startsWith("-") &&
                    !pattern.contains('\n') && !pattern.contains('\r')
                ) { "Invalid grep pattern." }
                val file = resolvePath(root, cwd, args[1], false)
                require(file.isFile && file.length() <= MAX_FILE) {
                    "grep only reads regular files up to 512 KB."
                }
            }

            "wc", "head", "tail" -> {
                require(args.size == 1) { "$command requires one file path." }
                val file = resolvePath(root, cwd, args[0], false)
                require(file.isFile && file.length() <= MAX_FILE) {
                    "$command only reads regular files up to 512 KB."
                }
            }

            "stat" -> {
                require(args.size == 1) { "stat requires one path." }
                resolvePath(root, cwd, args[0], false)
            }
        }

        val builder = ProcessBuilder(
            listOf(TOYBOX, command) + args
        ).directory(cwd).redirectErrorStream(true)

        builder.environment().clear()
        builder.environment()["PATH"] = "/system/bin"
        builder.environment()["HOME"] = context.filesDir.absolutePath
        builder.environment()["TMPDIR"] = context.cacheDir.absolutePath
        builder.environment()["LANG"] = "C"

        val process = builder.start()
        process.outputStream.close()

        val output = ByteArrayOutputStream()
        val truncated = AtomicBoolean(false)

        val reader = thread(
            name = "termai-agent-command-output",
            isDaemon = true
        ) {
            try {
                process.inputStream.use { input ->
                    val buffer = ByteArray(4096)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        synchronized(output) {
                            val room = (MAX_OUTPUT - output.size()).coerceAtLeast(0)
                            val copied = minOf(count, room)
                            if (copied > 0) output.write(buffer, 0, copied)
                            if (copied < count) truncated.set(true)
                        }
                    }
                }
            } catch (_: Throwable) {
                // Process termination closes the output stream.
            }
        }

        val completed = process.waitFor(TIMEOUT_MS, TimeUnit.MILLISECONDS)
        if (!completed) {
            process.destroy()
            if (!process.waitFor(300, TimeUnit.MILLISECONDS)) {
                process.destroyForcibly()
            }
            process.waitFor()
        }

        reader.join(1500)
        if (reader.isAlive) truncated.set(true)

        val exitCode = if (completed) process.exitValue() else -1
        val raw = synchronized(output) {
            String(output.toByteArray(), StandardCharsets.UTF_8)
        }
        val safeOutput = raw.lines().joinToString("\n") { line ->
            if (secretLine.containsMatchIn(line)) "[REDACTED]" else line
        }

        return mapOf(
            "ok" to (completed && exitCode == 0),
            "command" to command,
            "exit_code" to exitCode,
            "timed_out" to !completed,
            "truncated" to truncated.get(),
            "output" to safeOutput
        )
    }

    private fun resolvePath(
        root: File,
        base: File,
        raw: String,
        allowDot: Boolean
    ): File {
        if (allowDot && raw == ".") return base
        val parts = safeSegments(raw)
        val relativeBase = root.toPath().relativize(base.toPath()).toString()
        val all = (
            if (relativeBase.isBlank()) emptyList()
            else relativeBase.split(File.separatorChar)
        ) + parts

        var cursor = root
        for (part in all) {
            cursor = File(cursor, part)
            require(!Files.isSymbolicLink(cursor.toPath())) {
                "Symbolic links are not allowed."
            }
        }

        val resolved = cursor.canonicalFile
        require(withinOrSame(root, resolved)) {
            "Path escaped the workspace."
        }
        require(resolved.exists()) { "Path does not exist: $raw" }
        return resolved
    }

    private fun safeSegments(raw: String): List<String> {
        require(raw.isNotBlank() && raw.length <= 512) { "Invalid path." }
        val normalized = raw.replace('\\', '/')
        require(
            !normalized.startsWith("/") &&
            !normalized.startsWith("~") &&
            !normalized.contains(":")
        ) { "Absolute paths are forbidden." }

        val parts = normalized.split('/')
        require(parts.all {
            it.isNotEmpty() && it != "." && it != ".." &&
            !it.startsWith("-") && !sensitive(it)
        }) { "Unsafe or sensitive path." }
        return parts
    }

    private fun sensitive(segment: String): Boolean {
        val name = segment.lowercase()
        val exact = setOf(
            ".git", ".termai", ".env", ".npmrc", ".pypirc",
            ".netrc", ".git-credentials", "google-services.json"
        )
        val extensions = setOf(
            ".pem", ".p12", ".pfx", ".jks", ".keystore",
            ".key", ".gpg", ".asc"
        )
        return name in exact ||
            name.startsWith(".env.") ||
            name.startsWith("id_rsa") ||
            name.startsWith("id_ed25519") ||
            extensions.any { name.endsWith(it) } ||
            secretName.containsMatchIn(name)
    }

    private fun within(base: File, target: File): Boolean {
        return target.path.startsWith(base.path + File.separator)
    }

    private fun withinOrSame(base: File, target: File): Boolean {
        return target == base || within(base, target)
    }
}
