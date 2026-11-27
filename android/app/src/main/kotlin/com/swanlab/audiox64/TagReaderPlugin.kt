package com.swanlab.audiox64

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteOrder
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class TagReaderPlugin : FlutterPlugin, MethodCallHandler {
    companion object {
        private const val TAG = "Pathephon/TagReader"
        private const val CHANNEL = "pathephon/tag_reader"
    }

    private var context: Context? = null
    private var channel: MethodChannel? = null
    private lateinit var bgExecutor: ExecutorService
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        bgExecutor = Executors.newSingleThreadExecutor()
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        Log.i(TAG, "onAttachedToEngine")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
        try { bgExecutor.shutdown() } catch (_: Exception) {}
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "readTags" -> {
                val path = call.argument<String>("path") ?: ""
                val uri = call.argument<String>("uri") ?: ""
                if (path.isEmpty() && uri.isEmpty()) {
                    result.error("ERROR", "path or uri required", null)
                    return
                }
                try {
                    val tags = readTags(path, uri)
                    Log.i(TAG, "readTags: path=$path title=${tags["title"]} artist=${tags["artist"]} mime=${tags["mimeType"]} hasArt=${tags.containsKey("artBytes")}")
                    result.success(tags)
                } catch (e: Exception) {
                    Log.e(TAG, "readTags FAILED: path=$path error=${e.message}", e)
                    result.error("ERROR", e.message, null)
                }
            }
            "readArtwork" -> {
                val path = call.argument<String>("path") ?: ""
                val uri = call.argument<String>("uri") ?: ""
                if (path.isEmpty() && uri.isEmpty()) {
                    result.error("ERROR", "path or uri required", null)
                    return
                }
                try {
                    val art = readEmbeddedPicture(path, uri)
                    if (art != null) {
                        Log.i(TAG, "readArtwork: path=$path size=${art.size}")
                        result.success(art)
                    } else {
                        Log.i(TAG, "readArtwork: path=$path no embedded picture")
                        result.success(null)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "readArtwork FAILED: path=$path error=${e.message}", e)
                    result.error("ERROR", e.message, null)
                }
            }
            "scanLoudness" -> {
                val path = call.argument<String>("path") ?: ""
                if (path.isEmpty()) {
                    result.error("ERROR", "path required", null)
                    return
                }
                // Run on background thread — MediaCodec decode takes 1-2 seconds.
                bgExecutor.execute {
                    val loudness = scanLoudness(path)
                    mainHandler.post { result.success(loudness) }
                }
            }
            else -> result.notImplemented()
        }
    }

    /// Phase 44: Scan RMS loudness of an audio file.
    /// Decodes ~3 seconds from the middle of the track via MediaExtractor +
    /// MediaCodec, computes RMS of 16-bit PCM samples, returns RMS in dB.
    /// Used for automatic volume normalization across tracks.
    /// Returns a Double (RMS in dB, typically -25..-5 for music).
    /// Returns -20.0 (default) on any failure.
    private fun scanLoudness(path: String): Double {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(path)
            var audioTrackIdx = -1
            var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val fmt = extractor.getTrackFormat(i)
                val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    audioTrackIdx = i
                    format = fmt
                    break
                }
            }
            if (audioTrackIdx < 0 || format == null) {
                Log.w(TAG, "scanLoudness: no audio track in $path")
                return -20.0
            }
            extractor.selectTrack(audioTrackIdx)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: "audio/mpeg"
            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()

            // Seek to 30% of the track (avoid silence at start/end).
            val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) {
                format.getLong(MediaFormat.KEY_DURATION)
            } else 0L
            if (durationUs > 0) {
                extractor.seekTo(durationUs * 30 / 100, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
            }

            val sampleRate = if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            } else 44100
            val samplesToCollect = sampleRate * 3  // 3 seconds of audio
            var samplesCollected = 0
            var sumSquares = 0.0
            var inputDone = false
            var outputDone = false
            val info = MediaCodec.BufferInfo()

            while (!outputDone && samplesCollected < samplesToCollect) {
                if (!inputDone) {
                    val inIdx = codec.dequeueInputBuffer(10000)
                    if (inIdx >= 0) {
                        val inBuf = codec.getInputBuffer(inIdx)
                        if (inBuf != null) {
                            val sampleSize = extractor.readSampleData(inBuf, 0)
                            if (sampleSize < 0) {
                                codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputDone = true
                            } else {
                                codec.queueInputBuffer(inIdx, 0, sampleSize, extractor.sampleTime, 0)
                                extractor.advance()
                            }
                        }
                    }
                }

                val outIdx = codec.dequeueOutputBuffer(info, 10000)
                if (outIdx >= 0) {
                    val outBuf = codec.getOutputBuffer(outIdx)
                    if (outBuf != null && info.size > 0) {
                        // Decode 16-bit PCM samples (interleaved L/R for stereo).
                        // Byte order: native (little-endian on ARM/x86).
                        val sb = outBuf.duplicate().order(ByteOrder.nativeOrder())
                        sb.position(info.offset)
                        sb.limit(info.offset + info.size)
                        val numShorts = info.size / 2
                        for (i in 0 until numShorts) {
                            if (samplesCollected >= samplesToCollect) break
                            val raw = sb.get().toInt()
                            val sample = raw.toDouble() / 32768.0
                            sumSquares += sample * sample
                            samplesCollected++
                        }
                    }
                    codec.releaseOutputBuffer(outIdx, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                }
            }

            if (samplesCollected == 0) {
                Log.w(TAG, "scanLoudness: no samples decoded for $path")
                return -20.0
            }
            val rms = Math.sqrt(sumSquares / samplesCollected)
            val rmsDb = 20.0 * Math.log10(if (rms > 0.0) rms else 1e-6)
            Log.i(TAG, "scanLoudness: path=$path rmsDb=${"%.1f".format(rmsDb)} samples=$samplesCollected")
            return rmsDb
        } catch (e: Exception) {
            Log.e(TAG, "scanLoudness FAILED: path=$path error=${e.message}", e)
            return -20.0
        } finally {
            try { codec?.stop() } catch (_: Exception) {}
            try { codec?.release() } catch (_: Exception) {}
            try { extractor.release() } catch (_: Exception) {}
        }
    }

    /// Reads embedded picture from audio file via MediaMetadataRetriever.
    /// Returns ByteArray (JPEG/PNG) or null if no embedded artwork.
    private fun readEmbeddedPicture(path: String, uri: String): ByteArray? {
        val mmr = MediaMetadataRetriever()
        try {
            try {
                if (uri.isNotEmpty() && uri.startsWith("content://")) {
                    val ctx = context ?: return null
                    mmr.setDataSource(ctx, android.net.Uri.parse(uri))
                } else if (path.isNotEmpty()) {
                    mmr.setDataSource(path)
                }
            } catch (e: Exception) {
                Log.w(TAG, "setDataSource failed for path=$path: ${e.message}")
                if (uri.isNotEmpty()) {
                    val ctx = context ?: return null
                    mmr.setDataSource(ctx, android.net.Uri.parse(uri))
                } else {
                    return null
                }
            }
            return mmr.embeddedPicture
        } finally {
            try { mmr.release() } catch (_: Exception) {}
        }
    }

    private fun readTags(path: String, uri: String): Map<String, Any> {
        val result = mutableMapOf<String, Any>()

        // MediaMetadataRetriever
        val mmr = MediaMetadataRetriever()
        try {
            try {
                if (uri.isNotEmpty() && uri.startsWith("content://")) {
                    val ctx = context ?: return result
                    mmr.setDataSource(ctx, android.net.Uri.parse(uri))
                } else if (path.isNotEmpty()) {
                    mmr.setDataSource(path)
                }
            } catch (e: Exception) {
                Log.w(TAG, "setDataSource failed for path=$path: ${e.message}")
                if (uri.isNotEmpty()) {
                    val ctx = context ?: return result
                    mmr.setDataSource(ctx, android.net.Uri.parse(uri))
                } else {
                    return result
                }
            }

            val title = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE) ?: ""
            val artist = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST) ?: ""
            val album = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM) ?: ""
            val albumArtist = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST) ?: ""
            val genre = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_GENRE) ?: ""
            val year = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_YEAR) ?: ""
            val trackNumber = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER) ?: ""
            val durationMs = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION) ?: "0"
            val mimeType = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE) ?: ""
            val bitrate = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE) ?: "0"

            result["title"] = title
            result["artist"] = artist
            result["album"] = album
            result["albumArtist"] = albumArtist
            result["genre"] = genre
            result["year"] = year
            result["trackNumber"] = trackNumber
            result["durationMs"] = durationMs
            result["mimeType"] = mimeType
            result["bitrate"] = bitrate

            // Read embedded picture (artwork) — NEW
            val picture = mmr.embeddedPicture
            if (picture != null) {
                result["artBytes"] = picture
            }
        } finally {
            try { mmr.release() } catch (_: Exception) {}
        }

        // ID3v2 fallback
        if ((result["title"] as String? ?: "").isEmpty() && path.isNotEmpty()) {
            val id3tags = parseID3v2(path)
            if (id3tags.isNotEmpty()) {
                Log.i(TAG, "  ID3v2 parsed: ${id3tags.keys}")
                if ((result["title"] as String? ?: "").isEmpty()) result["title"] = id3tags["title"] ?: ""
                if ((result["artist"] as String? ?: "").isEmpty()) result["artist"] = id3tags["artist"] ?: ""
                if ((result["album"] as String? ?: "").isEmpty()) result["album"] = id3tags["album"] ?: ""
                if ((result["albumArtist"] as String? ?: "").isEmpty()) result["albumArtist"] = id3tags["albumArtist"] ?: ""
                if ((result["genre"] as String? ?: "").isEmpty()) result["genre"] = id3tags["genre"] ?: ""
                if ((result["year"] as String? ?: "").isEmpty()) result["year"] = id3tags["year"] ?: ""
                if ((result["trackNumber"] as String? ?: "").isEmpty()) result["trackNumber"] = id3tags["trackNumber"] ?: ""
            }
        }

        return result
    }

    private fun parseID3v2(path: String): Map<String, String> {
        val result = mutableMapOf<String, String>()
        try {
            val raf = RandomAccessFile(path, "r")
            try {
                val header = ByteArray(10)
                raf.readFully(header)

                if (header[0] != 'I'.code.toByte() || header[1] != 'D'.code.toByte() || header[2] != '3'.code.toByte()) {
                    return result
                }

                val version = (header[3].toInt() and 0xFF)
                val flags = header[5].toInt() and 0xFF

                val size = ((header[6].toInt() and 0x7F) shl 21) or
                           ((header[7].toInt() and 0x7F) shl 14) or
                           ((header[8].toInt() and 0x7F) shl 7) or
                           (header[9].toInt() and 0x7F)

                if (size <= 0 || size > 10 * 1024 * 1024) return result

                val tagData = ByteArray(size)
                raf.readFully(tagData)

                var pos = 0
                while (pos < tagData.size - 10) {
                    val frameId = String(tagData, pos, 4, Charsets.ISO_8859_1)
                    if (frameId[0] == '\u0000') break

                    val frameSize: Int
                    if (version == 4) {
                        frameSize = ((tagData[pos + 4].toInt() and 0x7F) shl 21) or
                                    ((tagData[pos + 5].toInt() and 0x7F) shl 14) or
                                    ((tagData[pos + 6].toInt() and 0x7F) shl 7) or
                                    (tagData[pos + 7].toInt() and 0x7F)
                    } else {
                        frameSize = ((tagData[pos + 4].toInt() and 0xFF) shl 24) or
                                    ((tagData[pos + 5].toInt() and 0xFF) shl 16) or
                                    ((tagData[pos + 6].toInt() and 0xFF) shl 8) or
                                    (tagData[pos + 7].toInt() and 0xFF)
                    }

                    if (frameSize <= 0 || frameSize > tagData.size - pos - 10) break

                    val dataOffset = pos + 10
                    if (dataOffset + frameSize > tagData.size) break

                    val frameData = tagData.copyOfRange(dataOffset, dataOffset + frameSize)
                    val text = decodeFrame(frameData, frameId)

                    when (frameId) {
                        "TIT2" -> result["title"] = text
                        "TPE1" -> result["artist"] = text
                        "TPE2" -> result["albumArtist"] = text
                        "TALB" -> result["album"] = text
                        "TCON" -> result["genre"] = text
                        "TYER", "TDRC" -> result["year"] = text
                        "TRCK" -> result["trackNumber"] = text
                    }

                    pos = dataOffset + frameSize
                }
            } finally {
                raf.close()
            }
        } catch (e: Exception) {
            Log.w(TAG, "parseID3v2 failed: ${e.message}")
        }
        return result
    }

    private fun decodeFrame(data: ByteArray, frameId: String): String {
        if (data.isEmpty()) return ""
        try {
            val encoding = data[0].toInt() and 0xFF
            val textData = data.copyOfRange(1, data.size)

            return when (encoding) {
                0 -> {
                    val str = String(textData, Charsets.ISO_8859_1)
                    str.trimEnd('\u0000').trim()
                }
                1 -> {
                    val str = String(textData, Charsets.UTF_16)
                    str.trimEnd('\u0000').trim()
                }
                2 -> {
                    val str = String(textData, Charsets.UTF_16BE)
                    str.trimEnd('\u0000').trim()
                }
                3 -> {
                    val str = String(textData, Charsets.UTF_8)
                    str.trimEnd('\u0000').trim()
                }
                else -> {
                    val str = String(textData, Charsets.ISO_8859_1)
                    str.trimEnd('\u0000').trim()
                }
            }
        } catch (e: Exception) {
            return ""
        }
    }
}
