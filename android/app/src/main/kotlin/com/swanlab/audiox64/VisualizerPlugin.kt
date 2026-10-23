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
                // Waveform bytes: unsigned 0..255, centered at 128.
                // For typical music, deviation is ~30-60, so RMS ~ 0.25-0.45.
                // We do NOT multiply by any factor — keep real values so the
                // VU needle stays in green/yellow zone.
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
                // Mild boost (1.5x) to lift needle off zero on quiet passages,
                // but capped at 0.85 so it never enters red zone (which starts ~0.85).
                val scaledL = (rmsL * 1.5).coerceIn(0.0, 0.85)
                val scaledR = (rmsR * 1.5).coerceIn(0.0, 0.85)
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