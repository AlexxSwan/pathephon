package com.swanlab.audiox64

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "Pathephon/Main"
        private const val CHANNEL_ID = "pathephon_playback"
        private const val LAUNCH_CHANNEL = "pathephon/launch_intent"
        private const val BATTERY_CHANNEL = "pathephon/battery"
    }

    private var visualizerPlugin: VisualizerPlugin? = null
    private var equalizerPlugin: EqualizerPlugin? = null
    private var folderScannerPlugin: FolderScannerPlugin? = null
    private var pendingLaunchUri: String? = null
    private var pendingLaunchName: String? = null
    private var pendingLaunchContent: String? = null
    private var launchChannel: MethodChannel? = null
    private var batteryChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i(TAG, ">>> onCreate")
        try {
            KeepAliveService.start(this)
            Log.i(TAG, ">>> KeepAliveService started")
        } catch (e: Exception) {
            Log.e(TAG, ">>> KeepAliveService start failed: ${e.message}")
        }
        handleLaunchIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.i(TAG, ">>> onNewIntent: action=${intent.action}")
        handleLaunchIntent(intent)
    }

    private fun handleLaunchIntent(intent: Intent?) {
        if (intent?.action == Intent.ACTION_VIEW) {
            val data = intent.data
            if (data != null) {
                pendingLaunchUri = data.toString()
                pendingLaunchName = queryFileName(data)
                val isM3u = pendingLaunchName?.endsWith(".m3u") == true ||
                             pendingLaunchName?.endsWith(".m3u8") == true ||
                             data.toString().contains(".m3u")
                if (isM3u) {
                    pendingLaunchContent = readFileContent(data)
                    Log.i(TAG, ">>> ACTION_VIEW M3U: $pendingLaunchUri (${pendingLaunchContent?.length ?: 0} chars)")
                } else {
                    Log.i(TAG, ">>> ACTION_VIEW uri=$pendingLaunchUri name=$pendingLaunchName")
                }
                trySendLaunchIntent()
            }
        }
    }

    private fun readFileContent(uri: android.net.Uri): String? {
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                input.bufferedReader().readText()
            }
        } catch (e: Exception) {
            Log.w(TAG, ">>> readFileContent failed: ${e.message}")
            null
        }
    }

    private fun queryFileName(uri: android.net.Uri): String? {
        if (uri.scheme == "file") {
            return uri.lastPathSegment
        }
        var name: String? = null
        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(uri, null, null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) name = cursor.getString(idx)
            }
        } catch (e: Exception) {
            Log.w(TAG, ">>> queryFileName failed: ${e.message}")
        } finally {
            cursor?.close()
        }
        return name
    }

    private fun trySendLaunchIntent() {
        val uri = pendingLaunchUri ?: return
        val ch = launchChannel ?: return
        launchChannel?.invokeMethod(
            "onLaunchIntent",
            mapOf("uri" to uri, "name" to (pendingLaunchName ?: ""))
        )
        Log.i(TAG, ">>> sending launch intent to Dart: $uri name=${pendingLaunchName ?: ""}")
        ch.invokeMethod("onLaunchIntent", mapOf("uri" to uri, "name" to (pendingLaunchName ?: "")))
        pendingLaunchUri = null
        pendingLaunchName = null
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
        flutterEngine.plugins.add(TagReaderPlugin())
        Log.i(TAG, ">>> TagReaderPlugin registered")
        Log.i(TAG, ">>> MediaSessionPlugin registered")

        launchChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LAUNCH_CHANNEL)
        launchChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getLaunchIntent" -> {
                    val uri = pendingLaunchUri
                    val name = pendingLaunchName
                    val content = pendingLaunchContent
                    pendingLaunchUri = null
                    pendingLaunchName = null
                    pendingLaunchContent = null
                    if (uri != null) {
                        val payload = mutableMapOf("uri" to uri, "name" to (name ?: ""))
                        content?.let { payload["content"] = it }
                        result.success(payload)
                    } else {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        Log.i(TAG, ">>> launch_intent channel registered")
        trySendLaunchIntent()

        batteryChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL)
        batteryChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    try {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        val isIgnoring = pm.isIgnoringBatteryOptimizations(packageName)
                        Log.i(TAG, ">>> isIgnoringBatteryOptimizations: $isIgnoring")
                        result.success(isIgnoring)
                    } catch (e: Exception) {
                        Log.w(TAG, ">>> isIgnoringBatteryOptimizations failed: ${e.message}")
                        result.success(false)
                    }
                }
                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                        intent.data = android.net.Uri.parse("package:$packageName")
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        Log.i(TAG, ">>> requestIgnoreBatteryOptimizations: dialog shown")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w(TAG, ">>> requestIgnoreBatteryOptimizations failed: ${e.message}")
                        result.success(false)
                    }
                }
                "stopKeepAlive" -> {
                    try {
                        KeepAliveService.stop(this)
                        Log.i(TAG, ">>> stopKeepAlive: service stopped")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w(TAG, ">>> stopKeepAlive failed: ${e.message}")
                        result.success(false)
                    }
                }
                "setIdleExit" -> {
                    try {
                        val delayMs = (call.argument<Number>("delayMs") ?: 1200000).toLong()
                        KeepAliveService.scheduleIdleExit(delayMs)
                        Log.i(TAG, ">>> setIdleExit:  min")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w(TAG, ">>> setIdleExit failed: ${e.message}")
                        result.success(false)
                    }
                }
                "cancelIdleExit" -> {
                    try {
                        KeepAliveService.cancelIdleExit()
                        Log.i(TAG, ">>> cancelIdleExit")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w(TAG, ">>> cancelIdleExit failed: ${e.message}")
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
        Log.i(TAG, ">>> battery channel registered")
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        val levelStr = when (level) {
            TRIM_MEMORY_COMPLETE -> "COMPLETE"
            TRIM_MEMORY_MODERATE -> "MODERATE"
            TRIM_MEMORY_BACKGROUND -> "BACKGROUND"
            TRIM_MEMORY_UI_HIDDEN -> "UI_HIDDEN"
            TRIM_MEMORY_RUNNING_CRITICAL -> "RUNNING_CRITICAL"
            TRIM_MEMORY_RUNNING_LOW -> "RUNNING_LOW"
            TRIM_MEMORY_RUNNING_MODERATE -> "RUNNING_MODERATE"
            else -> "UNKNOWN($level)"
        }
        Log.w(TAG, ">>> onTrimMemory: " + levelStr)
    }

    override fun onLowMemory() {
        super.onLowMemory()
        Log.w(TAG, ">>> onLowMemory: about to be killed!")
    }

    override fun onDestroy() {
        visualizerPlugin?.dispose()
        equalizerPlugin?.dispose()
        visualizerPlugin = null
        equalizerPlugin = null
        folderScannerPlugin = null
        launchChannel = null
        batteryChannel = null
        KeepAliveService.stop(this)
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