package com.swanlab.audiox64

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.os.Build
import android.os.Bundle
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
    }

    private var visualizerPlugin: VisualizerPlugin? = null
    private var equalizerPlugin: EqualizerPlugin? = null
    private var folderScannerPlugin: FolderScannerPlugin? = null
    private var pendingLaunchUri: String? = null
    private var pendingLaunchName: String? = null
    private var pendingLaunchContent: String? = null
    private var launchChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i(TAG, ">>> onCreate")
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
                // Для .m3u файлов — читаем контент
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

    /// Читает текстовый файл из Uri (для .m3u).
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

    /// Получает имя файла из Uri (работает для content:// и file://).
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
        // Отправляем имя файла вместе с uri через pathephon/launch_intent channel.
        // SystemChannels.navigation не позволяет передать extra данные, поэтому
        // используем свой channel.
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

        // Channel для передачи ACTION_VIEW intent в Dart.
        // Используем push-модель: Kotlin сам вызывает onLaunchIntent когда
        // есть данные, а не ждёт пока Dart попросит.
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
        // Если intent пришёл ДО регистрации channel — отправляем сейчас
        trySendLaunchIntent()
    }

    override fun onDestroy() {
        visualizerPlugin?.dispose()
        equalizerPlugin?.dispose()
        visualizerPlugin = null
        equalizerPlugin = null
        folderScannerPlugin = null
        launchChannel = null
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