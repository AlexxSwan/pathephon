// ============================================================================
//  now_playing_screen.dart - Now Playing with playlist (NO visualization)
//
//  Layout (top to bottom):
//    1. Top bar: exit | title | (queue icon removed - playlist is always visible)
//    2. Album art (flex 3)
//    3. Track title + artist (below the art)
//    4. Seek bar
//    5. Playback controls
//    6. Playlist (flex 2) - current track highlighted in amber
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tube_colors.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/models/track.dart';
import '../providers/providers.dart';
import '../widgets/playback_controls.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
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
          child: Column(
            children: [
              // ---- Top bar ----
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
                  const SizedBox(width: 48),
                ],
              ),

              const SizedBox(height: 8),

              // ---- Album art (smaller, flex 3) ----
              Expanded(
                flex: 3,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: TubeColors.brass, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: TubeColors.amberHot.withOpacity(0.25),
                            blurRadius: 30,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: _ArtworkImage(track: track),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ---- Track title + artist ----
              Text(
                track?.title ?? '\u2014',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
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

              const SizedBox(height: 8),

              // ---- Seek bar ----
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

              // ---- Controls ----
              const PlaybackControls(),

              const SizedBox(height: 12),

              // ---- Playlist (flex 2, current track highlighted) ----
              Expanded(
                flex: 2,
                child: queue.isEmpty
                    ? Center(
                        child: Text(
                          '\u041E\u0447\u0435\u0440\u0435\u0434\u044C \u043F\u0443\u0441\u0442\u0430',
                          style: TextStyle(color: TubeColors.textMuted),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: queue.length,
                        itemExtent: 44,
                        itemBuilder: (_, i) {
                          final t = queue[i];
                          final isCurrent = i == currentIndex;
                          return InkWell(
                            onTap: () {
                              playback.playQueue(tracks: queue, startIndex: i);
                            },
                            child: Container(
                              color: isCurrent
                                  ? TubeColors.amberHot.withOpacity(0.15)
                                  : Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 28,
                                    child: isCurrent
                                        ? const Icon(Icons.play_arrow, size: 20, color: TubeColors.amberHot)
                                        : Text('${i + 1}',
                                            style: const TextStyle(color: TubeColors.textMuted, fontSize: 13),
                                            textAlign: TextAlign.center),
                                  ),
                                  const SizedBox(width: 8),
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
                                            fontSize: 14,
                                            height: 1.15,
                                          ),
                                        ),
                                        if (t.artist.isNotEmpty)
                                          Text(t.artist,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(color: TubeColors.textSecondary, fontSize: 11, height: 1.15)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (t.durationMs > 0)
                                    Text(formatDuration(Duration(milliseconds: t.durationMs)),
                                        style: const TextStyle(color: TubeColors.textMuted, fontSize: 11)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
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
            child: const Text('\u041E\u0442\u043C\u0435\u043D\u0430',
                style: TextStyle(color: Color(0xFFB89968))),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              SystemNavigator.pop();
            },
            child: const Text('\u0412\u044B\u0439\u0442\u0438',
                style: TextStyle(color: Color(0xFFFF6B1A))),
          ),
        ],
      ),
    );
  }
}

/// Simple artwork: track.artUri -> album fallback -> app icon.
class _ArtworkImage extends ConsumerWidget {
  const _ArtworkImage({required this.track});
  final Track? track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = track;
    if (t == null) return _appIconFallback();

    if (t.artUri.isNotEmpty) {
      return Image.network(
        t.artUri,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _appIconFallback(),
      );
    }

    final albumArt = ref.watch(albumArtIndexProvider)[
        '${t.albumArtist.isEmpty ? t.artist : t.albumArtist}||${t.album}'];
    if (albumArt != null && albumArt.isNotEmpty) {
      return Image.network(
        albumArt,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _appIconFallback(),
      );
    }

    return _appIconFallback();
  }

  Widget _appIconFallback() {
    return Container(
      color: TubeColors.surfaceVariant,
      alignment: Alignment.center,
      child: Image.asset(
        'assets/app_icon.png',
        fit: BoxFit.contain,
        width: 100,
        height: 100,
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.album,
          size: 100,
          color: TubeColors.brass,
        ),
      ),
    );
  }
}