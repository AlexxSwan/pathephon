package com.swanlab.audiox64

import android.content.Context
import android.media.MediaMetadataRetriever
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class TagReaderPlugin : FlutterPlugin, MethodCallHandler {
    companion object {
        private const val TAG = "Pathephon/TagReader"
        private const val CHANNEL = "pathephon/tag_reader"
    }

    private var context: Context? = null
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        Log.i(TAG, "onAttachedToEngine")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "readTags" -> {
                val path = call.argument<String>("path") ?: ""
                val uri = call.argument<String>("uri") ?: ""
                if (path.isEmpty() && uri.isEmpty()) {
                    result.error("ERROR", "path or uri required", null)
                    return
                }
                try {
                    val tags = readTags(path, uri)
                    Log.i(TAG, "readTags: path=$path title=${tags["title"]} artist=${tags["artist"]} mime=${tags["mimeType"]}")
                    result.success(tags)
                } catch (e: Exception) {
                    Log.e(TAG, "readTags FAILED: path=$path error=${e.message}", e)
                    result.error("ERROR", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun readTags(path: String, uri: String): Map<String, Any> {
        val mmr = MediaMetadataRetriever()
        val result = mutableMapOf<String, Any>()
        try {
            // Пробуем разные способы установки dataSource
            try {
                if (uri.isNotEmpty() && uri.startsWith("content://")) {
                    val ctx = context ?: return result
                    mmr.setDataSource(ctx, android.net.Uri.parse(uri))
                } else if (path.isNotEmpty()) {
                    mmr.setDataSource(path)
                }
            } catch (e: Exception) {
                Log.w(TAG, "setDataSource failed for path=$path: ${e.message}")
                // Пробуем через contentResolver если есть uri
                if (uri.isNotEmpty()) {
                    val ctx = context ?: return result
                    mmr.setDataSource(ctx, android.net.Uri.parse(uri))
                } else {
                    return result
                }
            }

            val title = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE) ?: ""
            val artist = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST) ?: ""
            val album = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM) ?: ""
            val albumArtist = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST) ?: ""
            val genre = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_GENRE) ?: ""
            val year = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_YEAR) ?: ""
            val trackNumber = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER) ?: ""
            val durationMs = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION) ?: "0"
            val mimeType = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE) ?: ""
            val bitrate = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE) ?: "0"

            Log.i(TAG, "  title=$title artist=$artist album=$album mime=$mimeType dur=$durationMs")

            result["title"] = title
            result["artist"] = artist
            result["album"] = album
            result["albumArtist"] = albumArtist
            result["genre"] = genre
            result["year"] = year
            result["trackNumber"] = trackNumber
            result["durationMs"] = durationMs
            result["mimeType"] = mimeType
            result["bitrate"] = bitrate
        } finally {
            try { mmr.release() } catch (_: Exception) {}
        }
        return result
    }
}