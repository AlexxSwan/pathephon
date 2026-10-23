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
        // Do NOT fall back to session 0 (global output mix). Session 0
        // captures ALL audio on the device — system sounds, notifications,
        // other apps — which makes the VU react to non-music audio.
        // If we can't attach to the player's own session, VU just stays
        // at 0 (better silent than wrong).
        if (sessionId == 0) {
            Log.w("VisualizerPlugin", "sessionId is 0 — refusing to attach to global mix")
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
                if (eventCount % 100 == 1) {
                    Log.i("VisualizerPlugin", "captured event #$eventCount, bytes=${waveform.size}")
                }
                val n = waveform.size
                if (n < 4) return
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
                // Real RMS values for music are typically 0.1-0.4.
                // Multiply by 1.8 for visible swing, cap at 0.85 (just below
                // red zone which starts ~0.85).
                val scaledL = (rmsL * 1.8).coerceIn(0.0, 0.85)
                val scaledR = (rmsR * 1.8).coerceIn(0.0, 0.85)
                eventSink?.success(listOf(scaledL, scaledR))
            }
            override fun onFftDataCapture(viz: Visualizer?, fft: ByteArray?, samplingRate: Int) {}
        }, 20000, true, false)
        v.enabled = true
        visualizer = v
        Log.i("VisualizerPlugin", "Visualizer attached to player session $sessionId captureSize=$captureSize")
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