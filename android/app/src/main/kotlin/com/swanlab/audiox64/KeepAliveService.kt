package com.swanlab.audiox64

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/// Минимальный foreground service — только показывает уведомление.
/// НЕ зависит от Dart, НЕ создаёт MediaSession, НЕ регистрирует receiver.
/// Защищает процесс от ColorOS SIGKILL.
class KeepAliveService : Service() {
    companion object {
        private const val TAG = "Pathephon/KeepAlive"
        private const val CHANNEL_ID = "pathephon_keepalive"
        private const val NOTIFICATION_ID = 42

        fun start(context: Context) {
            try {
                val intent = Intent(context, KeepAliveService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                Log.i(TAG, ">>> start requested")
            } catch (e: Exception) {
                Log.e(TAG, ">>> start failed: ${e.message}")
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, KeepAliveService::class.java))
            } catch (e: Exception) {
                Log.e(TAG, ">>> stop failed: ${e.message}")
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, ">>> onCreate")
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, ">>> onStartCommand")
        try {
            val notification = Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("Pathephon")
                .setContentText("Аудиоплеер активен")
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setOngoing(true)
                .build()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            Log.i(TAG, ">>> startForeground OK")
        } catch (e: Exception) {
            Log.e(TAG, ">>> startForeground FAILED: ${e.message}")
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val ch = NotificationChannel(
            CHANNEL_ID, "Pathephon Keep Alive", NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps app alive in background"
            setShowBadge(false)
            enableLights(false)
            enableVibration(false)
        }
        nm.createNotificationChannel(ch)
        Log.i(TAG, ">>> channel created")
    }
}