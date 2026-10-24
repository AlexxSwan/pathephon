package com.swanlab.audiox64

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import java.io.InputStream

/// Native folder scanner using Storage Access Framework (SAF).
/// RECURSIVE: scans all subfolders. Each audio file gets its own
/// cover art URI from its parent folder (so different albums show
/// different covers).
class FolderScannerPlugin(binaryMessenger: BinaryMessenger, private val context: Context) {
    private val methodChannel = MethodChannel(binaryMessenger, "pathephon/folder_scanner")

    init {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFolder" -> {
                    val treeUriStr = call.argument<String>("treeUri") ?: ""
                    try {
                        val files = scanFolder(treeUriStr)
                        result.success(files)
                    } catch (e: Exception) {
                        Log.e("FolderScanner", "scanFolder failed: ${e.message}", e)
                        result.error("SCAN_FAILED", e.message, null)
                    }
                }
                "readFileBytes" -> {
                    val uriStr = call.argument<String>("uri") ?: ""
                    try {
                        val bytes = readFileBytes(uriStr)
                        result.success(bytes)
                    } catch (e: Exception) {
                        result.error("READ_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private val audioExtensions = setOf(
        "mp3", "flac", "wav", "ogg", "opus", "aac", "m4a", "alac",
        "ape", "wv", "tta", "mpc", "mod", "s3m", "xm", "it",
        "dsf", "dsd", "dff", "amr", "3gp", "m4b", "mka", "ofr", "spx",
        "mp2", "mid", "midi", "aiff", "aif", "wma", "asf"
    )

    private val coverBases = setOf(
        "cover", "folder", "album", "front", "albumart", "coverart", "art"
    )
    private val coverExtensions = setOf("jpg", "jpeg", "png", "webp")

    private fun readFileBytes(uriStr: String): ByteArray {
        val uri = Uri.parse(uriStr)
        val inputStream: InputStream = context.contentResolver.openInputStream(uri)
            ?: throw IllegalArgumentException("cannot open input stream for URI: $uriStr")
        return inputStream.use { it.readBytes() }
    }

    /// Find cover art in a specific DocumentFile directory.
    /// Returns the cover's URI string, or null if not found.
    private fun findCoverInDir(dir: DocumentFile): String? {
        val children = dir.listFiles()
        val byName = mutableMapOf<String, DocumentFile>()
        for (child in children) {
            if (!child.isFile) continue
            val name = child.name?.lowercase() ?: continue
            byName[name] = child
        }
        // Standard names
        for (base in coverBases) {
            for (ext in coverExtensions) {
                byName["$base.$ext"]?.let { return it.uri.toString() }
            }
        }
        // Files starting with cover/folder/album/front
        for ((name, doc) in byName) {
            val dotIdx = name.lastIndexOf('.')
            if (dotIdx < 0) continue
            val baseName = name.substring(0, dotIdx)
            val ext = name.substring(dotIdx + 1)
            if (coverExtensions.contains(ext) &&
                (baseName.startsWith("cover") || baseName.startsWith("folder") ||
                 baseName.startsWith("album") || baseName.startsWith("front"))) {
                return doc.uri.toString()
            }
        }
        // Any image file (except artist.*/back.*)
        for ((name, doc) in byName) {
            val dotIdx = name.lastIndexOf('.')
            if (dotIdx < 0) continue
            val baseName = name.substring(0, dotIdx)
            val ext = name.substring(dotIdx + 1)
            if (coverExtensions.contains(ext) &&
                !baseName.startsWith("artist") && !baseName.startsWith("back")) {
                return doc.uri.toString()
            }
        }
        return null
    }

    /// RECURSIVE scan: walks all subfolders, collects audio files.
    /// Each audio file gets its own cover URI from its parent folder.
    private fun scanFolder(treeUriStr: String): List<Map<String, Any>> {
        if (treeUriStr.isEmpty()) throw IllegalArgumentException("treeUri is empty")
        val treeUri = Uri.parse(treeUriStr)
        val rootDir = DocumentFile.fromTreeUri(context, treeUri)
            ?: throw IllegalArgumentException("cannot access tree URI")
        if (!rootDir.isDirectory) throw IllegalArgumentException("not a directory")

        val result = mutableListOf<Map<String, Any>>()
        val dirCoverCache = mutableMapOf<String, String?>()

        // Recursive walker
        fun walk(dir: DocumentFile, depth: Int) {
            if (depth > 10) return  // Safety limit
            val children = dir.listFiles()
            // Find cover for THIS folder (cache by uri)
            val dirKey = dir.uri.toString()
            val coverUri = dirCoverCache.getOrPut(dirKey) { findCoverInDir(dir) }

            for (child in children) {
                if (child.isDirectory) {
                    walk(child, depth + 1)
                } else if (child.isFile) {
                    val name = child.name ?: continue
                    val dotIdx = name.lastIndexOf('.')
                    if (dotIdx < 0) continue
                    val ext = name.substring(dotIdx + 1).lowercase()
                    if (!audioExtensions.contains(ext)) continue

                    val map = mutableMapOf<String, Any>(
                        "uri" to child.uri.toString(),
                        "name" to name,
                        "size" to child.length(),
                        "lastModified" to child.lastModified()
                    )
                    coverUri?.let { map["artUri"] = it }
                    result.add(map)
                }
            }
        }

        walk(rootDir, 0)

        // Sort by name (full path order would be better, but name works for MVP)
        result.sortBy { it["name"] as String }

        Log.i("FolderScanner", "Recursive scan: ${result.size} audio files found")
        return result
    }
}