package com.swanlab.audiox64

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/// Native MediaSession + notification for lock screen controls.
///
/// Creates a MediaSession, updates metadata + playback state, shows a
/// notification with transport controls, and handles media button events
/// (headset, Bluetooth, lock screen).
class MediaSessionHelper(
    binaryMessenger: BinaryMessenger,
    private val context: Context
) {
    private val methodChannel = MethodChannel(binaryMessenger, "pathephon/media_session")
    private val eventChannel = EventChannel(binaryMessenger, "pathephon/media_session/events")
    private var eventSink: EventChannel.EventSink? = null

    private var mediaSession: MediaSession? = null
    private var notificationManager: NotificationManager? = null
    private var isRegistered = false

    companion object {
        private const val CHANNEL_ID = "pathephon_playback"
        private const val NOTIFICATION_ID = 1
        private const val ACTION_PLAY = "pathephon.PLAY"
        private const val ACTION_PAUSE = "pathephon.PAUSE"
        private const val ACTION_NEXT = "pathephon.NEXT"
        private const val ACTION_PREV = "pathephon.PREV"
        private const val ACTION_STOP = "pathephon.STOP"
    }

    init {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    startSession()
                    result.success(true)
                }
                "updateMetadata" -> {
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val album = call.argument<String>("album") ?: ""
                    val durationMs = call.argument<Long>("durationMs") ?: 0L
                    updateMetadata(title, artist, album, durationMs)
                    result.success(null)
                }
                "updatePlaybackState" -> {
                    val state = call.argument<String>("state") ?: "stopped"
                    val positionMs = call.argument<Long>("positionMs") ?: 0L
                    updatePlaybackState(state, positionMs)
                    result.success(null)
                }
                "stop" -> {
                    stopSession()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                eventSink = sink
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    private fun startSession() {
        try {
            // Create notification channel (required Android 8+)
            if (notificationManager == null) {
                notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Pathephon Playback",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Media playback controls"
                    setShowBadge(false)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
                notificationManager?.createNotificationChannel(channel)
            }

            // Create MediaSession
            mediaSession = MediaSession(context, "Pathephon").apply {
                setFlags(
                    MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS
                )

                // Handle transport callbacks from headset/Bluetooth/lock screen
                setCallback(object : MediaSession.Callback() {
                    override fun onPlay() {
                        Log.i("MediaSession", "onPlay (from headset/lockscreen)")
                        eventSink?.success("play")
                    }
                    override fun onPause() {
                        Log.i("MediaSession", "onPause (from headset/lockscreen)")
                        eventSink?.success("pause")
                    }
                    override fun onSkipToNext() {
                        Log.i("MediaSession", "onSkipToNext")
                        eventSink?.success("next")
                    }
                    override fun onSkipToPrevious() {
                        Log.i("MediaSession", "onSkipToPrevious")
                        eventSink?.success("prev")
                    }
                    override fun onStop() {
                        Log.i("MediaSession", "onStop")
                        eventSink?.success("stop")
                    }
                    override fun onSeekTo(pos: Long) {
                        Log.i("MediaSession", "onSeekTo $pos")
                        eventSink?.success("seek:$pos")
                    }
                })

                isActive = true
            }

            // Register broadcast receiver for media button actions
            if (!isRegistered) {
                val filter = IntentFilter().apply {
                    addAction(ACTION_PLAY)
                    addAction(ACTION_PAUSE)
                    addAction(ACTION_NEXT)
                    addAction(ACTION_PREV)
                    addAction(ACTION_STOP)
                }
                context.registerReceiver(mediaButtonReceiver, filter)
                isRegistered = true
            }

            Log.i("MediaSession", "Session started successfully")
        } catch (e: Exception) {
            Log.e("MediaSession", "startSession failed: ${e.message}", e)
        }
    }

    private fun updateMetadata(title: String, artist: String, album: String, durationMs: Long) {
        try {
            val metadata = android.media.MediaMetadata.Builder()
                .putString(android.media.MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(android.media.MediaMetadata.METADATA_KEY_ARTIST, artist)
                .putString(android.media.MediaMetadata.METADATA_KEY_ALBUM, album)
                .putLong(android.media.MediaMetadata.METADATA_KEY_DURATION, durationMs)
                .build()
            mediaSession?.setMetadata(metadata)
            Log.i("MediaSession", "Metadata updated: $title - $artist")
        } catch (e: Exception) {
            Log.e("MediaSession", "updateMetadata failed: ${e.message}", e)
        }
    }

    private fun updatePlaybackState(state: String, positionMs: Long) {
        try {
            val playbackState = when (state) {
                "playing" -> PlaybackState.Builder()
                    .setState(PlaybackState.STATE_PLAYING, positionMs, 1.0f)
                    .setActions(
                        PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_PLAY_PAUSE or
                        PlaybackState.ACTION_SKIP_TO_NEXT or
                        PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                        PlaybackState.ACTION_STOP or
                        PlaybackState.ACTION_SEEK_TO
                    )
                "paused" -> PlaybackState.Builder()
                    .setState(PlaybackState.STATE_PAUSED, positionMs, 1.0f)
                    .setActions(
                        PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_PLAY_PAUSE or
                        PlaybackState.ACTION_SKIP_TO_NEXT or
                        PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                        PlaybackState.ACTION_STOP or
                        PlaybackState.ACTION_SEEK_TO
                    )
                else -> PlaybackState.Builder()
                    .setState(PlaybackState.STATE_STOPPED, positionMs, 1.0f)
                    .setActions(0L)
            }
            mediaSession?.setPlaybackState(playbackState.build())
            showNotification(state, positionMs)
            Log.i("MediaSession", "PlaybackState updated: $state, pos=$positionMs")
        } catch (e: Exception) {
            Log.e("MediaSession", "updatePlaybackState failed: ${e.message}", e)
        }
    }

    private fun showNotification(state: String, positionMs: Long) {
        try {
            val isPlaying = state == "playing"

            // Build notification with media controls
            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentTitle("Pathephon")
                .setContentText("Playing")
                .setOngoing(true)
                .setShowWhen(false)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOnlyAlertOnce(true)

            // Add transport control actions
            builder.addAction(
                android.R.drawable.ic_media_previous,
                "Previous",
                createPendingIntent(ACTION_PREV, 1)
            )

            if (isPlaying) {
                builder.addAction(
                    android.R.drawable.ic_media_pause,
                    "Pause",
                    createPendingIntent(ACTION_PAUSE, 2)
                )
                builder.setContentText("Now Playing")
            } else {
                builder.addAction(
                    android.R.drawable.ic_media_play,
                    "Play",
                    createPendingIntent(ACTION_PLAY, 3)
                )
                builder.setContentText("Paused")
            }

            builder.addAction(
                android.R.drawable.ic_media_next,
                "Next",
                createPendingIntent(ACTION_NEXT, 4)
            )

            // Link to MediaSession
            val token = mediaSession?.sessionToken
            if (token != null) {
                builder.setStyle(
                    androidx.media.app.NotificationCompat.MediaStyle()
                        .setMediaSession(token)
                        .setShowActionsInCompactView(0, 1, 2)
                )
            }

            notificationManager?.notify(NOTIFICATION_ID, builder.build())
            Log.i("MediaSession", "Notification shown, state=$state")
        } catch (e: Exception) {
            Log.e("MediaSession", "showNotification failed: ${e.message}", e)
        }
    }

    private fun createPendingIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(action).setPackage(context.packageName)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.getBroadcast(context, requestCode, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        } else {
            PendingIntent.getBroadcast(context, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT)
        }
    }

    private val mediaButtonReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                ACTION_PLAY -> { Log.i("MediaSession", "Notification: PLAY"); eventSink?.success("play") }
                ACTION_PAUSE -> { Log.i("MediaSession", "Notification: PAUSE"); eventSink?.success("pause") }
                ACTION_NEXT -> { Log.i("MediaSession", "Notification: NEXT"); eventSink?.success("next") }
                ACTION_PREV -> { Log.i("MediaSession", "Notification: PREV"); eventSink?.success("prev") }
                ACTION_STOP -> { Log.i("MediaSession", "Notification: STOP"); eventSink?.success("stop") }
            }
        }
    }

    private fun stopSession() {
        try {
            mediaSession?.isActive = false
            mediaSession?.release()
            mediaSession = null
            notificationManager?.cancel(NOTIFICATION_ID)
            if (isRegistered) {
                context.unregisterReceiver(mediaButtonReceiver)
                isRegistered = false
            }
            Log.i("MediaSession", "Session stopped")
        } catch (e: Exception) {
            Log.e("MediaSession", "stopSession failed: ${e.message}", e)
        }
    }

    fun dispose() {
        stopSession()
        eventSink = null
    }
}