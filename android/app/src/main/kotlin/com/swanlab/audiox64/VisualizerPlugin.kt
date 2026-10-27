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
                // IMPORTANT: DC (fft[0]) and Nyquist (fft[1]) are NOT real frequencies.
                // Including them causes the leftmost bins to always be at peak (DC offset).
                // We skip them entirely.
                val numBins = n / 2  // total bins including DC/Nyquist
                // Take bins 2..33 (32 display bins), fully skipping DC/Nyquist.
                // At 22050 Hz sample rate with 256 bins, each bin = ~86 Hz.
                // Bin 2 = ~172 Hz, bin 33 = ~2838 Hz - musical range.
                val startBin = 2
                val numDisplayBins = 32
                val result = FloatArray(numDisplayBins)
                for (i in 0 until numDisplayBins) {
                    val k = startBin + i
                    if (k >= numBins) { result[i] = 0f; continue }
                    // Real at fft[2*k], Imaginary at fft[2*k+1]
                    val real = fft[2 * k].toFloat()
                    val imag = fft[2 * k + 1].toFloat()
                    val mag = Math.sqrt((real * real + imag * imag).toDouble()).toFloat()
                    // Normalize: Visualizer magnitudes typically 0..~50 for music
                    val norm = (mag / 50f).coerceIn(0f, 1f)
                    // Perceptual compensation: music naturally has more bass energy
                    // (pink noise / 1/f). To make the spectrum look balanced:
                    // - Attenuate low bins (i=0..7): gain 0.4..0.7
                    // - Keep mid bins (i=8..23): gain 0.8..1.0
                    // - Boost high bins (i=24..31): gain 1.0..1.5
                    val gain = when {
                        i < 4 -> 0.35f   // very low bass - heavily attenuated
                        i < 8 -> 0.55f   // bass - attenuated
                        i < 16 -> 0.80f  // low-mid - slightly attenuated
                        i < 24 -> 1.0f   // mid-high - neutral
                        else -> 1.3f     // high - boosted
                    }
                    val compensated = (norm * gain).coerceIn(0f, 1f)
                    // Log scaling for better visual response
                    val logScaled = (Math.log10(1.0 + 9.0 * compensated.toDouble()) * 255f).toFloat()
                    result[i] = logScaled
                }

                val list = ArrayList<Double>(numDisplayBins)
                for (v in result) {
                    list.add(v.toDouble())
                }
                eventSink?.success(list)
            }
        }, 50000, false, true)
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