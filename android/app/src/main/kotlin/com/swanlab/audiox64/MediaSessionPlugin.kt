package com.swanlab.audiox64

import android.content.Context
import android.graphics.BitmapFactory
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.SystemClock
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.net.URL
import java.util.concurrent.Executors

class MediaSessionPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    companion object {
        private const val TAG = "Pathephon/MediaSession"
        private const val CHANNEL = "pathephon/native_media_session"
    }
    private var context: Context? = null
    private var channel: MethodChannel? = null
    private var mediaSession: MediaSession? = null
    private val executor = Executors.newSingleThreadExecutor()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.i(TAG, ">>> onAttachedToEngine START")
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
            Log.i(TAG, ">>> MethodChannel '$CHANNEL' registered")
        }
        ensureMediaSession()
        Log.i(TAG, ">>> onAttachedToEngine END — mediaSession=$mediaSession")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.i(TAG, ">>> onDetachedFromEngine")
        try { mediaSession?.release() } catch (e: Exception) {
            Log.w(TAG, "release: ${e.message}")
        }
        mediaSession = null
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        Log.i(TAG, ">>> onMethodCall: ${call.method} args=${call.arguments}")
        try {
            when (call.method) {
                "setMediaItem" -> {
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val album = call.argument<String>("album") ?: ""
                    val durationMs = call.argument<Long>("durationMs") ?: 0L
                    val artUri = call.argument<String>("artUri") ?: ""
                    Log.i(TAG, ">>> setMediaItem: title='$title' artist='$artist' artUri='$artUri'")
                    updateMetadata(title, artist, album, durationMs, artUri)
                    result.success(null)
                }
                "setPlaybackState" -> {
                    val playing = call.argument<Boolean>("playing")
                    val pos = call.argument<Long>("position") ?: 0L
                    val hasNext = call.argument<Boolean>("hasNext") ?: false
                    val hasPrev = call.argument<Boolean>("hasPrev") ?: false
                    Log.i(TAG, ">>> setPlaybackState: playing=$playing pos=$pos next=$hasNext prev=$hasPrev")
                    if (playing != null) {
                        updatePlaybackState(playing, pos, hasNext, hasPrev)
                    }
                    result.success(null)
                }
                else -> {
                    Log.w(TAG, ">>> unknown method: ${call.method}")
                    result.notImplemented()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, ">>> ${call.method} FAILED: ${e.message}", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun ensureMediaSession() {
        if (mediaSession != null) {
            Log.i(TAG, ">>> ensureMediaSession: already exists, skip")
            return
        }
        val ctx = context ?: run {
            Log.e(TAG, ">>> ensureMediaSession: context is null!")
            return
        }
        try {
            Log.i(TAG, ">>> ensureMediaSession: creating MediaSession...")
            val s = MediaSession(ctx, "Pathephon")
            Log.i(TAG, ">>> MediaSession created, setting flags...")
            s.setFlags(
                MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or
                MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS
            )
            Log.i(TAG, ">>> setting callback...")
            s.setCallback(object : MediaSession.Callback() {
                override fun onPlay()  { Log.i(TAG, ">>> BT CALLBACK: onPlay");  channel?.invokeMethod("play",  null) }
                override fun onPause() { Log.i(TAG, ">>> BT CALLBACK: onPause"); channel?.invokeMethod("pause", null) }
                override fun onSkipToNext()     { Log.i(TAG, ">>> BT CALLBACK: onSkipToNext"); channel?.invokeMethod("next", null) }
                override fun onSkipToPrevious() { Log.i(TAG, ">>> BT CALLBACK: onSkipToPrevious"); channel?.invokeMethod("prev", null) }
                override fun onStop()   { Log.i(TAG, ">>> BT CALLBACK: onStop"); channel?.invokeMethod("stop",  null) }
                override fun onSeekTo(pos: Long) {
                    Log.i(TAG, ">>> BT CALLBACK: onSeekTo $pos")
                    channel?.invokeMethod("seek", mapOf("position" to pos))
                }
            })
            Log.i(TAG, ">>> activating session...")
            s.isActive = true
            mediaSession = s
            Log.i(TAG, ">>> MediaSession ACTIVE! session=$s")
        } catch (e: Exception) {
            Log.e(TAG, ">>> ensureMediaSession FAILED: ${e.message}", e)
        }
    }

    private fun updateMetadata(title: String, artist: String, album: String, durationMs: Long, artUri: String) {
        val s = mediaSession ?: run {
            Log.w(TAG, ">>> updateMetadata: mediaSession is null!")
            return
        }
        try {
            Log.i(TAG, ">>> updateMetadata: building metadata...")
            val b = MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
                .putString(MediaMetadata.METADATA_KEY_ALBUM, album)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, durationMs)
            if (artUri.isNotEmpty()) {
                Log.i(TAG, ">>> updateMetadata: loading bitmap async from $artUri")
                executor.execute {
                    try {
                        val bmp = loadBitmap(artUri)
                        if (bmp != null) {
                            Log.i(TAG, ">>> bitmap loaded ${bmp.width}x${bmp.height}")
                            b.putBitmap(MediaMetadata.METADATA_KEY_ART, bmp)
                            b.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, bmp)
                        } else {
                            Log.w(TAG, ">>> bitmap null for $artUri")
                        }
                        s.setMetadata(b.build())
                        Log.i(TAG, ">>> metadata set WITH art: $title")
                    } catch (e: Exception) {
                        Log.e(TAG, ">>> bitmap load failed, set metadata without art", e)
                        s.setMetadata(b.build())
                    }
                }
            } else {
                s.setMetadata(b.build())
                Log.i(TAG, ">>> metadata set WITHOUT art: $title")
            }
        } catch (e: Exception) {
            Log.e(TAG, ">>> updateMetadata FAILED: ${e.message}", e)
        }
    }

    private fun loadBitmap(uri: String): android.graphics.Bitmap? {
        return try {
            when {
                uri.startsWith("file://") -> BitmapFactory.decodeFile(uri.removePrefix("file://"))
                uri.startsWith("content://") -> {
                    val ctx = context ?: return null
                    ctx.contentResolver.openInputStream(android.net.Uri.parse(uri))?.use {
                        BitmapFactory.decodeStream(it)
                    }
                }
                uri.startsWith("http://") || uri.startsWith("https://") -> {
                    URL(uri).openStream().use { BitmapFactory.decodeStream(it) }
                }
                else -> null
            }
        } catch (e: Exception) {
            Log.w(TAG, ">>> loadBitmap($uri) failed: ${e.message}")
            null
        }
    }

    private fun updatePlaybackState(playing: Boolean, posMs: Long, hasNext: Boolean, hasPrev: Boolean) {
        val s = mediaSession ?: run {
            Log.w(TAG, ">>> updatePlaybackState: mediaSession is null!")
            return
        }
        try {
            val state = if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED
            val actions = (
                PlaybackState.ACTION_PLAY or
                PlaybackState.ACTION_PAUSE or
                PlaybackState.ACTION_PLAY_PAUSE or
                PlaybackState.ACTION_STOP or
                PlaybackState.ACTION_SEEK_TO or
                (if (hasNext) PlaybackState.ACTION_SKIP_TO_NEXT else 0L) or
                (if (hasPrev) PlaybackState.ACTION_SKIP_TO_PREVIOUS else 0L)
            )
            s.setPlaybackState(
                PlaybackState.Builder()
                    .setActions(actions)
                    .setState(state, posMs, 1.0f, SystemClock.elapsedRealtime())
                    .build()
            )
            Log.i(TAG, ">>> PlaybackState SET: state=$state pos=$posMs next=$hasNext prev=$hasPrev")
        } catch (e: Exception) {
            Log.e(TAG, ">>> updatePlaybackState FAILED: ${e.message}", e)
        }
    }
}