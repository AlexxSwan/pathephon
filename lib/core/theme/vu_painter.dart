// ============================================================================
//  vu_painter.dart - DEPRECATED, use spectrum_painter.dart instead
//  Kept for backward compatibility (any leftover imports won't break build).
// ============================================================================
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'tube_colors.dart';

class PPMPainter extends CustomPainter {
  PPMPainter({required this.amplitude, required this.brightness});
  final double amplitude;
  final double brightness;
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(covariant PPMPainter old) => false;
}