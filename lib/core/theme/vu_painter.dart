// ============================================================================
//  pp_painter.dart - Peak Program Meter dial
//
//  Classic BBC PPM styling:
//   - Cream dial face with equidistant marks 1..7
//   - Mark 4 = "0 dB" reference (center-up)
//   - Mark 6 = "+6 dB" (yellow)
//   - Mark 7 = "+9 dB" (red PEAK)
//   - Black needle pivoting from bottom-center
//   - Needle has fast attack, slow decay (handled in VisualizerService)
//
//  amplitude (0..1) maps linearly to needle position:
//   0.0 -> mark 1 (leftmost, -28 dB)
//   0.5 -> mark 4 (center, 0 dB)
//   0.85 -> mark 6 (+6 dB)
//   1.0 -> mark 7 (rightmost, +9 dB PEAK)
// ============================================================================
import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'tube_colors.dart';

class PPMPainter extends CustomPainter {
  PPMPainter({
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

    // ---- Arc zones (PPM standard: green 1-4, yellow 4-6, red 6-7) ------
    const startAngle = -math.pi * 0.85;
    const sweepAngle = math.pi * 0.70;
    final tickArea = Rect.fromCircle(center: Offset(cx, cy), radius: r - 10);

    // Green zone: marks 1-4 (0% to ~57% of sweep)
    final greenArc = Paint()
      ..color = TubeColors.phosphorGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawArc(tickArea, startAngle, sweepAngle * 0.57, false, greenArc);

    // Yellow zone: marks 4-6 (~57% to ~85%)
    final yellowArc = Paint()
      ..color = const Color(0xFFE8C547)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawArc(tickArea, startAngle + sweepAngle * 0.57, sweepAngle * 0.28, false, yellowArc);

    // Red zone: marks 6-7 (~85% to 100%)
    final redArc = Paint()
      ..color = TubeColors.phosphorRed
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawArc(tickArea, startAngle + sweepAngle * 0.85, sweepAngle * 0.15, false, redArc);

    // ---- PPM marks 1..7 with numbers ------------------------------------
    final tickPaint = Paint()
      ..color = const Color(0xFF2E1F12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    for (var i = 0; i < 7; i++) {
      final t = i / 6; // 0..1 across 7 marks
      final a = startAngle + sweepAngle * t;
      final inner = Offset(cx + math.cos(a) * (r - 20), cy + math.sin(a) * (r - 20));
      final outer = Offset(cx + math.cos(a) * (r - 8), cy + math.sin(a) * (r - 8));
      canvas.drawLine(inner, outer, tickPaint);

      // Number label
      final labelR = r - 32;
      final labelPos = Offset(
        cx + math.cos(a) * labelR,
        cy + math.sin(a) * labelR,
      );
      final labelPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
            color: Color(0xFF2E1F12),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(labelPos.dx - labelPainter.width / 2,
               labelPos.dy - labelPainter.height / 2),
      );
    }

    // ---- Needle ----------------------------------------------------------
    // LINEAR mapping: amplitude 0..1 -> angle 0..1 across the sweep.
    final normalized = amplitude.clamp(0.0, 1.0);
    final needleAngle = startAngle + sweepAngle * normalized;

    final needleLen = r - 14;
    final tip = Offset(
      cx + math.cos(needleAngle) * needleLen,
      cy + math.sin(needleAngle) * needleLen,
    );

    // Needle glow (only when brightness > 0)
    if (brightness > 0.05) {
      final halo = Paint()
        ..color = TubeColors.amberHot.withOpacity(0.4 * brightness)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawCircle(tip, 4 + 4 * brightness, halo);
    }

    // Black needle (PPM uses black needle, not colored)
    final needlePaint = Paint()
      ..color = const Color(0xFF1A1410)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, cy), tip, needlePaint);

    // ---- Center hub (brass cap) -----------------------------------------
    final hub = Paint()
      ..color = TubeColors.brass
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 7, hub);
    canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = TubeColors.brassDark);

    // ---- "PPM" label at top ---------------------------------------------
    final ppmLabel = TextPainter(
      text: TextSpan(
        text: 'PPM',
        style: TextStyle(
          color: const Color(0xFF2E1F12).withOpacity(0.6),
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    ppmLabel.paint(
      canvas,
      Offset(cx - ppmLabel.width / 2, cy - r + 14),
    );
  }

  @override
  bool shouldRepaint(covariant PPMPainter old) =>
      old.amplitude != amplitude || old.brightness != brightness;
}