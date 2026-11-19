// ============================================================================
//  winamp_theme.dart — Winamp classic skin colors + widgets
//  Phase 1 MVP: LCD display, metallic buttons, LED seek bar, title bar
// ============================================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Winamp classic skin color palette.
class WinampColors {
  const WinampColors._();

  // LCD display
  static const lcdBg = Color(0xFF000000);
  static const lcdText = Color(0xFF00FF00);
  static const lcdDim = Color(0xFF004400);
  static const lcdBorder = Color(0xFF1A3A1A);

  // Metallic surfaces
  static const metalLight = Color(0xFFD0D0D0);
  static const metalMid = Color(0xFF909090);
  static const metalDark = Color(0xFF505050);
  static const metalDarker = Color(0xFF2A2A2A);

  // Main background
  static const bgMain = Color(0xFF1A1A1A);
  static const bgPanel = Color(0xFF0D0D0D);

  // Title bar gradient
  static const titleBarStart = Color(0xFF000080);
  static const titleBarEnd = Color(0xFF1084D0);

  // Accent
  static const accent = Color(0xFF00FF00);
  static const textPrimary = Color(0xFF00FF00);
  static const textSecondary = Color(0xFF00CC00);
  static const textMuted = Color(0xFF006600);
}

/// LCD font helper — ShareTechMono (condensed, more Winamp-like).
TextStyle lcdStyle({
  double size = 14,
  Color color = WinampColors.lcdText,
  double letterSpacing = 0.5,
}) {
  return GoogleFonts.shareTechMono(
    fontSize: size,
    color: color,
    letterSpacing: letterSpacing,
  );
}

/// Winamp-style LCD display — green text on black with glow.
class WinampLcd extends StatelessWidget {
  const WinampLcd({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(10),
    this.height,
  });

  final Widget child;
  final EdgeInsets padding;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: WinampColors.lcdBg,
        border: Border.all(color: WinampColors.metalDark, width: 2),
        boxShadow: [
          BoxShadow(
            color: WinampColors.lcdText.withOpacity(0.12),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Winamp-style metallic button with pressed animation.
class WinampButton extends StatefulWidget {
  const WinampButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 40,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool active;

  @override
  State<WinampButton> createState() => _WinampButtonState();
}

class _WinampButtonState extends State<WinampButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: _pressed ? Alignment.bottomCenter : Alignment.topCenter,
            end: _pressed ? Alignment.topCenter : Alignment.bottomCenter,
            colors: [
              WinampColors.metalLight,
              WinampColors.metalMid,
              WinampColors.metalDark,
            ],
          ),
          border: Border.all(color: WinampColors.metalDarker, width: 1),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Icon(
          widget.icon,
          size: widget.size * 0.5,
          color: widget.active ? WinampColors.lcdText : WinampColors.metalDarker,
        ),
      ),
    );
  }
}

/// Winamp-style LED segment seek bar.
class WinampSeekBar extends StatelessWidget {
  const WinampSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.segments = 40,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final int segments;

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final posMs = position.inMilliseconds.toDouble().clamp(0.0, totalMs);
    final progress = (posMs / totalMs).clamp(0.0, 1.0);
    final filledSegments = (progress * segments).round();

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: (details) {
            final seekProgress =
                (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
            onSeek(Duration(milliseconds: (seekProgress * totalMs).toInt()));
          },
          child: Container(
            height: 16,
            decoration: BoxDecoration(
              color: WinampColors.lcdBg,
              border: Border.all(color: WinampColors.metalDark, width: 1),
            ),
            child: Row(
              children: List.generate(segments, (i) {
                final filled = i < filledSegments;
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
                    decoration: BoxDecoration(
                      color: filled ? WinampColors.lcdText : WinampColors.lcdDim,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}

/// Winamp-style title bar — dark gray, centered text, double border.
class WinampTitleBar extends StatelessWidget {
  const WinampTitleBar({super.key, required this.title, this.onClose});
  final String title;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      decoration: BoxDecoration(
        color: WinampColors.metalDarker,
        border: Border(
          top: BorderSide(color: WinampColors.metalMid, width: 1),
          bottom: BorderSide(color: WinampColors.metalMid, width: 1),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: Text(title,
              style: lcdStyle(size: 12, color: WinampColors.lcdText)),
          ),
          if (onClose != null)
            Positioned(
              right: 4,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: onClose,
                child: Icon(Icons.close, size: 12, color: WinampColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}
