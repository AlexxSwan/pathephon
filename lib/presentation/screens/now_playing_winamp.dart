// ============================================================================
//  now_playing_winamp.dart — Authentic Winamp classic skin layout
//  Two windows: main player + playlist, compact pixel-perfect layout
// ============================================================================
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/winamp_theme.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/models/track.dart';
import '../providers/providers.dart';
import '../../services/playback_service.dart';

class NowPlayingWinamp extends ConsumerStatefulWidget {
  const NowPlayingWinamp({super.key, this.onExit});
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
  double _volume = 0.7;
  double _balance = 0.0; // -1 left, 0 center, +1 right
  bool _shuffle = false;
  bool _repeat = false;
  bool _eqPanel = false;
  bool _plPanel = true;

  // Simple CPU/spectrum mock
  final List<double> _spectrumBars = List.filled(16, 0.0);
  Timer? _spectrumTimer;

  @override
  void initState() {
    super.initState();
    _startSpectrum();
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _spectrumTimer?.cancel();
    _playlistScrollController.dispose();
    super.dispose();
  }

  void _startSpectrum() {
    _spectrumTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        setState(() {
          final isPlaying = ref.read(isPlayingProvider);
          if (isPlaying) {
            for (var i = 0; i < _spectrumBars.length; i++) {
              _spectrumBars[i] = (_spectrumBars[i] * 0.7 +
                  (0.3 + 0.7 * _pseudoRandom()) * 0.3).clamp(0.0, 1.0);
            }
          } else {
            for (var i = 0; i < _spectrumBars.length; i++) {
              _spectrumBars[i] *= 0.85;
            }
          }
        });
      }
    });
  }

  double _pseudoRandom() {
    return ((DateTime.now().microsecondsSinceEpoch * 1103515245 + 12345) &
            0x7fffffff) /
        0x7fffffff;
  }

  void _startTitleScroll(String title) {
    if (title == _displayTitle) return;
    _displayTitle = title;
    _scrollOffset = 0;
    _scrollTimer?.cancel();
    if (title.length > 28) {
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
        if (mounted) {
          setState(() {
            _scrollOffset++;
            if (_scrollOffset > title.length + 5) _scrollOffset = 0;
          });
        }
      });
    }
  }

  String _scrollTitle(String title) {
    if (title.length <= 28) return title;
    final padded = '$title   **   ';
    final start = _scrollOffset % padded.length;
    return (padded.substring(start) + padded).substring(0, 28);
  }

  String _formatTotal(List<Track> queue) {
    int totalMs = 0;
    for (final t in queue) {
      totalMs += t.durationMs;
    }
    final h = totalMs ~/ 3600000;
    final m = (totalMs % 3600000) ~/ 60000;
    final s = (totalMs % 60000) ~/ 1000;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(playbackSnapshotProvider).valueOrNull;
    final pos = ref.watch(playbackPositionProvider).valueOrNull ?? Duration.zero;
    final playback = ref.watch(playbackServiceProvider);
    final isPlaying = snap?.isPlaying ?? false;

    final track = snap?.current;
    final queue = snap?.queue ?? const <Track>[];
    final currentIndex = snap?.index ?? 0;
    final duration = snap?.duration ?? Duration.zero;

    if (track != null) _startTitleScroll(track.title);

    final remainingMs = (duration.inMilliseconds - pos.inMilliseconds)
        .clamp(0, duration.inMilliseconds);
    final remaining = Duration(milliseconds: remainingMs);

    // Auto-scroll playlist
    if (currentIndex != _lastScrolledIndex) {
      _lastScrolledIndex = currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_playlistScrollController.hasClients) {
          final target = currentIndex * 18.0;
          final viewport = _playlistScrollController.position.viewportDimension;
          final offset = _playlistScrollController.offset;
          if (target < offset || target > offset + viewport - 18) {
            _playlistScrollController.animateTo(
              (target - viewport / 2 + 9).clamp(
                  0.0, _playlistScrollController.position.maxScrollExtent),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        }
      });
    }

    final titleStr = track?.title ?? '---';
    final artistStr = track?.artist ?? '';

    return Scaffold(
      backgroundColor: WinampColors.bgMain,
      body: SafeArea(
        child: Column(
          children: [
            // ==================== MAIN WINDOW ====================
            Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: WinampColors.bgPanel,
                border: Border.all(color: WinampColors.metalDark, width: 1),
              ),
              child: Column(
                children: [
                  // Title bar
                  WinampTitleBar(title: 'WINAMP', onClose: widget.onExit),

                  // LCD display
                  Container(
                    margin: const EdgeInsets.all(2),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: WinampColors.lcdBg,
                      border: Border.all(color: WinampColors.metalDark, width: 1),
                    ),
                    child: Column(
                      children: [
                        // Row 1: scrolling title + bitrate
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                artistStr.isNotEmpty
                                    ? '$artistStr - ${_scrollTitle(titleStr)}'
                                    : _scrollTitle(titleStr),
                                style: lcdStyle(size: 14),
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                              ),
                            ),
                            if (track?.durationMs != null && track!.durationMs > 0)
                              Text(
                                '${(track.durationMs / 1000).round()}',
                                style: lcdStyle(size: 12, color: WinampColors.textSecondary),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        // Row 2: time + remaining + stereo + spectrum
                        Row(
                          children: [
                            // Time display
                            Text(
                              formatDuration(pos),
                              style: lcdStyle(size: 20),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '-${formatDuration(remaining)}',
                              style: lcdStyle(size: 14, color: WinampColors.textSecondary),
                            ),
                            const Spacer(),
                            // Stereo indicator
                            Text('STEREO',
                              style: lcdStyle(size: 10,
                                color: isPlaying ? WinampColors.lcdText : WinampColors.lcdDim),
                            ),
                            const SizedBox(width: 6),
                            // Mini spectrum
                            SizedBox(
                              width: 48,
                              height: 14,
                              child: CustomPaint(
                                painter: _WinampSpectrumPainter(_spectrumBars),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Seek bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: WinampSeekBar(
                      position: pos,
                      duration: duration,
                      onSeek: (d) => playback.seekTo(d),
                      segments: 28,
                    ),
                  ),

                  // Volume + Balance sliders
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      children: [
                        Text('VOL', style: lcdStyle(size: 10, color: WinampColors.textMuted)),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 3,
                          child: _WinampHSlider(
                            value: _volume,
                            onChanged: (v) {
                              setState(() => _volume = v);
                              playback.setVolume(v);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('BAL', style: lcdStyle(size: 10, color: WinampColors.textMuted)),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 2,
                          child: _WinampHSlider(
                            value: (_balance + 1) / 2,
                            onChanged: (v) {
                              setState(() => _balance = (v * 2 - 1).clamp(-1.0, 1.0));
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Control buttons row
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left: EQ + PL toggles
                        Row(children: [
                          _WinampToggleButton(
                            label: 'EQ',
                            active: _eqPanel,
                            onTap: () => setState(() => _eqPanel = !_eqPanel),
                          ),
                          const SizedBox(width: 3),
                          _WinampToggleButton(
                            label: 'PL',
                            active: _plPanel,
                            onTap: () => setState(() => _plPanel = !_plPanel),
                          ),
                        ]),
                        // Center: playback
                        Row(children: [
                          WinampButton(icon: Icons.skip_previous, size: 28,
                            onTap: () => playback.skipToPrevious()),
                          const SizedBox(width: 4),
                          WinampButton(
                            icon: isPlaying ? Icons.pause : Icons.play_arrow,
                            size: 32,
                            active: isPlaying,
                            onTap: () => isPlaying ? playback.pause() : playback.play(),
                          ),
                          const SizedBox(width: 4),
                          WinampButton(icon: Icons.stop, size: 28,
                            onTap: () => playback.stop()),
                          const SizedBox(width: 4),
                          WinampButton(icon: Icons.skip_next, size: 28,
                            onTap: () => playback.skipToNext()),
                        ]),
                        // Right: SHUFFLE + REPEAT
                        Row(children: [
                          _WinampToggleButton(
                            label: 'SHF',
                            active: _shuffle,
                            onTap: () {
                              setState(() => _shuffle = !_shuffle);
                              playback.setShuffle(_shuffle);
                            },
                          ),
                          const SizedBox(width: 3),
                          _WinampToggleButton(
                            label: 'REP',
                            active: _repeat,
                            onTap: () {
                              setState(() => _repeat = !_repeat);
                              // Cycle repeat mode
                            },
                          ),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ==================== PLAYLIST WINDOW ====================
            if (_plPanel)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
                  decoration: BoxDecoration(
                    color: WinampColors.bgPanel,
                    border: Border.all(color: WinampColors.metalDark, width: 1),
                  ),
                  child: Column(
                    children: [
                      // Playlist title bar
                      Container(
                        height: 20,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [WinampColors.titleBarStart, WinampColors.titleBarEnd],
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('WINAMP PLAYLIST',
                              style: lcdStyle(size: 12, color: Colors.white)),
                            Text('${queue.length} tracks  ${_formatTotal(queue)}',
                              style: lcdStyle(size: 10, color: Colors.white70)),
                          ],
                        ),
                      ),
                      // Track list
                      Expanded(
                        child: Container(
                          color: WinampColors.lcdBg,
                          child: ListView.builder(
                            controller: _playlistScrollController,
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            itemCount: queue.length,
                            itemExtent: 18,
                            itemBuilder: (_, i) {
                              final t = queue[i];
                              final isCurrent = i == currentIndex;
                              final dispArtist = t.artist.isNotEmpty ? t.artist : '';
                              final dispTitle = t.title;
                              final dur = t.durationMs > 0
                                ? formatDuration(Duration(milliseconds: t.durationMs))
                                : '';
                              return GestureDetector(
                                onTap: () => playback.playQueue(tracks: queue, startIndex: i),
                                child: Container(
                                  color: isCurrent
                                    ? WinampColors.lcdText.withOpacity(0.08)
                                    : Colors.transparent,
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Row(children: [
                                    SizedBox(
                                      width: 20,
                                      child: Text('${(i + 1).toString().padLeft(2, '0')}',
                                        style: lcdStyle(size: 11,
                                          color: isCurrent ? WinampColors.lcdText : WinampColors.textMuted),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        dispArtist.isNotEmpty
                                          ? '$dispArtist - $dispTitle'
                                          : dispTitle,
                                        style: lcdStyle(size: 11,
                                          color: isCurrent ? WinampColors.lcdText : WinampColors.textSecondary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (dur.isNotEmpty)
                                      Text(dur,
                                        style: lcdStyle(size: 11, color: WinampColors.textMuted)),
                                  ]),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      // Bottom action bar
                      Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: WinampColors.bgPanel,
                          border: Border(top: BorderSide(color: WinampColors.metalDark, width: 1)),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _WinampMiniButton(label: 'ADD'),
                            _WinampMiniButton(label: 'REM'),
                            _WinampMiniButton(label: 'SEL'),
                            _WinampMiniButton(label: 'MISC'),
                            _WinampMiniButton(label: 'LIST'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal LED slider for volume/balance.
class _WinampHSlider extends StatelessWidget {
  const _WinampHSlider({required this.value, required this.onChanged});
  final double value; // 0.0 to 1.0
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final segments = 20;
      final filled = (value * segments).round();
      return GestureDetector(
        onTapDown: (details) {
          onChanged((details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0));
        },
        onHorizontalDragUpdate: (details) {
          onChanged((details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0));
        },
        child: Container(
          height: 8,
          decoration: BoxDecoration(
            color: WinampColors.lcdBg,
            border: Border.all(color: WinampColors.metalDark, width: 1),
          ),
          child: Row(
            children: List.generate(segments, (i) {
              return Expanded(child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 0.5, vertical: 1),
                color: i < filled ? WinampColors.lcdText : WinampColors.lcdDim,
              ));
            }),
          ),
        ),
      );
    });
  }
}

/// Small toggle button (EQ, PL, SHUFFLE, REPEAT).
class _WinampToggleButton extends StatelessWidget {
  const _WinampToggleButton({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 16,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: active ? Alignment.bottomCenter : Alignment.topCenter,
            end: active ? Alignment.topCenter : Alignment.bottomCenter,
            colors: [WinampColors.metalLight, WinampColors.metalMid, WinampColors.metalDark],
          ),
          border: Border.all(color: WinampColors.metalDarker, width: 1),
        ),
        child: Center(
          child: Text(label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: active ? WinampColors.lcdText : WinampColors.metalDarker,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}

/// Mini button for playlist actions (ADD, REM, etc.)
class _WinampMiniButton extends StatelessWidget {
  const _WinampMiniButton({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [WinampColors.metalLight, WinampColors.metalMid, WinampColors.metalDark],
          ),
          border: Border.all(color: WinampColors.metalDarker, width: 1),
        ),
        child: Text(label,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
            color: WinampColors.metalDarker, fontFamily: 'monospace'),
        ),
      ),
    );
  }
}

/// Mini spectrum visualizer painter.
class _WinampSpectrumPainter extends CustomPainter {
  final List<double> bars;
  _WinampSpectrumPainter(this.bars);

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final barW = size.width / bars.length;
    final paint = Paint()..color = WinampColors.lcdText;

    for (var i = 0; i < bars.length; i++) {
      final h = (bars[i] * size.height).clamp(0.0, size.height);
      canvas.drawRect(
        Rect.fromLTWH(i * barW + 0.5, size.height - h, barW - 1, h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WinampSpectrumPainter old) => true;
}
