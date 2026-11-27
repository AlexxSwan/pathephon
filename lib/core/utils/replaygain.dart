// ============================================================================
//  replaygain.dart — volume normalization utilities
//
//  Two modes:
//  1. ReplayGain tag-based (dbToVolume / selectGain) — requires files with
//     REPLAYGAIN_TRACK_GAIN / REPLAYGAIN_ALBUM_GAIN tags.
//  2. RMS-based auto-normalization (rmsToVolume) — measures RMS loudness via
//     native MediaCodec decode and normalizes to a target level. Works for
//     ALL files, no tags needed. Phase 44.
//
//  ExoPlayer accepts `player.volume` in 0.0..1.0; values > 1.0 are clamped.
// ============================================================================
import 'dart:math' as math;

class ReplayGainApplier {
  ReplayGainApplier._();

  /// Convert a dB gain to a normalized volume in [0, 1].
  /// [gainDb] typically comes from ID3 `REPLAYGAIN_TRACK_GAIN` or
  /// Vorbis `REPLAYGAIN_TRACK_GAIN`.
  /// [referenceDb] sets the headroom — defaults to 6 dB so a +6 dB tag
  /// maps to full scale.
  static double dbToVolume(double? gainDb, {double referenceDb = 6.0}) {
    if (gainDb == null) return 1.0;
    final linear = math.pow(10.0, (gainDb - referenceDb) / 20.0).toDouble();
    return linear.clamp(0.0, 1.0);
  }

  /// Pick the right gain given the mode: track (default) or album.
  static double selectGain({
    required double? trackGain,
    required double? albumGain,
    required ReplayGainMode mode,
  }) {
    switch (mode) {
      case ReplayGainMode.off:
        return 1.0;
      case ReplayGainMode.track:
        return dbToVolume(trackGain);
      case ReplayGainMode.album:
        return dbToVolume(albumGain);
    }
  }

  /// Phase 44: Convert measured RMS (in dB) to a volume multiplier in [0, 1].
  ///
  /// [rmsDb] is the measured RMS loudness of the track (e.g., -12.0 for a
  /// loud pop track, -22.0 for a quiet classical piece).
  /// [targetDb] is the target RMS level — all tracks are normalized toward
  /// this level. Default -16.0 dB (moderate, avoids making everything too
  /// quiet).
  /// [minGainDb] / [maxGainDb] clamp the correction to avoid extreme
  /// adjustments. Default [-12, +6] dB.
  ///
  /// Since ExoPlayer clamps volume to [0, 1], loud tracks (RMS > target)
  /// are reduced, quiet tracks (RMS < target) play at full volume (1.0).
  /// This reduces the loudness gap between tracks from different sources.
  static double rmsToVolume(
    double rmsDb, {
    double targetDb = -16.0,
    double minGainDb = -12.0,
    double maxGainDb = 6.0,
  }) {
    final gainDb = (targetDb - rmsDb).clamp(minGainDb, maxGainDb);
    final volume = math.pow(10.0, gainDb / 20.0).toDouble();
    return volume.clamp(0.0, 1.0);
  }
}

enum ReplayGainMode { off, track, album }
