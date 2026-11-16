// TERMAI_GITHUB_AUTOMATION_UPDATE_20261116_V1
package com.aram.termaix

import android.content.Context
import android.net.ConnectivityManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.net.URL
import java.nio.file.Files
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * App-private Ubuntu runtime. PRoot and its loaders are packaged in nativeLibraryDir;
 * the guest rootfs is downloaded from Canonical and never written to shared storage.
 */
object LinuxRuntimeChannel {
    private const val CHANNEL = "termai/linux"
    private const val UBUNTU_URL = "https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.5-base-arm64.tar.gz"
    private const val UBUNTU_SHA256 = "a91d5a93010193712d346d761372b7c9db6dfcf093893161c64ca107f05914f2"
    private const val MAX_ARCHIVE_BYTES = 128L * 1024L * 1024L
    private const val MIN_FREE_BYTES = 1200L * 1024L * 1024L
    private const val OUTPUT_LIMIT = 96 * 1024
    // ARAM_NEXUS_SOURCE_UPDATE_20261116: persisted progress snapshot and replay for Linux installation.
    private val installing = AtomicBoolean(false)
    @Volatile private var installEventSink: EventChannel.EventSink? = null
    @Volatile private var deploymentEventSink: EventChannel.EventSink? = null
    @Volatile private var installAppContext: Context? = null
    @Volatile private var lastPersistedAt = 0L
    @Volatile private var lastInstallEvent: Map<String, Any?> = mapOf(
        "stage" to "idle", "message" to "لم تبدأ عملية تهيئة Ubuntu بعد.", "active" to false
    )

    private fun persistInstallEvent(snapshot: Map<String, Any?>, force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - lastPersistedAt < 1000L) return
        lastPersistedAt = now
        val context = installAppContext ?: return
        val downloaded = snapshot["downloadedBytes"] as? Long ?: -1L
        val total = snapshot["totalBytes"] as? Long ?: -1L
        val percent = snapshot["percent"] as? Double ?: -1.0
        context.getSharedPreferences("termai_linux_install_state", Context.MODE_PRIVATE).edit()
            .putString("stage", snapshot["stage"]?.toString() ?: "idle")
            .putString("message", snapshot["message"]?.toString() ?: "")
            .putLong("downloadedBytes", downloaded)
            .putLong("totalBytes", total)
            .putFloat("percent", percent.toFloat())
            .putBoolean("active", snapshot["active"] == true)
            .putLong("updatedAt", now)
            .apply()
    }

    private fun emitInstallProgress(
        handler: Handler,
        stage: String,
        message: String,
        downloadedBytes: Long? = null,
        totalBytes: Long? = null
    ) {
        val percent = if (downloadedBytes != null && totalBytes != null && totalBytes > 0L) {
            downloadedBytes.toDouble() * 100.0 / totalBytes.toDouble()
        } else null
        val snapshot = mapOf<String, Any?>(
            "stage" to stage, "message" to message,
            "downloadedBytes" to downloadedBytes, "totalBytes" to totalBytes,
            "remainingBytes" to if (downloadedBytes != null && totalBytes != null)
                (totalBytes - downloadedBytes).coerceAtLeast(0L) else null,
            "percent" to percent, "active" to installing.get()
        )
        lastInstallEvent = snapshot
        persistInstallEvent(snapshot, force = stage == "complete" || stage == "error")
        handler.post { installEventSink?.success(snapshot) }
    }

    private val agentCommands = setOf(
        "pwd", "ls", "find", "grep", "rg", "cat", "sed", "awk", "wc",
        "head", "tail", "stat", "git", "gh", "python3", "python", "pip3",
        "node", "npm", "npx", "java", "javac", "gradle", "mvn", "pytest",
        "cmake", "make", "gcc", "g++", "cargo", "rustc", "dart", "flutter",
        "apt-get", "bash", "sh", "tar", "unzip", "zip", "curl"
    )

    private data class ProcessResult(val exitCode: Int, val output: String, val timedOut: Boolean)

    fun register(engine: FlutterEngine, context: Context) {
        val app = context.applicationContext

        installAppContext = app
        EventChannel(engine.dartExecutor.binaryMessenger, "termai/linux/deployment-events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    deploymentEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    deploymentEventSink = null
                }
            })
        val savedState = app.getSharedPreferences("termai_linux_install_state", Context.MODE_PRIVATE)
        val savedWasActive = savedState.getBoolean("active", false)
        if (savedState.contains("stage")) {
            val restoredStage = if (savedWasActive) "interrupted" else savedState.getString("stage", "idle") ?: "idle"
            val restoredMessage = if (savedWasActive) "انقطعت عملية التهيئة السابقة عند آخر نقطة محفوظة؛ أعد بدء التهيئة لفحص الموارد وإكمالها." else savedState.getString("message", "") ?: ""
            lastInstallEvent = mapOf(
                "stage" to restoredStage, "message" to restoredMessage,
                "downloadedBytes" to savedState.getLong("downloadedBytes", -1L).takeIf { it >= 0L },
                "totalBytes" to savedState.getLong("totalBytes", -1L).takeIf { it >= 0L },
                "percent" to savedState.getFloat("percent", -1f).takeIf { it >= 0f }?.toDouble(),
                "active" to false
            )
            if (savedWasActive) persistInstallEvent(lastInstallEvent, force = true)
        }
        EventChannel(
            engine.dartExecutor.binaryMessenger,
            "termai/linux/install-events"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                installEventSink = events
                val snapshot = lastInstallEvent + ("active" to installing.get())
                Handler(Looper.getMainLooper()).post {
                    if (installEventSink === events) events.success(snapshot)
                }
            }

            override fun onCancel(arguments: Any?) {
                installEventSink = null
            }
        })
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "publishWorkspace" -> {
                    val workspace = call.argument<String>("workspacePath")
                    val projectId = call.argument<String>("projectId")
                    val repository = call.argument<String>("repository")
                    val token = call.argument<String>("token")
                    val message = call.argument<String>("commitMessage") ?: "Build Android app"
                    if (workspace.isNullOrBlank() || projectId.isNullOrBlank() ||
                        repository.isNullOrBlank() || token.isNullOrBlank()) {
                        result.error("INVALID_GITHUB_PUBLISH", "بيانات نشر GitHub غير مكتملة.", null)
                        return@setMethodCallHandler
                    }
                    thread(name = "termai-github-publish", isDaemon = true) {
                        try {
                            val response = publishWorkspace(app, projectId, workspace, repository, token, message) { stage, status, percent ->
                                Handler(Looper.getMainLooper()).post {
                                    deploymentEventSink?.success(mapOf(
                                        "projectId" to projectId,
                                        "stage" to stage,
                                        "message" to status,
                                        "percent" to percent
                                    ))
                                }
                            }
                            Handler(Looper.getMainLooper()).post { result.success(response) }
                        } catch (error: Throwable) {
                            val safe = error.message.orEmpty().replace(token, "[TOKEN REDACTED]")
                            Handler(Looper.getMainLooper()).post {
                                result.error("GITHUB_PUBLISH_FAILED", safe, null)
                            }
                        }
                    }
                }
                "runProjectCommand" -> {
                    val workspace = call.argument<String>("workspacePath")
                    val command = call.argument<String>("command")
                    val rawArgs = call.argument<List<*>>("args") ?: emptyList<Any>()
                    val cwd = call.argument<String>("workingDirectory") ?: "."
                    val timeoutSeconds = call.argument<Int>("timeoutSeconds") ?: 120
                    if (workspace.isNullOrBlank() || command.isNullOrBlank() ||
                        rawArgs.any { it !is String }) {
                        result.error("INVALID_AGENT_COMMAND", "بيانات أمر الوكيل غير صالحة.", null)
                        return@setMethodCallHandler
                    }
                    val args = rawArgs.map { it as String }
                    val mainHandler = Handler(Looper.getMainLooper())
                    thread(name = "termai-ubuntu-agent-command", isDaemon = true) {
                        try {
                            val output = runProjectCommand(
                                app, workspace, command, args, cwd, timeoutSeconds
                            )
                            mainHandler.post { result.success(output) }
                        } catch (error: Throwable) {
                            mainHandler.post {
                                result.error(
                                    "UBUNTU_AGENT_COMMAND_FAILED",
                                    error.message ?: error.javaClass.simpleName,
                                    null
                                )
                            }
                        }
                    }
                }
                "installStatus" -> result.success(lastInstallEvent + mapOf(
                    "active" to installing.get(), "installed" to isInstalled(app)
                ))
                "isInstalled" -> result.success(isInstalled(app))
                "install" -> {
                    if (!installing.compareAndSet(false, true)) {
                        result.error("LINUX_INSTALL_BUSY", "تهيئة Linux جارية بالفعل.", null)
                        return@setMethodCallHandler
                    }
                    val mainHandler = Handler(Looper.getMainLooper())
                    emitInstallProgress(mainHandler, "prepare", "بدأت عملية تهيئة Ubuntu…")
                    thread(name = "termai-linux-install", isDaemon = true) {
                        try {
                            val details = install(app) { stage, message, downloaded, total ->
                                emitInstallProgress(mainHandler, stage, message, downloaded, total)
                            }
                            mainHandler.post { result.success(details) }
                        } catch (error: Throwable) {
                            emitInstallProgress(
                                mainHandler,
                                "error",
                                error.message ?: error.javaClass.simpleName
                            )
                            mainHandler.post {
                                result.error("LINUX_INSTALL_FAILED", error.message ?: error.javaClass.simpleName, null)
                            }
                        } finally {
                            installing.set(false)
                            val snapshot = lastInstallEvent + ("active" to false)
                            lastInstallEvent = snapshot
                            persistInstallEvent(snapshot, force = true)
                            mainHandler.post { installEventSink?.success(snapshot) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun isInstalled(context: Context): Boolean {
        val root = rootfs(context)
        return File(root, ".termai-ubuntu-installed").isFile &&
            File(root, "etc/os-release").isFile &&
            File(root, "bin/bash").exists() &&
            File(root, "usr/bin/git").exists() &&
            File(root, "usr/bin/gh").exists() &&
            File(root, "usr/bin/python3").exists() &&
            File(root, "usr/bin/gcc").exists() &&
            File(root, "usr/bin/make").exists() &&
            File(root, "usr/bin/curl").exists() &&
            File(root, "usr/bin/ssh").exists() &&
            runtimeBinariesPresent(context)
    }

    private fun rootfs(context: Context) = File(context.filesDir, "linux")

    private fun runtimeBinariesPresent(context: Context): Boolean {
        if (Build.SUPPORTED_ABIS.none { it == "arm64-v8a" }) return false
        val native = File(context.applicationInfo.nativeLibraryDir)
        return listOf(
            "libproot.so", "libproot_loader.so", "libproot_loader32.so",
            "libtalloc.so", "libandroid-shmem.so"
        ).all { File(native, it).isFile }
    }

    private fun install(
        context: Context,
        progress: (String, String, Long?, Long?) -> Unit
    ): Map<String, Any> {
        progress("prepare", "فحص متطلبات بيئة Linux…", null, null)
        require(Build.SUPPORTED_ABIS.any { it == "arm64-v8a" }) {
            "بيئة Ubuntu المضمّنة متاحة حالياً لأجهزة Android بمعمارية ARM64 فقط."
        }
        check(runtimeBinariesPresent(context)) {
            "ملفات PRoot الأصلية غير موجودة داخل APK. أعد بناء التطبيق بعد إضافة مكونات ARM64."
        }
        if (isInstalled(context)) {
            return mapOf("installed" to true, "distribution" to "Ubuntu 24.04.5 LTS", "output" to "Ubuntu is already installed.")
        }
        val target = rootfs(context)
        if (target.exists()) {
            check(!File(target, ".termai-ubuntu-installed").isFile) {
                "وجدت Ubuntu موجوداً لكن فحصه لم ينجح. حفاظاً على ملفات Linux الحالية، لن أحذف المجلد: ${target.absolutePath}"
            }
            check(target.canonicalFile.parentFile == context.filesDir.canonicalFile) {
                "مسار Linux الجزئي لا يطابق مساحة التطبيق الخاصة؛ لن ألمس هذا المسار."
            }
            check(target.deleteRecursively()) {
                "تعذر تنظيف بقايا تثبيت Ubuntu غير المكتمل داخل مساحة التطبيق."
            }
        }
        val available = StatFs(context.filesDir.absolutePath).availableBytes
        check(available >= MIN_FREE_BYTES) {
            "المساحة الحرة غير كافية. يلزم توفر 1200 MB على الأقل داخل مساحة التطبيق؛ المتاح ${available / (1024 * 1024)} MB."
        }

        val downloadDir = File(context.cacheDir, "termai-linux-downloads")
        val tmpDir = File(context.cacheDir, "termai-proot-tmp")
        check(target.mkdirs() && (downloadDir.mkdirs() || downloadDir.isDirectory) &&
            (tmpDir.mkdirs() || tmpDir.isDirectory)) {
            "تعذر إنشاء مجلدات تثبيت Linux داخل مساحة التطبيق."
        }

        try {
            val l2s = File(target, ".l2s")
            val hostMount = File(target, "mnt/host")
            val guestTmp = File(target, "tmp")
            check(l2s.mkdirs() && hostMount.mkdirs() && guestTmp.mkdirs()) {
                "تعذر إنشاء مجلدات Ubuntu المؤقتة."
            }
            val archive = File(downloadDir, "ubuntu-base-24.04.5-base-arm64.tar.gz")
            progress("download", "جارٍ تنزيل Ubuntu من خوادم Canonical…", null, null)
            downloadAndVerify(archive) { stage, downloaded, total ->
                val message = if (stage == "verify") {
                    "اكتمل التنزيل؛ جارٍ التحقق من SHA-256…"
                } else {
                    "جارٍ تنزيل Ubuntu…"
                }
                progress(stage, message, downloaded, total)
            }

            // Extract the verified rootfs with the in-app Commons Compress extractor.
            // Preserve guest absolute symlinks for PRoot to resolve inside Ubuntu.
            progress("extract", "جارٍ فك ضغط ملفات Ubuntu…", null, null)

            val extraction = runHostTar(archive, target)
            requireSuccess("استخراج Ubuntu Base مباشرة من Android", extraction)
            progress("validate", "جارٍ فحص ملفات Ubuntu الأساسية…", null, null)

            validateUbuntuBase(target)

            progress("configure", "جارٍ إعداد بيئة Ubuntu وPRoot…", null, null)

            prepareGuestConfig(context, target)
            // Prove that PRoot can execute Bash, resolve its guest ELF loader, and read
            // Ubuntu release metadata before invoking apt or installing packages.
            progress("bash_test", "جارٍ اختبار تشغيل Bash داخل Ubuntu…", null, null)

            val bashProbe = runProot(
                context = context,
                root = target,
                extraBinds = emptyList(),
                workingDirectory = "/root",
                command = listOf(
                    "/bin/bash", "-c",
                    "set -e; test -r /etc/os-release; . /etc/os-release; test -n \"\${PRETTY_NAME:-}\"; printf 'Ubuntu guest: %s\\n' \"\$PRETTY_NAME\"; /bin/bash --version"
                ),
                timeoutMs = 30_000L
            )
            requireSuccess("اختبار تشغيل Bash داخل PRoot قبل تثبيت الحزم", bashProbe)
            progress("packages_index", "جارٍ تحديث فهارس حزم Ubuntu…", null, null)
            val aptUpdate = runProot(context, target, emptyList(), "/root",
                listOf("apt-get", "update"), timeoutMs = 18 * 60 * 1000L)
            requireSuccess("تحديث فهارس حزم Ubuntu", aptUpdate)

            val packageGroups = listOf(
                Triple("packages_git", "تثبيت Git وGitHub CLI…", listOf("git", "gh")),
                Triple("packages_python", "تثبيت Python وأدواته…", listOf("python3", "python3-pip")),
                Triple("packages_build", "تثبيت GCC وG++ وMake وأدوات البناء…", listOf("build-essential")),
                Triple("packages_network", "تثبيت شهادات TLS وCurl وOpenSSH…", listOf("ca-certificates", "curl", "openssh-client"))
            )
            val packageOutputs = StringBuilder()
            for ((stage, message, packages) in packageGroups) {
                progress(stage, message, null, null)
                val packageCommand = "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${packages.joinToString(" ")}"
                val installed = runProot(context, target, emptyList(), "/root",
                    listOf("/bin/bash", "-lc", packageCommand),
                    timeoutMs = 18 * 60 * 1000L)
                requireSuccess("$message", installed)
                packageOutputs.append(installed.output).append('\n')
            }
            progress("packages_cleanup", "جارٍ تنظيف فهارس الحزم المؤقتة…", null, null)
            val aptClean = runProot(context, target, emptyList(), "/root",
                listOf("/bin/bash", "-lc", "apt-get clean && rm -rf /var/lib/apt/lists/*"),
                timeoutMs = 120_000L)
            requireSuccess("تنظيف حزم Ubuntu", aptClean)

            progress("final_verify", "جارٍ التحقق النهائي من Ubuntu والأدوات…", null, null)

            val verify = runProot(
                context = context,
                root = target,
                extraBinds = emptyList(),
                workingDirectory = "/root",
                command = listOf(
                    "/bin/bash", "-lc",
                    "set -e; test \"\$(id -u)\" = 0; . /etc/os-release; echo \"\$PRETTY_NAME\"; uname -m; git --version; gh --version | head -1; python3 --version; gcc --version | head -1; g++ --version | head -1; make --version | head -1; curl --version | head -1; ssh -V 2>&1 | head -1"
                ),
                timeoutMs = 90_000L
            )
            requireSuccess("التحقق من Ubuntu وGit وGitHub CLI", verify)
            check(File(target, "etc/os-release").isFile && File(target, "bin/bash").exists() &&
                File(target, "usr/bin/git").exists() && File(target, "usr/bin/gh").exists() &&
                File(target, "usr/bin/python3").exists() && File(target, "usr/bin/gcc").exists() &&
                File(target, "usr/bin/make").exists() && File(target, "usr/bin/curl").exists() &&
                File(target, "usr/bin/ssh").exists()) {
                "اكتمل أمر التثبيت لكن فشل فحص ملفات النظام الأساسية."
            }
            File(target, ".termai-ubuntu-installed").writeText("Ubuntu 24.04.5 LTS ARM64\n")
            check(isInstalled(context)) { "وُضع مؤشر التثبيت لكن فشل الفحص النهائي لبيئة Ubuntu." }
            progress("complete", "اكتملت تهيئة Ubuntu بنجاح.", null, null)
            archive.delete()
            downloadDir.deleteRecursively()
            return mapOf(
                "installed" to true,
                "distribution" to "Ubuntu 24.04.5 LTS",
                "output" to (extraction.output + "\\n" + packageOutputs.toString().takeLast(OUTPUT_LIMIT) + "\\n" + verify.output)
            )
        } catch (error: Throwable) {
            // Remove only an unmarked, incomplete guest created by this installation attempt.
            // A marked guest is preserved so user Linux data is never deleted on recovery.
            if (!File(target, ".termai-ubuntu-installed").isFile) target.deleteRecursively()
            throw error
        }
    }

    private fun downloadAndVerify(
        destination: File,
        onProgress: (String, Long, Long) -> Unit
    ) {
        val partial = File(destination.parentFile, destination.name + ".part")
        partial.delete()
        val connection = (URL(UBUNTU_URL).openConnection() as HttpURLConnection).apply {
            connectTimeout = 30_000
            readTimeout = 60_000
            instanceFollowRedirects = true
            useCaches = false
        }
        try {
            connection.connect()
            require(connection.responseCode == HttpURLConnection.HTTP_OK) {
                "خادم Canonical أعاد HTTP ${connection.responseCode} أثناء تنزيل Ubuntu."
            }
            require(connection.url.host == "cdimage.ubuntu.com") {
                "تم تحويل تنزيل Ubuntu إلى مضيف غير متوقع: ${connection.url.host}"
            }
            val length = connection.contentLengthLong
            require(length in 1..MAX_ARCHIVE_BYTES) { "حجم Ubuntu Base غير متوقع: $length bytes" }
            val digest = MessageDigest.getInstance("SHA-256")
            var total = 0L
            var lastReported = 0L
            connection.inputStream.use { input ->
                FileOutputStream(partial).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        require(total <= MAX_ARCHIVE_BYTES) { "تجاوز ملف Ubuntu الحد المسموح للحجم." }
                        digest.update(buffer, 0, count)
                        output.write(buffer, 0, count)
                        if (total - lastReported >= 256L * 1024L || total == length) {
                            onProgress("download", total, length)
                            lastReported = total
                        }
                    }
                    output.fd.sync()
                }
            }
            require(total == length) { "التنزيل غير مكتمل: المتوقع $length bytes وتم تنزيل $total فقط." }
            onProgress("verify", total, length)
            val actual = digest.digest().joinToString("") { "%02x".format(it) }
            require(actual == UBUNTU_SHA256) { "فشل تحقق SHA-256 لملف Ubuntu الرسمي. لن يُفك ضغطه." }
            check(partial.renameTo(destination)) { "تعذر تثبيت ملف Ubuntu الذي تم التحقق منه." }
        } catch (error: Throwable) {
            partial.delete()
            throw error
        } finally {
            connection.disconnect()
        }
    }
    /** Extracts the verified Ubuntu rootfs with the in-app Commons Compress extractor. */
    private fun runHostTar(archive: File, destination: File): ProcessResult {
        return try {
            val summary = UbuntuTarExtractor.extract(archive, destination)
            ProcessResult(0, summary, false)
        } catch (error: Exception) {
            val detail = error.message ?: error.javaClass.simpleName
            ProcessResult(1, "فشل مستخرج Ubuntu الآمن: $detail", false)
        }
    }

    /**
     * Validates the extracted Ubuntu ARM64 Bash ELF and its PT_INTERP loader.
     * A missing ELF interpreter can make PRoot report that an existing Bash file
     * is "not found", so checking only File.exists() is not sufficient.
     */
    private fun validateUbuntuBase(root: File) {
        val canonicalRoot = root.canonicalFile
        val bash = File(root, "bin/bash")
        check(bash.exists() && bash.isFile) {
            "اكتمل فك ضغط Ubuntu لكن /bin/bash غير موجود. افحص أرشيف Ubuntu Base وطريقة استخراج الروابط والملفات."
        }
        val canonicalBash = bash.canonicalFile
        check(isUnderRoot(canonicalRoot, canonicalBash)) {
            "مسار /bin/bash يشير إلى خارج جذر Ubuntu: ${canonicalBash.absolutePath}"
        }
        check(canonicalBash.canRead() && canonicalBash.canExecute()) {
            "ملف Ubuntu /bin/bash موجود لكن صلاحيات القراءة أو التنفيذ غير كافية: ${canonicalBash.absolutePath}"
        }
        check(File(root, "etc/os-release").isFile) {
            "ملف Ubuntu Base لا يحتوي على etc/os-release بعد الاستخراج."
        }

        val interpreter = readElfInterpreter(canonicalBash)
        check(interpreter.startsWith("/")) {
            "تعذر تحديد محمّل ELF الديناميكي لملف /bin/bash."
        }
        val loaderComponents = interpreter.removePrefix("/").split('/')
        check(loaderComponents.isNotEmpty() &&
            loaderComponents.none { it.isEmpty() || it == "." || it == ".." }) {
            "مسار محمّل ELF غير آمن داخل Ubuntu: $interpreter"
        }
        // PT_INTERP is an absolute path in the guest namespace. Do not call
        // File.exists(), canonicalFile, or canonicalPath for it on Android:
        // those APIs resolve "/lib/..." from the phone's host root, not Ubuntu.
        // The PRoot preflight below proves that the guest loader is actually usable.

    }

    private fun isUnderRoot(root: File, candidate: File): Boolean {
        val rootPath = root.canonicalPath
        val candidatePath = candidate.canonicalPath
        return candidatePath == rootPath || candidatePath.startsWith(rootPath + File.separator)
    }

    /** Reads the ELF64 little-endian AArch64 PT_INTERP path from a binary. */
    private fun readElfInterpreter(binary: File): String {
        RandomAccessFile(binary, "r").use { input ->
            check(input.length() >= 64L) { "ملف Bash أقصر من ترويسة ELF64: ${binary.absolutePath}" }
            val header = ByteArray(64)
            input.readFully(header)
            check(
                header[0] == 0x7f.toByte() && header[1] == 'E'.code.toByte() &&
                    header[2] == 'L'.code.toByte() && header[3] == 'F'.code.toByte()
            ) { "الملف /bin/bash ليس ملف ELF صالحاً: ${binary.absolutePath}" }
            check((header[4].toInt() and 0xff) == 2 && (header[5].toInt() and 0xff) == 1) {
                "ملف Bash ليس ELF64 little-endian؛ لا يمكن تشغيله في بيئة ARM64 المتوقعة."
            }
            val headerView = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
            val machine = headerView.getShort(18).toInt() and 0xffff
            check(machine == 183) {
                "معمارية Bash غير متوافقة: ELF e_machine=$machine، والمتوقع AArch64 (183)."
            }
            val programHeaderOffset = headerView.getLong(32)
            val programHeaderSize = headerView.getShort(54).toInt() and 0xffff
            val programHeaderCount = headerView.getShort(56).toInt() and 0xffff
            check(
                programHeaderOffset >= 64L && programHeaderSize >= 56 &&
                    programHeaderCount in 1..1024 &&
                    programHeaderOffset < input.length()
            ) { "ترويسة ELF الخاصة بـ Bash تحتوي على جدول program headers غير صالح." }

            for (index in 0 until programHeaderCount) {
                val entryOffset = programHeaderOffset + index.toLong() * programHeaderSize
                check(entryOffset >= 0L && entryOffset + programHeaderSize <= input.length()) {
                    "جدول ELF الخاص بـ Bash يتجاوز نهاية الملف."
                }
                input.seek(entryOffset)
                val entry = ByteArray(programHeaderSize)
                input.readFully(entry)
                val view = ByteBuffer.wrap(entry).order(ByteOrder.LITTLE_ENDIAN)
                if (view.getInt(0) == 3) { // PT_INTERP
                    val interpreterOffset = view.getLong(8)
                    val interpreterSize = view.getLong(32)
                    check(
                        interpreterOffset >= 0L && interpreterSize in 2L..4096L &&
                            interpreterOffset + interpreterSize <= input.length()
                    ) { "مدخل PT_INTERP في ملف Bash غير صالح." }
                    input.seek(interpreterOffset)
                    val raw = ByteArray(interpreterSize.toInt())
                    input.readFully(raw)
                    val terminator = raw.indexOf(0.toByte()).let { if (it < 0) raw.size else it }
                    return String(raw, 0, terminator, Charsets.UTF_8)
                }
            }
            error("ملف Bash لا يحتوي على PT_INTERP؛ لم يتم العثور على محمّل ELF ديناميكي.")
        }
    }

    private fun prepareGuestConfig(context: Context, root: File) {
        listOf("etc/apt/apt.conf.d", "root/projects", "tmp", "proc", "sys", "dev/pts", "mnt/host", ".l2s").forEach {
            check(File(root, it).mkdirs() || File(root, it).isDirectory) { "تعذر إنشاء Ubuntu/$it" }
        }
        File(root, "etc/apt/sources.list").writeText(
            "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble main restricted universe multiverse\n" +
            "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble-updates main restricted universe multiverse\n" +
            "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble-security main restricted universe multiverse\n"
        )
        File(root, "etc/apt/apt.conf.d/99termai-proot").writeText(
            "APT::Sandbox::User \"root\";\n" +
            "Acquire::http::Pipeline-Depth \"0\";\n" +
            "Acquire::https::Pipeline-Depth \"0\";\n" +
            "Acquire::PDiffs \"false\";\n" +
            "Acquire::Retries \"2\";\n"
        )
        val dns = try {
            val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            val network = manager?.activeNetwork
            manager?.getLinkProperties(network)?.dnsServers?.mapNotNull { it.hostAddress?.substringBefore('%') }
                ?.filter { it.isNotBlank() }.orEmpty()
        } catch (_: Throwable) { emptyList() }
        val resolvers = dns.ifEmpty { listOf("1.1.1.1", "8.8.8.8") }
        val resolv = File(root, "etc/resolv.conf")
        runCatching { if (java.nio.file.Files.isSymbolicLink(resolv.toPath())) java.nio.file.Files.delete(resolv.toPath()) }
        resolv.writeText(resolvers.joinToString("") { "nameserver $it\n" })
    }

    private fun runProot(
        context: Context,
        root: File,
        extraBinds: List<String>,
        workingDirectory: String,
        command: List<String>,
        timeoutMs: Long,
        extraEnvironment: Map<String, String> = emptyMap()
    ): ProcessResult {
        val native = File(context.applicationInfo.nativeLibraryDir)
        val proot = File(native, "libproot.so")
        check(proot.isFile) { "ملف PRoot غير موجود في nativeLibraryDir." }
        val l2s = File(root, ".l2s")
        val tmp = File(context.cacheDir, "termai-proot-tmp").apply { mkdirs() }
        val args = mutableListOf(proot.absolutePath, "-0", "-l", "-r", root.absolutePath)
        val binds = mutableListOf("${l2s.absolutePath}:${l2s.absolutePath}")
        val bindCandidates = listOf(
            "/proc", "/sys", "/dev", "/dev/pts",
            "/proc/self/fd:/dev/fd",
            "/proc/self/fd/0:/dev/stdin",
            "/proc/self/fd/1:/dev/stdout",
            "/proc/self/fd/2:/dev/stderr"
        )
        bindCandidates.forEach { bind ->
            if (File(bind.substringBefore(':')).exists()) binds.add(bind)
        }
        extraBinds.forEach { binds.add(it) }
        for (bind in binds) {
            args.add("-b")
            args.add(bind)
        }
        args.add("-w")
        args.add(workingDirectory)
        args.addAll(command)

        val builder = ProcessBuilder(args).directory(context.filesDir).redirectErrorStream(true)
        builder.environment().apply {
            put("LD_LIBRARY_PATH", native.absolutePath)
            put("PROOT_LOADER", File(native, "libproot_loader.so").absolutePath)
            put("PROOT_LOADER32", File(native, "libproot_loader32.so").absolutePath)
            put("PROOT_TMP_DIR", tmp.absolutePath)
            put("PROOT_L2S_DIR", l2s.absolutePath)
            put("TERM", "xterm-256color")
            put("HOME", "/root")
            put("USER", "root")
            put("LOGNAME", "root")
            put("LANG", "C.UTF-8")
            put("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
            put("TMPDIR", "/tmp")
            put("DEBIAN_FRONTEND", "noninteractive")
            putAll(extraEnvironment)
        }
        val process = builder.start()
        val bytes = ByteArrayOutputStream()
        val reader = thread(name = "termai-proot-output", isDaemon = true) {
            process.inputStream.use { input ->
                val buffer = ByteArray(4096)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    synchronized(bytes) {
                        val remaining = (OUTPUT_LIMIT - bytes.size()).coerceAtLeast(0)
                        if (remaining > 0) bytes.write(buffer, 0, minOf(count, remaining))
                    }
                }
            }
        }
        val finished = process.waitFor(timeoutMs, TimeUnit.MILLISECONDS)
        if (!finished) {
            process.destroy()
            if (!process.waitFor(500, TimeUnit.MILLISECONDS)) process.destroyForcibly()
            process.waitFor()
        }
        reader.join(2_000)
        val output = synchronized(bytes) { bytes.toString(Charsets.UTF_8.name()) }
        return ProcessResult(if (finished) process.exitValue() else -1, output, !finished)
    }

    /** Executes one argv-based command inside the app-private Ubuntu guest. */    private fun publishWorkspace(
        context: Context,
        projectId: String,
        workspacePath: String,
        repository: String,
        token: String,
        commitMessage: String,
        progress: (String, String, Int) -> Unit
    ): Map<String, Any> {
        check(!installing.get()) { "تثبيت Ubuntu جارٍ؛ لا يمكن بدء النشر الآن." }
        check(isInstalled(context)) { "Ubuntu/PRoot غير مثبت أو لم يجتز الفحص النهائي." }
        require(repository.matches(Regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"))) { "اسم مستودع GitHub غير صالح." }
        require(token.length in 20..512 && token.none { it.isWhitespace() || it == '\u0000' }) { "رمز GitHub غير صالح." }
        require(commitMessage.isNotBlank() && commitMessage.length <= 180 && !commitMessage.contains('\n')) { "رسالة commit غير صالحة." }

        val dataRoot = File(context.applicationInfo.dataDir).canonicalFile
        val workspace = File(workspacePath).canonicalFile
        require(workspace.isDirectory &&
            workspace.parentFile?.name == "workspaces" &&
            workspace.parentFile?.parentFile?.name == "TermiAI-Nexus" &&
            workspace.path.startsWith(dataRoot.path + File.separator)) {
            "مساحة العمل خارج مجلد مشاريع TermiAI-Nexus الخاص بالتطبيق."
        }
        val ignoredDirectories = setOf(".git", ".termai", ".dart_tool", ".gradle", "build", "node_modules", ".idea", "Pods")
        val sensitiveNames = setOf(".env", ".npmrc", ".netrc", ".git-credentials", "google-services.json", "id_rsa", "id_ed25519", "local.properties", "key.properties")
        val sensitiveExtensions = setOf(".pem", ".p12", ".pfx", ".jks", ".keystore", ".key", ".gpg")
        val secretTokens = listOf(
            Regex("-----BEGIN [A-Z ]*PRIVATE KEY-----"),
            Regex("\\bgh[pousr]_[A-Za-z0-9]{24,}\\b"),
            Regex("\\bgithub_pat_[A-Za-z0-9_]{30,}\\b"),
            Regex("\\bAKIA[0-9A-Z]{16}\\b"),
            Regex("(?im)^\\s*(storePassword|keyPassword|keyAlias|signingPassword)\\s*=")
        )
        var fileCount = 0
        var totalBytes = 0L
        val unsafeFiles = mutableListOf<String>()
        workspace.walkTopDown().onEnter { directory ->
            if (java.nio.file.Files.isSymbolicLink(directory.toPath())) {
                unsafeFiles.add(directory.relativeTo(workspace).invariantSeparatorsPath + " (symlink)")
                false
            } else {
                directory == workspace || directory.name !in ignoredDirectories
            }
        }.forEach { file ->
            val relative = file.relativeTo(workspace).invariantSeparatorsPath
            if (java.nio.file.Files.isSymbolicLink(file.toPath())) {
                unsafeFiles.add("$relative (symlink)")
                return@forEach
            }
            if (!file.isFile) return@forEach
            val parts = relative.split('/')
            val name = parts.last().lowercase(Locale.ROOT)
            val extension = name.substringAfterLast('.', "").let { if (it.isEmpty()) "" else ".$it" }
            if (parts.any { it.lowercase(Locale.ROOT) in sensitiveNames } ||
                (name.startsWith(".env.") && name !in setOf(".env.example", ".env.sample", ".env.template")) || name in sensitiveNames || extension in sensitiveExtensions) {
                unsafeFiles.add(relative)
                return@forEach
            }
            fileCount++
            totalBytes += file.length()
            check(fileCount <= 2500) { "عدد الملفات يتجاوز حد النشر الآمن (2500 ملف)." }
            check(file.length() <= 20L * 1024L * 1024L && totalBytes <= 100L * 1024L * 1024L) {
                "حجم ملفات المشروع يتجاوز حدود النشر (20 MB للملف و100 MB إجمالاً)."
            }
            if (file.length() <= 5L * 1024L * 1024L) {
                val sample = runCatching { file.readText(Charsets.UTF_8) }.getOrDefault("")
                if (secretTokens.any { it.containsMatchIn(sample) }) unsafeFiles.add("$relative (secret pattern)")
            }
        }
        check(unsafeFiles.isEmpty()) {
            "أُوقف النشر حفاظاً على الأسرار. ملفات يجب إزالتها أو نقلها خارج مساحة المصدر: ${unsafeFiles.take(8).joinToString(", ")}"
        }

        val ignoreFile = File(workspace, ".gitignore")
        val ignoreLines = listOf(
            ".termai/", ".dart_tool/", ".gradle/", "**/build/", "build/", "node_modules/", ".idea/",
            ".env", ".env.*", "!.env.example", "!.env.sample", "!.env.template",
            "*.jks", "*.keystore", "*.pem", "*.p12", "*.pfx", "*.key", "*.gpg",
            ".git-credentials", ".npmrc", ".netrc", "google-services.json",
            "local.properties", "key.properties"
        )
        val existing = if (ignoreFile.isFile) ignoreFile.readText() else ""
        val additions = ignoreLines.filterNot { existing.lineSequence().any { line -> line.trim() == it } }
        if (additions.isNotEmpty()) {
            ignoreFile.appendText((if (existing.isNotEmpty() && !existing.endsWith("\n")) "\n" else "") + additions.joinToString("\n", postfix = "\n"))
        }

        val askPassName = "termai-github-askpass-$projectId.sh"
        require(askPassName.matches(Regex("^[A-Za-z0-9_.-]+$"))) { "معرف المشروع غير صالح لمسار المساعد." }
        val askPass = File(rootfs(context), "tmp/$askPassName")
        check(askPass.parentFile?.mkdirs() == true || askPass.parentFile?.isDirectory == true) { "تعذر تجهيز قناة Git الآمنة." }
        askPass.writeText(
            "#!/bin/sh\ncase \"\$1\" in\n  *Username*) printf '%s\\n' 'x-access-token' ;;\n  *Password*) printf '%s\\n' \"\$GH_TOKEN\" ;;\n  *) exit 1 ;;\nesac\n"
        )
        check(askPass.setExecutable(true, true)) { "تعذر تفعيل Git askpass المؤقت." }
        val guestAskPass = "/tmp/$askPassName"
        val environment = mapOf(
            "GH_TOKEN" to token,
            "GIT_ASKPASS" to guestAskPass,
            "SSH_ASKPASS" to guestAskPass,
            "GIT_TERMINAL_PROMPT" to "0"
        )
        fun git(args: List<String>, stage: String, message: String): Map<String, Any> {
            progress(stage, message, when (stage) {
                "preflight" -> 5
                "git_init" -> 15
                "git_stage" -> 35
                "git_commit" -> 55
                "git_push" -> 75
                else -> 80
            })
            val result = runProjectCommand(
                context, workspace.absolutePath, "git", args, ".", 900,
                allowGitWrite = true, extraEnvironment = environment
            )
            val output = result["output"]?.toString().orEmpty().replace(token, "[TOKEN REDACTED]")
            check(result["ok"] == true) {
                "فشل git ${args.joinToString(" ")}: ${output.take(1600)}"
            }
            return result
        }
        try {
            progress("preflight", "اجتاز فحص الأسرار وحدود الحجم؛ يجهز Git داخل Ubuntu.", 5)
            if (!File(workspace, ".git").isDirectory) {
                git(listOf("init", "--initial-branch=main"), "git_init", "إنشاء مستودع Git محلي داخل مساحة عمل المشروع.")
                git(listOf("config", "user.name", "TermiAI-Nexus"), "git_init", "ضبط هوية commit للمشروع.")
                git(listOf("config", "user.email", "termai-nexus@users.noreply.github.com"), "git_init", "ضبط هوية commit للمشروع.")
            }
            val remoteCheck = runProjectCommand(context, workspace.absolutePath, "git", listOf("remote", "get-url", "origin"), ".", 30, allowGitWrite = true)
            val expectedRemote = "https://github.com/$repository.git"
            if (remoteCheck["ok"] == true) {
                val currentRemote = remoteCheck["output"]?.toString()?.trim().orEmpty()
                check(currentRemote == expectedRemote) { "مساحة العمل مرتبطة بمستودع مختلف؛ أوقف النظام النشر لمنع دفع المصدر إلى وجهة غير مقصودة." }
            } else {
                git(listOf("remote", "add", "origin", expectedRemote), "git_init", "ربط المستودع البعيد المحدد.")
            }
            git(listOf("add", "-A"), "git_stage", "تجهيز ملفات المصدر وWorkflow للنشر.")
            git(listOf("diff", "--cached", "--check"), "git_stage", "فحص تنسيق التغييرات قبل commit.")
            val staged = runProjectCommand(context, workspace.absolutePath, "git", listOf("diff", "--cached", "--name-only"), ".", 30, allowGitWrite = true)
            val stagedNames = staged["output"]?.toString()?.trim().orEmpty()
            val hasHead = runProjectCommand(context, workspace.absolutePath, "git", listOf("rev-parse", "--verify", "HEAD"), ".", 30, allowGitWrite = true)
            if (stagedNames.isNotEmpty()) {
                git(listOf("commit", "-m", commitMessage), "git_commit", "إنشاء commit لمصدر المشروع.")
            } else {
                check(hasHead["ok"] == true) { "لا توجد ملفات صالحة لإنشاء أول commit." }
            }
            git(listOf("push", "-u", "origin", "main"), "git_push", "رفع commit إلى GitHub عبر اتصال HTTPS آمن.")
            val head = runProjectCommand(context, workspace.absolutePath, "git", listOf("rev-parse", "HEAD"), ".", 30, allowGitWrite = true)
            check(head["ok"] == true) { "تم الرفع لكن تعذر قراءة commit SHA المحلي." }
            progress("uploaded", "تم رفع المصدر بنجاح؛ يجري التحقق من GitHub Actions.", 80)
            return mapOf("ok" to true, "repository" to repository, "commit" to head["output"].toString().trim(), "files" to fileCount, "bytes" to totalBytes)
        } finally {
            askPass.delete()
        }
    }


    private fun runProjectCommand(
        context: Context,
        workspacePath: String,
        command: String,
        args: List<String>,
        workingDirectory: String,
        timeoutSeconds: Int,
        allowGitWrite: Boolean = false,
        extraEnvironment: Map<String, String> = emptyMap()
    ): Map<String, Any> {
        check(!installing.get()) { "تثبيت Ubuntu جارٍ؛ انتظر انتهاء التثبيت قبل تنفيذ أمر وكيل." }
        check(isInstalled(context)) { "Ubuntu/PRoot غير مثبت أو لم يجتز الفحص. لا يوجد تنفيذ أوامر على Android host كبديل." }
        require(command in agentCommands) { "الأمر غير موجود في قائمة Ubuntu المسموحة: $command" }
        require(args.size <= 64 && args.sumOf { it.length } <= 32768 &&
            args.none { it.contains('\u0000') }) { "وسائط الأمر تتجاوز الحدود الآمنة." }
        require(timeoutSeconds in 1..900) { "مهلة الأمر يجب أن تكون بين ثانية و900 ثانية." }

        val dataRoot = File(context.applicationInfo.dataDir).canonicalFile
        val workspace = File(workspacePath).canonicalFile
        require(workspace.isDirectory &&
            workspace.parentFile?.name == "workspaces" &&
            workspace.parentFile?.parentFile?.name == "TermiAI-Nexus" &&
            workspace.path.startsWith(dataRoot.path + File.separator)) {
            "مساحة العمل خارج مجلد مشاريع TermiAI-Nexus الخاص بالتطبيق."
        }

        fun resolveWorkspacePath(raw: String, allowDot: Boolean): File {
            if (allowDot && raw == ".") return workspace
            val normalized = raw.replace('\\', '/')
            require(normalized.isNotBlank() && normalized.length <= 512 &&
                !normalized.startsWith("/") && !normalized.startsWith("~") && !normalized.contains(':')) {
                "مسار مساحة العمل غير صالح."
            }
            val parts = normalized.split('/')
            require(parts.all { it.isNotEmpty() && it != "." && it != ".." && !it.startsWith("-") && it != ".termai" && it != ".git" }) {
                "المسار يحتوي على عنصر محظور أو غير آمن."
            }
            var cursor = workspace
            for (part in parts) {
                cursor = File(cursor, part)
                require(!Files.isSymbolicLink(cursor.toPath())) { "Ubuntu agent command refuses workspace symlinks." }
            }
            val resolved = cursor.canonicalFile
            require(resolved.path == workspace.path || resolved.path.startsWith(workspace.path + File.separator)) {
                "المسار خرج من مساحة العمل."
            }
            return resolved
        }

        val cwd = resolveWorkspacePath(workingDirectory, allowDot = true)
        require(cwd.isDirectory) { "مجلد العمل غير موجود: $workingDirectory" }
        if (command == "git" && !allowGitWrite) {
            val verb = args.firstOrNull().orEmpty()
            require(verb in setOf("status", "diff", "log", "show", "rev-parse", "ls-files", "check-ignore")) {
                "يسمح الوكيل بعمليات Git للقراءة فقط؛ العمليات الكتابية أو البعيدة تتطلب موافقة صريحة."
            }
            require(args.none { arg ->
                arg == "-c" || arg.startsWith("-c") ||
                arg in setOf(
                    "--output", "--ext-diff", "--textconv", "--pager",
                    "--exec-path", "--git-dir", "--work-tree", "--config-env"
                ) ||
                arg.startsWith("--output=") ||
                arg.startsWith("--git-dir=") ||
                arg.startsWith("--work-tree=") ||
                arg.startsWith("--config-env=")
            }) { "وسيط Git قد يغير الإعدادات أو يكتب ملفات؛ تم رفضه." }
        }
        if (command == "gh") {
            val verb = args.firstOrNull().orEmpty()
            require(verb in setOf("repo", "pr", "issue", "run", "auth")) {
                "أمر GitHub الكتابي غير مسموح في التنفيذ التلقائي."
            }
            require(args.getOrNull(1) in setOf("list", "view", "status", "refresh")) {
                "يسمح وكيل المشروع بعمليات GitHub الاستعلامية فقط."
            }
        }
        if (command == "apt-get") {
            require(args.firstOrNull() in setOf("update", "install", "download", "show", "list")) {
                "يسمح داخل Ubuntu بتحديث الفهارس وتثبيت/فحص الحزم فقط."
            }
        }
        val actualArgs = args.toMutableList()
        if (command == "bash" || command == "sh") {
            require(actualArgs.isNotEmpty() && !actualArgs.first().startsWith("-")) {
                "لا يسمح بتمرير shell code عبر -c/-lc؛ شغّل ملفاً داخل مساحة العمل مباشرة."
            }
            val script = resolveWorkspacePath(actualArgs.first(), allowDot = false)
            require(script.isFile) { "ملف script غير موجود: ${actualArgs.first()}" }
            val relative = workspace.toPath().relativize(script.toPath()).toString().replace(File.separatorChar, '/')
            actualArgs[0] = "/workspace/$relative"
        }

        val guestCwd = if (cwd == workspace) "/workspace" else
            "/workspace/" + workspace.toPath().relativize(cwd.toPath()).toString().replace(File.separatorChar, '/')
        val result = runProot(
            context = context,
            root = rootfs(context),
            extraBinds = listOf("${workspace.absolutePath}:/workspace"),
            workingDirectory = guestCwd,
            command = listOf(command) + actualArgs,
            timeoutMs = timeoutSeconds.toLong() * 1000L,
            extraEnvironment = extraEnvironment
        )
        return mapOf(
            "ok" to (!result.timedOut && result.exitCode == 0),
            "command" to command,
            "args" to args,
            "exit_code" to result.exitCode,
            "timed_out" to result.timedOut,
            "truncated" to (result.output.length >= OUTPUT_LIMIT),
            "output" to result.output
        )
    }

    private fun requireSuccess(label: String, result: ProcessResult) {
        check(!result.timedOut) { "$label تجاوز مهلة التنفيذ. آخر إخراج: ${result.output.takeLast(4000)}" }
        check(result.exitCode == 0) { "$label فشل (exit ${result.exitCode}). آخر إخراج: ${result.output.takeLast(6000)}" }
    }

    /** Called by the existing PTY route; only the active process receives the GitHub token. */
    fun terminalBootstrap(context: Context, workspacePath: String): String {
        check(isInstalled(context)) { "Ubuntu غير مثبت." }
        val native = File(context.applicationInfo.nativeLibraryDir)
        val root = rootfs(context)
        val l2s = File(root, ".l2s")
        val tmp = File(context.cacheDir, "termai-proot-tmp").apply { mkdirs() }
        val appData = File(context.applicationInfo.dataDir).canonicalFile
        val workspaces = File(workspacePath).canonicalFile
        require(workspaces.name == "workspaces" &&
            workspaces.parentFile?.name == "TermiAI-Nexus" &&
            workspaces.path.startsWith(appData.path + File.separator)) {
            "مسار مساحة العمل ليس مجلداً خاصاً بالتطبيق أو لا يطابق بنية المشروع المعتمدة."
        }
        check(workspaces.mkdirs() || workspaces.isDirectory) { "تعذر إنشاء مجلد مشاريع التطبيق." }
        val binds = mutableListOf(
            "${l2s.absolutePath}:${l2s.absolutePath}",
            "${workspaces.absolutePath}:/root/projects"
        )
        val bindCandidates = listOf(
            "/proc", "/sys", "/dev", "/dev/pts",
            "/proc/self/fd:/dev/fd",
            "/proc/self/fd/0:/dev/stdin",
            "/proc/self/fd/1:/dev/stdout",
            "/proc/self/fd/2:/dev/stderr"
        )
        bindCandidates.forEach { bind ->
            if (File(bind.substringBefore(':')).exists()) binds.add(bind)
        }
        val helper = """!f() { [ "${'$'}1" = get ] || exit 0; data=${'$'}(cat); case "${'$'}data" in *host=github.com*) ;; *) exit 0 ;; esac; [ -n "${'$'}GH_TOKEN" ] || exit 0; printf 'username=x-access-token\npassword=%s\n\n' "${'$'}GH_TOKEN"; }; f"""
        val guestSetup = "git config --global credential.helper ${shellQuote(helper)}; exec /bin/bash --login -i"
        val args = mutableListOf(
            File(native, "libproot.so").absolutePath,
            "-0", "-l", "-r", root.absolutePath
        )
        binds.forEach { args.add("-b"); args.add(it) }
        args.addAll(listOf("-w", "/root/projects", "/bin/bash", "-lc", guestSetup))

        val exports = mutableListOf(
            "export LD_LIBRARY_PATH=${shellQuote(native.absolutePath)}",
            "export PROOT_LOADER=${shellQuote(File(native, "libproot_loader.so").absolutePath)}",
            "export PROOT_LOADER32=${shellQuote(File(native, "libproot_loader32.so").absolutePath)}",
            "export PROOT_TMP_DIR=${shellQuote(tmp.absolutePath)}",
            "export PROOT_L2S_DIR=${shellQuote(l2s.absolutePath)}",
            "export TERM='xterm-256color'",
            "export HOME='/root'",
            "export USER='root'",
            "export LOGNAME='root'",
            "export LANG='C.UTF-8'",
            "export PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'",
            "export TMPDIR='/tmp'",
            "export GIT_TERMINAL_PROMPT=0"
        )
        exports.add("stty echo")
        exports.add("exec ${args.joinToString(" ", transform = ::shellQuote)}")
        return exports.joinToString("; ")
    }

    private fun shellQuote(value: String): String = "'" + value.replace("'", "'\\''") + "'"
}
