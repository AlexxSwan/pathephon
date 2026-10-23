package com.swanlab.audiox64

import android.media.audiofx.Equalizer
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger

/// Native Android Equalizer bridge.
/// Attaches to the given audio session id and applies 5-band EQ.
class EqualizerPlugin(binaryMessenger: BinaryMessenger) {
    private val methodChannel = MethodChannel(binaryMessenger, "pathephon/equalizer")
    private var equalizer: Equalizer? = null
    private var enabled: Boolean = false

    init {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "attach" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    try {
                        attach(sessionId)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("EqualizerPlugin", "attach failed: ${e.message}", e)
                        result.error("ATTACH_FAILED", e.message, null)
                    }
                }
                "setEnabled" -> {
                    val en = call.argument<Boolean>("enabled") ?: false
                    setEnabled(en)
                    result.success(null)
                }
                "setBandGain" -> {
                    val band = call.argument<Int>("band") ?: -1
                    val gain = call.argument<Double>("gain") ?: 0.0
                    setBandGain(band, gain)
                    result.success(null)
                }
                "setAllBands" -> {
                    val gains = call.argument<List<Double>>("gains")
                    if (gains != null) setAllBands(gains)
                    result.success(null)
                }
                "release" -> {
                    release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun attach(sessionId: Int) {
        release()
        if (sessionId == 0) {
            Log.w("EqualizerPlugin", "sessionId is 0 - cannot attach")
            return
        }
        val eq = Equalizer(0, sessionId)
        equalizer = eq
        eq.enabled = enabled
        Log.i("EqualizerPlugin", "Equalizer attached to session $sessionId, bands=${eq.numberOfBands}")
    }

    private fun setEnabled(en: Boolean) {
        enabled = en
        try {
            equalizer?.enabled = en
            Log.i("EqualizerPlugin", "enabled=$en")
        } catch (e: Exception) {
            Log.w("EqualizerPlugin", "setEnabled failed: ${e.message}")
        }
    }

    private fun setBandGain(band: Int, gain: Double) {
        val eq = equalizer ?: return
        try {
            if (band < 0 || band >= eq.numberOfBands) return
            val minGain = eq.bandLevelRange[0].toDouble() / 100.0  // mB to dB
            val maxGain = eq.bandLevelRange[1].toDouble() / 100.0
            val clamped = gain.coerceIn(minGain, maxGain)
            val mB = (clamped * 100).toInt()
            eq.setBandLevel(band.toShort(), mB.toShort())
            Log.i("EqualizerPlugin", "band $band set to $clamped dB")
        } catch (e: Exception) {
            Log.w("EqualizerPlugin", "setBandGain failed: ${e.message}")
        }
    }

    private fun setAllBands(gains: List<Double>) {
        val eq = equalizer ?: return
        try {
            val range = eq.bandLevelRange
            val minGain = range[0].toDouble() / 100.0
            val maxGain = range[1].toDouble() / 100.0
            val count = minOf(gains.size, eq.numberOfBands.toInt())
            for (i in 0 until count) {
                val clamped = gains[i].coerceIn(minGain, maxGain)
                val mB = (clamped * 100).toInt()
                eq.setBandLevel(i.toShort(), mB.toShort())
            }
            Log.i("EqualizerPlugin", "set $count bands")
        } catch (e: Exception) {
            Log.w("EqualizerPlugin", "setAllBands failed: ${e.message}")
        }
    }

    private fun release() {
        try {
            equalizer?.let {
                it.enabled = false
                it.release()
            }
        } catch (e: Exception) {
            Log.w("EqualizerPlugin", "release: ${e.message}")
        }
        equalizer = null
    }

    fun dispose() {
        release()
    }
}