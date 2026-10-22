// ============================================================================
//  retro_theme.dart — Material 3 ThemeData for the retro-tube look
//
//  - Dark-only (the player is meant for evening listening; OLED-friendly).
//  - Custom ColorScheme built on TubeColors.
//  - VT323 / Share Tech Mono / Crimson Pro typography swap (loaded by
//    pubspec.yaml `fonts:` block).
// ============================================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tube_colors.dart';

class RetroTheme {
  RetroTheme._();

  static ThemeData get dark {
    final amber = TubeColors.ambientOverride ?? TubeColors.amber;

    final colorScheme = const ColorScheme.dark().copyWith(
      primary: amber,
      onPrimary: TubeColors.background,
      secondary: TubeColors.brass,
      onSecondary: TubeColors.background,
      tertiary: TubeColors.phosphorGreen,
      onTertiary: TubeColors.background,
      surface: TubeColors.surface,
      onSurface: TubeColors.textPrimary,
      surfaceContainerHighest: TubeColors.surfaceVariant,
      onSurfaceVariant: TubeColors.textSecondary,
      outline: TubeColors.outline,
      outlineVariant: TubeColors.brassDark,
      error: TubeColors.phosphorRed,
      onError: TubeColors.background,
      scrim: Colors.black,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: TubeColors.background,
      canvasColor: TubeColors.background,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    // ---- Typography: 3 families -------------------------------------------
    //   VT323         → display (giant retro headers)
    //   ShareTechMono → labels, technical readouts (timecode, EQ band Hz)
    //   CrimsonPro    → body / long-form (album notes, lyrics)
    final vt = GoogleFonts.vt323();
    final stm = GoogleFonts.shareTechMono();
    final crimson = GoogleFonts.crimsonPro();

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayLarge: vt.copyWith(fontSize: 64, color: TubeColors.textPrimary, letterSpacing: 1.2),
        displayMedium: vt.copyWith(fontSize: 48, color: TubeColors.textPrimary),
        displaySmall: vt.copyWith(fontSize: 32, color: TubeColors.amber, letterSpacing: 1.0),
        headlineLarge: vt.copyWith(fontSize: 28, color: TubeColors.textPrimary),
        headlineMedium: vt.copyWith(fontSize: 22, color: TubeColors.textPrimary),
        headlineSmall: vt.copyWith(fontSize: 18, color: TubeColors.textSecondary),
        titleLarge: stm.copyWith(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0.8),
        titleMedium: stm.copyWith(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: 0.6),
        titleSmall: stm.copyWith(fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0.5),
        bodyLarge: crimson.copyWith(fontSize: 16, height: 1.45),
        bodyMedium: crimson.copyWith(fontSize: 14, height: 1.4),
        bodySmall: crimson.copyWith(fontSize: 12, height: 1.35),
        labelLarge: stm.copyWith(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.0),
        labelMedium: stm.copyWith(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8),
        labelSmall: stm.copyWith(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.6),
      ),

      // ---- Buttons: amber filaments with bronze trim -----------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: amber,
          foregroundColor: TubeColors.background,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero, // sharp = chassis look
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: amber,
          side: BorderSide(color: TubeColors.brass, width: 1.5),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: amber,
          iconSize: 24,
          padding: const EdgeInsets.all(8),
        ),
      ),

      // ---- App bars: brass-trimmed chassis --------------------------------
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: stm.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: TubeColors.amber,
        ),
        iconTheme: IconThemeData(color: amber, size: 24),
      ),

      // ---- Cards: recessed chassis panels ---------------------------------
      // NOTE: cardTheme API differs across Flutter versions
      // (CardTheme in <3.27, CardThemeData in 3.27+). We avoid the conflict
      // by post-mutating base ThemeData via copyWith.
      // (handled below — see end of method)

      // ---- Sliders: brass track + amber thumb ------------------------------
      sliderTheme: SliderThemeData(
        activeTrackColor: amber,
        inactiveTrackColor: TubeColors.brassDark,
        thumbColor: TubeColors.filament,
        overlayColor: amber.withOpacity(0.18),
        trackHeight: 2,
        thumbShape: const _RetroThumbShape(),
      ),

      // ---- Lists: chassis rows --------------------------------------------
      listTileTheme: ListTileThemeData(
        iconColor: amber,
        textColor: TubeColors.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: TubeColors.outline, width: 0.5),
        ),
      ),

      // ---- Dividers: hairline bronze --------------------------------------
      dividerTheme: DividerThemeData(
        color: TubeColors.outline,
        thickness: 1,
        space: 1,
      ),

      // ---- Bottom nav: brass backplate ------------------------------------
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: TubeColors.surface,
        indicatorColor: amber,
        labelTextStyle: WidgetStatePropertyAll(
          stm.copyWith(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? TubeColors.background : amber, size: 24);
        }),
      ),

      // ---- Snackbars: amber-on-black --------------------------------------
      snackBarTheme: SnackBarThemeData(
        backgroundColor: TubeColors.surfaceVariant,
        contentTextStyle: stm.copyWith(fontSize: 13, color: TubeColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    );

    // ---- Cards: applied via copyWith to avoid CardTheme/CardThemeData
    //      API mismatch across Flutter 3.24 / 3.27+.
    return base.copyWith(
      cardTheme: base.cardTheme.copyWith(
        color: TubeColors.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: TubeColors.outline, width: 1),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
    );
  }

  /// Toggle the ambient accent color extracted from the current track's
  /// album art. Pass `null` to revert to default amber.
  static void setAmbientColor(Color? color) {
    TubeColors.ambientOverride = color;
  }
}

/// Square brass-trimmed slider thumb — mimics a knob.
class _RetroThumbShape extends SliderComponentShape {
  const _RetroThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(20, 20);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double textScaleFactor,
    required Size sizeWithOverflow,
    required double value,
  }) {
    final canvas = context.canvas;
    final r = 8.0;
    final paint = Paint()
      ..color = TubeColors.filament
      ..style = PaintingStyle.fill;
    final rim = Paint()
      ..color = TubeColors.brass
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, r, paint);
    canvas.drawCircle(center, r, rim);
    canvas.drawCircle(center, r * 0.4, Paint()..color = TubeColors.amberHot);
  }
}
