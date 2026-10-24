package com.swanlab.audiox64

import android.media.audiofx.Visualizer
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel.EventSink

/// Native Android Visualizer - FFT spectrum analyzer mode.
/// Captures FFT data and returns frequency bin magnitudes (0..255 normalized).
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

        // Use captureSize = 256 -> FFT gives 128 bins (we'll take first 32 for display)
        val captureSize = 256

        val v = Visualizer(sessionId)
        v.captureSize = captureSize
        // Enable FFT data capture (not waveform)
        v.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
            override fun onWaveFormDataCapture(viz: Visualizer?, waveform: ByteArray?, samplingRate: Int) {}
            override fun onFftDataCapture(viz: Visualizer?, fft: ByteArray?, samplingRate: Int) {
                if (fft == null || eventSink == null) return
                val n = fft.size
                if (n < 4) return

                // FFT format from Android Visualizer:
                // fft[0] = DC, fft[1] = Nyquist
                // For k >= 2: real part at fft[2k-2], imaginary at fft[2k-1]
                // We compute magnitude = sqrt(real^2 + imag^2) for each bin.
                // Number of frequency bins = (n - 2) / 2 + 1 = n/2

                val numBins = n / 2
                val magnitudes = FloatArray(numBins)

                // DC component (bin 0)
                magnitudes[0] = Math.abs(fft[0].toFloat())
                // Nyquist (bin numBins-1)
                if (numBins > 1) {
                    magnitudes[numBins - 1] = Math.abs(fft[1].toFloat())
                }
                // Other bins
                for (k in 1 until numBins - 1) {
                    val real = fft[2 * k].toFloat()
                    val imag = fft[2 * k + 1].toFloat()
                    magnitudes[k] = Math.sqrt((real * real + imag * imag).toDouble()).toFloat()
                }

                // Normalize to 0..255 (byte range)
                // Find max for normalization, then scale
                var maxMag = 1f
                for (m in magnitudes) {
                    if (m > maxMag) maxMag = m
                }
                val scale = 255f / maxMag

                // Take first 32 bins (covers ~0 to ~5kHz at 22kHz sample rate)
                // These are the most musically relevant frequencies
                val numDisplayBins = Math.min(32, numBins)
                val result = FloatArray(numDisplayBins)
                for (i in 0 until numDisplayBins) {
                    // Apply slight log scaling for better visual response
                    val norm = (magnitudes[i] * scale / 255f).coerceIn(0f, 1f)
                    val logScaled = (Math.log10(1.0 + 9.0 * norm) * 255f).toFloat()
                    result[i] = logScaled
                }

                // Convert to List<Double> for Flutter
                val list = ArrayList<Double>(numDisplayBins)
                for (v in result) {
                    list.add(v.toDouble())
                }
                eventSink?.success(list)
            }
        }, 20000, false, true)  // waveform=false, fft=true
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