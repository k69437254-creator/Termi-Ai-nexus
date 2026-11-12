
#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

ROOT="$HOME/TermiAI-Nexus-aram-integration"

cd "$ROOT" || {
    echo "ERROR: Project directory not found: $ROOT"
    exit 1
}

echo "=================================================="
echo " TermiAI-Nexus | Aram AI Integration"
echo "=================================================="

python3 - <<'PY'
from pathlib import Path
import subprocess
import shutil
import os
import sys
import time

ROOT = Path.cwd()
EXPECTED_BRANCH = "integration/aram-ai-engine"

def fail(message):
    print("\nERROR:", message)
    sys.exit(1)

def read(rel):
    path = ROOT / rel
    if not path.is_file():
        fail(f"الملف غير موجود: {rel}")
    return path.read_text(encoding="utf-8")

def replace_once(source, old, new, label):
    count = source.count(old)
    if count != 1:
        fail(
            f"تعذر تحديد موضع التعديل بأمان: {label}. "
            f"عدد التطابقات: {count}"
        )
    return source.replace(old, new, 1)

def git(*args):
    return subprocess.run(
        ["git", *args],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )

# --------------------------------------------------
# 1. Git safety checks
# --------------------------------------------------

branch = git("branch", "--show-current")

if branch.returncode != 0:
    fail("تعذرت قراءة فرع Git.")

if branch.stdout.strip() != EXPECTED_BRANCH:
    fail(
        f"الفرع الحالي: {branch.stdout.strip()}\n"
        f"الفرع المطلوب: {EXPECTED_BRANCH}"
    )

status = git("status", "--porcelain")

if status.returncode != 0:
    fail("تعذرت قراءة حالة Git.")

allowed_status = {
    "lib/core/aram_engine_bridge.dart": {"??"},
    "lib/screens/engine_center_screen.dart": {"??"},
    "myao/apply_aram_integration.sh": {"AM"},
    "myao/apply_aram_integration.sh.before-mainactivity-fix": {"??"},
}

unexpected = []
for line in status.stdout.splitlines():
    if len(line) < 4:
        unexpected.append(line)
        continue

    state = line[:2]
    rel = line[3:]

    if state not in allowed_status.get(rel, set()):
        unexpected.append(line)

if unexpected:
    fail(
        "توجد تغييرات محلية أخرى غير متوقعة. "
        "لم يتم تعديل أي ملف:\n" + "\n".join(unexpected)
    )

bridge = ROOT / "lib/core/aram_engine_bridge.dart"

if not bridge.is_file():
    fail("ملف aram_engine_bridge.dart غير موجود.")

screen = ROOT / "lib/screens/engine_center_screen.dart"

if not screen.is_file() or screen.stat().st_size < 100:
    fail(
        "ملف engine_center_screen.dart غير موجود "
        "أو يبدو فارغًا. ضع كود الشاشة السابق فيه أولًا."
    )

print("OK: Git branch and local changes verified.")
print("OK: aram_engine_bridge.dart will remain untouched.")

# --------------------------------------------------
# 2. Read all source files before editing
# --------------------------------------------------

paths = {
    "app_shell": "lib/app_shell.dart",
    "main_activity":
        "android/app/src/main/kotlin/com/aram/termaix/MainActivity.kt",
    "channel":
        "android/app/src/main/kotlin/com/aram/termaix/AramEngineChannel.kt",
    "service":
        "android/aram-engine/src/main/java/com/aram/ai/engine/AramEngineService.kt",
    "prefs":
        "android/aram-engine/src/main/java/com/aram/ai/data/AppPrefs.kt",
    "model_files":
        "android/aram-engine/src/main/java/com/aram/ai/data/ModelFiles.kt",
    "runtime":
        "android/aram-engine/src/main/java/com/aram/ai/engine/ModelRuntime.kt",
}

data = {
    key: read(path)
    for key, path in paths.items()
}

# --------------------------------------------------
# 3. AppShell navigation
# --------------------------------------------------

s = data["app_shell"]

s = replace_once(
    s,
    "import 'screens/agents_screen.dart';",
    "import 'screens/agents_screen.dart';\n"
    "import 'screens/engine_center_screen.dart';",
    "AppShell screen import"
)

s = replace_once(
    s,
    "    7 => const SettingsScreen(),",
    "    7 => const SettingsScreen(),\n"
    "    8 => EngineCenterScreen(),",
    "AppShell page index"
)

s = replace_once(
    s,
    "'فريق الوكلاء', 'الإعدادات'][_selected]",
    "'فريق الوكلاء', 'الإعدادات', "
    "'مركز محرك Aram AI'][_selected]",
    "AppShell title"
)

s = replace_once(
    s,
    "        NavigationDrawerDestination(icon: Icon(Icons.settings_outlined), "
    "selectedIcon: Icon(Icons.settings), label: Text('الإعدادات')),\n",
    "        NavigationDrawerDestination(icon: Icon(Icons.settings_outlined), "
    "selectedIcon: Icon(Icons.settings), label: Text('الإعدادات')),\n"
    "        NavigationDrawerDestination(icon: Icon(Icons.memory_outlined), "
    "selectedIcon: Icon(Icons.memory), "
    "label: Text('مركز محرك Aram AI')),\n",
    "AppShell drawer destination"
)

data["app_shell"] = s

# --------------------------------------------------
# 4. AppPrefs busy state
# --------------------------------------------------

s = data["prefs"]

s = replace_once(
    s,
    '"STARTING", "DOWNLOADING_MODEL", "LOADING_MODEL", '
    '"STARTING_SERVER", "STOPPING"',
    '"STARTING", "DOWNLOADING_MODEL", "LOADING_MODEL", '
    '"STARTING_SERVER", "IMPORTING_MODEL", "STOPPING"',
    "AppPrefs importing state"
)

data["prefs"] = s

# --------------------------------------------------
# 5. ModelFiles GGUF validation
# --------------------------------------------------

s = data["model_files"]

s = replace_once(
    s,
    '    fun isModelReady(context: Context): Boolean {\n'
    '        val file = modelFile(context)\n'
    '        return file.isFile && file.length() >= MIN_MODEL_BYTES\n'
    '    }',
    '    fun isValidGguf(file: File): Boolean {\n'
    '        if (!file.isFile || file.length() < MIN_MODEL_BYTES) return false\n'
    '        return try {\n'
    '            file.inputStream().use { input ->\n'
    '                val magic = ByteArray(4)\n'
    '                if (input.read(magic) != 4) return false\n'
    '                magic.contentEquals(byteArrayOf(0x47, 0x47, 0x55, 0x46))\n'
    '            }\n'
    '        } catch (_: Throwable) {\n'
    '            false\n'
    '        }\n'
    '    }\n'
    '\n'
    '    fun isModelReady(context: Context): Boolean =\n'
    '        isValidGguf(modelFile(context))',
    "ModelFiles GGUF validation"
)

s = replace_once(
    s,
    '        if (!temporary.isFile || '
    'temporary.length() < MIN_MODEL_BYTES) return false',
    '        if (!isValidGguf(temporary)) return false',
    "ModelFiles download validation"
)

data["model_files"] = s

# --------------------------------------------------
# 6. ModelRuntime failed-load cleanup
# --------------------------------------------------

s = data["runtime"]

s = replace_once(
    s,
    '        require(modelFile.isFile && '
    'modelFile.length() >= ModelFiles.MIN_MODEL_BYTES) {\n'
    '            "ملف النموذج غير موجود أو تنزيله غير مكتمل"\n'
    '        }',
    '        require(ModelFiles.isValidGguf(modelFile)) {\n'
    '            "ملف النموذج غير صالح أو تنزيله غير مكتمل أو ليس GGUF صحيحًا"\n'
    '        }',
    "ModelRuntime GGUF validation"
)

s = replace_once(
    s,
    '        } catch (failure: Throwable) {\n'
    '            acceptingRequests = false\n'
    '            loaded = false\n'
    '            throw failure\n'
    '        }',
    '        } catch (failure: Throwable) {\n'
    '            acceptingRequests = false\n'
    '            loaded = false\n'
    '            try {\n'
    '                withContext(Dispatchers.IO) { instance.cleanUp() }\n'
    '                if (engine === instance) engine = null\n'
    '            } catch (cleanupFailure: Throwable) {\n'
    '                failure.addSuppressed(cleanupFailure)\n'
    '            }\n'
    '            throw failure\n'
    '        }',
    "ModelRuntime failed initialization cleanup"
)


s = replace_once(
    s,
    '        if (loaded) return@withLock\n'
    '        val instance = engine ?: withContext(Dispatchers.Default) {',
    '        if (loaded) return@withLock\n'
    '        check(engine == null) {\n'
    '            "تعذر إعادة استخدام المحرك؛ فشل تنظيفه سابقًا. أعد محاولة إيقاف المحرك أولًا."\n'
    '        }\n'
    '        val instance = engine ?: withContext(Dispatchers.Default) {',
    "ModelRuntime failed-cleanup reload guard"
)

s = replace_once(
    s,
    '        } catch (failure: Throwable) {\n'
    '            acceptingRequests = false\n'
    '            loaded = false\n'
    '            try {\n'
    '                withContext(Dispatchers.IO) { instance.cleanUp() }\n'
    '            } catch (_: Throwable) { }\n'
    '            if (engine === instance) engine = null\n'
    '            throw failure\n'
    '        }',
    '        } catch (failure: Throwable) {\n'
    '            acceptingRequests = false\n'
    '            loaded = false\n'
    '            try {\n'
    '                withContext(Dispatchers.IO) { instance.cleanUp() }\n'
    '                if (engine === instance) engine = null\n'
    '            } catch (cleanupFailure: Throwable) {\n'
    '                failure.addSuppressed(cleanupFailure)\n'
    '            }\n'
    '            throw failure\n'
    '        }',
    "ModelRuntime failed-load cleanup preservation"
)

s = replace_once(
    s,
    '                val current = engine\n'
    '                engine = null\n'
    '                loaded = false\n'
    '                if (current != null) withContext(Dispatchers.IO) { current.cleanUp() }',
    '                val current = engine\n'
    '                loaded = false\n'
    '                if (current != null) {\n'
    '                    withContext(Dispatchers.IO) { current.cleanUp() }\n'
    '                    if (engine === current) engine = null\n'
    '                }',
    "ModelRuntime unload cleanup ordering"
)

data["runtime"] = s

# --------------------------------------------------
# 7. MainActivity activity result forwarding
# --------------------------------------------------

s = data["main_activity"]

s = replace_once(
    s,
    "import android.os.Handler",
    "import android.content.Intent\nimport android.os.Handler",
    "MainActivity Intent import"
)

s = replace_once(
    s,
    "    private fun startReader(handle: Long) {",
    '    @Deprecated("Deprecated in Android API; retained for compatibility")\n'
    '    override fun onActivityResult(\n'
    '        requestCode: Int,\n'
    '        resultCode: Int,\n'
    '        data: Intent?\n'
    '    ) {\n'
    '        if (!AramEngineChannel.onActivityResult(requestCode, resultCode, data)) {\n'
    '            super.onActivityResult(requestCode, resultCode, data)\n'
    '        }\n'
    '    }\n'
    '\n'
    '    private fun startReader(handle: Long) {',
    "MainActivity picker callback"
)

old_destroy = (
    '    override fun onDestroy() {\n'
    '        sessions.values.forEach { session ->\n'
    '            session.active = false\n'
    '            try { PtyNative.nativeClose(session.handle) } catch (_: Throwable) { }\n'
    '        }\n'
    '        sessions.clear()\n'
    '        super.onDestroy()\n'
    '    }'
)

new_destroy = (
    '    override fun onDestroy() {\n'
    '        sessions.values.forEach { session ->\n'
    '            session.active = false\n'
    '            try { PtyNative.nativeClose(session.handle) } catch (_: Throwable) { }\n'
    '        }\n'
    '        sessions.clear()\n'
    '        AramEngineChannel.unregister(this)\n'
    '        super.onDestroy()\n'
    '    }'
)

s = replace_once(
    s,
    old_destroy,
    new_destroy,
    "MainActivity existing onDestroy"
)

data["main_activity"] = s

# --------------------------------------------------
# 8. AramEngineChannel SAF picker
# --------------------------------------------------

s = data["channel"]

# Activity is already imported in the supplied source.
if "import android.app.Activity" not in s:
    fail("AramEngineChannel.kt لا يحتوي استيراد Activity المتوقع.")

s = replace_once(
    s,
    "import android.content.Intent",
    "import android.content.Intent\nimport android.net.Uri",
    "Channel Uri import"
)

s = replace_once(
    s,
    "    private val main = Handler(Looper.getMainLooper())",
    "    private val main = Handler(Looper.getMainLooper())\n"
    "    private const val MODEL_PICKER_REQUEST = 0x0A26\n"
    "    @Volatile private var pickerActivity: Activity? = null\n"
    "    @Volatile private var pendingPickerResult: MethodChannel.Result? = null",
    "Channel picker state"
)

s = replace_once(
    s,
    "    fun register(engine: FlutterEngine, activity: Activity) {\n"
    "        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->",
    "    fun register(engine: FlutterEngine, activity: Activity) {\n"
    "        pickerActivity = activity\n"
    "        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->",
    "Channel activity registration"
)

s = replace_once(
    s,
    '                    "status" -> {',
    '                    "importModel" -> {\n'
    '                        val currentActivity = pickerActivity\n'
    '                            ?: throw IllegalStateException("واجهة اختيار الملفات غير متاحة")\n'
    '                        if (pendingPickerResult != null) {\n'
    '                            throw IllegalStateException("يوجد طلب اختيار ملف قيد التنفيذ")\n'
    '                        }\n'
    '                        pendingPickerResult = result\n'
    '                        try {\n'
    '                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {\n'
    '                                addCategory(Intent.CATEGORY_OPENABLE)\n'
    '                                type = "*/*"\n'
    '                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)\n'
    '                            }\n'
    '                            currentActivity.startActivityForResult(\n'
    '                                intent, MODEL_PICKER_REQUEST\n'
    '                            )\n'
    '                        } catch (error: Throwable) {\n'
    '                            pendingPickerResult = null\n'
    '                            throw error\n'
    '                        }\n'
    '                    }\n'
    '                    "status" -> {',
    "Channel importModel method"
)

if not s.endswith("\n}"):
    fail("نهاية AramEngineChannel.kt غير مطابقة للبنية المتوقعة.")

channel_helpers = r'''

    fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ): Boolean {
        if (requestCode != MODEL_PICKER_REQUEST) return false

        val callback = pendingPickerResult
        pendingPickerResult = null

        if (callback == null) return true

        if (resultCode != Activity.RESULT_OK) {
            callback.success(false)
            return true
        }

        val uri: Uri? = data?.data

        if (uri == null) {
            callback.error(
                "MODEL_URI_MISSING",
                "لم يتم اختيار ملف.",
                null
            )
            return true
        }

        var persistedPermissionTaken = false
        var permissionActivity: Activity? = null

        try {
            val activity = pickerActivity
                ?: throw IllegalStateException("واجهة التطبيق لم تعد متاحة")
            permissionActivity = activity

            val grantedFlags = data?.flags ?: 0
            val readFlag = grantedFlags and Intent.FLAG_GRANT_READ_URI_PERMISSION
            val persistableFlag = grantedFlags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION

            if (readFlag == 0 || persistableFlag == 0) {
                throw SecurityException("مزود الملفات لم يمنح صلاحية قراءة دائمة.")
            }

            activity.contentResolver.takePersistableUriPermission(uri, readFlag)
            persistedPermissionTaken = true

            val serviceIntent = Intent(
                activity,
                AramEngineService::class.java
            ).apply {
                action = AramEngineService.ACTION_IMPORT_MODEL
                setData(uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            activity.startForegroundService(serviceIntent)
        } catch (error: Throwable) {
            if (persistedPermissionTaken) {
                runCatching {
                    permissionActivity?.contentResolver?.releasePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                }
            }
            callback.error(
                "MODEL_IMPORT_START_FAILED",
                error.message ?: error.javaClass.simpleName,
                null
            )
            return true
        }

        // The service has started and owns the import operation.
        // Do not release its persisted URI permission if this callback fails.
        runCatching { callback.success(true) }

        return true
    }

    fun unregister(activity: Activity) {
        if (pickerActivity === activity) {
            pickerActivity = null
        }

        if (pickerActivity == null) {
            val callback = pendingPickerResult
            pendingPickerResult = null

            if (callback != null) {
                runCatching {
                    callback.error(
                        "ACTIVITY_DESTROYED",
                        "أُغلقت واجهة اختيار الملف.",
                        null
                    )
                }
            }
        }
    }
'''

s = s[:-2] + channel_helpers + "\n}"
data["channel"] = s

# --------------------------------------------------
# 9. AramEngineService import implementation
# --------------------------------------------------

s = data["service"]

s = replace_once(
    s,
    "import android.content.Intent",
    "import android.content.Intent\n"
    "import android.net.Uri\n"
    "import android.os.StatFs\n"
    "import java.io.File\n"
    "import java.io/FileOutputStream\n"
    "import kotlinx.coroutines.NonCancellable\n"
    "import kotlinx.coroutines.withContext",
    "Service import dependencies"
)

s = replace_once(
    s,
    "    @Volatile private var starting = false",
    "    @Volatile private var starting = false\n"
    "    @Volatile private var importRequested = false",
    "Service import state"
)

# Separate the import action from normal start.
old_start = '''    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
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
        if (!starting && server == null) startEngine()
        return START_STICKY
    }'''

new_start = '''    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            if (importRequested) {
                updateNotification("يجري استيراد النموذج؛ تم تجاهل طلب الإيقاف لحماية العملية.")
                return START_NOT_STICKY
            }
            stopEngine()
            return START_NOT_STICKY
        }

        try {
            startForegroundCompat()
            acquireWakeLock()
        } catch (error: Throwable) {
            AppPrefs.setEngineState(
                this,
                "ERROR",
                "تعذر بدء خدمة Aram AI: ${error.message ?: error.javaClass.simpleName}"
            )
            stopSelf(startId)
            return START_NOT_STICKY
        }

        if (intent?.action == ACTION_IMPORT_MODEL) {
            if (importRequested) {
                updateNotification("يوجد استيراد نموذج قيد التنفيذ بالفعل.")
                return START_NOT_STICKY
            }
            val uri = intent.data

            if (uri == null) {
                AppPrefs.setEngineState(
                    this,
                    "ERROR",
                    "لم يصل ملف النموذج المختار."
                )
                releaseWakeLock()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf(startId)
                return START_NOT_STICKY
            }

            importRequested = true

            scope.launch {
                try {
                    lifecycleMutex.withLock {
                        importModel(uri)
                    }
                } finally {
                    importRequested = false
                    runCatching {
                        contentResolver.releasePersistableUriPermission(
                            uri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION
                        )
                    }
                }
            }

            return START_NOT_STICKY
        }

        if (!starting && server == null && !importRequested) {
            startEngine()
        }

        return START_STICKY
    }'''

s = replace_once(
    s,
    old_start,
    new_start,
    "Service onStartCommand"
)

# Avoid stopping the service when an import request is waiting.
s = replace_once(
    s,
    '                        AppPrefs.setEngineState(this@AramEngineService, "DOWNLOADING_MODEL", "يجري تنزيل Spark-X2.6-1.7B إلى مساحة TermiAI-Nexus الخاصة…")\n'
    '                        updateNotification("تنزيل نموذج Spark-X2.6-1.7B جارٍ عبر Download Manager")\n'
    '                        starting = false\n'
    '                        stopForeground(STOP_FOREGROUND_REMOVE)\n'
    '                        stopSelf()\n'
    '                        return@withLock',
    '                        AppPrefs.setEngineState(this@AramEngineService, "DOWNLOADING_MODEL", "يجري تنزيل Spark-X2.6-1.7B إلى مساحة TermiAI-Nexus الخاصة…")\n'
    '                        updateNotification("تنزيل نموذج Spark-X2.6-1.7B جارٍ عبر Download Manager")\n'
    '                        starting = false\n'
    '                        if (!importRequested) {\n'
    '                            releaseWakeLock()\n'
    '                            stopForeground(STOP_FOREGROUND_REMOVE)\n'
    '                            stopSelf()\n'
    '                        }\n'
    '                        return@withLock',
    "Service import/download race"
)

service_helpers = r'''    @Volatile private var apiServerStarted = false
    @Volatile private var serviceDestroying = false

    private suspend fun importModel(uri: Uri) {
        var stagingForCleanup: File? = null
        try {
            val destination = ModelFiles.modelFile(this)
            val directory = destination.parentFile
                ?: error("تعذر تحديد مجلد تخزين النموذج")

            if (!directory.exists() && !directory.mkdirs()) {
                error("تعذر إنشاء مجلد تخزين النموذج")
            }

            val staging = File(
                directory,
                "${ModelFiles.MODEL_NAME}.importing"
            )
            stagingForCleanup = staging

            val backup = File(
                directory,
                "${ModelFiles.MODEL_NAME}.rollback"
            )

            check(!backup.exists()) {
                "توجد نسخة استعادة سابقة محفوظة ولم تُحذف: ${backup.absolutePath}. "
                    + "أوقف الاستيراد وافحصها يدويًا قبل المتابعة."
            }

            AppPrefs.setEngineState(
                this,
                "IMPORTING_MODEL",
                "نسخ النموذج المختار والتحقق منه…"
            )
            updateNotification("استيراد نموذج Aram AI والتحقق منه…")

            val available = StatFs(directory.absolutePath).availableBytes
            val required =
                ModelFiles.MIN_MODEL_BYTES + 64L * 1024L * 1024L

            require(available >= required) {
                "المساحة الحرة غير كافية لاستيراد النموذج."
            }

            if (staging.exists()) {
                check(staging.delete()) {
                    "تعذر حذف ملف الاستيراد المؤقت السابق."
                }
            }

            val input = contentResolver.openInputStream(uri)
                ?: error("تعذر فتح الملف المختار.")

            input.use { source ->
                FileOutputStream(staging).use { output ->
                    val buffer = ByteArray(1024 * 1024)
                    var total = 0L

                    while (true) {
                        val count = source.read(buffer)
                        if (count < 0) break
                        if (count == 0) continue

                        total += count

                        require(total <= 8L * 1024L * 1024L * 1024L) {
                            "حجم الملف أكبر من الحد المدعوم."
                        }

                        output.write(buffer, 0, count)
                    }

                    output.flush()
                    output.fd.sync()
                }
            }

            require(ModelFiles.isValidGguf(staging)) {
                "الملف ليس نموذج GGUF صالحًا أو حجمه غير كافٍ."
            }

            // Cancel any existing DownloadManager job.
            val downloadId = AppPrefs.downloadId(this)
            AppPrefs.setDownloadId(this, -1L)

            if (downloadId >= 0L) {
                runCatching {
                    (getSystemService(Context.DOWNLOAD_SERVICE)
                        as DownloadManager).remove(downloadId)
                }
            }

            File(
                directory,
                "${ModelFiles.MODEL_NAME}.download"
            ).delete()

            AppPrefs.setEngineState(
                this,
                "IMPORTING_MODEL",
                "إيقاف التوليد الحالي وتجهيز استبدال النموذج…"
            )

            stopApiServer()

            ModelRuntime.unload()

            val hadPrevious = destination.exists()

            if (hadPrevious) {
                check(destination.renameTo(backup)) {
                    "تعذر حفظ النموذج السابق كنسخة احتياطية."
                }
            }

            try {
                check(staging.renameTo(destination)) {
                    "تعذر نقل النموذج المستورد إلى مجلد التشغيل."
                }

                ModelRuntime.load(this, destination)
                startApiServer()

                val backupRetained = backup.exists() && !backup.delete()

                AppPrefs.setEngineState(
                    this,
                    "READY",
                    "تم استيراد النموذج وتشغيل Aram AI بنجاح · API على 127.0.0.1:8766" +
                        if (backupRetained) " · النسخة السابقة محفوظة: ${backup.absolutePath}" else ""
                )

                updateNotification("Aram AI جاهز · النموذج المستورد يعمل")

            } catch (newModelError: Throwable) {
                withContext(NonCancellable) {
                    stopApiServer()
                    ModelRuntime.unload()

                if (destination.exists()) {
                    check(destination.delete()) {
                        "تعذر حذف النموذج الجديد؛ حُفظت النسخة الاحتياطية دون تغيير: ${backup.absolutePath}"
                    }
                }

                if (hadPrevious && backup.exists()) {
                    check(backup.renameTo(destination)) {
                        "فشل النموذج الجديد وتعذرت استعادة النسخة السابقة. "
                            + "النسخة الاحتياطية باقية: ${backup.absolutePath}"
                    }

                    ModelRuntime.load(this, destination)
                    startApiServer()

                    AppPrefs.setEngineState(
                        this,
                        "READY",
                        "فشل النموذج المستورد؛ تمت استعادة النموذج السابق وتشغيله. السبب: ${newModelError.message}"
                    )

                    updateNotification("تمت استعادة نموذج Aram AI السابق")
                } else {
                    throw newModelError
                }
                }
            }
        } catch (error: Throwable) {
            val previousEngineStillRunning =
                apiServerStarted && server != null && ModelRuntime.isLoaded()

            AppPrefs.setEngineState(
                this,
                if (previousEngineStillRunning) "READY" else "ERROR",
                if (previousEngineStillRunning) {
                    "فشل الاستيراد، لكن المحرك السابق ما زال يعمل: " +
                        (error.message ?: error.javaClass.simpleName)
                } else {
                    "فشل استيراد النموذج: " +
                        (error.message ?: error.javaClass.simpleName)
                }
            )

            updateNotification(
                if (previousEngineStillRunning) {
                    "فشل الاستيراد؛ نموذج Aram AI السابق ما زال يعمل"
                } else {
                    "فشل استيراد نموذج Aram AI · افتح مركز المحرك"
                }
            )

            runCatching { stagingForCleanup?.delete() }

            if (server == null && !ModelRuntime.isLoaded()) {
                releaseWakeLock()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        } finally {
            runCatching {
                contentResolver.releasePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            }
        }
    }

    private fun startApiServer() {
        check(!serviceDestroying) {
            "تعذر تشغيل خادم API بعد بدء إغلاق الخدمة."
        }

        val existing = server

        if (existing != null) {
            check(apiServerStarted) {
                "حالة خادم API غير مؤكدة؛ لن يتم إنشاء خادم آخر."
            }
            return
        }

        val localServer = com.aram.ai.server.ApiHttpServer(
            "127.0.0.1",
            ApiKeyStore(this),
            8766
        )

        server = localServer
        apiServerStarted = false

        try {
            localServer.start(NanoHTTPD.SOCKET_READ_TIMEOUT, false)
            apiServerStarted = true
        } catch (error: Throwable) {
            apiServerStarted = false

            try {
                localServer.stop()
                if (server === localServer) server = null
            } catch (stopFailure: Throwable) {
                error.addSuppressed(stopFailure)
            }

            throw error
        }
    }

    private fun stopApiServer() {
        val current = server

        if (current == null) {
            apiServerStarted = false
            return
        }

        // Never report READY if stop() fails or leaves the state uncertain.
        apiServerStarted = false

        current.stop()

        if (server === current) {
            server = null
        }
    }

'''

s = replace_once(
    s,
    "    private fun isDownloadActive(id: Long): Boolean {",
    service_helpers + "    private fun isDownloadActive(id: Long): Boolean {",
    "Service import helper insertion"
)

s = replace_once(
    s,
    '                    val localServer = com.aram.ai.server.ApiHttpServer("127.0.0.1", ApiKeyStore(this@AramEngineService), 8766)\n'
    '                    localServer.start(NanoHTTPD.SOCKET_READ_TIMEOUT, false)\n'
    '                    server = localServer',
    '                    startApiServer()',
    "Service shared API startup"
)

s = replace_once(
    s,
    '                    runCatching { server?.stop() }\n'
    '                    server = null\n'
    '                    runCatching { ModelRuntime.unload() }',
    '                    val cleanupFailure = runCatching {\n'
    '                        stopApiServer()\n'
    '                        ModelRuntime.unload()\n'
    '                    }.exceptionOrNull()\n'
    '                    if (cleanupFailure != null && cleanupFailure !== error) {\n'
    '                        error.addSuppressed(cleanupFailure)\n'
    '                    }',
    "Service startup failure cleanup preservation"
)

s = replace_once(
    s,
    '                    stopForeground(STOP_FOREGROUND_REMOVE)\n'
    '                    releaseWakeLock()\n'
    '                    stopSelf()',
    '                    if (cleanupFailure == null) {\n'
    '                        stopForeground(STOP_FOREGROUND_REMOVE)\n'
    '                        releaseWakeLock()\n'
    '                        stopSelf()\n'
    '                    } else {\n'
    '                        updateNotification("تعذر تنظيف موارد المحرك بأمان؛ بقيت الخدمة نشطة للمحاولة مجددًا.")\n'
    '                    }',
    "Service startup retains resources after cleanup failure"
)

s = replace_once(
    s,
    """    private fun stopEngine() {
        scope.launch {
            lifecycleMutex.withLock {
                runCatching { server?.stop() }
                server = null
                runCatching { ModelRuntime.unload() }
                AppPrefs.setEngineState(this@AramEngineService, "STOPPED", "تم إيقاف محرك Aram AI وتحرير موارده")
                releaseWakeLock()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
    }""",
    """    private fun stopEngine() {
        scope.launch {
            lifecycleMutex.withLock {
                val stopFailure = runCatching {
                    stopApiServer()
                }.exceptionOrNull()

                if (stopFailure != null) {
                    AppPrefs.setEngineState(
                        this@AramEngineService,
                        "ERROR",
                        "تعذر إيقاف خادم API بأمان: ${stopFailure.message ?: stopFailure.javaClass.simpleName}"
                    )
                    updateNotification("تعذر إيقاف خادم API؛ بقيت الخدمة نشطة للمحاولة مجددًا.")
                    return@withLock
                }

                try {
                    ModelRuntime.unload()
                } catch (error: Throwable) {
                    AppPrefs.setEngineState(
                        this@AramEngineService,
                        "ERROR",
                        "تعذر تحرير موارد محرك Aram AI: ${error.message ?: error.javaClass.simpleName}"
                    )
                    updateNotification("تعذر تحرير موارد المحرك؛ بقيت الخدمة نشطة للمحاولة مجددًا.")
                    return@withLock
                }

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
    }""",
    "Service stop preserves server and native engine references"
)

s = replace_once(
    s,
    '        const val ACTION_STOP = "com.aram.termaix.aram.STOP"',
    '        const val ACTION_STOP = "com.aram.termaix.aram.STOP"\n'
    '        const val ACTION_IMPORT_MODEL = "com.aram.termaix.aram.IMPORT_MODEL"',
    "Service import action"
)

s = replace_once(
    s,
    '        if (state.state == "READY" || state.state == "STARTING" || state.state == "LOADING_MODEL" || state.state == "STARTING_SERVER") {',
    '        if (state.state == "READY" || state.state == "STARTING" || state.state == "LOADING_MODEL" || state.state == "STARTING_SERVER" || state.state == "IMPORTING_MODEL") {',
    "Service onDestroy state"
)

s = replace_once(
    s,
    """    override fun onDestroy() {
        runCatching { server?.stop() }
        server = null
        releaseWakeLock()
        val state = AppPrefs.engineStatus(this)
        if (state.state == "READY" || state.state == "STARTING" || state.state == "LOADING_MODEL" || state.state == "STARTING_SERVER" || state.state == "IMPORTING_MODEL") {
            AppPrefs.setEngineState(this, "STOPPED", "توقفت خدمة محرك Aram AI")
        }
        scope.cancel()
        super.onDestroy()
    }""",
    """    override fun onDestroy() {
        serviceDestroying = true

        val wasImporting = importRequested
        val stopFailure = runCatching {
            stopApiServer()
        }.exceptionOrNull()

        releaseWakeLock()

        val state = AppPrefs.engineStatus(this)

        if (wasImporting || stopFailure != null) {
            val reason = if (wasImporting) {
                "توقفت الخدمة أثناء استيراد النموذج. افحص ملفات .importing و.rollback قبل إعادة المحاولة."
            } else {
                "تعذر إيقاف خادم API أثناء إغلاق الخدمة: " +
                    (stopFailure?.message ?: stopFailure?.javaClass?.simpleName ?: "سبب غير معروف")
            }

            AppPrefs.setEngineState(this, "ERROR", reason)
        } else if (
            state.state == "READY" ||
            state.state == "STARTING" ||
            state.state == "LOADING_MODEL" ||
            state.state == "STARTING_SERVER"
        ) {
            AppPrefs.setEngineState(
                this,
                "STOPPED",
                "توقفت خدمة محرك Aram AI"
            )
        }

        scope.cancel()
        super.onDestroy()
    }""",
    "Service safe destruction lifecycle"
)
data["service"] = s

# --------------------------------------------------
# 10. Validate and create backup
# --------------------------------------------------

for key, content in data.items():
    if not content or len(content) < 100:
        fail(f"المحتوى الناتج غير صالح: {key}")

if "lib/core/aram_engine_bridge.dart" in data:
    fail("حماية: لا يسمح بتعديل aram_engine_bridge.dart.")

stamp = time.strftime("%Y%m%d-%H%M%S")

backup_root = (
    ROOT / "myao" / "backups" / f"aram-integration-{stamp}"
)

backup_root.mkdir(parents=True, exist_ok=False)

originals = {}

for key, rel in paths.items():
    path = ROOT / rel
    originals[rel] = path.read_bytes()

    backup = backup_root / rel
    backup.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, backup)

# --------------------------------------------------
# 11. Atomic writes with rollback on write failure
# --------------------------------------------------

written = []

try:
    for key, rel in paths.items():
        path = ROOT / rel
        content = data[key]

        temp = path.with_name(path.name + ".aram-tmp")
        temp.write_text(content, encoding="utf-8")

        os.replace(temp, path)
        written.append(rel)

except Exception as error:
    for rel in reversed(written):
        path = ROOT / rel
        path.write_bytes(originals[rel])

    fail(
        "حدث خطأ أثناء كتابة الملفات، "
        f"وأُعيدت الملفات المعدلة إلى حالتها السابقة: {error}"
    )

print("\n==================================================")
print("PATCH COMPLETED")
print("==================================================")
print("Modified files:")

for rel in written:
    print("  ✓", rel)

print("\nBackup directory:")
print(backup_root)

print("\nProtected file:")
print("  ✓ lib/core/aram_engine_bridge.dart")

print("\nNo Git staging or commits were performed.")
PY

echo
echo "=================================================="
echo " Patch application finished"
echo "=================================================="
echo "Build and Flutter analysis must be verified through CI."
git status --short
