package com.swanlab.audiox64

import android.media.audiofx.Visualizer
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel.EventSink

/// Native Android Visualizer bridge - PPM peak detection.
/// Returns peak in dBFS (decibels relative to full scale):
///   0 dBFS  = full scale (digital max)
///   -60 dBFS = silence
/// The Dart side maps dBFS to the PPM needle position.
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
        if (sessionId == 0) {
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
                val n = waveform.size
                if (n < 2) return

                // Peak: max absolute deviation from center (128).
                var maxAbs = 0
                for (i in 0 until n) {
                    val sample = (waveform[i].toInt() and 0xFF) - 128
                    val abs = if (sample < 0) -sample else sample
                    if (abs > maxAbs) maxAbs = abs
                }

                // Convert peak (0..128) to dBFS:
                //   peak/128 = linear amplitude (0..1)
                //   dBFS = 20 * log10(linear)
                //   0 dBFS = full scale, -inf = silence
                val linear = maxAbs.toDouble() / 128.0
                val dbFs = if (linear <= 0.001) {
                    -60.0  // floor at -60 dBFS (silence)
                } else {
                    20.0 * Math.log10(linear)
                }

                // Return dBFS as a number (-60..0)
                eventSink?.success(dbFs)
            }
            override fun onFftDataCapture(viz: Visualizer?, fft: ByteArray?, samplingRate: Int) {}
        }, 20000, true, false)
        v.enabled = true
        visualizer = v
        Log.i("VisualizerPlugin", "PPM Visualizer attached to session $sessionId")
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