// ============================================================================
//  now_playing_screen.dart - uses Preset.of(context) for theme-aware colors
//  v0.11.0+194: CPU% индикатор в верхнем левом углу.
//               Читает /proc/self/stat (utime+stime) каждую секунду.
//               StreamBuilder — пересобирается только бейдж, не весь экран.
//               Цвет: зелёный (0%) → жёлтый (50%) → красный (100%).
// ============================================================================
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/retro_theme.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/models/track.dart';
import '../providers/providers.dart';
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
  // StreamController<int> — бейдж подписывается через StreamBuilder,
  // setState НЕ вызывается — весь экран не пересобирается.
  final _cpuController = StreamController<int>.broadcast();
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

  /// Читает /proc/self/stat каждые 1 сек, считает CPU% по дельте utime+stime.
  /// /proc/self/stat — виртуальный файл procfs, читается мгновенно (без I/O).
  /// Поля (после comm в скобках): [0]=state, [11]=utime, [12]=stime.
  /// clk_tck на ARM64 = 100, поэтому 1 секунда = 100 jiffies max на ядро.
  void _startCpuMonitor() {
    // Первое чтение — устанавливает baseline, ничего не шлёт в stream
    _readCpuStat();
    // Периодические обновления
    _cpuTimer = Timer.periodic(const Duration(seconds: 1), (_) => _readCpuStat());
  }

  void _readCpuStat() {
    try {
      final stat = File('/proc/self/stat').readAsStringSync();
      // comm может содержать скобки/пробелы — берём всё после последней ')'
      final lastParen = stat.lastIndexOf(') ');
      if (lastParen < 0) return;
      final fields = stat.substring(lastParen + 2).split(RegExp(r'\s+'));
      if (fields.length < 13) return;
      final utime = int.parse(fields[11]);
      final stime = int.parse(fields[12]);

      if (_prevUtime > 0 || _prevStime > 0) {
        final deltaJiffies = (utime - _prevUtime) + (stime - _prevStime);
        // 1 секунда * 100 jiffies/sec = 100 max per core
        // Ограничиваем 100% (один_core_эквивалент) — интуитивно для пользователя
        final pct = deltaJiffies.clamp(0, 100);
        _cpuController.add(pct);
      }
      _prevUtime = utime;
      _prevStime = stime;
    } catch (_) {
      // /proc/self/stat недоступен (iOS/desktop) — индикатор просто не обновляется
    }
  }

  /// Цветовая градация: 0% = зелёный, 50% = жёлтый, 100% = красный.
  Color _cpuColor(int pct) {
    if (pct <= 50) {
      // зелёный → жёлтый
      return Color.lerp(
        const Color(0xFF4CAF50), // Material Green 500
        const Color(0xFFFFC107), // Material Amber 500
        pct / 50,
      )!;
    } else {
      // жёлтый → красный
      return Color.lerp(
        const Color(0xFFFFC107),
        const Color(0xFFF44336), // Material Red 500
        (pct - 50) / 50,
      )!;
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
            // ====== Топ-бар: [CPU%] [title] [playlist toggle] ======
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // ЛЕВО: CPU индикатор (StreamBuilder — пересобирается только он)
                StreamBuilder<int>(
                  stream: _cpuController.stream,
                  initialData: 0,
                  builder: (context, snapshot) {
                    final pct = snapshot.data ?? 0;
                    final color = _cpuColor(pct);
                    return Container(
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
                    );
                  },
                ),
                Text(l.nowPlayingTitle, style: Theme.of(context).textTheme.titleMedium),
                // ПРАВО: playlist toggle
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