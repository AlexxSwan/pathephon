// ============================================================================
//  about_winamp.dart — Легенда-styled About screen
//  - Bottom nav hidden by _Shell early-return (see app.dart patch)
//  - 5 big buttons (40px tall, 14pt text) in 3 rows
//  - ПЛЕЙЕР not highlighted (same style as others)
//  - Skin toggle: icon-only, 40px tall, 24pt icon
//  - Dialogs (ЛОГ/СТАТИСТИКА/ОПИСАНИЕ) use _LegendaDialog:
//      * WinampTitleBar header
//      * Metal border (metalMid) like main window
//      * LCD background content area
//      * Winamp-styled action buttons
// ============================================================================
import 'dart:io';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/winamp_theme.dart';
import '../../core/utils/duration_format.dart';
import '../../services/crash_logger.dart';
import '../../services/playback_service.dart';
import '../providers/providers.dart';
import '../providers/skin_provider.dart';

class AboutWinamp extends ConsumerStatefulWidget {
  const AboutWinamp({super.key, this.onBack});

  /// Tap ПЛЕЙЕР button -> back to Now Playing
  final VoidCallback? onBack;

  @override
  ConsumerState<AboutWinamp> createState() => _AboutWinampState();
}

class _AboutWinampState extends ConsumerState<AboutWinamp> {
  String _version = '';
  String _buildNumber = '';
  String _logPreview = '';
  bool _logLoading = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _version = info.version;
          _buildNumber = info.buildNumber;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _version = '?'; _buildNumber = '?'; });
    }
  }

  String _fmtDuration(int ms) {
    final s = ms ~/ 1000;
    final y = s ~/ 31536000;
    final mo = (s % 31536000) ~/ 2592000;
    final d = (s % 2592000) ~/ 86400;
    final h = (s % 86400) ~/ 3600;
    final mi = (s % 3600) ~/ 60;
    final se = s % 60;
    final parts = <String>[];
    if (y > 0) parts.add('$yг');
    if (mo > 0) parts.add('$moм');
    if (d > 0) parts.add('$dд');
    if (h > 0) parts.add('$hч');
    if (mi > 0) parts.add('$miм');
    parts.add('$seс');
    return parts.join(' ');
  }

  Future<void> _showStatistics() async {
    final playback = ref.read(playbackServiceProvider);
    final stats = playback.getStatistics();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => _LegendaDialog(
        title: 'СТАТИСТИКА',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ЗА ВСЁ ВРЕМЯ:',
                style: lcdStyle(size: 12, color: WinampColors.textSecondary)),
            const SizedBox(height: 4),
            Text('Треков: ${stats['alltime_tracks']}',
                style: lcdStyle(size: 12)),
            Text('Время: ${_fmtDuration(stats['alltime_play_ms'] as int)}',
                style: lcdStyle(size: 12)),
            const SizedBox(height: 14),
            Text('ЗА СЕССИЮ:',
                style: lcdStyle(size: 12, color: WinampColors.textSecondary)),
            const SizedBox(height: 4),
            Text('Треков: ${stats['session_tracks']}',
                style: lcdStyle(size: 12)),
            Text('Время: ${_fmtDuration(stats['session_play_ms'] as int)}',
                style: lcdStyle(size: 12)),
          ],
        ),
        actions: [
          _LegendaActionButton(
              label: 'ЗАКРЫТЬ',
              onTap: () => Navigator.of(ctx).pop()),
        ],
      ),
    );
  }

  Future<void> _showLogDialog() async {
    setState(() => _logLoading = true);
    final log = await crashLogger.readLog();
    if (!mounted) return;
    setState(() {
      _logPreview = log.isEmpty ? '(лог пуст)' : log;
      _logLoading = false;
    });
    showDialog<void>(
      context: context,
      builder: (ctx) => _LegendaDialog(
        title: 'ЛОГ',
        child: _logLoading
            ? const SizedBox(
                height: 120,
                child: Center(
                    child: CircularProgressIndicator(
                        color: WinampColors.lcdText, strokeWidth: 2)),
              )
            : SizedBox(
                width: double.maxFinite,
                height: 280,
                child: SingleChildScrollView(
                  child: SelectableText(
                    _logPreview,
                    style: TextStyle(
                        color: WinampColors.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        height: 1.3),
                  ),
                ),
              ),
        actions: [
          _LegendaActionButton(
              label: 'ОЧИСТИТЬ',
              onTap: () async {
                await crashLogger.clear();
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (mounted) setState(() => _logPreview = '');
              }),
          _LegendaActionButton(
              label: 'ПОДЕЛИТЬСЯ',
              highlight: true,
              onTap: () async {
                await _shareLog();
                if (ctx.mounted) Navigator.of(ctx).pop();
              }),
          _LegendaActionButton(
              label: 'ЗАКРЫТЬ',
              onTap: () => Navigator.of(ctx).pop()),
        ],
      ),
    );
  }

  void _showDescription() {
    showDialog<void>(
      context: context,
      builder: (ctx) => _LegendaDialog(
        title: 'ОПИСАНИЕ',
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Патефон — аудиоплеер для Android с ретро-дизайном.',
                  style: lcdStyle(size: 12)),
              const SizedBox(height: 10),
              Text('ВОЗМОЖНОСТИ:',
                  style: lcdStyle(size: 11, color: WinampColors.textSecondary)),
              const SizedBox(height: 4),
              Text(
                  '\u2022 MP3, FLAC, OGG, M4A, WAV, AAC, Opus\n'
                  '\u2022 Управление очередью\n'
                  '\u2022 Shuffle и Repeat\n'
                  '\u2022 Эквалайзер (5 полос)\n'
                  '\u2022 Поиск по библиотеке\n'
                  '\u2022 Импорт/экспорт .m3u\n'
                  '\u2022 Bluetooth-управление\n'
                  '\u2022 Датчик CPU\n'
                  '\u2022 Статистика прослушивания\n'
                  '\u2022 Сохранение состояния',
                  style: lcdStyle(size: 11, color: WinampColors.textSecondary)),
            ],
          ),
        ),
        actions: [
          _LegendaActionButton(
              label: 'ЗАКРЫТЬ',
              onTap: () => Navigator.of(ctx).pop()),
        ],
      ),
    );
  }

  Future<void> _shareLog() async {
    try {
      final logPath = crashLogger.publicLogPath;
      if (logPath != null && File(logPath).existsSync()) {
        await Share.shareXFiles([XFile(logPath)], subject: 'Pathephon log');
      } else {
        final log = await crashLogger.readLog();
        await Share.share(log, subject: 'Pathephon log');
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final versionStr =
        _version.isEmpty ? 'ЗАГРУЗКА...' : 'v$_version+$_buildNumber';
    final skin = ref.watch(skinProvider);

    return Scaffold(
      backgroundColor: WinampColors.bgMain,
      body: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: WinampColors.bgPanel,
            border: Border.all(color: WinampColors.metalMid, width: 2),
          ),
          child: Column(children: [
            WinampTitleBar(title: 'О ПРОГРАММЕ'),
            // LCD content
            Expanded(
              child: Container(
                color: WinampColors.lcdBg,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Logo + name
                    Icon(Icons.graphic_eq, size: 48, color: WinampColors.lcdText),
                    const SizedBox(height: 6),
                    Text('ПАТЕФОН', style: lcdStyle(size: 22)),
                    Text(versionStr,
                        style: lcdStyle(size: 12, color: WinampColors.textSecondary)),
                    const SizedBox(height: 10),
                    // Author
                    Text('SwanLab',
                        style: lcdStyle(size: 13, color: WinampColors.metalLight)),
                    Text('github.com/AlexxSwan/pathephon',
                        style: lcdStyle(size: 11, color: WinampColors.textMuted)),
                    const SizedBox(height: 16),
                    // Row 1: СТАТИСТИКА | ЛОГ  (40px tall, 14pt text)
                    Row(children: [
                      Expanded(child: _LegendaAboutButton(
                          label: 'СТАТИСТИКА', onTap: _showStatistics)),
                      const SizedBox(width: 6),
                      Expanded(child: _LegendaAboutButton(
                          label: 'ЛОГ', onTap: _showLogDialog)),
                    ]),
                    const SizedBox(height: 6),
                    // Row 2: ОПИСАНИЕ | ПЛЕЙЕР  (no highlight on ПЛЕЙЕР)
                    Row(children: [
                      Expanded(child: _LegendaAboutButton(
                          label: 'ОПИСАНИЕ', onTap: _showDescription)),
                      const SizedBox(width: 6),
                      Expanded(child: _LegendaAboutButton(
                          label: 'ПЛЕЙЕР',
                          onTap: () => widget.onBack?.call())),
                    ]),
                    const SizedBox(height: 10),
                    // Row 3: skin toggle — icon only, 40px tall, 24pt icon
                    _LegendaSkinButton(
                      skin: skin,
                      onTap: () {
                        final newSkin = skin == 'retro' ? 'winamp' : 'retro';
                        ref.read(skinProvider.notifier).state = newSkin;
                        ref.read(sharedPreferencesProvider)
                            .setString('pathephon.skin', newSkin);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Легенда-styled About screen button — 40px tall, 14pt text.
/// NO active state on ПЛЕЙЕР (all buttons look identical unless pressed).
class _LegendaAboutButton extends StatefulWidget {
  const _LegendaAboutButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_LegendaAboutButton> createState() => _LegendaAboutButtonState();
}

class _LegendaAboutButtonState extends State<_LegendaAboutButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: Container(
        width: double.infinity,
        height: 40,
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
              style: lcdStyle(size: 14, color: WinampColors.metalDarker)
                  .copyWith(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

/// Skin toggle button — icon only (no text label), 40px tall, 24pt icon.
/// Toggles between 'winamp' and 'retro' on tap.
class _LegendaSkinButton extends StatefulWidget {
  const _LegendaSkinButton({required this.skin, required this.onTap});
  final String skin;
  final VoidCallback onTap;

  @override
  State<_LegendaSkinButton> createState() => _LegendaSkinButtonState();
}

class _LegendaSkinButtonState extends State<_LegendaSkinButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: Container(
        width: 80,
        height: 40,
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
          child: Icon(
            widget.skin == 'winamp' ? Icons.phone_android : Icons.graphic_eq,
            size: 24,
            color: WinampColors.metalDarker,
          ),
        ),
      ),
    );
  }
}

/// Легенда-styled dialog wrapper.
/// Uses WinampTitleBar header + metal border + LCD background.
/// Matches the main About window look.
class _LegendaDialog extends StatelessWidget {
  const _LegendaDialog({
    required this.title,
    required this.child,
    this.actions = const [],
  });
  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: WinampColors.bgPanel,
          border: Border.all(color: WinampColors.metalMid, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title bar — same WinampTitleBar used on main screen
            WinampTitleBar(title: title),
            // LCD content area
            Container(
              color: WinampColors.lcdBg,
              padding: const EdgeInsets.all(14),
              child: child,
            ),
            // Action buttons strip — metallic, like main window buttons
            if (actions.isNotEmpty)
              Container(
                color: WinampColors.bgPanel,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions
                      .expand((a) => [a, const SizedBox(width: 4)])
                      .toList()
                      ..removeLast(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Легенда-styled action button for dialogs — 28px tall, 11pt text.
/// highlight=true -> green LCD text (for primary action like ПОДЕЛИТЬСЯ).
class _LegendaActionButton extends StatefulWidget {
  const _LegendaActionButton({
    required this.label,
    required this.onTap,
    this.highlight = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  State<_LegendaActionButton> createState() => _LegendaActionButtonState();
}

class _LegendaActionButtonState extends State<_LegendaActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 14),
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
