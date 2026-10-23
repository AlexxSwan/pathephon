package com.swanlab.audiox64

import android.media.audiofx.Visualizer
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel.EventSink

class VisualizerPlugin(binaryMessenger: BinaryMessenger) {
    private val methodChannel = MethodChannel(binaryMessenger, "pathephon/visualizer")
    private val eventChannel = EventChannel(binaryMessenger, "pathephon/visualizer/events")
    private var visualizer: Visualizer? = null
    private var eventSink: EventSink? = null

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
                "isActive" -> {
                    result.success(visualizer?.enabled == true)
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
        val captureRange = Visualizer.getCaptureSizeRange()
        val captureSize = if (captureRange != null && captureRange.size >= 2) {
            captureRange[0]
        } else {
            128
        }

        // Try the given session id first; if it fails, fall back to 0 (output mix).
        // sessionId=0 means "global output mix" - works for any audio output but
        // requires RECORD_AUDIO permission on Android 14+.
        val actualSessionId = try {
            val test = Visualizer(sessionId)
            test.release()
            sessionId
        } catch (e: Exception) {
            Log.w("VisualizerPlugin", "sessionId $sessionId failed, trying 0: ${e.message}")
            0
        }

        val v = Visualizer(actualSessionId)
        v.captureSize = captureSize
        v.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
            override fun onWaveFormDataCapture(viz: Visualizer?, waveform: ByteArray?, samplingRate: Int) {
                if (waveform == null || eventSink == null) return
                val n = waveform.size
                if (n < 4) return
                // Android Visualizer returns MONO mix (not real stereo).
                // Splitting the array in half gives a synthetic L/R approximation
                // that visually differentiates channels when content has stereo
                // panning. RMS of each half, normalized to 0..1.
                val half = n / 2
                var sumL = 0.0
                var sumR = 0.0
                for (i in 0 until half) {
                    val l = (waveform[i].toInt() and 0xFF) - 128
                    val r = (waveform[i + half].toInt() and 0xFF) - 128
                    sumL += (l * l).toDouble()
                    sumR += (r * r).toDouble()
                }
                val rmsL = Math.sqrt(sumL / half) / 128.0
                val rmsR = Math.sqrt(sumR / half) / 128.0
                // Boost: typical RMS for music is ~0.1-0.3; multiply by 3 for visible swing.
                val scaledL = (rmsL * 3.0).coerceIn(0.0, 1.0)
                val scaledR = (rmsR * 3.0).coerceIn(0.0, 1.0)
                eventSink?.success(listOf(scaledL, scaledR))
            }
            override fun onFftDataCapture(viz: Visualizer?, fft: ByteArray?, samplingRate: Int) {}
        }, 20000, true, false)
        v.enabled = true
        visualizer = v
        Log.i("VisualizerPlugin", "Visualizer started on sessionId=$actualSessionId captureSize=$captureSize")
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
    }

    fun dispose() {
        stop()
        eventSink = null
    }
}