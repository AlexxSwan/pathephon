// ============================================================================
//  pp_painter.dart - Peak Program Meter dial (BBC PPM style)
//
//  amplitude is in dBFS (-60..0):
//    -60 dBFS -> mark 1 (silence)
//    -18 dBFS -> mark 4 (PPM 0 dB reference)
//    -6 dBFS  -> mark 6 (+6 dB, yellow)
//     0 dBFS  -> mark 7 (PEAK, red)
//  Needle position is LINEAR between these calibration points.
// ============================================================================
import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'tube_colors.dart';

class PPMPainter extends CustomPainter {
  PPMPainter({
    required this.amplitude,
    required this.brightness,
  });

  /// Peak level in dBFS (-60..0).
  final double amplitude;
  final double brightness;

  /// Map dBFS to needle position (0..1) across the 7-mark scale.
  /// Calibration points (BBC PPM standard, mapped to digital dBFS):
  ///   PPM 1 = -28 dBFS  -> 0.0
  ///   PPM 4 = -18 dBFS  -> 0.5  (reference, 0 dB)
  ///   PPM 6 = -6 dBFS   -> 0.83
  ///   PPM 7 = 0 dBFS    -> 1.0  (PEAK)
  double _dbToPosition(double db) {
    if (db <= -60) return 0.0;
    if (db >= 0) return 1.0;
    // Linear interpolation between calibration points.
    // Using a piecewise curve so the needle moves naturally:
    //   -60..-18 dBFS -> 0..0.5 (silent to reference, half the arc)
    //   -18..-6 dBFS  -> 0.5..0.83 (reference to +6)
    //   -6..0 dBFS    -> 0.83..1.0 (+6 to PEAK)
    if (db <= -18) {
      // -60..-18 -> 0..0.5
      return ((db - (-60)) / (-18 - (-60))) * 0.5;
    } else if (db <= -6) {
      // -18..-6 -> 0.5..0.83
      return 0.5 + ((db - (-18)) / (-6 - (-18))) * 0.33;
    } else {
      // -6..0 -> 0.83..1.0
      return 0.83 + ((db - (-6)) / (0 - (-6))) * 0.17;
    }
  }

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

    // ---- Arc zones -------------------------------------------------------
    const startAngle = -math.pi * 0.85;
    const sweepAngle = math.pi * 0.70;
    final tickArea = Rect.fromCircle(center: Offset(cx, cy), radius: r - 10);

    // Green zone: marks 1-4 (0% to 50% of sweep)
    final greenArc = Paint()
      ..color = TubeColors.phosphorGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawArc(tickArea, startAngle, sweepAngle * 0.5, false, greenArc);

    // Yellow zone: marks 4-6 (50% to 83%)
    final yellowArc = Paint()
      ..color = const Color(0xFFE8C547)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawArc(tickArea, startAngle + sweepAngle * 0.5, sweepAngle * 0.33, false, yellowArc);

    // Red zone: marks 6-7 (83% to 100%)
    final redArc = Paint()
      ..color = TubeColors.phosphorRed
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawArc(tickArea, startAngle + sweepAngle * 0.83, sweepAngle * 0.17, false, redArc);

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

    // ---- Needle (mapped from dBFS) --------------------------------------
    final normalized = _dbToPosition(amplitude);
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

    // Black needle
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