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
          size: widget.size * 0.65,
          color: widget.active ? WinampColors.lcdText : WinampColors.metalLight,
        ),
      ),
    );
  }
}

/// Winamp-style LED segment seek bar — compact.
class WinampSeekBar extends StatelessWidget {
  const WinampSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.segments = 24,
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
            height: 10,
            decoration: BoxDecoration(
              color: WinampColors.lcdBg,
              border: Border.all(color: WinampColors.metalMid, width: 2),
            ),
            child: Row(
              children: List.generate(segments, (i) {
                final filled = i < filledSegments;
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 0.5, vertical: 1),
                    decoration: BoxDecoration(
                      color: filled ? WinampColors.lcdText : WinampColors.lcdDim,
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

/// Winamp-style title bar — dark gray, centered text with double solid lines.
class WinampTitleBar extends StatelessWidget {
  const WinampTitleBar({super.key, required this.title, this.onClose, this.trailing});
  final String title;
  final VoidCallback? onClose;
  final Widget? trailing;

  static const _lineColor = Color(0xFFC8B888); // pale yellow

  Widget _doubleLine() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(height: 1, color: _lineColor),
        const SizedBox(height: 2),
        Container(height: 1, color: _lineColor),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18,
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
          Row(
            children: [
              Expanded(child: _doubleLine()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(title,
                  style: lcdStyle(size: 10, color: WinampColors.metalLight)),
              ),
              Expanded(child: _doubleLine()),
            ],
          ),
          if (onClose != null)
            Positioned(right: 4, top: 0, bottom: 0,
              child: GestureDetector(
                onTap: onClose,
                child: Icon(Icons.close, size: 12, color: WinampColors.textMuted),
              ),
            ),
          if (trailing != null)
            Positioned(right: 4, top: 0, bottom: 0,
              child: Center(child: trailing!)),
        ],
      ),
    );
  }
}

// ============================================================================
//  LegendaDialog — public reusable Легенда-styled dialog wrapper
//  Used by about_winamp.dart and library_screen.dart (when skin == 'winamp').
//
//  Layout of action buttons:
//    - primaryActions: rendered in row 1, each button takes equal share
//      (1/N of row width, where N = primaryActions.length).
//    - secondaryAction: rendered in row 2, centered, with the SAME width
//      as a single row-1 button when N=2 (~50% of row width).
// ============================================================================
class LegendaDialog extends StatelessWidget {
  const LegendaDialog({
    super.key,
    required this.title,
    required this.child,
    this.primaryActions = const [],
    this.secondaryAction,
  });
  final String title;
  final Widget child;
  final List<Widget> primaryActions;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    final hasRow1 = primaryActions.isNotEmpty;
    final hasRow2 = secondaryAction != null;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: WinampColors.bgPanel,
          border: Border.all(color: WinampColors.metalMid, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WinampTitleBar(title: title),
            Container(
              color: WinampColors.lcdBg,
              padding: const EdgeInsets.all(14),
              child: child,
            ),
            if (hasRow1 || hasRow2)
              Container(
                color: WinampColors.bgPanel,
                padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasRow1)
                      Row(
                        children: [
                          for (int i = 0; i < primaryActions.length; i++) ...[
                            if (i > 0) const SizedBox(width: 4),
                            Expanded(child: primaryActions[i]),
                          ],
                        ],
                      ),
                    if (hasRow1 && hasRow2) const SizedBox(height: 6),
                    if (hasRow2)
                      Row(
                        children: [
                          const Expanded(flex: 1, child: SizedBox()),
                          Expanded(flex: 2, child: secondaryAction!),
                          const Expanded(flex: 1, child: SizedBox()),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Легенда-styled action button for dialogs — 32px tall, 11pt text.
class LegendaActionButton extends StatefulWidget {
  const LegendaActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  State<LegendaActionButton> createState() => _LegendaActionButtonState();
}

class _LegendaActionButtonState extends State<LegendaActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: _pressed ? Alignment.bottomCenter : Alignment.topCenter,
            end: _pressed ? Alignment.topCenter : Alignment.bottomCenter,
            colors: [
              WinampColors.metalLight,
              WinampColors.metalMid,
              WinampColors.metalDark
            ],
          ),
          border: Border.all(color: WinampColors.metalDarker, width: 1),
        ),
        child: Center(
          child: Text(widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: lcdStyle(
                  size: 11,
                  color: widget.highlight
                      ? WinampColors.lcdText
                      : WinampColors.metalDarker)
                  .copyWith(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

// ============================================================================
//  Classic Winamp bevel button (approved v15 design)
//  Outer: 2px raised bevel (white TL + black BR + light TL + dark BR)
//  Inner: child widget (SunkenShape for STOP/PAUSE, SunkenIcon for PLAY/PREV/NEXT)
// ============================================================================

class WinampBevelButton extends StatefulWidget {
  const WinampBevelButton({
    super.key,
    required this.onTap,
    this.size = 44,
    this.pressed = false,
    this.child,
  });
  final VoidCallback onTap;
  final double size;
  final bool pressed;
  final Widget? child;

  @override
  State<WinampBevelButton> createState() => _WinampBevelButtonState();
}

class _WinampBevelButtonState extends State<WinampBevelButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDown = _pressed || widget.pressed;
    const white = Color(0xFFFFFFFF);
    const black = Color(0xFF000000);
    const light = Color(0xFFDFDFDF);
    const dark = Color(0xFF808080);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: const Color(0xFFC0C0C0),
          border: Border(
            top:    BorderSide(color: isDown ? black : white, width: 1),
            left:   BorderSide(color: isDown ? black : white, width: 1),
            right:  BorderSide(color: isDown ? white : black, width: 1),
            bottom: BorderSide(color: isDown ? white : black, width: 1),
          ),
        ),
        child: Container(
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            border: Border(
              top:    BorderSide(color: isDown ? dark : light, width: 1),
              left:   BorderSide(color: isDown ? dark : light, width: 1),
              right:  BorderSide(color: isDown ? light : dark, width: 1),
              bottom: BorderSide(color: isDown ? light : dark, width: 1),
            ),
          ),
          child: Center(child: widget.child),
        ),
      ),
    );
  }
}

/// Sunken shape — dark gray (#606060) with inverted bevel (dark TL + light BR).
/// Used for STOP (square) and PAUSE (bars).
class SunkenShape extends StatelessWidget {
  const SunkenShape({
    super.key,
    required this.width,
    required this.height,
  });
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        color: Color(0xFF606060),
        border: Border(
          top:    BorderSide(color: Color(0xFF000000), width: 1),
          left:   BorderSide(color: Color(0xFF000000), width: 1),
          right:  BorderSide(color: Color(0xFFFFFFFF), width: 1),
          bottom: BorderSide(color: Color(0xFFFFFFFF), width: 1),
        ),
      ),
    );
  }
}

/// Stacked icon with crisp sunken bevel.
/// 3 layers: white at +1,+1 (back), black at -1,-1 (middle), #606060 body (front).
/// Used for PLAY (triangle), PREV (bar+triangle), NEXT (triangle+bar).
class SunkenIcon extends StatelessWidget {
  const SunkenIcon({
    super.key,
    required this.icon,
    this.size = 28,
  });
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 4,
      height: size + 4,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Transform.translate(
            offset: const Offset(1, 1),
            child: Icon(icon, size: size, color: const Color(0xFFFFFFFF)),
          ),
          Transform.translate(
            offset: const Offset(-1, -1),
            child: Icon(icon, size: size, color: const Color(0xFF000000)),
          ),
          Icon(icon, size: size, color: const Color(0xFF606060)),
        ],
      ),
    );
  }
}
