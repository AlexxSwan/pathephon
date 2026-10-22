// ============================================================================
//  vu_meter.dart — vintage VU meter widget using VUPainter
//  Animated via amplitudeStream (50 Hz) and playback state.
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/vu_painter.dart';
import '../providers/providers.dart';

class VUMeter extends ConsumerStatefulWidget {
  const VUMeter({super.key, this.size = 200});
  final double size;

  @override
  ConsumerState<VUMeter> createState() => _VUMeterState();
}

class _VUMeterState extends ConsumerState<VUMeter> {
  double _amplitude = 0;
  double _brightness = 0;

  @override
  Widget build(BuildContext context) {
    ref.listen(amplitudeProvider, (_, amp) {
      if (!amp.hasValue) return;
      setState(() {
        _amplitude = amp.value!;
        // Brightness = exponential smoothing toward target.
        final target = _amplitude > 0.05 ? 1.0 : 0.0;
        _brightness += (target - _brightness) * 0.1;
      });
    });

    return CustomPaint(
      size: Size(widget.size, widget.size * 0.7),
      painter: VUPainter(amplitude: _amplitude, brightness: _brightness),
    );
  }
}
