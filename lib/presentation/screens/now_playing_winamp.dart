// ============================================================================
//  now_playing_winamp.dart — Winamp-style Now Playing screen (Phase 1)
// ============================================================================
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/winamp_theme.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/models/track.dart';
import '../providers/providers.dart';
import '../../services/playback_service.dart';

class NowPlayingWinamp extends ConsumerStatefulWidget {
  const NowPlayingWinamp({super.key});

  @override
  ConsumerState<NowPlayingWinamp> createState() => _NowPlayingWinampState();
}

class _NowPlayingWinampState extends ConsumerState<NowPlayingWinamp> {
  final _playlistScrollController = ScrollController();
  int _lastScrolledIndex = -1;
  Timer? _scrollTimer;
  String _displayTitle = '';
  int _scrollOffset = 0;

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _playlistScrollController.dispose();
    super.dispose();
  }

  void _startTitleScroll(String title) {
    if (title == _displayTitle) return;
    _displayTitle = title;
    _scrollOffset = 0;
    _scrollTimer?.cancel();
    if (title.length > 25) {
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
        setState(() {
          _scrollOffset++;
          if (_scrollOffset > title.length + 5) {
            _scrollOffset = 0;
          }
        });
      });
    }
  }

  String _scrollTitle(String title) {
    if (title.length <= 25) return title;
    final padded = '$title   ***   ';
    final start = _scrollOffset % padded.length;
    final result = padded.substring(start) + padded;
    return result.substring(0, 25);
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(playbackSnapshotProvider).valueOrNull;
    final pos = ref.watch(playbackPositionProvider).valueOrNull ?? Duration.zero;
    final playback = ref.watch(playbackServiceProvider);
    ref.watch(isPlayingProvider);

    final track = snap?.current;
    final queue = snap?.queue ?? const <Track>[];
    final currentIndex = snap?.index ?? 0;
    final duration = snap?.duration ?? Duration.zero;
    final isPlaying = snap?.isPlaying ?? false;

    if (track != null) {
      _startTitleScroll(track.title);
    }

    final remainingMs =
        (duration.inMilliseconds - pos.inMilliseconds).clamp(0, duration.inMilliseconds);
    final remaining = Duration(milliseconds: remainingMs);

    // Auto-scroll playlist to current track
    if (currentIndex != _lastScrolledIndex) {
      _lastScrolledIndex = currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_playlistScrollController.hasClients) {
          final target = currentIndex * 24.0;
          final viewport = _playlistScrollController.position.viewportDimension;
          final offset = _playlistScrollController.offset;
          if (target < offset || target > offset + viewport - 24) {
            _playlistScrollController.animateTo(
              (target - viewport / 2 + 12)
                  .clamp(0.0, _playlistScrollController.position.maxScrollExtent),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        }
      });
    }

    return Scaffold(
      backgroundColor: WinampColors.bgMain,
      body: SafeArea(
        child: Column(children: [
          // Title bar
          const WinampTitleBar(title: 'PATHEPHON'),

          // LCD display area
          Container(
            margin: const EdgeInsets.all(4),
            child: WinampLcd(
              height: 90,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(currentIndex + 1).toString().padLeft(2, '0')}/${queue.length.toString().padLeft(2, '0')}',
                        style: lcdStyle(size: 16),
                      ),
                      Text(
                        '${formatDuration(pos)}  -${formatDuration(remaining)}',
                        style: lcdStyle(size: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Text(
                      _scrollTitle(track?.title ?? '---'),
                      style: lcdStyle(size: 22),
                      maxLines: 1,
                    ),
                  ),
                  if (track?.artist.isNotEmpty == true)
                    Text(
                      track!.artist,
                      style: lcdStyle(size: 14, color: WinampColors.textSecondary),
                      maxLines: 1,
                    ),
                ],
              ),
            ),
          ),

          // Seek bar (LED segments)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: WinampSeekBar(
              position: pos,
              duration: duration,
              onSeek: (d) => playback.seekTo(d),
            ),
          ),

          // Playback controls (metallic buttons)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(vertical: 4),
            color: WinampColors.bgPanel,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                WinampButton(
                  icon: Icons.skip_previous,
                  onTap: () => playback.skipToPrevious(),
                ),
                const SizedBox(width: 8),
                WinampButton(
                  icon: isPlaying ? Icons.pause : Icons.play_arrow,
                  onTap: () {
                    if (isPlaying) {
                      playback.pause();
                    } else {
                      playback.play();
                    }
                  },
                  active: isPlaying,
                  size: 48,
                ),
                const SizedBox(width: 8),
                WinampButton(
                  icon: Icons.stop,
                  onTap: () => playback.stop(),
                ),
                const SizedBox(width: 8),
                WinampButton(
                  icon: Icons.skip_next,
                  onTap: () => playback.skipToNext(),
                ),
              ],
            ),
          ),

          // Playlist (Winamp style)
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: WinampColors.lcdBg,
                border: Border.all(color: WinampColors.metalDark, width: 1),
              ),
              child: ListView.builder(
                controller: _playlistScrollController,
                padding: EdgeInsets.zero,
                itemCount: queue.length,
                itemExtent: 24,
                itemBuilder: (_, i) {
                  final t = queue[i];
                  final isCurrent = i == currentIndex;
                  return GestureDetector(
                    onTap: () =>
                        playback.playQueue(tracks: queue, startIndex: i),
                    child: Container(
                      color: isCurrent
                          ? WinampColors.lcdText.withOpacity(0.1)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${(i + 1).toString().padLeft(2, '0')}',
                            style: lcdStyle(
                              size: 14,
                              color: isCurrent
                                  ? WinampColors.lcdText
                                  : WinampColors.textMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            t.title,
                            style: lcdStyle(
                              size: 14,
                              color: isCurrent
                                  ? WinampColors.lcdText
                                  : WinampColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (t.durationMs > 0)
                          Text(
                            formatDuration(Duration(milliseconds: t.durationMs)),
                            style: lcdStyle(
                                size: 14, color: WinampColors.textMuted),
                          ),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
