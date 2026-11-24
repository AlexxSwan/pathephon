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
        fun setChannel(ch: MethodChannel) { channel = ch }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MEDIA_BUTTON) return
        val event: KeyEvent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
        }
        if (event == null || event.action != KeyEvent.ACTION_DOWN) return
        val ch = channel ?: return
        val cmd = when (event.keyCode) {
            KeyEvent.KEYCODE_MEDIA_PLAY -> "play"
            KeyEvent.KEYCODE_MEDIA_PAUSE -> "pause"
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> "play_pause"
            KeyEvent.KEYCODE_MEDIA_NEXT -> "next"
            KeyEvent.KEYCODE_MEDIA_PREVIOUS -> "prev"
            KeyEvent.KEYCODE_MEDIA_STOP -> "stop"
            else -> return
        }
        ch.invokeMethod(cmd, null, object : MethodChannel.Result {
            override fun success(result: Any?) {}
            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
            override fun notImplemented() {}
        })
    }
}
