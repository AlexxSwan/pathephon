// ============================================================================
//  vu_painter.dart - CustomPainter for the vintage VU-meter
//
//  Draws TWO needles: Left channel (upper) and Right channel (lower).
//  Each amplitude is 0..1 and maps LINEARLY to the needle angle.
//  Real RMS data comes from VisualizerService via stereoAmplitudeProvider.
// ============================================================================
import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'tube_colors.dart';

class VUPainter extends CustomPainter {
  VUPainter({
    required this.leftAmplitude,
    required this.rightAmplitude,
    required this.brightness,
  });

  /// 0..1, real RMS from Visualizer
  final double leftAmplitude;
  final double rightAmplitude;
  final double brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Two dials side-by-side, each square-ish.
    final dialW = w / 2 - 8;
    final dialH = h;
    _drawDial(canvas, Rect.fromLTWH(4, 0, dialW, dialH), leftAmplitude, 'L');
    _drawDial(canvas, Rect.fromLTWH(w / 2 + 4, 0, dialW, dialH), rightAmplitude, 'R');
  }

  void _drawDial(Canvas canvas, Rect rect, double amplitude, String label) {
    final cx = rect.center.dx;
    final cy = rect.bottom - 8;
    final r = math.min(rect.width / 2, rect.height * 0.95) - 4;

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
      ..strokeWidth = 6;
    canvas.drawCircle(Offset(cx, cy), r, bezel);

    // ---- Dial face (cream paper) ----------------------------------------
    final face = Paint()
      ..color = const Color(0xFFF4E9D2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), r - 3, face);

    // ---- Arc ticks (-20 dB .. +3 dB) ------------------------------------
    const startAngle = -math.pi * 0.85;
    const sweepAngle = math.pi * 0.70;
    final tickArea = Rect.fromCircle(center: Offset(cx, cy), radius: r - 8);

    final greenArc = Paint()
      ..color = TubeColors.phosphorGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final redArc = Paint()
      ..color = TubeColors.phosphorRed
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawArc(tickArea, startAngle, sweepAngle * 0.8, false, greenArc);
    canvas.drawArc(tickArea, startAngle + sweepAngle * 0.8, sweepAngle * 0.2, false, redArc);

    // ---- Minor tick marks -----------------------------------------------
    final tickPaint = Paint()
      ..color = const Color(0xFF2E1F12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (var i = 0; i <= 10; i++) {
      final t = i / 10;
      final a = startAngle + sweepAngle * t;
      final inner = Offset(cx + math.cos(a) * (r - 14), cy + math.sin(a) * (r - 14));
      final outer = Offset(cx + math.cos(a) * (r - 6), cy + math.sin(a) * (r - 6));
      canvas.drawLine(inner, outer, tickPaint);
    }

    // ---- Needle ----------------------------------------------------------
    final normalized = amplitude.clamp(0.0, 1.0);
    final needleAngle = startAngle + sweepAngle * normalized;
    final needleLen = r - 10;
    final tip = Offset(
      cx + math.cos(needleAngle) * needleLen,
      cy + math.sin(needleAngle) * needleLen,
    );

    if (brightness > 0.05) {
      final halo = Paint()
        ..color = TubeColors.amberHot.withOpacity(0.35 * brightness)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(tip, 3 + 3 * brightness, halo);
    }

    final needlePaint = Paint()
      ..color = TubeColors.amberHot
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, cy), tip, needlePaint);

    // ---- Center hub (brass cap) -----------------------------------------
    canvas.drawCircle(Offset(cx, cy), 5, Paint()..color = TubeColors.brass);
    canvas.drawCircle(Offset(cx, cy), 2.5, Paint()..color = TubeColors.brassDark);

    // ---- Channel label (L or R) -----------------------------------------
    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFF2E1F12),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(canvas, Offset(cx - labelPainter.width / 2, rect.top + 6));
  }

  @override
  bool shouldRepaint(covariant VUPainter old) =>
      old.leftAmplitude != leftAmplitude ||
      old.rightAmplitude != rightAmplitude ||
      old.brightness != brightness;
}