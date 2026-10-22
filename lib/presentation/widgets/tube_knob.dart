// ============================================================================
//  tube_knob.dart — rotary knob widget for EQ band sliders
//  Draggable in a circular gesture; reports 0..1.
// ============================================================================
import 'package:flutter/material.dart';

import '../../core/theme/tube_colors.dart';

class TubeKnob extends StatefulWidget {
  const TubeKnob({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 56,
    this.label,
  });

  /// 0..1
  final double value;
  final ValueChanged<double> onChanged;
  final double size;
  final String? label;

  @override
  State<TubeKnob> createState() => _TubeKnobState();
}

class _TubeKnobState extends State<TubeKnob> {
  Offset? _dragStart;
  double? _dragStartValue;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragStart: (d) {
        _dragStart = d.globalPosition;
        _dragStartValue = widget.value;
      },
      onVerticalDragUpdate: (d) {
        if (_dragStart == null || _dragStartValue == null) return;
        final delta = _dragStart!.dy - d.globalPosition.dy;
        final next = (_dragStartValue! + delta / 200).clamp(0.0, 1.0);
        widget.onChanged(next);
      },
      onVerticalDragEnd: (_) {
        _dragStart = null;
        _dragStartValue = null;
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _KnobGraphic(value: widget.value, size: widget.size),
          if (widget.label != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.label!,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _KnobGraphic extends StatelessWidget {
  const _KnobGraphic({required this.value, required this.size});
  final double value; // 0..1
  final double size;

  @override
  Widget build(BuildContext context) {
    // Knob rotates from -135° (value=0) to +135° (value=1).
    final angle = (-135 + 270 * value) * 3.14159 / 180;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Brass body
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [TubeColors.brass, TubeColors.brassDark, TubeColors.brass],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          // Tick ring
          ..._buildTicks(),
          // Indicator line
          Transform.rotate(
            angle: angle,
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: EdgeInsets.only(top: size * 0.12),
                width: 2,
                height: size * 0.32,
                color: TubeColors.amberHot,
              ),
            ),
          ),
          // Center cap
          Container(
            width: size * 0.25,
            height: size * 0.25,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: TubeColors.surface,
              border: Border.all(color: TubeColors.brassDark, width: 1),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTicks() {
    final out = <Widget>[];
    for (var i = 0; i <= 10; i++) {
      final t = i / 10;
      final angle = (-135 + 270 * t) * 3.14159 / 180;
      out.add(Transform.rotate(
        angle: angle,
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: EdgeInsets.only(top: size * 0.02),
            width: 1.5,
            height: size * 0.06,
            color: TubeColors.amber.withOpacity(0.4),
          ),
        ),
      ));
    }
    return out;
  }
}
