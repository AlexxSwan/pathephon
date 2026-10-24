package com.swanlab.audiox64

import android.media.audiofx.Visualizer
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel.EventSink

/// Native Android Visualizer bridge.
/// Attaches to the player's audio session id, captures waveform at 20Hz,
/// computes RMS amplitude (0..1), streams to Dart.
class VisualizerPlugin(binaryMessenger: BinaryMessenger) {
    private val methodChannel = MethodChannel(binaryMessenger, "pathephon/visualizer")
    private val eventChannel = EventChannel(binaryMessenger, "pathephon/visualizer/events")
    private var visualizer: Visualizer? = null
    private var eventSink: EventSink? = null
    private var eventCount: Int = 0

    init {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    try {
                        start(sessionId)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("VisualizerPlugin", "start failed: ${e.message}", e)
                        result.error("START_FAILED", e.message, null)
                    }
                }
                "stop" -> {
                    stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventSink) {
                eventSink = sink
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    private fun start(sessionId: Int) {
        stop()
        if (sessionId == 0) {
            Log.w("VisualizerPlugin", "sessionId is 0 - cannot attach")
            throw IllegalArgumentException("sessionId 0 not supported")
        }

        val captureRange = Visualizer.getCaptureSizeRange()
        val captureSize = if (captureRange != null && captureRange.size >= 2) {
            captureRange[0]
        } else {
            128
        }

        val v = Visualizer(sessionId)
        v.captureSize = captureSize
        v.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
            override fun onWaveFormDataCapture(viz: Visualizer?, waveform: ByteArray?, samplingRate: Int) {
                if (waveform == null || eventSink == null) return
                eventCount++
                if (eventCount % 200 == 1) {
                    Log.i("VisualizerPlugin", "captured event #$eventCount, bytes=${waveform.size}")
                }
                val n = waveform.size
                if (n < 2) return
                // Waveform bytes: unsigned 0..255, centered at 128.
                // Compute RMS deviation from center.
                var sumSq = 0.0
                for (i in 0 until n) {
                    val sample = (waveform[i].toInt() and 0xFF) - 128
                    sumSq += (sample * sample).toDouble()
                }
                val rms = Math.sqrt(sumSq / n) / 128.0
                // Real RMS for music is typically 0.1..0.4.
                // No artificial boost - keep it real.
                // Clamp to 0..1 for the painter.
                val amplitude = rms.coerceIn(0.0, 1.0)
                eventSink?.success(amplitude)
            }
            override fun onFftDataCapture(viz: Visualizer?, fft: ByteArray?, samplingRate: Int) {}
        }, 20000, true, false)
        v.enabled = true
        visualizer = v
        Log.i("VisualizerPlugin", "Visualizer attached to session $sessionId captureSize=$captureSize")
    }

    private fun stop() {
        try {
            visualizer?.let {
                it.enabled = false
                it.release()
            }
        } catch (e: Exception) {
            Log.w("VisualizerPlugin", "stop: ${e.message}")
        }
        visualizer = null
        eventCount = 0
    }

    fun dispose() {
        stop()
        eventSink = null
    }
}