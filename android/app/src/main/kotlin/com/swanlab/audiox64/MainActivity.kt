package com.swanlab.audiox64

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "Pathephon/Main"
        private const val CHANNEL_ID = "pathephon_playback"
        private const val LAUNCH_CHANNEL = "pathephon/launch_intent"
    }

    private var visualizerPlugin: VisualizerPlugin? = null
    private var equalizerPlugin: EqualizerPlugin? = null
    private var folderScannerPlugin: FolderScannerPlugin? = null
    private var pendingLaunchIntent: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleLaunchIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleLaunchIntent(intent)
    }

    private fun handleLaunchIntent(intent: Intent?) {
        if (intent?.action == Intent.ACTION_VIEW) {
            val data = intent.data
            if (data != null) {
                pendingLaunchIntent = data.toString()
                Log.i(TAG, ">>> ACTION_VIEW: $pendingLaunchIntent")
            }
        }
    }

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
        flutterEngine.plugins.add(MediaSessionPlugin())
        Log.i(TAG, ">>> MediaSessionPlugin registered")

        // Channel для передачи ACTION_VIEW intent в Dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LAUNCH_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getLaunchIntent") {
                    val data = pendingLaunchIntent
                    pendingLaunchIntent = null
                    result.success(data)
                } else {
                    result.notImplemented()
                }
            }
        Log.i(TAG, ">>> launch_intent channel registered")
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