// ============================================================================
//  retro_button.dart — chassis button with brass bezel + amber glow when pressed
// ============================================================================
import 'package:flutter/material.dart';

import '../../core/theme/tube_colors.dart';

class RetroButton extends StatefulWidget {
  const RetroButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.label,
    this.active = false,
    this.size = 48,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? label;
  final bool active;
  final double size;

  @override
  State<RetroButton> createState() => _RetroButtonState();
}

class _RetroButtonState extends State<RetroButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? TubeColors.amberHot : TubeColors.brass;

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onPressed?.call();
      },
      onTapCancel: () => setState(() => _down = false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: TubeColors.surface,
              border: Border.all(color: color, width: 2),
              boxShadow: _down || widget.active
                  ? [
                      BoxShadow(
                        color: TubeColors.amberHot.withOpacity(0.45),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
            ),
            child: Icon(
              widget.icon,
              color: color,
              size: widget.size * 0.45,
            ),
          ),
          if (widget.label != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.label!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
