package com.aram.termaix

import android.app.Activity
import android.os.Bundle
import android.net.Uri
import android.view.ViewGroup
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.TextView
import java.io.File
import java.net.URLConnection
import java.nio.file.Files

class ProjectPreviewActivity : Activity() {
    companion object {
        const val EXTRA_PATH = "termai.preview.path"
        private const val PREVIEW_HOST = "nexus-preview.local"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val rawPath = intent.getStringExtra(EXTRA_PATH)
        if (rawPath.isNullOrBlank()) {
            showError("مسار المعاينة غير متوفر.")
            return
        }

        try {
            val workspaceBase = File(applicationInfo.dataDir, "app_flutter/TermiAI-Nexus/workspaces").canonicalFile
            val inputFile = File(rawPath).absoluteFile.toPath().normalize().toFile()
            require(inputFile.toPath().startsWith(workspaceBase.toPath())) {
                "الملف خارج مسار مساحات عمل TermiAI-Nexus."
            }
            ensureNoSymlink(workspaceBase, inputFile)
            val htmlFile = inputFile.canonicalFile
            require(isWithin(workspaceBase, htmlFile) && htmlFile.isFile &&
                htmlFile.length() <= 4 * 1024 * 1024 &&
                htmlFile.extension.lowercase() in setOf("html", "htm")) {
                "المعاينة تدعم ملفات HTML داخل مساحة المشروع فقط."
            }

            var workspaceRoot = htmlFile.parentFile ?: error("Invalid preview directory")
            while (workspaceRoot.parentFile != workspaceBase && workspaceRoot != workspaceBase) {
                workspaceRoot = workspaceRoot.parentFile ?: error("Invalid project workspace")
            }
            require(workspaceRoot.parentFile == workspaceBase) { "تعذر تحديد جذر المشروع." }
            ensureNoSymlink(workspaceBase, workspaceRoot)
            ensureNoSymlink(workspaceRoot, htmlFile)

            val relativeHtml = workspaceRoot.toPath().relativize(htmlFile.toPath()).toString().replace(File.separatorChar, '/')
            val relativeDirectory = relativeHtml.substringBeforeLast('/', "")
            val baseUrl = "https://$PREVIEW_HOST/" + if (relativeDirectory.isEmpty()) "" else "$relativeDirectory/"
            val html = htmlFile.readText(Charsets.UTF_8)

            val web = WebView(this).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.allowFileAccess = false
                settings.allowContentAccess = false
                settings.allowFileAccessFromFileURLs = false
                settings.allowUniversalAccessFromFileURLs = false
                webViewClient = object : WebViewClient() {
                    override fun shouldInterceptRequest(view: WebView?, request: android.webkit.WebResourceRequest?): WebResourceResponse? {
                        val uri = request?.url ?: return blocked()
                        if (uri.scheme != "https" || uri.host != PREVIEW_HOST) return blocked()
                        return runCatching { serveLocal(workspaceRoot, uri) }.getOrElse { blocked() }
                    }

                    override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                        val uri = runCatching { Uri.parse(url ?: "") }.getOrNull() ?: return true
                        return uri.scheme != "https" || uri.host != PREVIEW_HOST
                    }
                }
                loadDataWithBaseURL(baseUrl, html, "text/html", "UTF-8", null)
            }
            setContentView(web, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        } catch (error: Throwable) {
            showError(error.message ?: "تعذر فتح المعاينة.")
        }
    }

    private fun serveLocal(root: File, uri: Uri): WebResourceResponse {
        val relative = Uri.decode(uri.path.orEmpty()).trimStart('/')
        require(relative.isNotBlank() && !relative.contains('\\'))
        val segments = relative.split('/')
        require(segments.none(::isSensitiveSegment)) { "المعاينة ترفض المسارات الحساسة." }
        val unresolved = File(root, relative).absoluteFile.toPath().normalize().toFile()
        require(unresolved.toPath().startsWith(root.toPath()))
        ensureNoSymlink(root, unresolved)
        val target = unresolved.canonicalFile
        require(isWithin(root, target) && target.isFile && target.length() <= 4 * 1024 * 1024)
        val mime = URLConnection.guessContentTypeFromName(target.name) ?: when (target.extension.lowercase()) {
            "js" -> "application/javascript"
            "mjs" -> "application/javascript"
            "css" -> "text/css"
            "svg" -> "image/svg+xml"
            "json" -> "application/json"
            "wasm" -> "application/wasm"
            else -> "application/octet-stream"
        }
        return WebResourceResponse(mime, "UTF-8", target.inputStream())
    }

    private fun blocked() = WebResourceResponse("text/plain", "UTF-8", "Blocked".byteInputStream())

    private fun isSensitiveSegment(segment: String): Boolean {
        val name = segment.lowercase()
        val exact = setOf(
            ".git", ".termai", ".env", ".npmrc", ".netrc",
            ".git-credentials", "google-services.json", ".ssh", ".aws",
            ".azure", ".kube"
        )
        val extension = listOf(".pem", ".p12", ".pfx", ".jks", ".keystore", ".key", ".gpg", ".asc", ".der", ".cer")
        val secretName = Regex("""(^|[._-])(secret|secrets|credential|credentials|token|password|passwd|private|apikey|api_key|auth|service-account)([._-]|$)""")
        return name in exact || name.startsWith(".env.") || name.endsWith(".env") ||
            name.startsWith("id_rsa") || name.startsWith("id_ed25519") ||
            extension.any { name.endsWith(it) } || secretName.containsMatchIn(name)
    }

    private fun ensureNoSymlink(root: File, target: File) {
        val relative = root.toPath().relativize(target.toPath())
        var cursor = root
        for (part in relative) {
            cursor = File(cursor, part.toString())
            require(!Files.isSymbolicLink(cursor.toPath())) { "المعاينة ترفض الروابط الرمزية." }
        }
    }

    private fun isWithin(root: File, target: File): Boolean {
        val rootPath = root.canonicalPath
        val targetPath = target.canonicalPath
        return targetPath.startsWith(rootPath + File.separator)
    }

    private fun showError(message: String) {
        setContentView(TextView(this).apply {
            text = "تعذر فتح معاينة المشروع\n\n$message"
            textSize = 16f
            setPadding(28, 40, 28, 40)
        })
    }
}
