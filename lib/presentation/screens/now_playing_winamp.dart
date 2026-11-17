// ============================================================================
//  now_playing_winamp.dart — Winamp-style Now Playing screen (Phase 1.1)
//  Fixed: compact buttons, no text clipping, exit button in title bar
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
  const NowPlayingWinamp({super.key, this.onExit});

  /// Called when user taps the "close" button in the title bar.
  /// Typically switches to the About tab so user can change skin back.
  final VoidCallback? onExit;

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
    if (title.length > 20) {
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
        setState(() {
          _scrollOffset++;
          if (_scrollOffset > title.length + 3) {
            _scrollOffset = 0;
          }
        });
      });
    }
  }

  String _scrollTitle(String title) {
    if (title.length <= 20) return title;
    final padded = '$title   ***   ';
    final start = _scrollOffset % padded.length;
    final result = padded.substring(start) + padded;
    return result.substring(0, 20);
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

    // Auto-scroll playlist
    if (currentIndex != _lastScrolledIndex) {
      _lastScrolledIndex = currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_playlistScrollController.hasClients) {
          final target = currentIndex * 20.0;
          final viewport = _playlistScrollController.position.viewportDimension;
          final offset = _playlistScrollController.offset;
          if (target < offset || target > offset + viewport - 20) {
            _playlistScrollController.animateTo(
              (target - viewport / 2 + 10)
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
          // Title bar with exit button
          WinampTitleBar(
            title: 'PATHEPHON',
            onClose: widget.onExit,
          ),

          // LCD display — compact
          Container(
            margin: const EdgeInsets.all(3),
            child: WinampLcd(
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1: track number + time
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(currentIndex + 1).toString().padLeft(2, '0')}/${queue.length}',
                        style: lcdStyle(size: 14),
                      ),
                      Text(
                        '${formatDuration(pos)} -${formatDuration(remaining)}',
                        style: lcdStyle(size: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Row 2: scrolling title
                  Text(
                    _scrollTitle(track?.title ?? '---'),
                    style: lcdStyle(size: 18),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                  ),
                  // Row 3: artist (if present)
                  if (track?.artist.isNotEmpty == true)
                    Text(
                      track!.artist,
                      style: lcdStyle(size: 12, color: WinampColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ),

          // Seek bar (LED segments)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: WinampSeekBar(
              position: pos,
              duration: duration,
              onSeek: (d) => playback.seekTo(d),
              segments: 32,
            ),
          ),

          // Playback controls — compact buttons
          Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(vertical: 2),
            color: WinampColors.bgPanel,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                WinampButton(
                  icon: Icons.skip_previous,
                  onTap: () => playback.skipToPrevious(),
                  size: 32,
                ),
                const SizedBox(width: 6),
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
                  size: 36,
                ),
                const SizedBox(width: 6),
                WinampButton(
                  icon: Icons.stop,
                  onTap: () => playback.stop(),
                  size: 32,
                ),
                const SizedBox(width: 6),
                WinampButton(
                  icon: Icons.skip_next,
                  onTap: () => playback.skipToNext(),
                  size: 32,
                ),
              ],
            ),
          ),

          // Playlist — fills remaining space
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(3, 0, 3, 3),
              decoration: BoxDecoration(
                color: WinampColors.lcdBg,
                border: Border.all(color: WinampColors.metalDark, width: 1),
              ),
              child: ListView.builder(
                controller: _playlistScrollController,
                padding: const EdgeInsets.symmetric(vertical: 2),
                itemCount: queue.length,
                itemExtent: 20,
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
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(children: [
                        SizedBox(
                          width: 24,
                          child: Text(
                            '${(i + 1).toString().padLeft(2, '0')}',
                            style: lcdStyle(
                              size: 12,
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
                              size: 12,
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
                                size: 12, color: WinampColors.textMuted),
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
