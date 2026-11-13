package com.aram.ai.data

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.OpenableColumns
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

object ModelFiles {
    const val MODEL_ID = "spark-x2.6-1.7b"
    const val MODEL_NAME = "Spark-X2.6-1.7B-Q4_K_M.gguf"
    const val MODEL_URL =
        "https://huggingface.co/XHToken/Spark-X2.6-1.7B-GGUF/resolve/main/Spark-X2.6-1.7B-Q4_K_M.gguf"

    // Spark-X2.6-1.7B Q4_K_M variants are published around 1.1–1.8 GB.
    // Accept smaller valid GGUF quants too; integrity is checked by GGUF magic/version
    // and, for imports, by comparing the copied size with the provider's declared size.
    const val MIN_MODEL_BYTES = 550_000_000L
    private const val MAX_MODEL_BYTES = 4_500_000_000L

    private const val TEMP_NAME = "$MODEL_NAME.download"
    private const val IMPORT_TEMP_NAME = "$MODEL_NAME.importing"
    private const val MIN_FREE_SPACE_MARGIN = 100L * 1024L * 1024L

    fun modelFile(context: Context): File {
        val directory = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: File(context.filesDir, "models")

        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("تعذر إنشاء مجلد النماذج")
        }

        return File(directory, MODEL_NAME)
    }

    fun validateModel(file: File): Boolean {
        if (!file.isFile || file.length() < MIN_MODEL_BYTES) return false

        return try {
            FileInputStream(file).use { input ->
                val header = ByteArray(8)
                var offset = 0

                while (offset < header.size) {
                    val count = input.read(header, offset, header.size - offset)
                    if (count <= 0) return false
                    offset += count
                }

                val magic = String(header, 0, 4, Charsets.US_ASCII)
                if (magic != "GGUF") return false

                val version = ByteBuffer.wrap(header, 4, 4)
                    .order(ByteOrder.LITTLE_ENDIAN)
                    .int

                version in 2..3
            }
        } catch (_: Exception) {
            false
        }
    }

    fun isModelReady(context: Context): Boolean {
        return validateModel(modelFile(context))
    }

    private fun promoteValidatedFile(
        temporary: File,
        destination: File
    ): Boolean {
        if (!validateModel(temporary)) return false

        val directory = destination.parentFile ?: return false

        val backup = File(
            directory,
            "$MODEL_NAME.previous.${System.currentTimeMillis()}"
        )

        val hadPrevious = destination.exists()

        if (hadPrevious && !destination.renameTo(backup)) {
            return false
        }

        if (temporary.renameTo(destination)) {
            return validateModel(destination).also { valid ->
                if (!valid) {
                    destination.delete()
                    if (hadPrevious) backup.renameTo(destination)
                }
            }
        }

        if (hadPrevious) {
            backup.renameTo(destination)
        }

        return false
    }

    fun importModel(
        context: Context,
        uri: Uri,
        onProgress: (String, Long, Long) -> Unit = { _, _, _ -> }
    ): Boolean {
        val destination = modelFile(context)
        val directory = destination.parentFile
            ?: throw IllegalStateException("مجلد النموذج غير صالح")

        val temporary = File(directory, IMPORT_TEMP_NAME)

        if (temporary.exists() && !temporary.delete()) {
            throw IllegalStateException("تعذر تنظيف ملف الاستيراد المؤقت")
        }

        val declaredSize = context.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.SIZE),
            null,
            null,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else -1L
        } ?: -1L

        if (declaredSize >= 0L && declaredSize < MIN_MODEL_BYTES) {
            throw IllegalArgumentException("حجم ملف GGUF أصغر من الحد الأدنى المقبول؛ قد يكون الملف غير مكتمل")
        }
        if (declaredSize > MAX_MODEL_BYTES) {
            throw IllegalArgumentException("حجم ملف النموذج يتجاوز الحد الأقصى المسموح")
        }
        onProgress("COPYING", 0L, declaredSize)
        val requiredSpace = if (declaredSize > 0L) declaredSize else MIN_MODEL_BYTES
        if (directory.usableSpace < requiredSpace + MIN_FREE_SPACE_MARGIN) {
            throw IllegalStateException("مساحة التخزين غير كافية لنسخ ملف النموذج كاملًا")
        }

        try {
            val source = context.contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("تعذر فتح الملف المحدد")

            source.use { input ->
                FileOutputStream(temporary).use { output ->
                    val buffer = ByteArray(1024 * 1024)
                    var total = 0L
                    var lastProgressAt = 0L

                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (count == 0) continue

                        total += count
                        if (total > MAX_MODEL_BYTES) {
                            throw IllegalStateException("حجم الملف يتجاوز الحد الأقصى المسموح")
                        }

                        output.write(buffer, 0, count)
                        val now = System.nanoTime()
                        if (now - lastProgressAt >= 250_000_000L) {
                            onProgress("COPYING", total, declaredSize)
                            lastProgressAt = now
                        }
                    }

                    onProgress("COPYING", total, declaredSize)
                    output.flush()
                    output.fd.sync()
                }
            }

            onProgress("VERIFYING", temporary.length(), declaredSize)
            if (declaredSize > 0L && temporary.length() != declaredSize) {
                throw IllegalArgumentException("حجم الملف المنسوخ لا يطابق حجم الملف الأصلي؛ أُوقف الاستيراد لحماية النموذج")
            }

            if (!validateModel(temporary)) {
                throw IllegalArgumentException(
                    "الملف ليس نموذج GGUF صالحًا أو أن حجمه غير مكتمل"
                )
            }

            if (!promoteValidatedFile(temporary, destination)) {
                throw IllegalStateException("تعذر اعتماد النموذج مع الحفاظ على النسخة السابقة")
            }

            onProgress("COMPLETE", destination.length(), declaredSize)
            return true
        } catch (error: Throwable) {
            temporary.delete()
            throw error
        }
    }

    fun downloadProgress(context: Context): Map<String, Any> {
        val id = AppPrefs.downloadId(context)
        if (id < 0L) return emptyMap()
        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val cursor = runCatching { manager.query(DownloadManager.Query().setFilterById(id)) }.getOrNull()
            ?: return mapOf(
                "transferOperation" to "DOWNLOAD",
                "transferStage" to "CONNECTING",
                "transferBytes" to 0L,
                "transferTotalBytes" to -1L,
                "transferPaused" to false
            )
        cursor.use {
            if (!it.moveToFirst()) return emptyMap()
            val downloaded = it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            val total = it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
            val status = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val reason = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
            val stage = when (status) {
                DownloadManager.STATUS_PENDING -> "PENDING"
                DownloadManager.STATUS_RUNNING -> "RUNNING"
                DownloadManager.STATUS_PAUSED -> "PAUSED"
                DownloadManager.STATUS_SUCCESSFUL -> "VERIFYING"
                DownloadManager.STATUS_FAILED -> "FAILED"
                else -> "UNKNOWN"
            }
            return mapOf(
                "transferOperation" to "DOWNLOAD",
                "transferStage" to stage,
                "transferBytes" to downloaded.coerceAtLeast(0L),
                "transferTotalBytes" to total,
                "transferPaused" to (status == DownloadManager.STATUS_PAUSED),
                "transferStatus" to stage,
                "transferReason" to reason
            )
        }
    }

    fun finalizeDownload(context: Context): Boolean {
        val directory = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: return false

        val temporary = File(directory, TEMP_NAME)
        val destination = modelFile(context)

        return promoteValidatedFile(temporary, destination)
    }

    fun enqueueDownload(context: Context): Long {
        val directory = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: throw IllegalStateException("مساحة تنزيل التطبيق غير متاحة")

        val temporary = File(directory, TEMP_NAME)

        if (temporary.exists() && !temporary.delete()) {
            throw IllegalStateException("تعذر تنظيف التنزيل السابق")
        }

        if (directory.usableSpace < MIN_MODEL_BYTES + MIN_FREE_SPACE_MARGIN) {
            throw IllegalStateException("مساحة التخزين غير كافية لتنزيل النموذج")
        }

        val request = DownloadManager.Request(Uri.parse(MODEL_URL))
            .setTitle("Spark-X2.6-1.7B")
            .setDescription("تنزيل نموذج Aram AI الرسمي — Q4_K_M")
            .setNotificationVisibility(
                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
            )
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(false)
            .setDestinationInExternalFilesDir(
                context,
                Environment.DIRECTORY_DOWNLOADS,
                TEMP_NAME
            )

        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE)
            as DownloadManager

        val id = manager.enqueue(request)
        AppPrefs.setDownloadId(context, id)
        return id
    }
}
