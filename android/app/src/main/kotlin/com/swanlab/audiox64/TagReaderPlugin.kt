package com.swanlab.audiox64

import android.content.Context
import android.media.MediaMetadataRetriever
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/// Читает теги (ID3/Vorbis/MP4) из медиафайлов через MediaMetadataRetriever.
/// Поддерживает: mp3, flac, ogg, m4a, aac, wav, opus и др.
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
                    result.success(tags)
                } catch (e: Exception) {
                    Log.e(TAG, "readTags failed: ${'$'}{e.message}", e)
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
            if (uri.isNotEmpty()) {
                val ctx = context ?: return result
                mmr.setDataSource(ctx, android.net.Uri.parse(uri))
            } else {
                mmr.setDataSource(path)
            }

            result["title"] = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE) ?: ""
            result["artist"] = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST) ?: ""
            result["album"] = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM) ?: ""
            result["albumArtist"] = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST) ?: ""
            result["genre"] = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_GENRE) ?: ""
            result["year"] = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_YEAR) ?: ""
            result["trackNumber"] = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER) ?: ""
            result["durationMs"] = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION) ?: "0"
            result["mimeType"] = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE) ?: ""
            result["bitrate"] = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE) ?: "0"
        } finally {
            mmr.release()
        }
        return result
    }
}