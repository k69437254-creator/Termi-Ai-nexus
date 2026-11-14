package com.aram.termaix

import android.content.Context
import android.net.ConnectivityManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
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
    private val installing = AtomicBoolean(false)

    private data class ProcessResult(val exitCode: Int, val output: String, val timedOut: Boolean)

    fun register(engine: FlutterEngine, context: Context) {
        val app = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isInstalled" -> result.success(isInstalled(app))
                "install" -> {
                    if (!installing.compareAndSet(false, true)) {
                        result.error("LINUX_INSTALL_BUSY", "تهيئة Linux جارية بالفعل.", null)
                        return@setMethodCallHandler
                    }
                    val mainHandler = Handler(Looper.getMainLooper())
                    thread(name = "termai-linux-install", isDaemon = true) {
                        try {
                            val details = install(app)
                            mainHandler.post { result.success(details) }
                        } catch (error: Throwable) {
                            mainHandler.post {
                                result.error("LINUX_INSTALL_FAILED", error.message ?: error.javaClass.simpleName, null)
                            }
                        } finally {
                            installing.set(false)
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

    private fun install(context: Context): Map<String, Any> {
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
            downloadAndVerify(archive)

            val extraction = runProot(
                context = context,
                root = target,
                extraBinds = listOf(
                    "/system:/system",
                    "/apex:/apex",
                    "${downloadDir.absolutePath}:/mnt/host"
                ),
                workingDirectory = "/",
                command = listOf(
                    "/system/bin/toybox", "tar", "-xzpf",
                    "/mnt/host/${archive.name}", "-C", "/"
                ),
                timeoutMs = 8 * 60 * 1000L
            )
            requireSuccess("استخراج Ubuntu Base", extraction)

            prepareGuestConfig(context, target)
            val installPackages = "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends git gh ca-certificates curl openssh-client python3 build-essential && apt-get clean && rm -rf /var/lib/apt/lists/*"
            val apt = runProot(
                context = context,
                root = target,
                extraBinds = emptyList(),
                workingDirectory = "/root",
                command = listOf("/bin/bash", "-lc", installPackages),
                timeoutMs = 18 * 60 * 1000L
            )
            requireSuccess("تثبيت Git وGitHub CLI وأدوات Linux", apt)

            val verify = runProot(
                context = context,
                root = target,
                extraBinds = emptyList(),
                workingDirectory = "/root",
                command = listOf(
                    "/bin/bash", "-lc",
                    "set -e; test \"\$(id -u)\" = 0; . /etc/os-release; echo \"\$PRETTY_NAME\"; uname -m; git --version; gh --version | head -1; python3 --version"
                ),
                timeoutMs = 90_000L
            )
            requireSuccess("التحقق من Ubuntu وGit وGitHub CLI", verify)
            check(File(target, "etc/os-release").isFile && File(target, "bin/bash").exists() &&
                File(target, "usr/bin/git").exists() && File(target, "usr/bin/gh").exists()) {
                "اكتمل أمر التثبيت لكن فشل فحص ملفات النظام الأساسية."
            }
            File(target, ".termai-ubuntu-installed").writeText("Ubuntu 24.04.5 LTS ARM64\n")
            check(isInstalled(context)) { "وُضع مؤشر التثبيت لكن فشل الفحص النهائي لبيئة Ubuntu." }
            archive.delete()
            downloadDir.deleteRecursively()
            return mapOf(
                "installed" to true,
                "distribution" to "Ubuntu 24.04.5 LTS",
                "output" to (extraction.output + "\\n" + apt.output.takeLast(OUTPUT_LIMIT) + "\\n" + verify.output)
            )
        } catch (error: Throwable) {
            // Remove only an unmarked, incomplete guest created by this installation attempt.
            // A marked guest is preserved so user Linux data is never deleted on recovery.
            if (!File(target, ".termai-ubuntu-installed").isFile) target.deleteRecursively()
            throw error
        }
    }

    private fun downloadAndVerify(destination: File) {
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
                    }
                    output.fd.sync()
                }
            }
            require(total == length) { "التنزيل غير مكتمل: المتوقع $length bytes وتم تنزيل $total فقط." }
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
        timeoutMs: Long
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
