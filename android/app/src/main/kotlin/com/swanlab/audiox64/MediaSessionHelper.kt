package com.swanlab.audiox64

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/// Bridge between Dart and MediaPlaybackService.
class MediaSessionHelper(
    binaryMessenger: BinaryMessenger,
    private val context: Context
) {
    private val methodChannel = MethodChannel(binaryMessenger, "pathephon/media_session")
    private val eventChannel = EventChannel(binaryMessenger, "pathephon/media_session/events")
    private var eventSink: EventChannel.EventSink? = null

    init {
        // Make methodChannel accessible to the service
        MediaPlaybackService.methodChannel = methodChannel

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    Log.i("MediaHelper", "start: starting foreground service")
                    MediaPlaybackService.start(context)
                    result.success(true)
                }
                "updateMetadata" -> {
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val album = call.argument<String>("album") ?: ""
                    val durationMs = call.argument<Long>("durationMs") ?: 0L
                    MediaPlaybackService.instance?.updateMetadata(title, artist, album, durationMs)
                    result.success(null)
                }
                "updatePlaybackState" -> {
                    val state = call.argument<String>("state") ?: "stopped"
                    val positionMs = call.argument<Long>("positionMs") ?: 0L
                    MediaPlaybackService.instance?.updatePlaybackState(state, positionMs)
                    result.success(null)
                }
                "stop" -> {
                    MediaPlaybackService.stop(context)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Handle callbacks FROM the service (media button events)
        methodChannel.setMethodCallHandler { call, result ->
            if (call.method == "onMediaButton") {
                val event = call.arguments as String
                Log.i("MediaHelper", "Media button: $event")
                eventSink?.success(event)
                result.success(null)
            }
        }

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { eventSink = sink }
            override fun onCancel(arguments: Any?) { eventSink = null }
        })
    }

    fun dispose() {
        MediaPlaybackService.stop(context)
        MediaPlaybackService.methodChannel = null
        eventSink = null
    }
}