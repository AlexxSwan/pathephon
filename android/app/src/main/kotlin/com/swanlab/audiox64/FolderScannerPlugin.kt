package com.swanlab.audiox64

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger

/// Native folder scanner using Storage Access Framework (SAF).
///
/// On Android 11+ FilePicker.getDirectoryPath() returns a SAF tree URI like
/// "content://com.android.externalstorage.documents/tree/primary%3AMusic".
/// dart:io Directory cannot list such URIs. We use DocumentFile API here to
/// enumerate files in the picked folder, returning audio file URIs that
/// just_audio can play directly.
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
        Log.i("FolderScanner", "scanning tree URI: $treeUriStr")

        val treeUri = Uri.parse(treeUriStr)
        val treeDir = DocumentFile.fromTreeUri(context, treeUri)
            ?: throw IllegalArgumentException("cannot access tree URI")

        if (!treeDir.isDirectory) {
            throw IllegalArgumentException("not a directory")
        }

        val children = treeDir.listFiles()
        Log.i("FolderScanner", "found ${children.size} entries")

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
        // If no standard cover found, take any image (except artist/back)
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

        // Second pass: collect audio files, sort by name
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

        // Build result list of maps
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