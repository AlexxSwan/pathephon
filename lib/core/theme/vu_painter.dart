// ============================================================================
//  vu_painter.dart - CustomPainter for the vintage VU-meter needle
//
//  amplitude (0..1) maps LINEARLY to the needle angle:
//    0.0  -> far left  (-20 dB tick)
//    0.5  -> middle    (around 0 dB)
//    0.85 -> start of red zone
//    1.0  -> far right (+3 dB)
//
//  This is intentional: we do NOT use 20*log10 because that pushes typical
//  fake-amplitude values (0.3..0.5) into the red zone. Linear mapping
//  keeps the needle in the green/yellow area where it looks natural.
// ============================================================================
import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'tube_colors.dart';

class VUPainter extends CustomPainter {
  VUPainter({
    required this.amplitude,
    required this.brightness,
  });

  final double amplitude;
  final double brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h * 0.92;
    final r = math.min(w / 2, h * 0.95);

    // ---- Bezel (brass ring) ---------------------------------------------
    final bezel = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        colors: [
          TubeColors.brass,
          TubeColors.brassDark,
          TubeColors.brass,
          TubeColors.brassDark,
          TubeColors.brass,
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawCircle(Offset(cx, cy), r, bezel);

    // ---- Dial face (cream paper) ----------------------------------------
    final face = Paint()
      ..color = const Color(0xFFF4E9D2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), r - 4, face);

    // ---- Arc ticks (-20 dB .. +3 dB) ------------------------------------
    const startAngle = -math.pi * 0.85;
    const sweepAngle = math.pi * 0.70;
    final tickArea = Rect.fromCircle(center: Offset(cx, cy), radius: r - 10);

    final greenArc = Paint()
      ..color = TubeColors.phosphorGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final redArc = Paint()
      ..color = TubeColors.phosphorRed
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawArc(tickArea, startAngle, sweepAngle * 0.8, false, greenArc);
    canvas.drawArc(tickArea, startAngle + sweepAngle * 0.8, sweepAngle * 0.2, false, redArc);

    // ---- Minor tick marks -----------------------------------------------
    final tickPaint = Paint()
      ..color = const Color(0xFF2E1F12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i <= 10; i++) {
      final t = i / 10;
      final a = startAngle + sweepAngle * t;
      final inner = Offset(cx + math.cos(a) * (r - 18), cy + math.sin(a) * (r - 18));
      final outer = Offset(cx + math.cos(a) * (r - 8), cy + math.sin(a) * (r - 8));
      canvas.drawLine(inner, outer, tickPaint);
    }

    // ---- Needle ----------------------------------------------------------
    // LINEAR mapping: amplitude 0..1 -> angle 0..1 across the sweep.
    // No log scale. This keeps typical values in the green zone.
    final normalized = amplitude.clamp(0.0, 1.0);
    final needleAngle = startAngle + sweepAngle * normalized;

    final needleLen = r - 14;
    final tip = Offset(
      cx + math.cos(needleAngle) * needleLen,
      cy + math.sin(needleAngle) * needleLen,
    );

    if (brightness > 0.05) {
      final halo = Paint()
        ..color = TubeColors.amberHot.withOpacity(0.35 * brightness)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(tip, 4 + 4 * brightness, halo);
    }

    final needlePaint = Paint()
      ..color = TubeColors.amberHot
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, cy), tip, needlePaint);

    // ---- Center hub (brass cap) -----------------------------------------
    final hub = Paint()
      ..color = TubeColors.brass
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 6, hub);
    canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = TubeColors.brassDark);
  }

  @override
  bool shouldRepaint(covariant VUPainter old) =>
      old.amplitude != amplitude || old.brightness != brightness;
}