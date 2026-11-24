package com.swanlab.audiox64

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.view.KeyEvent
import io.flutter.plugin.common.MethodChannel

class PathephonMediaButtonReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "Pathephon/MediaButton"
        private const val CHANNEL = "pathephon/native_media_session"
        private var channel: MethodChannel? = null

        fun setChannel(ch: MethodChannel) {
            channel = ch
            Log.i(TAG, "MethodChannel set")
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MEDIA_BUTTON) return

        val event: KeyEvent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
        }
        if (event == null) {
            Log.w(TAG, ">>> onReceive: KeyEvent is null")
            return
        }

        Log.i(TAG, ">>> onReceive: keyCode=${event.keyCode} action=${event.action}")

        if (event.action != KeyEvent.ACTION_DOWN) return

        val ch = channel ?: run {
            Log.w(TAG, ">>> channel is null")
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
            else -> return
        }
        Log.i(TAG, ">>> invoking: $cmd")
        ch.invokeMethod(cmd, null, object : MethodChannel.Result {
            override fun success(result: Any?) { Log.i(TAG, ">>> $cmd OK") }
            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                Log.e(TAG, ">>> $cmd error: $errorCode")
            }
            override fun notImplemented() { Log.w(TAG, ">>> $cmd notImplemented") }
        })
    }
}
