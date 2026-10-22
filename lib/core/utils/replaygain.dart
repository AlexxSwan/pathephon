// ============================================================================
//  replaygain.dart — convert ReplayGain tags to ExoPlayer volume scale
//
//  ExoPlayer accepts `player.volume` in 0.0..1.0; values > 1.0 are clamped.
//  To respect ReplayGain we therefore boost by converting dB → linear gain,
//  then scale so a +6 dB tag lands at volume=1.0 (full scale).
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
    // linear gain relative to reference
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
}

enum ReplayGainMode { off, track, album }
