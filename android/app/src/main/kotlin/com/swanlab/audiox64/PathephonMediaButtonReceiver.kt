package com.swanlab.audiox64

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.view.KeyEvent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Прямой BroadcastReceiver для ACTION_MEDIA_BUTTON.
 *
 * Зачем: ColorOS на OPPO/Realme блокирует audio_service's MediaSession
 * от получения BT-событий ("setLastMediaButtonReceiver: not add to stack").
 * Этот receiver перехватывает ACTION_MEDIA_BUTTON intents ДО того как
 * они попадут в MediaSession stack, и напрямую шлёт команды в Dart
 * через MethodChannel.
 *
 * Receiver регистрируется в манифесте с priority=MAX_INT, так что
 * получает intent первым. Также регистрируется в MainActivity.run()
 * чтобы получить доступ к FlutterEngine для MethodChannel.
 */
class PathephonMediaButtonReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "Pathephon/MediaButton"
        private const val CHANNEL = "pathephon/media_button"
        private var channel: MethodChannel? = null

        /// Вызывается из MainActivity чтобы передать MethodChannel.
        /// Receiver не имеет доступа к FlutterEngine при static manifest регистрации,
        /// поэтому канал прокидывается через companion object.
        fun setChannel(ch: MethodChannel) {
            channel = ch
            Log.i(TAG, "MethodChannel set")
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MEDIA_BUTTON) return
        val event = intent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT) ?: return
        Log.i(TAG, ">>> onReceive: keyCode=${event.keyCode} action=${event.action}")

        // Только ACTION_UP (отпускание кнопки) — ACTION_DOWN игнорируем
        // чтобы не было двойных срабатываний.
        if (event.action != KeyEvent.ACTION_UP) return

        val ch = channel ?: run {
            Log.w(TAG, ">>> channel is null — Dart side not ready")
            return
        }

        val cmd = when (event.keyCode) {
            KeyEvent.KEYCODE_MEDIA_PLAY -> "play"
            KeyEvent.KEYCODE_MEDIA_PAUSE -> "pause"
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> "play_pause"
            KeyEvent.KEYCODE_MEDIA_NEXT -> "next"
            KeyEvent.KEYCODE_MEDIA_PREVIOUS -> "prev"
            KeyEvent.KEYCODE_MEDIA_STOP -> "stop"
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> "fast_forward"
            KeyEvent.KEYCODE_MEDIA_REWIND -> "rewind"
            else -> {
                Log.w(TAG, ">>> unknown keyCode: ${event.keyCode}")
                return
            }
        }
        Log.i(TAG, ">>> invoking channel '$cmd'")
        ch.invokeMethod(cmd, null, object : MethodChannel.Result {
            override fun success(result: Any?) { Log.i(TAG, ">>> $cmd success") }
            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                Log.e(TAG, ">>> $cmd error: $errorCode / $errorMessage")
            }
            override fun notImplemented() { Log.w(TAG, ">>> $cmd notImplemented") }
        })
    }
}