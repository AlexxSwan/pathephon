package com.swanlab.audiox64

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// Foreground service + AlarmManager idle exit.
/// AlarmManager срабатывает даже когда ColorOS замораживает main thread.
class KeepAliveService : Service() {
    companion object {
        private const val TAG = "Pathephon/KeepAlive"
        private const val CHANNEL_ID = "pathephon_keepalive"
        private const val NOTIFICATION_ID = 42
        private const val ACTION_IDLE_EXIT = "com.swanlab.audiox64.IDLE_EXIT"
        private const val ACTION_IDLE_RETRY = "com.swanlab.audiox64.IDLE_RETRY"
        private const val LOG_FILE = "/storage/emulated/0/Download/Pathephon/pathephon_crash.log"

        @Volatile private var instance: KeepAliveService? = null

        private fun nativeLog(msg: String) {
            Log.i(TAG, msg)
            try {
                val ts = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSSSS", Locale.US).format(Date())
                File(LOG_FILE).appendText("[$ts] [INFO] [NATIVE] $msg\n")
            } catch (_: Exception) {}
        }

        fun scheduleIdleExit(delayMs: Long) {
            val svc = instance ?: run {
                nativeLog(">>> scheduleIdleExit: instance is NULL — service not running!")
                return
            }
            synchronized(svc) {
                val am = svc.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val intent = Intent(svc, KeepAliveService::class.java).apply {
                    action = ACTION_IDLE_EXIT
                }
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                else PendingIntent.FLAG_UPDATE_CURRENT
                val pi = PendingIntent.getService(svc, 42, intent, flags)

                // Отменяем предыдущий alarm
                am.cancel(pi)

                // setAndAllowWhileIdle — срабатывает даже в Doze mode
                // Не требует SCHEDULE_EXACT_ALARM permission
                am.setAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    SystemClock.elapsedRealtime() + delayMs,
                    pi
                )

                // Backup: Handler на main looper (может не сработать на ColorOS)
                svc.idleHandler?.removeCallbacksAndMessages(null)
                svc.idleHandler = Handler(Looper.getMainLooper())
                svc.idleRunnable = Runnable { svc.performIdleExit(1) }
                svc.idleHandler?.postDelayed(svc.idleRunnable!!, delayMs)

                nativeLog(">>> Idle exit scheduled: AlarmManager + Handler in ${delayMs / 60000} min")
            }
        }

        fun cancelIdleExit() {
            val svc = instance ?: return
            synchronized(svc) {
                // Cancel Handler
                svc.idleHandler?.removeCallbacksAndMessages(null)
                svc.idleHandler = null
                svc.idleRunnable = null

                // Cancel AlarmManager
                val am = svc.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val intent = Intent(svc, KeepAliveService::class.java).apply {
                    action = ACTION_IDLE_EXIT
                }
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_NO_CREATE
                else PendingIntent.FLAG_NO_CREATE
                val pi = PendingIntent.getService(svc, 42, intent, flags)
                pi?.let { am.cancel(it) }

                // Cancel retry alarm
                val retryIntent = Intent(svc, KeepAliveService::class.java).apply {
                    action = ACTION_IDLE_RETRY
                }
                val piRetry = PendingIntent.getService(svc, 43, retryIntent, flags)
                piRetry?.let { am.cancel(it) }
            }
            nativeLog(">>> Idle exit cancelled")
        }

        fun start(context: Context) {
            try {
                val intent = Intent(context, KeepAliveService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                nativeLog(">>> start requested")
            } catch (e: Exception) {
                nativeLog(">>> start failed: ${e.message}")
            }
        }

        fun stop(context: Context) {
            try {
                cancelIdleExit()
                context.stopService(Intent(context, KeepAliveService::class.java))
            } catch (e: Exception) {
                nativeLog(">>> stop failed: ${e.message}")
            }
        }
    }

    private var idleHandler: Handler? = null
    private var idleRunnable: Runnable? = null

    override fun onCreate() {
        super.onCreate()
        nativeLog(">>> onCreate")
        instance = this
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_IDLE_EXIT -> {
                nativeLog(">>> IDLE_EXIT alarm fired — killing process (attempt 1)")
                performIdleExit(1)
                return START_NOT_STICKY
            }
            ACTION_IDLE_RETRY -> {
                val attempt = intent.getIntExtra("attempt", 2)
                nativeLog(">>> IDLE_RETRY fired — killing process (attempt $attempt)")
                performIdleExit(attempt)
                return START_NOT_STICKY
            }
        }

        nativeLog(">>> onStartCommand (normal start)")
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
            nativeLog(">>> startForeground OK")
        } catch (e: Exception) {
            nativeLog(">>> startForeground FAILED: ${e.message}")
        }
        return START_STICKY
    }

    /// Убивает процесс. Если не получилось — планирует retry через 30 сек.
    private fun performIdleExit(attempt: Int) {
        nativeLog(">>> performIdleExit attempt=$attempt — stopForeground + stopSelf + killProcess + System.exit")

        try { stopForeground(true) } catch (_: Exception) {}
        try { stopSelf() } catch (_: Exception) {}

        // Wake lock на 5 сек чтобы процесс точно успел умереть
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            val wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Pathephon:IdleExit")
            wl.acquire(5000)
            nativeLog(">>> WakeLock acquired for kill")
        } catch (e: Exception) {
            nativeLog(">>> WakeLock failed: ${e.message}")
        }

        // Планируем retry если этот attempt не убьёт процесс
        if (attempt < 3) {
            try {
                val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val retryIntent = Intent(this, KeepAliveService::class.java).apply {
                    action = ACTION_IDLE_RETRY
                    putExtra("attempt", attempt + 1)
                }
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                else PendingIntent.FLAG_UPDATE_CURRENT
                val pi = PendingIntent.getService(this, 43, retryIntent, flags)
                am.setAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    SystemClock.elapsedRealtime() + 30000,
                    pi
                )
                nativeLog(">>> Retry scheduled in 30 sec (attempt ${attempt + 1})")
            } catch (e: Exception) {
                nativeLog(">>> Retry schedule failed: ${e.message}")
            }
        }

        // Пытаемся убить процесс
        try {
            Process.killProcess(Process.myPid())
        } catch (e: Exception) {
            nativeLog(">>> killProcess failed: ${e.message}")
        }
        try {
            System.exit(0)
        } catch (e: Exception) {
            nativeLog(">>> System.exit failed: ${e.message}")
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        cancelIdleExit()
        instance = null
        nativeLog(">>> onDestroy")
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
        nativeLog(">>> channel created")
    }
}