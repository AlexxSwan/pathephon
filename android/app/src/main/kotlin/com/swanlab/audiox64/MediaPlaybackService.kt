package com.swanlab.audiox64

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import io.flutter.plugin.common.MethodChannel

/// Foreground service that holds MediaSession + shows persistent notification.
/// This is REQUIRED on Android 10+ for lock screen controls.
class MediaPlaybackService : Service() {

    companion object {
        const val CHANNEL_ID = "pathephon_playback"
        const val NOTIFICATION_ID = 1
        const val ACTION_START = "pathephon.START"
        const val ACTION_STOP = "pathephon.STOP_SERVICE"
        const val ACTION_PLAY = "pathephon.PLAY"
        const val ACTION_PAUSE = "pathephon.PAUSE"
        const val ACTION_NEXT = "pathephon.NEXT"
        const val ACTION_PREV = "pathephon.PREV"
        const val ACTION_STOP_PLAYBACK = "pathephon.STOP"

        var instance: MediaPlaybackService? = null
        var methodChannel: MethodChannel? = null

        fun start(context: Context) {
            val intent = Intent(context, MediaPlaybackService::class.java).setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, MediaPlaybackService::class.java).setAction(ACTION_STOP)
            context.startService(intent)
        }
    }

    private var mediaSession: MediaSessionCompat? = null
    private var notificationManager: NotificationManager? = null
    private var isRegistered = false
    private var currentTitle = "Pathephon"
    private var currentArtist = ""
    private var currentAlbum = ""
    private var isPlaying = false

    override fun onCreate() {
        super.onCreate()
        instance = this
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Create notification channel
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Pathephon Playback", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Media playback controls"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            notificationManager?.createNotificationChannel(channel)
        }

        createMediaSession()
        registerReceiver()
        Log.i("MediaService", "Service created")
    }

    private fun createMediaSession() {
        try {
            val sessionIntent = packageManager.getLaunchIntentForPackage(packageName)
            val pi = PendingIntent.getActivity(this, 0, sessionIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

            mediaSession = MediaSessionCompat(this, "Pathephon", null, pi).apply {
                setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                         MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS)
                setSessionActivity(pi)

                setCallback(object : MediaSessionCompat.Callback() {
                    override fun onPlay() {
                        Log.i("MediaService", "onPlay callback")
                        methodChannel?.invokeMethod("onMediaButton", "play")
                    }
                    override fun onPause() {
                        Log.i("MediaService", "onPause callback")
                        methodChannel?.invokeMethod("onMediaButton", "pause")
                    }
                    override fun onSkipToNext() {
                        Log.i("MediaService", "onSkipToNext callback")
                        methodChannel?.invokeMethod("onMediaButton", "next")
                    }
                    override fun onSkipToPrevious() {
                        Log.i("MediaService", "onSkipToPrevious callback")
                        methodChannel?.invokeMethod("onMediaButton", "prev")
                    }
                    override fun onStop() {
                        Log.i("MediaService", "onStop callback")
                        methodChannel?.invokeMethod("onMediaButton", "stop")
                    }
                    override fun onSeekTo(pos: Long) {
                        methodChannel?.invokeMethod("onMediaButton", "seek:$pos")
                    }
                })
                isActive = true
            }
            Log.i("MediaService", "MediaSession created and active")
        } catch (e: Exception) {
            Log.e("MediaService", "createMediaSession failed: ${e.message}", e)
        }
    }

    private fun registerReceiver() {
        if (!isRegistered) {
            val filter = IntentFilter().apply {
                addAction(ACTION_PLAY); addAction(ACTION_PAUSE)
                addAction(ACTION_NEXT); addAction(ACTION_PREV); addAction(ACTION_STOP_PLAYBACK)
            }
            registerReceiver(mediaButtonReceiver, filter)
            isRegistered = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                Log.i("MediaService", "START command")
                startForeground(NOTIFICATION_ID, buildNotification(false))
            }
            ACTION_STOP -> {
                Log.i("MediaService", "STOP command")
                stopSelf()
            }
        }
        return START_STICKY
    }

    fun updateMetadata(title: String, artist: String, album: String, durationMs: Long) {
        currentTitle = title
        currentArtist = artist
        currentAlbum = album
        try {
            val metadata = MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
                .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
                .build()
            mediaSession?.setMetadata(metadata)
            Log.i("MediaService", "Metadata: $title - $artist")
        } catch (e: Exception) {
            Log.e("MediaService", "updateMetadata: ${e.message}")
        }
    }

    fun updatePlaybackState(state: String, positionMs: Long) {
        isPlaying = state == "playing"
        try {
            val pbState = when (state) {
                "playing" -> PlaybackStateCompat.STATE_PLAYING
                "paused" -> PlaybackStateCompat.STATE_PAUSED
                else -> PlaybackStateCompat.STATE_STOPPED
            }
            val actions = PlaybackStateCompat.ACTION_PLAY or PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_PLAY_PAUSE or PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or PlaybackStateCompat.ACTION_STOP or
                PlaybackStateCompat.ACTION_SEEK_TO

            val playbackState = PlaybackStateCompat.Builder()
                .setState(pbState, positionMs, 1.0f)
                .setActions(actions)
                .build()
            mediaSession?.setPlaybackState(playbackState)

            // Update notification
            notificationManager?.notify(NOTIFICATION_ID, buildNotification(isPlaying))
            Log.i("MediaService", "PlaybackState: $state, pos=$positionMs")
        } catch (e: Exception) {
            Log.e("MediaService", "updatePlaybackState: ${e.message}")
        }
    }

    private fun buildNotification(playing: Boolean): Notification {
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(currentTitle)
            .setContentText(if (playing) "Now Playing" else "Paused")
            .setSubText(currentArtist)
            .setOngoing(true)
            .setShowWhen(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)

        builder.addAction(android.R.drawable.ic_media_previous, "Prev", createPI(ACTION_PREV, 1))
        if (playing) {
            builder.addAction(android.R.drawable.ic_media_pause, "Pause", createPI(ACTION_PAUSE, 2))
        } else {
            builder.addAction(android.R.drawable.ic_media_play, "Play", createPI(ACTION_PLAY, 3))
        }
        builder.addAction(android.R.drawable.ic_media_next, "Next", createPI(ACTION_NEXT, 4))

        mediaSession?.let { session ->
            builder.setStyle(
                MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )
        }

        return builder.build()
    }

    private fun createPI(action: String, reqCode: Int): PendingIntent {
        val intent = Intent(action).setPackage(packageName)
        return PendingIntent.getBroadcast(this, reqCode, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private val mediaButtonReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                ACTION_PLAY -> { methodChannel?.invokeMethod("onMediaButton", "play") }
                ACTION_PAUSE -> { methodChannel?.invokeMethod("onMediaButton", "pause") }
                ACTION_NEXT -> { methodChannel?.invokeMethod("onMediaButton", "next") }
                ACTION_PREV -> { methodChannel?.invokeMethod("onMediaButton", "prev") }
                ACTION_STOP_PLAYBACK -> { methodChannel?.invokeMethod("onMediaButton", "stop") }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        try {
            if (isRegistered) {
                unregisterReceiver(mediaButtonReceiver)
                isRegistered = false
            }
            mediaSession?.isActive = false
            mediaSession?.release()
            mediaSession = null
        } catch (e: Exception) {
            Log.e("MediaService", "onDestroy: ${e.message}")
        }
        instance = null
        super.onDestroy()
    }
}