// ============================================================================
//  spectrum_painter.dart - Frequency spectrum bars (like the HTML reference)
//
//  Draws vertical bars with green->yellow->red gradient.
//  Each bar represents a frequency bin (0..255 magnitude).
// ============================================================================
import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'tube_colors.dart';

class SpectrumPainter extends CustomPainter {
  SpectrumPainter({
    required this.bins,
    required this.brightness,
  });

  final List<double> bins; // each 0..255
  final double brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background
    final bgPaint = Paint()..color = const Color(0xFF0A0805);
    canvas.drawRect(Offset.zero & size, bgPaint);

    if (bins.isEmpty) return;

    final n = bins.length;
    // Bar width with gap (80% bar, 20% gap, like the HTML reference)
    final totalGap = (w / n) * 0.2;
    final barWidth = (w / n) * 0.8;
    final gap = totalGap / (n > 1 ? n - 1 : 1).toDouble().clamp(1, double.infinity);
    // Simpler: each cell = barWidth + gap, with gap after each bar
    final cellWidth = w / n;
    final actualBarWidth = cellWidth * 0.8;

    for (var i = 0; i < n; i++) {
      final value = bins[i].clamp(0.0, 255.0);
      final barHeight = (value / 255.0) * h;

      final x = i * cellWidth;
      final y = h - barHeight;

      // Gradient: green (bottom) -> yellow (middle) -> red (top)
      final gradient = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          TubeColors.phosphorGreen,
          const Color(0xFFE8C547), // yellow
          TubeColors.phosphorRed,
        ],
        stops: const [0.0, 0.6, 1.0],
      );

      final rect = Rect.fromLTWH(x, y, actualBarWidth, barHeight);
      final paint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.fill;

      canvas.drawRect(rect, paint);

      // Bright top cap (peak indicator) when brightness > 0
      if (brightness > 0.05 && barHeight > 2) {
        final capPaint = Paint()
          ..color = TubeColors.amberHot.withOpacity(0.8 * brightness)
          ..style = PaintingStyle.fill;
        canvas.drawRect(
          Rect.fromLTWH(x, y, actualBarWidth, 2),
          capPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant SpectrumPainter old) =>
      old.bins != bins || old.brightness != brightness;
}