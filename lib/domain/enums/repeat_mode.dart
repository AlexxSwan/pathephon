// ============================================================================
//  repeat_mode.dart — playback loop mode
// ============================================================================
enum RepeatMode {
  off,
  all,
  one;

  RepeatMode get next => switch (this) {
        off => all,
        all => one,
        one => off,
      };
}
