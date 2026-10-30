// ============================================================================
//  now_playing_screen.dart
//  v0.11.6+200: CPU% индикатор кликабельный → открывает диалог "Состояние"
//  Все данные в диалоге — синхронное чтение procfs или уже в памяти.
//  Никаких async операций в UI потоке, всё обёрнуто в try/catch.
// ============================================================================
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/retro_theme.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/models/track.dart';
import '../providers/providers.dart';
import '../../services/crash_logger.dart';
import '../../services/playback_service.dart';
import '../widgets/playback_controls.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});
  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  bool _showPlaylist = true;
  final _playlistScrollController = ScrollController();
  int _lastScrolledIndex = -1;

  // === CPU мониторинг ===
  // StreamController<int> — бейдж обновляется через StreamBuilder,
  // весь экран не пересобирается.
  // Дополнительно: история последних 30 значений для мини-графика в диалоге.
  final _cpuController = StreamController<int>.broadcast();
  final List<int> _cpuHistory = List.filled(30, 0); // кольцевой буфер
  Timer? _cpuTimer;
  int _prevUtime = 0;
  int _prevStime = 0;

  @override
  void initState() {
    super.initState();
    _startCpuMonitor();
  }

  @override
  void dispose() {
    _cpuTimer?.cancel();
    _cpuController.close();
    _playlistScrollController.dispose();
    super.dispose();
  }

  void _startCpuMonitor() {
    _readCpuStat();
    _cpuTimer = Timer.periodic(const Duration(seconds: 1), (_) => _readCpuStat());
  }

  void _readCpuStat() {
    try {
      final stat = File('/proc/self/stat').readAsStringSync();
      final lastParen = stat.lastIndexOf(') ');
      if (lastParen < 0) return;
      final fields = stat.substring(lastParen + 2).split(RegExp(r'\s+'));
      if (fields.length < 13) return;
      final utime = int.parse(fields[11]);
      final stime = int.parse(fields[12]);

      if (_prevUtime > 0 || _prevStime > 0) {
        final deltaJiffies = (utime - _prevUtime) + (stime - _prevStime);
        final pct = deltaJiffies.clamp(0, 100);
        _cpuController.add(pct);
        // Сдвигаем историю (FIFO)
        for (var i = 0; i < _cpuHistory.length - 1; i++) {
          _cpuHistory[i] = _cpuHistory[i + 1];
        }
        _cpuHistory[_cpuHistory.length - 1] = pct;
      }
      _prevUtime = utime;
      _prevStime = stime;
    } catch (_) {}
  }

  Color _cpuColor(int pct) {
    if (pct <= 50) {
      return Color.lerp(
        const Color(0xFF4CAF50),
        const Color(0xFFFFC107),
        pct / 50,
      )!;
    } else {
      return Color.lerp(
        const Color(0xFFFFC107),
        const Color(0xFFF44336),
        (pct - 50) / 50,
      )!;
    }
  }

  /// Читает RSS и Threads из /proc/self/status — синхронно, мгновенно.
  /// Возвращает null если что-то пошло не так.
  Map<String, int>? _readMemInfo() {
    try {
      final status = File('/proc/self/status').readAsStringSync();
      final rssMatch = RegExp(r'VmRSS:\s+(\d+)\s+kB').firstMatch(status);
      final vmsizeMatch = RegExp(r'VmSize:\s+(\d+)\s+kB').firstMatch(status);
      final threadsMatch = RegExp(r'Threads:\s+(\d+)').firstMatch(status);
      return {
        'rss': rssMatch != null ? int.parse(rssMatch.group(1)!) : 0,
        'vmsize': vmsizeMatch != null ? int.parse(vmsizeMatch.group(1)!) : 0,
        'threads': threadsMatch != null ? int.parse(threadsMatch.group(1)!) : 0,
      };
    } catch (_) {
      return null;
    }
  }

  /// Читает uptime процесса из /proc/self/stat — поле 22 (starttime).
  /// Возвращает длительность в секундах.
  Duration? _readUptime() {
    try {
      final stat = File('/proc/self/stat').readAsStringSync();
      final lastParen = stat.lastIndexOf(') ');
      if (lastParen < 0) return null;
      final fields = stat.substring(lastParen + 2).split(RegExp(r'\s+'));
      if (fields.length < 22) return null;
      // starttime (fields[20] после смещения -1) в jiffies since boot
      final starttime = int.parse(fields[19]); // поле 22 (starttime), не 23 (vsize)
      // uptime системы
      final uptimeStr = File('/proc/uptime').readAsStringSync();
      final uptimeSec = double.parse(uptimeStr.split(' ')[0]);
      // clk_tck = 100 на ARM64
      final processStartSec = starttime / 100.0;
      final processUptimeSec = uptimeSec - processStartSec;
      if (processUptimeSec < 0) return null;
      return Duration(seconds: processUptimeSec.toInt());
    } catch (_) {
      return null;
    }
  }

  /// Показать диалог состояния.
  /// Все операции синхронные (procfs) или обёрнуты в try/catch.
  /// НЕ использует BuildContext через async gap.
  void _showStatusDialog() {
    // Собираем данные ДО showDialog — нет async gap
    final mem = _readMemInfo();
    final uptime = _readUptime();
    final snap = ref.read(playbackSnapshotProvider).valueOrNull;
    final playback = ref.read(playbackServiceProvider);
    final pos = ref.read(playbackPositionProvider).valueOrNull ?? Duration.zero;
    final currentTrack = snap?.current;
    final queueSize = snap?.queue.length ?? 0;
    final currentIndex = snap?.index ?? 0;
    final duration = snap?.duration ?? Duration.zero;
    final isPlaying = snap?.isPlaying ?? false;
    final p = Preset.of(context);
    final cpuHistoryCopy = List<int>.from(_cpuHistory);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surfaceVariant,
        title: Row(
          children: [
            Icon(Icons.monitor_heart, color: p.accentHot, size: 20),
            const SizedBox(width: 8),
            Text('Состояние', style: TextStyle(color: p.accent, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // === CPU секция с мини-графиком ===
                _sectionTitle('CPU', p),
                _cpuMiniChart(cpuHistoryCopy, p),
                const SizedBox(height: 8),
                // === Память ===
                _sectionTitle('Память', p),
                if (mem != null)
                  _infoRow('RSS', '${(mem['rss']! / 1024).toStringAsFixed(1)} MB', p)
                else
                  _infoRow('RSS', '—', p),
                if (mem != null)
                  _infoRow('Виртуальная', '${(mem['vmsize']! / 1024).toStringAsFixed(1)} MB', p),
                if (mem != null)
                  _infoRow('Потоки', '${mem['threads']!}', p),
                const SizedBox(height: 8),
                // === Время работы ===
                _sectionTitle('Время работы', p),
                if (uptime != null)
                  _infoRow('Приложение', _formatDuration(uptime), p)
                else
                  _infoRow('Приложение', '—', p),
                const SizedBox(height: 8),
                // === Воспроизведение ===
                _sectionTitle('Воспроизведение', p),
                _infoRow('Состояние', isPlaying ? '▶ Играет' : '⏸ Пауза', p),
                if (currentTrack != null) ...[
                  _infoRow('Трек', currentTrack.title, p, maxLines: 1),
                  if (currentTrack.artist.isNotEmpty)
                    _infoRow('Исполнитель', currentTrack.artist, p, maxLines: 1),
                ] else
                  _infoRow('Трек', '—', p),
                _infoRow('Позиция', formatDuration(pos), p),
                _infoRow('Длительность', formatDuration(duration), p),
                _infoRow('Очередь', '$queueSize треков (текущий #${currentIndex + 1})', p),
                const SizedBox(height: 8),
                // === Лог (последние строки) ===
                _sectionTitle('Последний лог', p),
                FutureBuilder<String>(
                  future: crashLogger.readLog(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text('загрузка...', style: TextStyle(color: p.textMuted, fontSize: 11)),
                      );
                    }
                    final lines = snapshot.data!.split('\n').where((l) => l.trim().isNotEmpty).toList();
                    final last5 = lines.length > 5 ? lines.sublist(lines.length - 5) : lines;
                    if (last5.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text('(пусто)', style: TextStyle(color: p.textMuted, fontSize: 11)),
                      );
                    }
                    return Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: p.background,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: last5.map((l) => Text(
                          l,
                          style: TextStyle(color: p.textSecondary, fontSize: 10, fontFamily: 'monospace', height: 1.2),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        )).toList(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                final logPath = crashLogger.publicLogPath;
                if (logPath != null && File(logPath).existsSync()) {
                  await Share.shareXFiles([XFile(logPath)], subject: 'Pathephon crash log');
                } else {
                  final log = await crashLogger.readLog();
                  await Share.share(log, subject: 'Pathephon crash log');
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка: $e')),
                  );
                }
              }
            },
            child: Text('Поделиться логом', style: TextStyle(color: p.accentHot)),
          ),
          TextButton(
            onPressed: () async {
              try {
                await crashLogger.clear();
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Лог очищен')),
                  );
                }
              } catch (_) {}
            },
            child: Text('Очистить лог', style: TextStyle(color: p.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Закрыть', style: TextStyle(color: p.brass)),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, ThemePreset p) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          color: p.brass,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, ThemePreset p, {int? maxLines}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(color: p.textMuted, fontSize: 11)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: p.textPrimary, fontSize: 11, fontFamily: 'monospace'),
              maxLines: maxLines,
              overflow: maxLines != null ? TextOverflow.ellipsis : null,
            ),
          ),
        ],
      ),
    );
  }

  /// Мини-график истории CPU — CustomPaint, 30 баров, ширина 280px.
  Widget _cpuMiniChart(List<int> history, ThemePreset p) {
    return Container(
      height: 60,
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: CustomPaint(
        size: Size.infinite,
        painter: _CpuChartPainter(history: history, color: p.accentHot),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}ч ${d.inMinutes.remainder(60)}м';
    } else if (d.inMinutes > 0) {
      return '${d.inMinutes}м ${d.inSeconds.remainder(60)}с';
    } else {
      return '${d.inSeconds}с';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = Preset.of(context);
    final snap = ref.watch(playbackSnapshotProvider).valueOrNull;
    final pos = ref.watch(playbackPositionProvider).valueOrNull ?? Duration.zero;
    final playback = ref.watch(playbackServiceProvider);
    ref.watch(isPlayingProvider);

    final track = snap?.current;
    final queue = snap?.queue ?? const <Track>[];
    final currentIndex = snap?.index ?? 0;
    final duration = snap?.duration ?? Duration.zero;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(children: [
            // ====== Топ-бар: [CPU% кликабельный] [title] [playlist toggle] ======
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // ЛЕВО: CPU индикатор — КЛИКАБЕЛЬНЫЙ
                StreamBuilder<int>(
                  stream: _cpuController.stream,
                  initialData: 0,
                  builder: (context, snapshot) {
                    final pct = snapshot.data ?? 0;
                    final color = _cpuColor(pct);
                    return GestureDetector(
                      onTap: _showStatusDialog,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.memory, size: 12, color: color),
                            const SizedBox(width: 3),
                            Text(
                              '$pct%',
                              style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                height: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                Text(l.nowPlayingTitle, style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: Icon(_showPlaylist ? Icons.queue_music : Icons.queue_music_outlined),
                  tooltip: _showPlaylist ? 'Скрыть очередь' : 'Показать очередь',
                  color: _showPlaylist ? p.accentHot : p.textMuted,
                  onPressed: () => setState(() => _showPlaylist = !_showPlaylist),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: _showPlaylist ? 3 : 5,
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: p.brass, width: 3),
                      boxShadow: [BoxShadow(color: p.accentHot.withOpacity(0.25), blurRadius: 30, spreadRadius: 4)],
                    ),
                    child: _ArtworkImage(track: track),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(track?.title ?? '\u2014', style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text([track?.artist, track?.album].whereType<String>().join(' \u00B7 '),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: p.textSecondary),
                textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(children: [
              Text(formatDuration(pos), style: Theme.of(context).textTheme.labelSmall),
              Expanded(child: Slider(
                min: 0,
                max: duration.inMilliseconds.toDouble().clamp(1.0, double.infinity),
                value: pos.inMilliseconds.toDouble().clamp(0, duration.inMilliseconds.toDouble()),
                onChanged: (v) => playback.seekTo(Duration(milliseconds: v.toInt())),
              )),
              Text(formatDuration(duration), style: Theme.of(context).textTheme.labelSmall),
            ]),
            const SizedBox(height: 8),
            const PlaybackControls(),
            const SizedBox(height: 12),
            if (_showPlaylist)
              Expanded(
                flex: 2,
                child: _buildPlaylist(queue, currentIndex, playback, p),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _buildPlaylist(List<Track> queue, int currentIndex, PlaybackService playback, ThemePreset p) {
    if (queue.isEmpty) {
      return Center(child: Text('\u041E\u0447\u0435\u0440\u0435\u0434\u044C \u043F\u0443\u0441\u0442\u0430', style: TextStyle(color: p.textMuted)));
    }
    if (currentIndex != _lastScrolledIndex) {
      _lastScrolledIndex = currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_playlistScrollController.hasClients) {
          final target = currentIndex * 44.0;
          final viewport = _playlistScrollController.position.viewportDimension;
          final offset = _playlistScrollController.offset;
          if (target < offset || target > offset + viewport - 44) {
            _playlistScrollController.animateTo(
              (target - viewport / 2 + 22).clamp(0.0, _playlistScrollController.position.maxScrollExtent),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        }
      });
    }
    return Container(
      decoration: BoxDecoration(
        color: p.background,
        border: Border.all(color: p.brass.withOpacity(0.3), width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListView.builder(
        controller: _playlistScrollController,
        padding: EdgeInsets.zero, itemCount: queue.length, itemExtent: 44,
        itemBuilder: (_, i) {
          final t = queue[i];
          final isCurrent = i == currentIndex;
          return InkWell(
            onTap: () {
              if (isCurrent) {
                _showFilePathDialog(t, p);
              } else {
                playback.playQueue(tracks: queue, startIndex: i);
              }
            },
            child: Container(
              color: isCurrent ? p.accentHot.withOpacity(0.15) : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(children: [
                SizedBox(width: 44, child: isCurrent
                    ? Icon(Icons.play_arrow, size: 20, color: p.accentHot)
                    : Text('${i + 1}', style: TextStyle(color: p.textMuted, fontSize: 13, fontFamily: 'monospace'), textAlign: TextAlign.end)),
                const SizedBox(width: 8),
                Expanded(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: isCurrent ? p.accentHot : p.textPrimary,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, fontSize: 14, height: 1.15)),
                    if (t.artist.isNotEmpty)
                      Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.textSecondary, fontSize: 11, height: 1.15)),
                  ],
                )),
                const SizedBox(width: 8),
                if (t.durationMs > 0)
                  Text(formatDuration(Duration(milliseconds: t.durationMs)), style: TextStyle(color: p.textMuted, fontSize: 11)),
              ]),
            ),
          );
        },
      ),
    );
  }

  void _showFilePathDialog(Track t, ThemePreset p) {
    final path = t.filePath.isNotEmpty ? t.filePath : t.uri;
    final cleanPath = path.startsWith('file://') ? Uri.parse(path).toFilePath() : path;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surfaceVariant,
        title: Text(t.title, style: TextStyle(color: p.accent, fontSize: 16)),
        content: SingleChildScrollView(child: SelectableText(cleanPath, style: TextStyle(color: p.textPrimary, fontSize: 12, fontFamily: 'monospace'))),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Закрыть', style: TextStyle(color: p.brass))),
        ],
      ),
    );
  }
}

/// Кастомный painter для мини-графика истории CPU.
/// Рисует 30 баров, высота пропорциональна %, цвет градиент green→yellow→red.
class _CpuChartPainter extends CustomPainter {
  final List<int> history;
  final Color color;
  _CpuChartPainter({required this.history, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;

    // === Сетка: тонкие горизонтальные линии на 20/40/60/80/100% ===
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = color.withOpacity(0.12);

    for (final pct in [20, 40, 60, 80, 100]) {
      final y = size.height - (pct / 100) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);

      // Маленькая метка процента справа
      final tp = TextPainter(
        text: TextSpan(
          text: '$pct',
          style: TextStyle(
            color: color.withOpacity(0.35),
            fontSize: 7,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      // Для 100% (y=0) метку кладём сверху, для остальных — чуть выше линии
      final labelY = (y == 0) ? 0.0 : (y - 3.5).clamp(0.0, size.height - 7.0);
      tp.paint(canvas, Offset(size.width - tp.width - 1, labelY));
    }

    // === Бары ===
    final barWidth = size.width / history.length;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < history.length; i++) {
      final pct = history[i].clamp(0, 100);
      final barHeight = (pct / 100) * size.height;
      final x = i * barWidth;
      final y = size.height - barHeight;

      if (pct <= 50) {
        paint.color = Color.lerp(
          const Color(0xFF4CAF50),
          const Color(0xFFFFC107),
          pct / 50,
        )!;
      } else {
        paint.color = Color.lerp(
          const Color(0xFFFFC107),
          const Color(0xFFF44336),
          (pct - 50) / 50,
        )!;
      }

      canvas.drawRect(
        Rect.fromLTWH(x + 0.5, y, barWidth - 1, barHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CpuChartPainter old) =>
      old.history.length != history.length ||
      (old.history.isNotEmpty && history.isNotEmpty && old.history.last != history.last);
}

class _ArtworkImage extends ConsumerWidget {
  const _ArtworkImage({required this.track});
  final Track? track;

  static final Map<String, String?> _coverCache = {};

  Future<String?> _findCoverInDir(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return null;
    if (_coverCache.containsKey(filePath)) return _coverCache[filePath];
    String? result;
    try {
      final file = File(filePath);
      final dir = file.parent;
      if (dir.existsSync()) {
        final entities = await dir.list(recursive: false, followLinks: false).toList();
        for (final e in entities) {
          final name = e.uri.pathSegments.last.toLowerCase();
          if (name == 'cover.jpg' || name == 'folder.jpg' ||
              name == 'album.jpg' || name == 'front.jpg' ||
              name == 'cover.png' || name == 'folder.png' ||
              name == 'album.png' || name == 'front.png') {
            result = 'file://${e.path}';
            break;
          }
        }
      }
    } catch (_) {}
    _coverCache[filePath] = result;
    return result;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Preset.of(context);
    final t = track;
    if (t == null) return _appIconFallback(p);
    String? artUri = t.artUri;

    if (artUri.isEmpty) {
      final fp = t.filePath.isNotEmpty ? t.filePath : null;
      if (fp != null && _coverCache.containsKey(fp)) {
        final cached = _coverCache[fp];
        if (cached != null && cached.isNotEmpty) {
          return Image.file(File(Uri.parse(cached).toFilePath()),
              fit: BoxFit.cover, errorBuilder: (_, e, __) => _appIconFallback(p));
        }
        return _appIconFallback(p);
      }
      _findCoverInDir(fp);
      return _appIconFallback(p);
    }

    final ms = ref.read(mediaStoreSourceProvider);
    final cachedBytes = ms.getCoverBytes(artUri);
    if (cachedBytes != null) {
      return Image.memory(cachedBytes, fit: BoxFit.cover, errorBuilder: (_, e, __) => _appIconFallback(p));
    }
    if (artUri.startsWith('file://')) {
      return Image.file(File(Uri.parse(artUri).toFilePath()), fit: BoxFit.cover, errorBuilder: (_, e, __) => _appIconFallback(p));
    }
    return Image.network(artUri, fit: BoxFit.cover, errorBuilder: (_, e, __) => _appIconFallback(p));
  }

  Widget _appIconFallback(ThemePreset p) {
    return Container(
      color: p.surfaceVariant,
      alignment: Alignment.center,
      child: Image.asset('assets/pathephon_fallback.png', fit: BoxFit.cover, width: double.infinity, height: double.infinity,
          errorBuilder: (_, e, __) => Icon(Icons.album, size: 100, color: p.brass)),
    );
  }
}