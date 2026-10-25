package com.swanlab.audiox64

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "Pathephon/Main"
        private const val CHANNEL_ID = "pathephon_playback"
    }

    private var visualizerPlugin: VisualizerPlugin? = null
    private var equalizerPlugin: EqualizerPlugin? = null
    private var folderScannerPlugin: FolderScannerPlugin? = null

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        createPlaybackNotificationChannel()
        return super.provideFlutterEngine(context)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createPlaybackNotificationChannel()
        visualizerPlugin = VisualizerPlugin(flutterEngine.dartExecutor.binaryMessenger)
        equalizerPlugin = EqualizerPlugin(flutterEngine.dartExecutor.binaryMessenger)
        folderScannerPlugin = FolderScannerPlugin(flutterEngine.dartExecutor.binaryMessenger, this)
        // Регистрируем MediaSessionPlugin — он создаёт сессию "Pathephon"
        // которая получает BT-события от ColorOS.
        flutterEngine.plugins.add(MediaSessionPlugin())
        Log.i(TAG, ">>> MediaSessionPlugin registered")
    }

    override fun onDestroy() {
        visualizerPlugin?.dispose()
        equalizerPlugin?.dispose()
        visualizerPlugin = null
        equalizerPlugin = null
        folderScannerPlugin = null
        super.onDestroy()
    }

    private fun createPlaybackNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val ch = NotificationChannel(
            CHANNEL_ID, "Pathephon Playback", NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Media playback controls"
            setShowBadge(false); enableLights(false); enableVibration(false)
        }
        nm.createNotificationChannel(ch)
    }
}