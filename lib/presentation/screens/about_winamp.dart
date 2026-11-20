// ============================================================================
//  about_winamp.dart — Winamp-styled About screen
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
  const AboutWinamp({super.key});

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
      if (mounted) setState(() => _version = '?', _buildNumber = '?');
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
      builder: (ctx) => AlertDialog(
        backgroundColor: WinampColors.lcdBg,
        title: Text('СТАТИСТИКА',
            style: lcdStyle(size: 14, color: WinampColors.lcdText)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ЗА ВСЁ ВРЕМЯ:',
                style: lcdStyle(size: 10, color: WinampColors.textSecondary)),
            Text('Треков: ${stats['alltime_tracks']}',
                style: lcdStyle(size: 10)),
            Text('Время: ${_fmtDuration(stats['alltime_play_ms'] as int)}',
                style: lcdStyle(size: 10)),
            const SizedBox(height: 12),
            Text('ЗА СЕССИЮ:',
                style: lcdStyle(size: 10, color: WinampColors.textSecondary)),
            Text('Треков: ${stats['session_tracks']}',
                style: lcdStyle(size: 10)),
            Text('Время: ${_fmtDuration(stats['session_play_ms'] as int)}',
                style: lcdStyle(size: 10)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('ЗАКРЫТЬ', style: lcdStyle(size: 10, color: WinampColors.metalLight)),
          ),
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
      builder: (ctx) => AlertDialog(
        backgroundColor: WinampColors.lcdBg,
        title: Text('ЛОГ', style: lcdStyle(size: 14, color: WinampColors.lcdText)),
        content: SizedBox(
          width: double.maxFinite,
          child: _logLoading
              ? const Center(child: CircularProgressIndicator(color: WinampColors.lcdText))
              : SingleChildScrollView(
                  child: SelectableText(
                    _logPreview,
                    style: TextStyle(
                        color: WinampColors.textSecondary,
                        fontSize: 9,
                        fontFamily: 'monospace',
                        height: 1.3),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('ЗАКРЫТЬ', style: lcdStyle(size: 10, color: WinampColors.metalLight)),
          ),
          TextButton(
            onPressed: () async {
              await _shareLog();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text('ПОДЕЛИТЬСЯ', style: lcdStyle(size: 10, color: WinampColors.lcdText)),
          ),
          TextButton(
            onPressed: () async {
              await crashLogger.clear();
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (mounted) setState(() => _logPreview = '');
            },
            child: Text('ОЧИСТИТЬ', style: lcdStyle(size: 10, color: WinampColors.textMuted)),
          ),
        ],
      ),
    );
  }

  void _showDescription() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WinampColors.lcdBg,
        title: Text('ОПИСАНИЕ', style: lcdStyle(size: 14, color: WinampColors.lcdText)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Патефон — аудиоплеер для Android с ретро-дизайном.',
                    style: lcdStyle(size: 11)),
                const SizedBox(height: 8),
                Text('ВОЗМОЖНОСТИ:',
                    style: lcdStyle(size: 9, color: WinampColors.textSecondary)),
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
                    style: lcdStyle(size: 9, color: WinampColors.textSecondary)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('ЗАКРЫТЬ', style: lcdStyle(size: 10, color: WinampColors.metalLight)),
          ),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Logo + name
                    Icon(Icons.graphic_eq, size: 40, color: WinampColors.lcdText),
                    const SizedBox(height: 4),
                    Text('ПАТЕФОН', style: lcdStyle(size: 18)),
                    Text(versionStr,
                        style: lcdStyle(size: 10, color: WinampColors.textSecondary)),
                    const SizedBox(height: 8),
                    // Author
                    Text('SwanLab',
                        style: lcdStyle(size: 11, color: WinampColors.metalLight)),
                    Text('github.com/AlexxSwan/pathephon',
                        style: lcdStyle(size: 9, color: WinampColors.textMuted)),
                    const SizedBox(height: 12),
                    // Buttons — Winamp style
                    _WinampAboutButton(
                        label: 'СТАТИСТИКА', onTap: _showStatistics),
                    const SizedBox(height: 4),
                    _WinampAboutButton(label: 'ЛОГ', onTap: _showLogDialog),
                    const SizedBox(height: 4),
                    _WinampAboutButton(
                        label: 'ОПИСАНИЕ', onTap: _showDescription),
                    const SizedBox(height: 4),
                    _WinampAboutButton(
                      label: skin == 'winamp' ? 'СКИН: WINAMP' : 'СКИН: RETRO',
                      active: true,
                      onTap: () {
                        final newSkin =
                            skin == 'retro' ? 'winamp' : 'retro';
                        ref.read(skinProvider.notifier).state = newSkin;
                        ref
                            .read(sharedPreferencesProvider)
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

/// Winamp-styled button for About screen.
class _WinampAboutButton extends StatelessWidget {
  const _WinampAboutButton({required this.label, required this.onTap, this.active = false});
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 20,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: active ? Alignment.bottomCenter : Alignment.topCenter,
            end: active ? Alignment.topCenter : Alignment.bottomCenter,
            colors: [
              WinampColors.metalLight,
              WinampColors.metalMid,
              WinampColors.metalDark
            ],
          ),
          border: Border.all(color: WinampColors.metalDarker, width: 1),
        ),
        child: Center(
          child: Text(label,
              style: lcdStyle(size: 8,
                  color: active ? WinampColors.lcdText : WinampColors.metalDarker)),
        ),
      ),
    );
  }
}
