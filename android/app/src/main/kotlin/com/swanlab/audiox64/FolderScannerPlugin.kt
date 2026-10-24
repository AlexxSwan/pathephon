package com.swanlab.audiox64

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger

/// Native folder scanner using Storage Access Framework (SAF).
class FolderScannerPlugin(binaryMessenger: BinaryMessenger, private val context: Context) {
    private val methodChannel = MethodChannel(binaryMessenger, "pathephon/folder_scanner")

    init {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFolder" -> {
                    val treeUriStr = call.argument<String>("treeUri") ?: ""
                    Log.i("FolderScanner", "scanFolder called with: '$treeUriStr'")
                    try {
                        val files = scanFolder(treeUriStr)
                        Log.i("FolderScanner", "returning ${files.size} files")
                        result.success(files)
                    } catch (e: Exception) {
                        Log.e("FolderScanner", "scanFolder FAILED: ${e.message}", e)
                        result.error("SCAN_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private val audioExtensions = setOf(
        "mp3", "flac", "wav", "ogg", "opus", "aac", "m4a", "alac",
        "ape", "wv", "tta", "mpc", "mod", "s3m", "xm", "it",
        "dsf", "dsd", "dff", "amr", "3gp", "m4b", "mka", "ofr", "spx"
    )

    private val coverBases = setOf(
        "cover", "folder", "album", "front", "albumart", "coverart", "art"
    )
    private val coverExtensions = setOf("jpg", "jpeg", "png", "webp")

    private fun scanFolder(treeUriStr: String): List<Map<String, Any>> {
        if (treeUriStr.isEmpty()) {
            throw IllegalArgumentException("treeUri is empty")
        }
        Log.i("FolderScanner", "raw treeUri: $treeUriStr")

        // Decode URL-encoded characters (%3A -> :, %2F -> /)
        val decodedUri = android.net.Uri.decode(treeUriStr)
        Log.i("FolderScanner", "decoded treeUri: $decodedUri")

        // Parse the URI
        val treeUri = Uri.parse(decodedUri)
        Log.i("FolderScanner", "parsed treeUri: $treeUri")
        Log.i("FolderScanner", "  authority: ${treeUri.authority}")
        Log.i("FolderScanner", "  scheme: ${treeUri.scheme}")

        // Try fromTreeUri - this is the standard way
        val treeDir = DocumentFile.fromTreeUri(context, treeUri)
        if (treeDir == null) {
            Log.e("FolderScanner", "DocumentFile.fromTreeUri returned NULL")
            throw IllegalArgumentException("cannot access tree URI - fromTreeUri returned null")
        }
        Log.i("FolderScanner", "treeDir exists: ${treeDir.exists()}, isDirectory: ${treeDir.isDirectory}, canRead: ${treeDir.canRead()}")

        if (!treeDir.isDirectory) {
            Log.e("FolderScanner", "not a directory")
            throw IllegalArgumentException("not a directory")
        }
        if (!treeDir.canRead()) {
            Log.e("FolderScanner", "cannot read directory")
            throw IllegalArgumentException("no read permission")
        }

        val children = treeDir.listFiles()
        Log.i("FolderScanner", "found ${children.size} entries")

        // Log first few entries for debugging
        var logged = 0
        for (child in children) {
            if (logged < 5) {
                Log.i("FolderScanner", "  entry: name='${child.name}', isFile=${child.isFile}, isDirectory=${child.isDirectory}")
                logged++
            }
        }

        // First pass: find cover art
        var coverUri: String? = null
        for (child in children) {
            if (!child.isFile) continue
            val name = child.name?.lowercase() ?: continue
            val dotIdx = name.lastIndexOf('.')
            if (dotIdx < 0) continue
            val base = name.substring(0, dotIdx)
            val ext = name.substring(dotIdx + 1)
            if (coverExtensions.contains(ext)) {
                if (coverBases.contains(base) || base.startsWith("cover") ||
                    base.startsWith("folder") || base.startsWith("album") ||
                    base.startsWith("front")) {
                    coverUri = child.uri.toString()
                    Log.i("FolderScanner", "found cover: $coverUri")
                    break
                }
            }
        }
        if (coverUri == null) {
            for (child in children) {
                if (!child.isFile) continue
                val name = child.name?.lowercase() ?: continue
                val dotIdx = name.lastIndexOf('.')
                if (dotIdx < 0) continue
                val base = name.substring(0, dotIdx)
                val ext = name.substring(dotIdx + 1)
                if (coverExtensions.contains(ext) &&
                    !base.startsWith("artist") && !base.startsWith("back")) {
                    coverUri = child.uri.toString()
                    Log.i("FolderScanner", "found fallback cover: $coverUri")
                    break
                }
            }
        }

        // Second pass: collect audio files
        val audioFiles = mutableListOf<Pair<String, DocumentFile>>()
        for (child in children) {
            if (!child.isFile) continue
            val name = child.name ?: continue
            val dotIdx = name.lastIndexOf('.')
            if (dotIdx < 0) continue
            val ext = name.substring(dotIdx + 1).lowercase()
            if (!audioExtensions.contains(ext)) continue
            audioFiles.add(Pair(name, child))
        }
        audioFiles.sortBy { it.first.lowercase() }
        Log.i("FolderScanner", "found ${audioFiles.size} audio files")

        val result = mutableListOf<Map<String, Any>>()
        for ((name, doc) in audioFiles) {
            val uri = doc.uri.toString()
            val map = mutableMapOf<String, Any>(
                "uri" to uri,
                "name" to name,
                "size" to (doc.length()),
                "lastModified" to (doc.lastModified())
            )
            if (coverUri != null) {
                map["artUri"] = coverUri
            }
            result.add(map)
        }
        return result
    }
}