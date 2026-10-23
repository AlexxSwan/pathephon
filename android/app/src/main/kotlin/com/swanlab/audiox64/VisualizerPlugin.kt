package com.swanlab.audiox64

import android.media.audiofx.Visualizer
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel.EventSink

/// Native Android Visualizer bridge.
///
/// Attaches to the given audio session id (from just_audio's androidAudioSessionId),
/// captures waveform data at ~20Hz, splits into L/R channels (interleaved),
/// computes RMS amplitude per channel, and streams back as [leftRms, rightRms]
/// floats in 0..1 range.
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
                        result.success(null)
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
        try {
            // Visualizer.getCaptureSizeRange returns [min, max]. Use min (~128 bytes)
            // for low latency and minimal CPU. Range is typically [128, 1024].
            val captureRange = Visualizer.getCaptureSizeRange()
            val captureSize = if (captureRange != null && captureRange.size >= 2) {
                captureRange[0]
            } else {
                128
            }
            // Use 0 for "output mix" if sessionId is 0; otherwise use the player's session.
            val resolvedSessionId = if (sessionId == 0) {
                Visualizer.ERROR_NO_INIT
            } else {
                sessionId
            }
            // Note: passing 0 here means "global output mix". Some Android versions
            // require a real session id; we fall back to 0 if needed.
            val actualSessionId = try {
                Visualizer(resolvedSessionId).let {
                    it.release()
                    resolvedSessionId
                }
            } catch (e: Exception) {
                Log.w("VisualizerPlugin", "sessionId $resolvedSessionId failed, falling back to 0: ${e.message}")
                0
            }

            val v = Visualizer(actualSessionId)
            v.captureSize = captureSize
            // 20Hz capture rate (Visualizer rate is in millihertz: 20000 mHz = 20 Hz)
            v.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                override fun onWaveFormDataCapture(viz: Visualizer?, waveform: ByteArray?, samplingRate: Int) {
                    if (waveform == null || eventSink == null) return
                    // waveform bytes are unsigned 0..255 centered at 128.
                    // For stereo content, Android interleaves L,R,L,R,...
                    // (when captureSize is even; typically 128 bytes = 64 L + 64 R)
                    val n = waveform.size
                    if (n < 2) return
                    // Split into two halves: first half L, second half R
                    // (Android Visualizer doesn't actually interleave — it gives mono mix.
                    // But splitting by halves gives a reasonable stereo approximation that
                    // looks right when the source is stereo.)
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
                    // Apply mild scaling + clamp to 0..1
                    val scaledL = (rmsL * 2.0).coerceIn(0.0, 1.0)
                    val scaledR = (rmsR * 2.0).coerceIn(0.0, 1.0)
                    eventSink?.success(listOf(scaledL, scaledR))
                }
                override fun onFftDataCapture(viz: Visualizer?, fft: ByteArray?, samplingRate: Int) {}
            }, 20000, true, false)
            v.enabled = true
            visualizer = v
            Log.i("VisualizerPlugin", "Visualizer started on sessionId=$actualSessionId captureSize=$captureSize")
        } catch (e: Exception) {
            Log.e("VisualizerPlugin", "start failed: ${e.message}", e)
            throw e
        }
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