// ============================================================================
//  vu_meter.dart - vintage VU meter widget using VUPainter
//  Stereo version: takes leftAmplitude + rightAmplitude directly.
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/vu_painter.dart';
import '../providers/providers.dart';

class VUMeter extends ConsumerWidget {
  const VUMeter({super.key, this.size = 200});
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stereo = ref.watch(stereoAmplitudeProvider).valueOrNull;
    final left = stereo?.left ?? 0.0;
    final right = stereo?.right ?? 0.0;
    final brightness = (left > 0.05 || right > 0.05) ? 1.0 : 0.0;

    return CustomPaint(
      size: Size(size, size * 0.7),
      painter: VUPainter(
        leftAmplitude: left,
        rightAmplitude: right,
        brightness: brightness,
      ),
    );
  }
}