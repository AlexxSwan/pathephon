package com.swanlab.audiox64

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/// Bridge between Dart and MediaPlaybackService.
///
/// CRITICAL FIX: setMethodCallHandler must be called ONCE, handling BOTH
/// incoming calls from Dart (start/updateMetadata/etc) AND callbacks from
/// the service (onMediaButton). Previously two separate setMethodCallHandler
/// calls were made - the second OVERWROTE the first, so "start" was never
/// handled and the service never started.
class MediaSessionHelper(
    binaryMessenger: BinaryMessenger,
    private val context: Context
) {
    private val methodChannel = MethodChannel(binaryMessenger, "pathephon/media_session")
    private val eventChannel = EventChannel(binaryMessenger, "pathephon/media_session/events")
    private var eventSink: EventChannel.EventSink? = null

    init {
        // Make methodChannel accessible to the service for callbacks
        MediaPlaybackService.methodChannel = methodChannel

        // SINGLE handler for ALL methods (both from Dart and from Service)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                // Methods called FROM Dart
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
                    Log.i("MediaHelper", "updateMetadata: $title - $artist")
                    MediaPlaybackService.instance?.updateMetadata(title, artist, album, durationMs)
                    result.success(null)
                }
                "updatePlaybackState" -> {
                    val state = call.argument<String>("state") ?: "stopped"
                    val positionMs = call.argument<Long>("positionMs") ?: 0L
                    Log.i("MediaHelper", "updatePlaybackState: $state, pos=$positionMs")
                    MediaPlaybackService.instance?.updatePlaybackState(state, positionMs)
                    result.success(null)
                }
                "stop" -> {
                    Log.i("MediaHelper", "stop service")
                    MediaPlaybackService.stop(context)
                    result.success(null)
                }
                // Callback FROM Service (media button events)
                "onMediaButton" -> {
                    val event = call.arguments as String
                    Log.i("MediaHelper", "Media button event: $event")
                    eventSink?.success(event)
                    result.success(null)
                }
                else -> {
                    Log.w("MediaHelper", "Unknown method: ${call.method}")
                    result.notImplemented()
                }
            }
        }

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                eventSink = sink
                Log.i("MediaHelper", "EventChannel listening")
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
                Log.i("MediaHelper", "EventChannel cancelled")
            }
        })
    }

    fun dispose() {
        MediaPlaybackService.stop(context)
        MediaPlaybackService.methodChannel = null
        eventSink = null
    }
}