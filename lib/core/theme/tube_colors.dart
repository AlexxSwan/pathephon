// ============================================================================
//  tube_colors.dart — Retro-tube color palette
//
//  Inspiration: vacuum-tube glow on dark chassis, brass bezels, walnut panels.
//  Carefully tuned for OLED (true black background) while keeping contrast
//  accessible (WCAG AA on body text).
// ============================================================================
import 'dart:ui';

class TubeColors {
  TubeColors._();

  // --- Surface / chassis ----------------------------------------------------
  /// Pure black for OLED power saving (true #000000, not "almost-black").
  static const Color background = Color(0xFF0E0B08);
  /// Slightly lifted panel surface (chassis recesses, knobs).
  static const Color surface = Color(0xFF181310);
  /// Brass-trim elevation surface (cards, dialogs).
  static const Color surfaceVariant = Color(0xFF221911);
  /// Hairline border between panels (tube socket seams).
  static const Color outline = Color(0xFF3A2A1C);

  // --- Tube glow (amber → orange → red) ------------------------------------
  /// Main accent — incandescent amber (cathode glow).
  static const Color amber = Color(0xFFFFB347);
  /// Hotter, more saturated — used for active/play state.
  static const Color amberHot = Color(0xFFFF7A00);
  /// Cooldown amber — passive states, dividers.
  static const Color amberCool = Color(0xFFB0611F);
  /// Filament white — peak highlights, near-white filament core.
  static const Color filament = Color(0xFFFFE5B4);

  // --- Brass / metalwork ----------------------------------------------------
  static const Color brass = Color(0xFFB08D57);
  static const Color brassDark = Color(0xFF6E5430);

  // --- Semantic -------------------------------------------------------------
  /// Phosphor green for VU-meter peaks / EQ meters (like vintage oscilloscopes).
  static const Color phosphorGreen = Color(0xFF39FF14);
  /// Red VU peak warning (clipping).
  static const Color phosphorRed = Color(0xFFFF3A3A);

  // --- Text -----------------------------------------------------------------
  static const Color textPrimary = Color(0xFFFFE5B4);
  static const Color textSecondary = Color(0xFFC9A77B);
  static const Color textMuted = Color(0xFF7A6347);

  // --- Ambient accent (extracted from album art at runtime) -----------------
  /// Override `amber` when an album-art palette is available — set via
  /// `AmbientColorController.setPalette()` in `retro_theme.dart`.
  static Color? ambientOverride;
}
