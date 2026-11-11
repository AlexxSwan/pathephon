package com.swanlab.audiox64

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Process
import android.util.Log

/// Foreground service — показывает уведомление + управляет idle exit.
/// НЕ зависит от Dart (Dart isolate в фоне приостановлен — Timer не сработает).
/// Нативный Handler работает всегда, пока service жив.
class KeepAliveService : Service() {
    companion object {
        private const val TAG = "Pathephon/KeepAlive"
        private const val CHANNEL_ID = "pathephon_keepalive"
        private const val NOTIFICATION_ID = 42

        @Volatile private var instance: KeepAliveService? = null

        /// Запланировать закрытие приложения через delayMs мс без воспроизведения.
        /// Вызывается из Dart через MethodChannel 'pathephon/battery' -> 'setIdleExit'.
        fun scheduleIdleExit(delayMs: Long) {
            val svc = instance ?: run {
                Log.w(TAG, ">>> scheduleIdleExit: service not running, cannot schedule")
                return
            }
            synchronized(svc) {
                svc.idleHandler?.removeCallbacksAndMessages(null)
                svc.idleHandler = Handler(Looper.getMainLooper())
                svc.idleRunnable = Runnable {
                    Log.i(TAG, ">>> Idle exit: killing process after ${delayMs / 60000} min idle")
                    try { svc.stopForeground(true) } catch (_: Exception) {}
                    try { svc.stopSelf() } catch (_: Exception) {}
                    try {
                        Process.killProcess(Process.myPid())
                    } catch (e: Exception) {
                        Log.e(TAG, ">>> killProcess failed: ${e.message}")
                        System.exit(0)
                    }
                }
                svc.idleHandler?.postDelayed(svc.idleRunnable!!, delayMs)
                Log.i(TAG, ">>> Idle exit scheduled in ${delayMs / 60000} min")
            }
        }

        /// Отменить запланированное закрытие.
        /// Вызывается из Dart через MethodChannel 'pathephon/battery' -> 'cancelIdleExit'.
        fun cancelIdleExit() {
            val svc = instance ?: return
            synchronized(svc) {
                svc.idleHandler?.removeCallbacksAndMessages(null)
                svc.idleHandler = null
                svc.idleRunnable = null
            }
            Log.i(TAG, ">>> Idle exit cancelled")
        }

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
                cancelIdleExit()
                context.stopService(Intent(context, KeepAliveService::class.java))
            } catch (e: Exception) {
                Log.e(TAG, ">>> stop failed: ${e.message}")
            }
        }
    }

    private var idleHandler: Handler? = null
    private var idleRunnable: Runnable? = null

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, ">>> onCreate")
        instance = this
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

    override fun onDestroy() {
        cancelIdleExit()
        instance = null
        Log.i(TAG, ">>> onDestroy")
        super.onDestroy()
    }

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