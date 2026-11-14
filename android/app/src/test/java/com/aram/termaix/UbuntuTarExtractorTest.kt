package com.aram.termaix

import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveOutputStream
import org.apache.commons.compress.archivers.tar.TarConstants
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.nio.file.LinkOption
import java.util.zip.GZIPOutputStream
import java.io.FileOutputStream

class UbuntuTarExtractorTest {
    private data class Entry(val tar: TarArchiveEntry, val bytes: ByteArray = ByteArray(0))

    private fun regular(path: String, content: String, mode: Int = 0x1A4) = Entry(
        TarArchiveEntry(path).apply { size = content.toByteArray().size.toLong(); this.mode = mode },
        content.toByteArray()
    )

    private fun link(path: String, target: String, flag: Byte) = Entry(
        TarArchiveEntry(path, flag).apply { linkName = target; mode = 0x1A4 }
    )

    private fun makeArchive(dir: File, entries: List<Entry>): File {
        val file = File(dir, "ubuntu.tar.gz")
        GZIPOutputStream(FileOutputStream(file)).use { gzip ->
            TarArchiveOutputStream(gzip).use { tar ->
                tar.setLongFileMode(TarArchiveOutputStream.LONGFILE_POSIX)
                for (entry in entries) {
                    tar.putArchiveEntry(entry.tar)
                    if (entry.bytes.isNotEmpty()) tar.write(entry.bytes)
                    tar.closeArchiveEntry()
                }
                tar.finish()
            }
        }
        return file
    }

    private fun root(dir: File) = File(dir, "root").apply { mkdirs() }

    @Test fun hardLinksWorkWhenTargetAppearsLaterAndEarlier() {
        val dir = Files.createTempDirectory("ubuntu-hardlinks").toFile()
        val archive = makeArchive(dir, listOf(
            link("usr/bin/perl", "usr/bin/perl5.38.2", TarConstants.LF_LINK),
            regular("usr/bin/perl5.38.2", "perl-data"),
            regular("usr/bin/gunzip", "gzip-data"),
            link("usr/bin/uncompress", "usr/bin/gunzip", TarConstants.LF_LINK)
        ))
        val out = root(dir)
        UbuntuTarExtractor.extract(archive, out)
        assertEquals("perl-data", File(out, "usr/bin/perl").readText())
        assertEquals("perl-data", File(out, "usr/bin/perl5.38.2").readText())
        assertEquals("gzip-data", File(out, "usr/bin/uncompress").readText())
        assertEquals("gzip-data", File(out, "usr/bin/gunzip").readText())
    }

    @Test fun binSymlinkRedirectsFilesAndNestedSymlinks() {
        val dir = Files.createTempDirectory("ubuntu-bin-link").toFile()
        val archive = makeArchive(dir, listOf(
            link("bin", "usr/bin", TarConstants.LF_SYMLINK),
            link("bin/sh", "bash", TarConstants.LF_SYMLINK),
            regular("bin/bash", "bash-elf", 0x1ED)
        ))
        val out = root(dir)
        UbuntuTarExtractor.extract(archive, out)
        assertTrue(Files.isSymbolicLink(File(out, "bin").toPath()))
        assertEquals("usr/bin", Files.readSymbolicLink(File(out, "bin").toPath()).toString())
        assertEquals("bash-elf", File(out, "usr/bin/bash").readText())
        assertTrue(File(out, "usr/bin/bash").canExecute())
        assertTrue(Files.isSymbolicLink(File(out, "usr/bin/sh").toPath()))
        assertEquals("bash", Files.readSymbolicLink(File(out, "usr/bin/sh").toPath()).toString())
    }

    @Test fun absoluteGuestSymlinkKeepsItsRootRelativeLoaderTarget() {
        val dir = Files.createTempDirectory("ubuntu-absolute-link").toFile()
        val archive = makeArchive(dir, listOf(
            regular("lib/ld-linux-aarch64.so.1", "loader-payload"),
            link("lib64/ld-linux-aarch64.so.1", "/lib/ld-linux-aarch64.so.1", TarConstants.LF_SYMLINK)
        ))
        val out = root(dir)
        UbuntuTarExtractor.extract(archive, out)
        val linkPath = File(out, "lib64/ld-linux-aarch64.so.1").toPath()
        assertTrue(Files.isSymbolicLink(linkPath))
        assertEquals("/lib/ld-linux-aarch64.so.1", Files.readSymbolicLink(linkPath).toString())

        // Android must not dereference the absolute link from the host root.
        // Confirm the link's intended target exists under the Ubuntu guest root.
        val guestTarget = File(out, "lib/ld-linux-aarch64.so.1")
        assertTrue(guestTarget.isFile)
        assertEquals("loader-payload", guestTarget.readText())
    }

    @Test fun rejectsTraversalAndAbsoluteEntryNames() {
        val cases = listOf(
            listOf(regular("../escape", "bad")),
            listOf(Entry(TarArchiveEntry("/absolute", TarConstants.LF_NORMAL, true).apply { size = 4 }, "bad!".toByteArray()))
        )
        for ((index, entries) in cases.withIndex()) {
            val dir = Files.createTempDirectory("ubuntu-path-$index").toFile()
            val archive = makeArchive(dir, entries)
            val out = root(dir)
            var rejected = false
            try { UbuntuTarExtractor.extract(archive, out) } catch (_: IllegalArgumentException) { rejected = true }
            assertTrue("unsafe archive path was accepted", rejected)
            assertFalse(File(dir, "escape").exists())
            assertFalse(File(dir, "absolute").exists())
        }
    }

    @Test fun rejectsSymlinkTargetEscapingGuestRoot() {
        val dir = Files.createTempDirectory("ubuntu-link-escape").toFile()
        val archive = makeArchive(dir, listOf(
            link("etc/escape", "../../../../outside", TarConstants.LF_SYMLINK)
        ))
        var rejected = false
        try { UbuntuTarExtractor.extract(archive, root(dir)) } catch (_: IllegalArgumentException) { rejected = true }
        assertTrue("escaping symlink was accepted", rejected)
        assertFalse(File(dir, "outside").exists())
    }

    @Test fun rejectsHardLinkTargetTraversalAndMissingTargets() {
        val dir = Files.createTempDirectory("ubuntu-hardlink-invalid").toFile()
        val archive = makeArchive(dir, listOf(
            link("usr/bin/escape", "../../../../outside", TarConstants.LF_LINK)
        ))
        var rejected = false
        try { UbuntuTarExtractor.extract(archive, root(dir)) } catch (_: IllegalArgumentException) { rejected = true }
        assertTrue("traversing hard link was accepted", rejected)
        assertFalse(File(dir, "outside").exists())

        val missingDir = Files.createTempDirectory("ubuntu-hardlink-missing").toFile()
        val missingArchive = makeArchive(missingDir, listOf(
            link("usr/bin/missing", "usr/bin/no-such-target", TarConstants.LF_LINK)
        ))
        rejected = false
        try { UbuntuTarExtractor.extract(missingArchive, root(missingDir)) }
        catch (_: IllegalArgumentException) { rejected = true }
        assertTrue("missing hard-link target was accepted", rejected)
    }
}
