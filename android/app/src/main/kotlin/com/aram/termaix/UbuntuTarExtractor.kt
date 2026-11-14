package com.aram.termaix

import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import java.io.File
import java.io.FileInputStream
import java.nio.file.Files
import java.nio.file.LinkOption
import java.util.zip.GZIPInputStream

/**
 * Extracts Ubuntu Base without calling the host link(2) syscall.
 *
 * The archive is scanned twice. The first pass builds a complete guest-root symlink
 * map, so entries such as bin/bash are redirected to usr/bin/bash even when the
 * symlink or the file appears later in the tar stream. Hard links are materialized
 * as independent copies and are resolved after ordinary files have been written.
 */
internal object UbuntuTarExtractor {
    private const val MAX_ENTRIES = 1_000_000
    private const val MAX_EXPANDED_BYTES = 900L * 1024L * 1024L
    private const val MAX_LINK_EXPANSIONS = 64
    private val NOFOLLOW = LinkOption.NOFOLLOW_LINKS

    private data class RawSymlink(val path: String, val target: String)
    private data class Symlink(val physicalPath: String, val storedTarget: String)
    private data class PendingHardlink(val destination: String, val target: String, val mode: Int)

    fun extract(archive: File, destination: File): String {
        require(archive.isFile && archive.length() > 0L) { "أرشيف Ubuntu غير موجود أو فارغ." }
        require(destination.isDirectory) { "مجلد وجهة Ubuntu غير موجود." }
        val root = destination.canonicalFile.toPath()

        val rawSymlinks = scanSymlinks(archive)
        val symlinkMap = buildSymlinkMap(rawSymlinks)
        // Reject loops in the declared links before writing any archive data.
        symlinkMap.keys.forEach { resolveGuestPath(it, symlinkMap) }

        val symlinks = rawSymlinks.map { raw ->
            val physical = physicalLeafPath(raw.path, symlinkMap)
            Symlink(physical, raw.target)
        }
        val symlinkPaths = symlinkMap.keys
        val createdFiles = HashSet<String>()
        val directoryModes = LinkedHashMap<String, Int>()
        val fileModes = LinkedHashMap<String, Int>()
        val hardlinks = ArrayList<PendingHardlink>()
        var entryCount = 0
        var expandedBytes = 0L

        TarArchiveInputStream(GZIPInputStream(FileInputStream(archive), 64 * 1024)).use { tar ->
            while (true) {
                val entry = tar.getNextEntry() ?: break
                entryCount++
                require(entryCount <= MAX_ENTRIES) { "أرشيف Ubuntu يحتوي عددًا غير طبيعي من العناصر." }
                val archivePath = safeArchivePath(entry.name)
                if (archivePath.isEmpty()) continue

                when {
                    entry.isSymbolicLink -> Unit // Created after regular files and hard links.
                    entry.isDirectory -> {
                        val physical = physicalLeafPath(archivePath, symlinkMap)
                        if (physical in symlinkPaths) continue // This directory entry names a symlink.
                        require(physical.isNotEmpty()) { "عنصر مجلد غير صالح في جذر Ubuntu: ${entry.name}" }
                        val target = safeHostPath(root, physical)
                        ensureDirectory(root, target)
                        directoryModes[physical] = entry.mode
                    }
                    entry.isLink -> {
                        val destinationPath = physicalLeafPath(archivePath, symlinkMap)
                        require(destinationPath !in symlinkPaths) {
                            "تعارض hard link مع رابط رمزي داخل Ubuntu: $archivePath"
                        }
                        require(destinationPath.isNotEmpty()) { "وجهة hard link غير صالحة: $archivePath" }
                        require(createdFiles.add(destinationPath)) { "مسار ملف مكرر داخل Ubuntu: $destinationPath" }
                        val rawTarget = safeHardlinkTarget(entry.linkName)
                        val targetLeaf = physicalLeafPath(rawTarget, symlinkMap)
                        require(targetLeaf !in symlinkPaths) {
                            "لن يتم تحويل hard link إلى رابط رمزي داخل Ubuntu: ${entry.linkName}"
                        }
                        val targetPath = resolveGuestPath(rawTarget, symlinkMap)
                        require(targetPath.isNotEmpty() && targetPath != destinationPath) {
                            "هدف hard link غير صالح: ${entry.linkName}"
                        }
                        hardlinks.add(PendingHardlink(destinationPath, targetPath, entry.mode))
                    }
                    entry.isFile -> {
                        require(entry.size >= 0L && entry.size <= MAX_EXPANDED_BYTES) {
                            "حجم ملف غير صالح داخل أرشيف Ubuntu: ${entry.name}"
                        }
                        val physical = physicalLeafPath(archivePath, symlinkMap)
                        require(physical !in symlinkPaths) {
                            "تعارض ملف عادي مع رابط رمزي داخل Ubuntu: $archivePath"
                        }
                        require(physical.isNotEmpty()) { "مسار ملف غير صالح في جذر Ubuntu: ${entry.name}" }
                        require(createdFiles.add(physical)) { "مسار ملف مكرر داخل Ubuntu: $physical" }
                        val target = safeHostPath(root, physical)
                        ensureDirectory(root, target.parent)
                        require(!Files.exists(target, NOFOLLOW)) { "الملف موجود مسبقًا داخل Ubuntu: $physical" }
                        Files.newOutputStream(
                            target,
                            java.nio.file.StandardOpenOption.CREATE_NEW,
                            java.nio.file.StandardOpenOption.WRITE
                        ).use { output ->
                            val buffer = ByteArray(64 * 1024)
                            while (true) {
                                val count = tar.read(buffer)
                                if (count < 0) break
                                expandedBytes += count.toLong()
                                require(expandedBytes <= MAX_EXPANDED_BYTES) {
                                    "حجم Ubuntu بعد فك الضغط تجاوز الحد الوقائي البالغ 900 MiB."
                                }
                                output.write(buffer, 0, count)
                            }
                        }
                        fileModes[physical] = entry.mode
                    }
                    else -> Unit // Device nodes and FIFOs are provided by Android/PRoot binds.
                }
            }
        }

        resolveHardlinks(root, hardlinks, MAX_EXPANDED_BYTES - expandedBytes)
        hardlinks.forEach { fileModes[it.destination] = it.mode }

        // Links are created only after all path writes, so Android never follows a
        // guest absolute symlink (for example /usr/lib) into the host filesystem.
        for (link in symlinks) {
            require(link.physicalPath.isNotEmpty()) { "مسار رابط رمزي فارغ داخل Ubuntu." }
            val path = safeHostPath(root, link.physicalPath)
            ensureDirectory(root, path.parent)
            require(!Files.exists(path, NOFOLLOW)) {
                "تعارض في موضع رابط رمزي داخل Ubuntu: ${link.physicalPath}"
            }
            val rawTarget = link.storedTarget
            require(rawTarget.isNotEmpty() && !rawTarget.contains('\u0000') && !rawTarget.contains('\\')) {
                "هدف رابط رمزي غير صالح داخل Ubuntu: ${link.physicalPath}"
            }
            Files.createSymbolicLink(path, java.nio.file.Paths.get(rawTarget))
        }

        // Apply file modes while all parents are still traversable, then lock
        // directory permissions deepest-first after all children already exist.
        fileModes.forEach { (relative, mode) ->
            applyMode(safeHostPath(root, relative).toFile(), mode)
        }
        directoryModes.entries.sortedByDescending { depth(it.key) }.forEach { (relative, mode) ->
            applyMode(safeHostPath(root, relative).toFile(), mode)
        }

        return "تم استخراج Ubuntu: $entryCount عنصرًا، ${expandedBytes / (1024L * 1024L)} MiB من الملفات، مع معالجة الروابط دون link()."
    }

    private fun scanSymlinks(archive: File): List<RawSymlink> {
        val links = ArrayList<RawSymlink>()
        var count = 0
        TarArchiveInputStream(GZIPInputStream(FileInputStream(archive), 64 * 1024)).use { tar ->
            while (true) {
                val entry = tar.getNextEntry() ?: break
                count++
                require(count <= MAX_ENTRIES) { "أرشيف Ubuntu يحتوي عددًا غير طبيعي من العناصر." }
                safeArchivePath(entry.name) // Validate every entry name during the planning pass.
                if (entry.isSymbolicLink) {
                    val path = safeArchivePath(entry.name)
                    require(path.isNotEmpty()) { "رابط رمزي باسم فارغ داخل أرشيف Ubuntu." }
                    links.add(RawSymlink(path, entry.linkName))
                }
            }
        }
        return links
    }

    private fun buildSymlinkMap(rawLinks: List<RawSymlink>): LinkedHashMap<String, String> {
        val map = LinkedHashMap<String, String>()
        val ordered = rawLinks.sortedWith(compareBy<RawSymlink> { depth(it.path) }.thenBy { it.path })
        for (link in ordered) {
            val parent = parentPath(link.path)
            val resolvedParent = if (parent.isEmpty()) "" else resolveGuestPath(parent, map)
            val leaf = link.path.substringAfterLast('/')
            val physicalPath = join(resolvedParent, leaf)
            require(physicalPath.isNotEmpty()) { "مسار رابط رمزي غير صالح: ${link.path}" }
            require(!map.containsKey(physicalPath)) { "رابط رمزي مكرر أو متعارض: $physicalPath" }
            map[physicalPath] = normalizeSymlinkTarget(resolvedParent, link.target)
        }
        return map
    }

    /** Resolve a guest path through known symlink prefixes without following host links. */
    private fun resolveGuestPath(rawPath: String, links: Map<String, String>): String {
        var parts = safeArchivePath(rawPath).split('/').filter { it.isNotEmpty() }
        var expansions = 0
        while (true) {
            var prefix = ArrayList<String>()
            var replaced = false
            for (index in parts.indices) {
                prefix.add(parts[index])
                val target = links[prefix.joinToString("/")] ?: continue
                expansions++
                require(expansions <= MAX_LINK_EXPANSIONS) {
                    "حلقة أو سلسلة روابط رمزية غير آمنة داخل Ubuntu: $rawPath"
                }
                val targetParts = if (target.isEmpty()) emptyList() else target.split('/').filter { it.isNotEmpty() }
                parts = targetParts + parts.drop(index + 1)
                replaced = true
                break
            }
            if (!replaced) return parts.joinToString("/")
        }
    }

    /** The final component is not followed; only its parent is resolved. */
    private fun physicalLeafPath(rawPath: String, links: Map<String, String>): String {
        val path = safeArchivePath(rawPath)
        require(path.isNotEmpty()) { "اسم مسار فارغ في أرشيف Ubuntu." }
        val parent = parentPath(path)
        val physicalParent = if (parent.isEmpty()) "" else resolveGuestPath(parent, links)
        return join(physicalParent, path.substringAfterLast('/'))
    }

    private fun normalizeSymlinkTarget(parent: String, target: String): String {
        require(target.isNotEmpty() && !target.contains('\u0000') && !target.contains('\\')) {
            "هدف رابط رمزي غير صالح داخل Ubuntu: $target"
        }
        val parts = if (target.startsWith('/')) ArrayList() else
            (if (parent.isEmpty()) emptyList() else parent.split('/')).toMutableList()
        for (segment in target.split('/')) {
            when (segment) {
                "", "." -> Unit
                ".." -> {
                    require(parts.isNotEmpty()) { "رابط رمزي يحاول الخروج من جذر Ubuntu: $parent -> $target" }
                    parts.removeAt(parts.lastIndex)
                }
                else -> parts.add(segment)
            }
        }
        return parts.joinToString("/")
    }

    private fun safeArchivePath(raw: String): String {
        require(raw.isNotEmpty() && !raw.startsWith('/') && !raw.startsWith('\\')) {
            "تم رفض مسار مطلق داخل أرشيف Ubuntu: $raw"
        }
        require(!raw.contains('\u0000') && !raw.contains('\\') && !Regex("^[A-Za-z]:").containsMatchIn(raw)) {
            "مسار غير صالح داخل أرشيف Ubuntu: $raw"
        }
        val parts = raw.split('/')
        require(parts.none { it == ".." }) { "تم رفض مسار يتجاوز جذر Ubuntu: $raw" }
        return parts.filter { it.isNotEmpty() && it != "." }.joinToString("/")
    }

    private fun safeHardlinkTarget(raw: String): String {
        // A hard-link target is interpreted relative to the guest root, never the host.
        val guestRelative = raw.removePrefix("/")
        return safeArchivePath(guestRelative)
    }

    private fun resolveHardlinks(
        root: java.nio.file.Path,
        hardlinks: List<PendingHardlink>,
        remainingBudget: Long
    ) {
        var pending = hardlinks.toList()
        var copiedBytes = 0L
        while (pending.isNotEmpty()) {
            val unresolved = ArrayList<PendingHardlink>()
            var copiedAny = false
            for (link in pending) {
                val source = safeHostPath(root, link.target)
                val destination = safeHostPath(root, link.destination)
                if (!Files.isRegularFile(source, NOFOLLOW)) {
                    unresolved.add(link)
                    continue
                }
                ensureDirectory(root, destination.parent)
                require(!Files.exists(destination, NOFOLLOW)) {
                    "وجهة hard link موجودة مسبقًا: ${link.destination}"
                }
                val sourceBytes = Files.size(source)
                require(sourceBytes >= 0L && copiedBytes + sourceBytes <= remainingBudget) {
                    "حجم نسخ hard links داخل Ubuntu تجاوز الحد الوقائي."
                }
                Files.copy(source, destination)
                copiedBytes += sourceBytes
                copiedAny = true
            }
            require(copiedAny || unresolved.isEmpty()) {
                "هدف hard link مفقود أو غير ملف عادي داخل Ubuntu: ${unresolved.first().target}"
            }
            pending = unresolved
        }
    }

    private fun safeHostPath(root: java.nio.file.Path, relative: String): java.nio.file.Path {
        require(relative.isNotEmpty()) { "لا يمكن أن يشير ملف إلى جذر Ubuntu نفسه." }
        val candidate = root.resolve(relative).normalize()
        require(candidate.startsWith(root) && candidate != root) {
            "تم رفض مسار خارج جذر Ubuntu: $relative"
        }
        var current = root
        val parent = candidate.parent
        if (parent != null) {
            for (part in root.relativize(parent)) {
                current = current.resolve(part)
                require(!Files.isSymbolicLink(current)) {
                    "تم رفض عبور رابط رمزي على Android أثناء الاستخراج: $current"
                }
                if (Files.exists(current, NOFOLLOW)) {
                    require(Files.isDirectory(current, NOFOLLOW)) { "مجلد أب غير صالح داخل Ubuntu: $current" }
                }
            }
        }
        return candidate
    }

    private fun ensureDirectory(root: java.nio.file.Path, directory: java.nio.file.Path) {
        require(directory.startsWith(root)) { "مجلد خارج جذر Ubuntu: $directory" }
        var current = root
        for (part in root.relativize(directory)) {
            current = current.resolve(part)
            require(!Files.isSymbolicLink(current)) { "رابط رمزي غير متوقع في مسار مجلد Ubuntu: $current" }
            if (Files.exists(current, NOFOLLOW)) {
                require(Files.isDirectory(current, NOFOLLOW)) { "المسار ليس مجلدًا داخل Ubuntu: $current" }
            } else {
                Files.createDirectory(current)
            }
        }
    }

    private fun applyMode(file: File, mode: Int) {
        // The app owns the rootfs files. Owner bits are what the host kernel checks
        // for the PRoot process; uid/gid cannot be changed in Android app storage.
        check(file.setReadable(mode and 0x100 != 0, true)) { "تعذر ضبط صلاحية القراءة: ${file.path}" }
        check(file.setWritable(mode and 0x80 != 0, true)) { "تعذر ضبط صلاحية الكتابة: ${file.path}" }
        check(file.setExecutable(mode and 0x40 != 0, true)) { "تعذر ضبط صلاحية التنفيذ: ${file.path}" }
    }

    private fun parentPath(path: String): String = path.substringBeforeLast('/', "")
    private fun join(parent: String, leaf: String): String = if (parent.isEmpty()) leaf else "$parent/$leaf"
    private fun depth(path: String): Int = if (path.isEmpty()) 0 else path.count { it == '/' } + 1
}
