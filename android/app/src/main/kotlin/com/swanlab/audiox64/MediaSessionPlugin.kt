package com.swanlab.audiox64

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.SystemClock
import android.util.Log
import android.view.KeyEvent
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
        }
        ensureMediaSession()
        Log.i(TAG, ">>> onAttachedToEngine END")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        try { mediaSession?.release() } catch (e: Exception) {}
        mediaSession = null
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    /// Helper: getInt — Flutter MethodChannel передаёт Dart int как java.lang.Integer,
    /// НЕ Long. Поэтому call.argument<Long> падает с ClassCastException.
    /// Используем Number и toLong() чтобы работать с обоими.
    private fun getInt(call: MethodCall, key: String, default: Long = 0L): Long {
        val v = call.argument<Number>(key) ?: return default
        return v.toLong()
    }

    private fun getBool(call: MethodCall, key: String, default: Boolean = false): Boolean {
        return call.argument<Boolean>(key) ?: default
    }

    private fun getString(call: MethodCall, key: String, default: String = ""): String {
        return call.argument<String>(key) ?: default
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                "setMediaItem" -> {
                    val title = getString(call, "title")
                    val artist = getString(call, "artist")
                    val album = getString(call, "album")
                    val durationMs = getInt(call, "durationMs")
                    val artUri = getString(call, "artUri")
                    val artBytes = call.argument<ByteArray>("artBytes")
                    Log.i(TAG, ">>> setMediaItem: title='$title' artist='$artist' dur=$durationMs artUri='$artUri' hasArtBytes=${artBytes != null}")
                    updateMetadata(title, artist, album, durationMs, artUri, artBytes)
                    result.success(null)
                }
                "setPlaybackState" -> {
                    val playing = getBool(call, "playing")
                    val pos = getInt(call, "position")
                    val hasNext = getBool(call, "hasNext")
                    val hasPrev = getBool(call, "hasPrev")
                    Log.i(TAG, ">>> setPlaybackState: playing=$playing pos=$pos next=$hasNext prev=$hasPrev")
                    updatePlaybackState(playing, pos, hasNext, hasPrev)
                    result.success(null)
                }
                "reclaimPriority" -> {
                    // Phase 42: called from Dart on every track change.
                    // Aggressively re-claims MediaSession priority from MAX.
                    reclaimPriority()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, ">>> onMethodCall ${call.method} FAILED: ${e.message}", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun ensureMediaSession() {
        if (mediaSession != null) return
        val ctx = context ?: return
        try {
            Log.i(TAG, ">>> creating MediaSession 'Pathephon'...")
            val s = MediaSession(ctx, "Pathephon")
            s.setFlags(
                MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or
                MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS
            )
            s.setCallback(object : MediaSession.Callback() {
                // onMediaButtonEvent removed — system routes to direct callbacks
                override fun onPlay()  { invokeDart("play_pause") }
                override fun onPause() { invokeDart("pause") }
                override fun onSkipToNext()     { invokeDart("next") }
                override fun onSkipToPrevious() { invokeDart("prev") }
                override fun onStop()   { invokeDart("stop") }
                override fun onSeekTo(pos: Long) {
                    channel?.invokeMethod("seek", mapOf("position" to pos))
                }
            })
            s.isActive = true
            // Phase 41: setMediaButtonReceiver — Tells the system to route
            // media-button events to PathephonMediaButtonReceiver when this
            // session is the priority one. Needed so that smartwatch / HID
            // button broadcasts wake Pathephon instead of going to MAX (ru.oneme.app).
            try {
                val mbIntent = Intent(Intent.ACTION_MEDIA_BUTTON)
                mbIntent.setClass(ctx, PathephonMediaButtonReceiver::class.java)
                val pi = PendingIntent.getBroadcast(
                    ctx, 0, mbIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                s.setMediaButtonReceiver(pi)
                Log.i(TAG, ">>> setMediaButtonReceiver OK")
            } catch (e: Exception) {
                Log.w(TAG, ">>> setMediaButtonReceiver failed: ${e.message}")
            }
            mediaSession = s
            Log.i(TAG, ">>> MediaSession 'Pathephon' ACTIVE")
            // Пушим начальный пустой state чтобы система увидела сессию готовой
            updatePlaybackState(false, 0L, false, false)
        } catch (e: Exception) {
            Log.e(TAG, ">>> ensureMediaSession FAILED: ${e.message}", e)
        }
    }

    private fun handleKeyCode(keyCode: Int) {
        val cmd = when (keyCode) {
            KeyEvent.KEYCODE_MEDIA_PLAY,
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> "play_pause"
            KeyEvent.KEYCODE_MEDIA_PAUSE -> "pause"
            KeyEvent.KEYCODE_MEDIA_NEXT -> "next"
            KeyEvent.KEYCODE_MEDIA_PREVIOUS -> "prev"
            KeyEvent.KEYCODE_MEDIA_STOP -> "stop"
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> "fast_forward"
            KeyEvent.KEYCODE_MEDIA_REWIND -> "rewind"
            else -> {
                Log.w(TAG, ">>> unknown keyCode: $keyCode")
                return
            }
        }
        Log.i(TAG, ">>> handleKeyCode: $cmd")
        invokeDart(cmd)
    }

    private fun invokeDart(method: String) {
        Log.i(TAG, ">>> invoking Dart '$method'")
        channel?.invokeMethod(method, null, object : MethodChannel.Result {
            override fun success(result: Any?) { Log.i(TAG, ">>> '$method' OK") }
            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                Log.e(TAG, ">>> '$method' ERROR: $errorCode / $errorMessage")
            }
            override fun notImplemented() { Log.w(TAG, ">>> '$method' notImplemented") }
        })
    }

    private fun keyCodeToString(code: Int): String = when (code) {
        KeyEvent.KEYCODE_MEDIA_PLAY -> "PLAY"
        KeyEvent.KEYCODE_MEDIA_PAUSE -> "PAUSE"
        KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> "PLAY_PAUSE"
        KeyEvent.KEYCODE_MEDIA_NEXT -> "NEXT"
        KeyEvent.KEYCODE_MEDIA_PREVIOUS -> "PREVIOUS"
        KeyEvent.KEYCODE_MEDIA_STOP -> "STOP"
        KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> "FAST_FORWARD"
        KeyEvent.KEYCODE_MEDIA_REWIND -> "REWIND"
        else -> "UNKNOWN($code)"
    }

    private fun updateMetadata(title: String, artist: String, album: String, durationMs: Long, artUri: String, artBytes: ByteArray? = null) {
        val s = mediaSession ?: return
        try {
            val b = MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
                .putString(MediaMetadata.METADATA_KEY_ALBUM, album)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, durationMs)
            if (artUri.isNotEmpty()) {
                executor.execute {
                    try {
                        val bmp = loadBitmap(artUri)
                        if (bmp != null) {
                            b.putBitmap(MediaMetadata.METADATA_KEY_ART, bmp)
                            b.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, bmp)
                            Log.i(TAG, ">>> metadata set WITH art: $title / $artist")
                        } else {
                            Log.i(TAG, ">>> metadata set WITHOUT art (bmp null): $title")
                        }
                        s.setMetadata(b.build())
                    } catch (e: Exception) {
                        Log.e(TAG, ">>> metadata bitmap failed: ${e.message}")
                        s.setMetadata(b.build())
                    }
                }
            } else if (artBytes != null) {
                executor.execute {
                    try {
                        val bmp = BitmapFactory.decodeByteArray(artBytes, 0, artBytes.size)
                        if (bmp != null) { b.putBitmap(MediaMetadata.METADATA_KEY_ART, bmp); b.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, bmp); Log.i(TAG, ">>> metadata set WITH embedded art: $title") }
                        s.setMetadata(b.build())
                    } catch (e: Exception) { Log.e(TAG, ">>> embedded art decode failed: ${e.message}"); s.setMetadata(b.build()) }
                }
            } else {
                executor.execute {
                    try {
                        val gifBmp = loadAssetBitmap("pathephon_fallback.png")
                        if (gifBmp != null) {
                            b.putBitmap(MediaMetadata.METADATA_KEY_ART, gifBmp)
                            b.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, gifBmp)
                        }
                        s.setMetadata(b.build())
                        Log.i(TAG, ">>> metadata set (no artUri, used gif): $title")
                    } catch (e: Exception) {
                        s.setMetadata(b.build())
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "updateMetadata: ${e.message}", e)
        }
    }

    private fun loadAssetBitmap(name: String): android.graphics.Bitmap? {
        return try {
            val assetManager = context?.assets ?: return null
            val input = assetManager.open("flutter_assets/assets/$name")
            BitmapFactory.decodeStream(input).also { input.close() }
        } catch (e: Exception) {
            null
        }
    }
    private fun loadBitmap(uri: String): android.graphics.Bitmap? {
        return try {
            when {
                uri.startsWith("file://") -> {
                    // URL-decode путь (file:///storage/.../Viva%20la%20Vida/cover.jpg → .../Viva la Vida/cover.jpg)
                    val rawPath = uri.removePrefix("file://")
                    val decodedPath = android.net.Uri.decode(rawPath)
                    Log.i(TAG, ">>> loadBitmap file: raw='$rawPath' decoded='$decodedPath'")
                    val file = java.io.File(decodedPath)
                    if (!file.exists()) {
                        Log.w(TAG, ">>> file not found: $decodedPath")
                        return null
                    }
                    BitmapFactory.decodeFile(decodedPath)
                }
                uri.startsWith("content://") -> {
                    val ctx = context ?: return null
                    val decodedUri = android.net.Uri.decode(uri)
                    ctx.contentResolver.openInputStream(android.net.Uri.parse(decodedUri))?.use {
                        BitmapFactory.decodeStream(it)
                    }
                }
                uri.startsWith("http://") || uri.startsWith("https://") -> {
                    URL(uri).openStream().use { BitmapFactory.decodeStream(it) }
                }
                else -> {
                    Log.w(TAG, ">>> loadBitmap unknown scheme: $uri")
                    null
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, ">>> loadBitmap FAILED: ${e.message}", e)
            null
        }
    }

    /// Phase 42: Aggressively re-claim MediaSession priority.
    /// Called from Dart on every track change (auto-advance or manual next/prev).
    /// Does MORE than just setActive(true):
    ///   1. Toggle isActive false -> true (forces system to re-evaluate)
    ///   2. Re-set flags (in case they were cleared by the system)
    ///   3. Re-set MediaButtonReceiver PendingIntent (in case it was dropped)
    /// This is needed because on ColorOS, MAX (ru.oneme.app) steals priority
    /// when it receives a message, and a simple setActive(true) doesn't override it.
    private fun reclaimPriority() {
        val s = mediaSession ?: return
        val ctx = context ?: return
        try {
            try { s.isActive = false } catch (_: Exception) {}
            try { s.isActive = true } catch (_: Exception) {}
            try {
                s.setFlags(
                    MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS
                )
            } catch (_: Exception) {}
            try {
                val mbIntent = Intent(Intent.ACTION_MEDIA_BUTTON)
                mbIntent.setClass(ctx, PathephonMediaButtonReceiver::class.java)
                val pi = PendingIntent.getBroadcast(
                    ctx, 0, mbIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                s.setMediaButtonReceiver(pi)
            } catch (_: Exception) {}
            Log.i(TAG, ">>> reclaimPriority: toggled isActive + re-set flags + re-set MediaButtonReceiver")
        } catch (e: Exception) {
            Log.e(TAG, ">>> reclaimPriority FAILED: ${e.message}", e)
        }
    }

    private fun updatePlaybackState(playing: Boolean, posMs: Long, hasNext: Boolean, hasPrev: Boolean) {
        val s = mediaSession ?: return
        try {
            // Phase 41: Re-claim media-session priority on every playing=true
            // state push. Without this, MAX (ru.oneme.app) steals priority
            // when it receives a message and the smartwatch buttons stop
            // controlling Pathephon. Calling setActive(true) again puts
            // Pathephon back at the top of the priority stack.
            if (playing) {
                try { s.isActive = true } catch (_: Exception) {}
            }
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
            Log.e(TAG, "updatePlaybackState: ${e.message}", e)
        }
    }
}