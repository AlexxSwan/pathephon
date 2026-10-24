package com.swanlab.audiox64

import android.media.audiofx.Visualizer
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel.EventSink

/// Native Android Visualizer - FFT spectrum analyzer mode.
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

        // captureSize 512 -> 256 frequency bins available
        val captureSize = 512

        val v = Visualizer(sessionId)
        v.captureSize = captureSize
        v.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
            override fun onWaveFormDataCapture(viz: Visualizer?, waveform: ByteArray?, samplingRate: Int) {}
            override fun onFftDataCapture(viz: Visualizer?, fft: ByteArray?, samplingRate: Int) {
                if (fft == null || eventSink == null) return
                val n = fft.size
                if (n < 8) return

                // FFT format from Android Visualizer:
                // fft[0] = DC (real), fft[1] = Nyquist (real)
                // For k >= 1: real at fft[2k], imag at fft[2k+1]
                val numBins = n / 2
                val magnitudes = FloatArray(numBins)
                magnitudes[0] = Math.abs(fft[0].toFloat())  // DC
                if (numBins > 1) {
                    magnitudes[numBins - 1] = Math.abs(fft[1].toFloat())  // Nyquist
                }
                for (k in 1 until numBins - 1) {
                    val real = fft[2 * k].toFloat()
                    val imag = fft[2 * k + 1].toFloat()
                    magnitudes[k] = Math.sqrt((real * real + imag * imag).toDouble()).toFloat()
                }

                // Take bins 3..34 (32 bins), skipping DC/Nyquist and very low rumble.
                // At 22050 Hz sample rate with 256 bins, each bin = ~86 Hz.
                // Bin 3 = ~258 Hz, bin 34 = ~2924 Hz - the most musical range.
                val startBin = 3
                val numDisplayBins = 32
                val result = FloatArray(numDisplayBins)
                for (i in 0 until numDisplayBins) {
                    val srcIdx = startBin + i
                    val mag = if (srcIdx < magnitudes.size) magnitudes[srcIdx] else 0f
                    // Normalize to 0..1 using a fixed scale (Visualizer magnitudes
                    // are typically 0..~50 for music, max ~127)
                    val norm = (mag / 50f).coerceIn(0f, 1f)
                    // Apply log scaling for better visual response
                    val logScaled = (Math.log10(1.0 + 9.0 * norm.toDouble()) * 255f).toFloat()
                    result[i] = logScaled
                }

                val list = ArrayList<Double>(numDisplayBins)
                for (v in result) {
                    list.add(v.toDouble())
                }
                eventSink?.success(list)
            }
        }, 20000, false, true)
        v.enabled = true
        visualizer = v
        Log.i("VisualizerPlugin", "FFT Visualizer attached to session $sessionId")
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