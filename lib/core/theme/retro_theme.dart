// ============================================================================
//  retro_theme.dart — Material 3 ThemeData + ThemePresetScope
//  3 presets: Amber (0), Ocean (1), Forest (2)
// ============================================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tube_colors.dart';

class ThemePreset {
  final String name;
  final Color accent, accentHot, accentCool, brass, brassDark;
  final Color background, surface, surfaceVariant, outline;
  final Color textPrimary, textSecondary, textMuted, filament;

  const ThemePreset({
    required this.name,
    required this.accent, required this.accentHot, required this.accentCool,
    required this.brass, required this.brassDark,
    required this.background, required this.surface, required this.surfaceVariant,
    required this.outline,
    required this.textPrimary, required this.textSecondary, required this.textMuted,
    required this.filament,
  });

  static const amber = ThemePreset(
    name: 'Янтарь',
    accent: Color(0xFFFFB347), accentHot: Color(0xFFFF7A00), accentCool: Color(0xFFB0611F),
    brass: Color(0xFFB08D57), brassDark: Color(0xFF6E5430),
    background: Color(0xFF0E0B08), surface: Color(0xFF181310), surfaceVariant: Color(0xFF221911),
    outline: Color(0xFF3A2A1C),
    textPrimary: Color(0xFFFFE5B4), textSecondary: Color(0xFFC9A77B), textMuted: Color(0xFF7A6347),
    filament: Color(0xFFFFE5B4),
  );

  static const ocean = ThemePreset(
    name: 'Океан',
    accent: Color(0xFF4FC3F7), accentHot: Color(0xFF0288D1), accentCool: Color(0xFF01579B),
    brass: Color(0xFF4A90A4), brassDark: Color(0xFF2A5060),
    background: Color(0xFF060A0E), surface: Color(0xFF0C1419), surfaceVariant: Color(0xFF102028),
    outline: Color(0xFF1A2A35),
    textPrimary: Color(0xFFB3E5FC), textSecondary: Color(0xFF7AB8D4), textMuted: Color(0xFF3A6080),
    filament: Color(0xFFB3E5FC),
  );

  static const forest = ThemePreset(
    name: 'Лес',
    accent: Color(0xFF66BB6A), accentHot: Color(0xFF2E7D32), accentCool: Color(0xFF1B5E20),
    brass: Color(0xFF558B5A), brassDark: Color(0xFF2E5032),
    background: Color(0xFF060A06), surface: Color(0xFF0C130C), surfaceVariant: Color(0xFF101A10),
    outline: Color(0xFF1A2A1A),
    textPrimary: Color(0xFFC8E6C9), textSecondary: Color(0xFF81C784), textMuted: Color(0xFF3A6040),
    filament: Color(0xFFC8E6C9),
  );

  static const all = [amber, ocean, forest];
}

/// InheritedWidget that provides the current ThemePreset to all descendants.
/// Use `Preset.of(context)` to get the current preset's colors.
class Preset extends InheritedWidget {
  final ThemePreset preset;
  const Preset({super.key, required this.preset, required super.child});

  static ThemePreset of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<Preset>()?.preset ?? ThemePreset.amber;
  }

  @override
  bool updateShouldNotify(Preset old) => preset != old.preset;
}

class RetroTheme {
  RetroTheme._();
  static ThemeData forPreset(int index) {
    final p = ThemePreset.all[index.clamp(0, ThemePreset.all.length - 1)];
    return _build(p);
  }
  static ThemeData get dark => forPreset(0);

  static ThemeData _build(ThemePreset p) {
    final colorScheme = const ColorScheme.dark().copyWith(
      primary: p.accent, onPrimary: p.background,
      secondary: p.brass, onSecondary: p.background,
      tertiary: TubeColors.phosphorGreen, onTertiary: p.background,
      surface: p.surface, onSurface: p.textPrimary,
      surfaceContainerHighest: p.surfaceVariant, onSurfaceVariant: p.textSecondary,
      outline: p.outline, outlineVariant: p.brassDark,
      error: TubeColors.phosphorRed, onError: p.background, scrim: Colors.black,
    );
    final base = ThemeData(
      useMaterial3: true, brightness: Brightness.dark, colorScheme: colorScheme,
      scaffoldBackgroundColor: p.background, canvasColor: p.background,
      splashFactory: InkSparkle.splashFactory, visualDensity: VisualDensity.standard,
    );
    final vt = GoogleFonts.vt323();
    final stm = GoogleFonts.shareTechMono();
    final crimson = GoogleFonts.crimsonPro();
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayLarge: vt.copyWith(fontSize: 64, color: p.textPrimary, letterSpacing: 1.2),
        displayMedium: vt.copyWith(fontSize: 48, color: p.textPrimary),
        displaySmall: vt.copyWith(fontSize: 32, color: p.accent, letterSpacing: 1.0),
        headlineLarge: vt.copyWith(fontSize: 28, color: p.textPrimary),
        headlineMedium: vt.copyWith(fontSize: 22, color: p.textPrimary),
        headlineSmall: vt.copyWith(fontSize: 18, color: p.textSecondary),
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
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: p.accent, foregroundColor: p.background,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor: p.accent, side: BorderSide(color: p.brass, width: 1.5),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      )),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: p.accent, iconSize: 24)),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent, elevation: 0, centerTitle: false,
        titleTextStyle: stm.copyWith(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: p.accent),
        iconTheme: IconThemeData(color: p.accent, size: 24),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent, inactiveTrackColor: p.brassDark,
        thumbColor: p.filament, overlayColor: p.accent.withOpacity(0.18),
        trackHeight: 2, thumbShape: _RetroThumbShape(p),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.accent, textColor: p.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: p.outline, width: 0.5)),
      ),
      dividerTheme: DividerThemeData(color: p.outline, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface, indicatorColor: p.accent,
        labelTextStyle: WidgetStatePropertyAll(stm.copyWith(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? p.background : p.accent, size: 24);
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceVariant,
        contentTextStyle: stm.copyWith(fontSize: 13, color: p.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: p.surface, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: p.outline, width: 1)),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
    );
  }
  static void setAmbientColor(Color? color) { TubeColors.ambientOverride = color; }
}

class _RetroThumbShape extends SliderComponentShape {
  const _RetroThumbShape(this.p);
  final ThemePreset p;
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(20, 20);
  @override
  void paint(PaintingContext context, Offset center, {
    required Animation<double> activationAnimation, required Animation<double> enableAnimation,
    required bool isDiscrete, required TextPainter labelPainter, required RenderBox parentBox,
    required SliderThemeData sliderTheme, required TextDirection textDirection,
    required double textScaleFactor, required Size sizeWithOverflow, required double value,
  }) {
    final canvas = context.canvas;
    final r = 8.0;
    canvas.drawCircle(center, r, Paint()..color = p.filament..style = PaintingStyle.fill);
    canvas.drawCircle(center, r, Paint()..color = p.brass..style = PaintingStyle.stroke..strokeWidth = 2);
    canvas.drawCircle(center, r * 0.4, Paint()..color = p.accentHot);
  }
}