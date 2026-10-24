// ============================================================================
//  now_playing_screen.dart - Now Playing with stereo VU + simple artwork
//
//  Artwork priority:
//    1. track.artUri (embedded art URI from MediaStore)
//    2. Album artwork fallback (another track in same album with artUri)
//    3. Embedded art via on_audio_query.queryArtwork (mediaStoreId)
//    4. App icon (gramophone PNG) as last-resort fallback
// ============================================================================
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tube_colors.dart';
import '../../core/theme/vu_painter.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/models/track.dart';
import '../providers/providers.dart';
import '../widgets/playback_controls.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final playback = ref.read(playbackServiceProvider);
      final visualizer = ref.read(visualizerServiceProvider);
      playback.audioSessionIdStream.listen((sessionId) {
        visualizer.attach(sessionId);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final snap = ref.watch(playbackSnapshotProvider).valueOrNull;
    final pos = ref.watch(playbackPositionProvider).valueOrNull ?? Duration.zero;
    final stereo = ref.watch(stereoAmplitudeProvider).valueOrNull;
    final playback = ref.watch(playbackServiceProvider);
    ref.watch(isPlayingProvider);

    final track = snap?.current;
    final duration = snap?.duration ?? Duration.zero;
    final leftAmp = stereo?.left ?? 0.0;
    final rightAmp = stereo?.right ?? 0.0;
    final isPlaying = snap?.isPlaying ?? false;
    final brightness = isPlaying ? 1.0 : 0.0;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.power_settings_new),
                    tooltip: '\u0412\u044B\u0445\u043E\u0434',
                    onPressed: () => _showExitDialog(context),
                  ),
                  Text(
                    l.nowPlayingTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.queue_music),
                    tooltip: '\u041E\u0447\u0435\u0440\u0435\u0434\u044C',
                    onPressed: () => _showQueueSheet(context, ref),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              Expanded(
                flex: 4,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: TubeColors.brass, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: TubeColors.amberHot.withOpacity(0.25),
                            blurRadius: 40,
                            spreadRadius: 6,
                          ),
                        ],
                      ),
                      child: _ArtworkImage(track: track),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),
              CustomPaint(
                size: Size(MediaQuery.of(context).size.width - 40, 120),
                painter: VUPainter(
                  leftAmplitude: leftAmp,
                  rightAmplitude: rightAmp,
                  brightness: brightness,
                ),
              ),

              const SizedBox(height: 12),
              Text(
                track?.title ?? '\u2014',
                style: Theme.of(context).textTheme.displaySmall,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                [track?.artist, track?.album].whereType<String>().join(' \u00B7 '),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TubeColors.textSecondary,
                    ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (track != null && track.isHiRes) ...[
                const SizedBox(height: 4),
                Text(
                  track.qualityLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: TubeColors.phosphorGreen,
                      ),
                ),
              ],

              const SizedBox(height: 12),

              Row(
                children: [
                  Text(formatDuration(pos), style: Theme.of(context).textTheme.labelSmall),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: duration.inMilliseconds.toDouble().clamp(1.0, double.infinity),
                      value: pos.inMilliseconds
                          .toDouble()
                          .clamp(0, duration.inMilliseconds.toDouble()),
                      onChanged: (v) =>
                          playback.seekTo(Duration(milliseconds: v.toInt())),
                    ),
                  ),
                  Text(formatDuration(duration), style: Theme.of(context).textTheme.labelSmall),
                ],
              ),

              const SizedBox(height: 8),

              const PlaybackControls(),
            ],
          ),
        ),
      ),
    );
  }

  void _showExitDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1410),
        title: Text(
          '\u0412\u044B\u0439\u0442\u0438 \u0438\u0437 \u043F\u0440\u0438\u043B\u043E\u0436\u0435\u043D\u0438\u044F?',
          style: const TextStyle(color: Color(0xFFF4E9D2), fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              '\u041E\u0442\u043C\u0435\u043D\u0430',
              style: TextStyle(color: Color(0xFFB89968)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              SystemNavigator.pop();
            },
            child: const Text(
              '\u0412\u044B\u0439\u0442\u0438',
              style: TextStyle(color: Color(0xFFFF6B1A)),
            ),
          ),
        ],
      ),
    );
  }

  void _showQueueSheet(BuildContext context, WidgetRef ref) {
    final snap = ref.read(playbackSnapshotProvider).valueOrNull;
    final queue = snap?.queue ?? const <Track>[];
    final currentIndex = snap?.index ?? 0;
    final playback = ref.read(playbackServiceProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: TubeColors.surface,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '\u041E\u0447\u0435\u0440\u0435\u0434\u044C \u00B7 ${queue.length}',
                      style: Theme.of(sheetCtx).textTheme.titleMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1),
              if (queue.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('\u041E\u0447\u0435\u0440\u0435\u0434\u044C \u043F\u0443\u0441\u0442\u0430'),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: queue.length,
                    itemExtent: 48,
                    itemBuilder: (_, i) {
                      final t = queue[i];
                      final isCurrent = i == currentIndex;
                      return InkWell(
                        onTap: () {
                          playback.playQueue(tracks: queue, startIndex: i);
                          Navigator.of(sheetCtx).pop();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 32,
                                child: isCurrent
                                    ? const Icon(Icons.play_arrow, size: 22, color: TubeColors.amberHot)
                                    : Text(
                                        '${i + 1}',
                                        style: const TextStyle(color: TubeColors.textMuted, fontSize: 14),
                                        textAlign: TextAlign.center,
                                      ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      t.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isCurrent ? TubeColors.amberHot : TubeColors.textPrimary,
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 15,
                                        height: 1.15,
                                      ),
                                    ),
                                    if (t.artist.isNotEmpty)
                                      Text(
                                        t.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: TubeColors.textSecondary, fontSize: 12, height: 1.15),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (t.durationMs > 0)
                                Text(
                                  formatDuration(Duration(milliseconds: t.durationMs)),
                                  style: const TextStyle(color: TubeColors.textMuted, fontSize: 12),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Artwork widget with fallbacks.
class _ArtworkImage extends ConsumerStatefulWidget {
  const _ArtworkImage({required this.track});
  final Track? track;

  @override
  ConsumerState<_ArtworkImage> createState() => _ArtworkImageState();
}

class _ArtworkImageState extends ConsumerState<_ArtworkImage> {
  Uint8List? _bytes;
  int? _loadingMediaStoreId;

  @override
  void didUpdateWidget(_ArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeFetch();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFetch());
  }

  void _maybeFetch() {
    final t = widget.track;
    if (t == null) {
      _bytes = null;
      _loadingMediaStoreId = null;
      return;
    }
    // If track has artUri OR album fallback artUri, no need to fetch from MediaStore
    final albumArt = ref.read(albumArtIndexProvider)[
        '${t.albumArtist.isEmpty ? t.artist : t.albumArtist}||${t.album}'];
    final hasUri = t.artUri.isNotEmpty || (albumArt != null && albumArt.isNotEmpty);
    if (hasUri) {
      _bytes = null;
      _loadingMediaStoreId = null;
      return;
    }
    if (t.mediaStoreId != null && t.mediaStoreId != _loadingMediaStoreId) {
      _loadingMediaStoreId = t.mediaStoreId;
      _bytes = null;
      _fetchArt(t.mediaStoreId!);
    } else if (t.mediaStoreId == null) {
      _bytes = null;
      _loadingMediaStoreId = null;
    }
  }

  Future<void> _fetchArt(int id) async {
    try {
      final ms = ref.read(mediaStoreSourceProvider);
      final bytes = await ms.query.queryArtwork(id, ArtworkType.AUDIO, size: 600);
      if (mounted && _loadingMediaStoreId == id) {
        setState(() => _bytes = bytes);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    if (t == null) {
      return _appIconFallback();
    }

    // 1. Track's own artUri
    if (t.artUri.isNotEmpty) {
      return Image.network(
        t.artUri,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _appIconFallback(),
      );
    }

    // 2. Album artwork fallback
    final albumArt = ref.watch(albumArtIndexProvider)[
        '${t.albumArtist.isEmpty ? t.artist : t.albumArtist}||${t.album}'];
    if (albumArt != null && albumArt.isNotEmpty) {
      return Image.network(
        albumArt,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _appIconFallback(),
      );
    }

    // 3. Embedded art from MediaStore
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _appIconFallback(),
      );
    }

    // 4. Loading state
    if (t.mediaStoreId != null) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: TubeColors.brass),
        ),
      );
    }

    // 5. Last-resort: app icon
    return _appIconFallback();
  }

  Widget _appIconFallback() {
    return Container(
      color: TubeColors.surfaceVariant,
      alignment: Alignment.center,
      child: Image.asset(
        'assets/app_icon.png',
        fit: BoxFit.contain,
        width: 120,
        height: 120,
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.album,
          size: 120,
          color: TubeColors.brass,
        ),
      ),
    );
  }
}