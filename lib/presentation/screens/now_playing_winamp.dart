// ============================================================================
//  now_playing_winamp.dart — Winamp with EQ panel + working ADD
//  EQ: inline panel between player and playlist (5 bands + preamp)
//  ADD: onAdd callback -> Library tab
//  Title: ПАТЕФОН / ПАТЕФОН СПИСОК
// ============================================================================
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;

import '../../core/theme/winamp_theme.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/enums/repeat_mode.dart';
import '../../domain/models/track.dart';
import '../providers/providers.dart';
import '../../services/equalizer_service.dart';
import '../../services/playback_service.dart';

class NowPlayingWinamp extends ConsumerStatefulWidget {
  const NowPlayingWinamp({
    super.key,
    this.onExit,
    this.onEQ,
    this.onAdd,
  });

  final VoidCallback? onExit;
  final VoidCallback? onEQ;
  final VoidCallback? onAdd;

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
  bool _plPanel = true;
  bool _eqPanel = false;
  // EQ state — synced with equalizerServiceProvider (REAL native EQ)
  List<double> _eqBands = List.filled(kEqBandCount, 0.0);
  bool _eqEnabled = false;
  StreamSubscription<int>? _eqSessionSub;

  final List<double> _spectrumBars = List.filled(16, 0.0);
  Timer? _spectrumTimer;

  @override
  void initState() {
    super.initState();
    _startSpectrum();
    _initEq();
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _spectrumTimer?.cancel();
    _eqSessionSub?.cancel();
    _playlistScrollController.dispose();
    super.dispose();
  }

  /// Initialize EQ: read saved state + hook to audio session
  void _initEq() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final eq = ref.read(equalizerServiceProvider);
      // Read current state from the service (loaded from prefs)
      _eqBands = List.from(eq.currentBands);
      _eqEnabled = eq.isEnabled;
      if (mounted) setState(() {});

      // CRITICAL: hook EQ to the player's audio session id.
      // Without this, EQ has no effect on audio output.
      final playback = ref.read(playbackServiceProvider);
      _eqSessionSub = playback.audioSessionIdStream.listen((sessionId) {
        eq.attachToSession(sessionId);
      });
    });
  }

  void _startSpectrum() {
    _spectrumTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final playing = ref.read(isPlayingProvider);
      setState(() {
        if (playing) {
          for (var i = 0; i < _spectrumBars.length; i++) {
            final r = ((DateTime.now().microsecondsSinceEpoch * (i + 1) * 1103) & 0x7FF) / 0x7FF;
            _spectrumBars[i] = (_spectrumBars[i] * 0.6 + r * 0.4).clamp(0.0, 1.0);
          }
        } else {
          for (var i = 0; i < _spectrumBars.length; i++) {
            _spectrumBars[i] *= 0.8;
          }
        }
      });
    });
  }

  void _startTitleScroll(String title) {
    if (title == _displayTitle) return;
    _displayTitle = title;
    _scrollOffset = 0;
    _scrollTimer?.cancel();
    if (title.length > 28) {
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
        if (!mounted) return;
        setState(() {
          _scrollOffset++;
          if (_scrollOffset > title.length + 5) _scrollOffset = 0;
        });
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
    for (final t in queue) totalMs += t.durationMs;
    final h = totalMs ~/ 3600000;
    final m = (totalMs % 3600000) ~/ 60000;
    final s = (totalMs % 60000) ~/ 1000;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Set individual band gain via REAL native EQ service
  void _onEqBandChanged(int bandIndex, double gainDb) {
    setState(() => _eqBands[bandIndex] = gainDb.clamp(-15.0, 15.0));
    ref.read(equalizerServiceProvider).setBandGain(bandIndex, gainDb);
  }

  /// Toggle EQ on/off via REAL native EQ service
  void _onEqToggle() {
    setState(() => _eqEnabled = !_eqEnabled);
    ref.read(equalizerServiceProvider).setEnabled(_eqEnabled);
  }

  void _addTracks() => widget.onAdd?.call();

  Future<void> _shareCurrentTrack() async {
    final snap = ref.read(playbackSnapshotProvider).valueOrNull;
    final track = snap?.current;
    if (track == null) return;
    try {
      String? filePath;
      if (track.filePath.isNotEmpty && File(track.filePath).existsSync()) {
        filePath = track.filePath;
      } else if (track.uri.startsWith('file://')) {
        final path = Uri.parse(track.uri).toFilePath();
        if (File(path).existsSync()) filePath = path;
      }
      if (filePath == null) return;
      await Share.shareXFiles([XFile(filePath)],
        subject: p.basename(filePath), text: track.title);
    } catch (_) {}
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
    final shuffle = snap?.shuffle ?? false;
    final repeatMode = snap?.repeatMode ?? RepeatMode.off;

    if (track != null) _startTitleScroll(track.title);

    final remainingMs = (duration.inMilliseconds - pos.inMilliseconds)
        .clamp(0, duration.inMilliseconds);
    final remaining = Duration(milliseconds: remainingMs);

    if (currentIndex != _lastScrolledIndex) {
      _lastScrolledIndex = currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_playlistScrollController.hasClients) {
          final target = currentIndex * 18.0;
          final viewport = _playlistScrollController.position.viewportDimension;
          final offset = _playlistScrollController.offset;
          if (target < offset || target > offset + viewport - 18) {
            _playlistScrollController.animateTo(
              (target - viewport / 2 + 9)
                  .clamp(0.0, _playlistScrollController.position.maxScrollExtent),
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
          }
        }
      });
    }

    final titleStr = track?.title ?? '---';
    final artistStr = track?.artist ?? '';

    return Scaffold(
      backgroundColor: WinampColors.bgMain,
      body: SafeArea(
        child: Column(children: [
          // ==================== MAIN WINDOW ====================
          Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: WinampColors.bgPanel,
              border: Border.all(color: WinampColors.metalDark, width: 1),
            ),
            child: Column(children: [
              WinampTitleBar(title: '\u041F\u0410\u0422\u0415\u0424\u041E\u041D'),
              // LCD display
              Container(
                margin: const EdgeInsets.all(2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: WinampColors.lcdBg,
                  border: Border.all(color: WinampColors.metalDark, width: 1),
                ),
                child: Column(children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(
                        artistStr.isNotEmpty
                          ? '$artistStr - ${_scrollTitle(titleStr)}'
                          : _scrollTitle(titleStr),
                        style: lcdStyle(size: 14),
                        maxLines: 1, overflow: TextOverflow.clip,
                      )),
                      if (track != null && track.durationMs > 0)
                        Text('${(track.durationMs / 1000).round()}',
                          style: lcdStyle(size: 12, color: WinampColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(children: [
                    Text(formatDuration(pos), style: lcdStyle(size: 20)),
                    const SizedBox(width: 8),
                    Text('-${formatDuration(remaining)}',
                      style: lcdStyle(size: 14, color: WinampColors.textSecondary)),
                    const Spacer(),
                    Text('STEREO',
                      style: lcdStyle(size: 10,
                        color: isPlaying ? WinampColors.lcdText : WinampColors.lcdDim)),
                    const SizedBox(width: 6),
                    SizedBox(width: 48, height: 14,
                      child: CustomPaint(painter: _WinampSpectrumPainter(_spectrumBars))),
                  ]),
                ]),
              ),
              // Seek bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: WinampSeekBar(
                  position: pos, duration: duration,
                  onSeek: (d) => playback.seekTo(d), segments: 28),
              ),
              // Volume + Balance
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(children: [
                  Text('VOL', style: lcdStyle(size: 10, color: WinampColors.textMuted)),
                  const SizedBox(width: 4),
                  Expanded(flex: 3, child: _WinampHSlider(
                    value: _volume,
                    onChanged: (v) { setState(() => _volume = v); playback.setVolume(v); })),
                  const SizedBox(width: 8),
                  Text('BAL', style: lcdStyle(size: 10, color: WinampColors.textMuted)),
                  const SizedBox(width: 4),
                  Expanded(flex: 2, child: _WinampHSlider(value: 0.5, onChanged: (_) {})),
                ]),
              ),
              // Controls
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      _WinampToggleButton(label: 'EQ', active: _eqPanel,
                        onTap: () => setState(() => _eqPanel = !_eqPanel)),
                      const SizedBox(width: 3),
                      _WinampToggleButton(label: 'PL', active: _plPanel,
                        onTap: () => setState(() => _plPanel = !_plPanel)),
                    ]),
                    Row(children: [
                      WinampButton(icon: Icons.skip_previous, size: 28,
                        onTap: () => playback.skipToPrevious()),
                      const SizedBox(width: 4),
                      WinampButton(icon: isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 32, active: isPlaying,
                        onTap: () => isPlaying ? playback.pause() : playback.play()),
                      const SizedBox(width: 4),
                      WinampButton(icon: Icons.stop, size: 28,
                        onTap: () => playback.stop()),
                      const SizedBox(width: 4),
                      WinampButton(icon: Icons.skip_next, size: 28,
                        onTap: () => playback.skipToNext()),
                    ]),
                    Row(children: [
                      _WinampToggleButton(label: 'SHF', active: shuffle,
                        onTap: () => playback.setShuffle(!shuffle)),
                      const SizedBox(width: 3),
                      _WinampToggleButton(
                        label: repeatMode == RepeatMode.one ? 'R1' : 'REP',
                        active: repeatMode != RepeatMode.off,
                        onTap: () {
                          final next = switch (repeatMode) {
                            RepeatMode.off => RepeatMode.all,
                            RepeatMode.all => RepeatMode.one,
                            RepeatMode.one => RepeatMode.off,
                          };
                          playback.setRepeatMode(next);
                        }),
                    ]),
                  ],
                ),
              ),
            ]),
          ),

          // ==================== EQ PANEL (toggles) ====================
          if (_eqPanel)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: WinampColors.bgPanel,
                border: Border.all(color: WinampColors.metalDark, width: 1),
              ),
              child: Column(children: [
                // EQ title bar
                Container(
                  height: 20,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [WinampColors.titleBarStart, WinampColors.titleBarEnd])),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('\u042D\u041A\u0412\u0410\u041B\u0410\u0419\u0417\u0415\u0420',
                        style: lcdStyle(size: 12, color: Colors.white)),
                      _WinampToggleButton(
                        label: 'ON',
                        active: _eqEnabled,
                        onTap: _onEqToggle),
                    ],
                  ),
                ),
                // EQ sliders: 5 bands with REAL frequencies
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: WinampColors.lcdBg,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(kEqBandCount, (i) {
                      final freq = kEqBandFreqs[i];
                      final label = freq >= 1000
                        ? '${(freq / 1000).toStringAsFixed(freq % 1000 == 0 ? 0 : 1)}k'
                        : freq.toStringAsFixed(0);
                      return _WinampVSlider(
                        label: label,
                        value: _eqBands[i],
                        range: 15.0,
                        onChanged: (v) => _onEqBandChanged(i, v),
                      );
                    }),
                  ),
                ),
              ]),
            ),

          // ==================== PLAYLIST ====================
          if (_plPanel)
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
                decoration: BoxDecoration(
                  color: WinampColors.bgPanel,
                  border: Border.all(color: WinampColors.metalDark, width: 1)),
                child: Column(children: [
                  Container(
                    height: 20,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [WinampColors.titleBarStart, WinampColors.titleBarEnd])),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('\u041F\u0410\u0422\u0415\u0424\u041E\u041D \u0421\u041F\u0418\u0421\u041E\u041A',
                          style: lcdStyle(size: 12, color: Colors.white)),
                        Text('${queue.length} tracks  ${_formatTotal(queue)}',
                          style: lcdStyle(size: 10, color: Colors.white70)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      color: WinampColors.lcdBg,
                      child: ListView.builder(
                        controller: _playlistScrollController,
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        itemCount: queue.length, itemExtent: 18,
                        itemBuilder: (_, i) {
                          final t = queue[i];
                          final isCurrent = i == currentIndex;
                          final dur = t.durationMs > 0
                            ? formatDuration(Duration(milliseconds: t.durationMs)) : '';
                          return GestureDetector(
                            onTap: () => playback.playQueue(tracks: queue, startIndex: i),
                            child: Container(
                              color: isCurrent ? WinampColors.lcdText.withOpacity(0.08) : Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Row(children: [
                                SizedBox(width: 20, child: Text('${(i + 1).toString().padLeft(2, '0')}',
                                  style: lcdStyle(size: 11,
                                    color: isCurrent ? WinampColors.lcdText : WinampColors.textMuted))),
                                Expanded(child: Text(
                                  t.artist.isNotEmpty ? '${t.artist} - ${t.title}' : t.title,
                                  style: lcdStyle(size: 11,
                                    color: isCurrent ? WinampColors.lcdText : WinampColors.textSecondary),
                                  maxLines: 1, overflow: TextOverflow.ellipsis)),
                                if (dur.isNotEmpty)
                                  Text(dur, style: lcdStyle(size: 11, color: WinampColors.textMuted)),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  // Action bar
                  Container(
                    height: 20,
                    decoration: BoxDecoration(
                      color: WinampColors.bgPanel,
                      border: Border(top: BorderSide(color: WinampColors.metalDark, width: 1))),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _WinampActionButton(label: 'ADD', onTap: _addTracks),
                        _WinampActionButton(label: 'SHR', onTap: _shareCurrentTrack),
                        _WinampActionButton(label: 'MISC', onTap: () => widget.onExit?.call()),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

// ==================== WIDGETS ====================

class _WinampHSlider extends StatelessWidget {
  const _WinampHSlider({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final seg = 20;
      final filled = (value * seg).round();
      return GestureDetector(
        onTapDown: (d) => onChanged(
            (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0)),
        onHorizontalDragUpdate: (d) => onChanged(
            (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0)),
        child: Container(
          height: 8,
          decoration: BoxDecoration(
            color: WinampColors.lcdBg,
            border: Border.all(color: WinampColors.metalDark, width: 1),
          ),
          child: Row(
            children: List.generate(seg, (i) {
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 0.5, vertical: 1),
                  color: i < filled
                      ? WinampColors.lcdText
                      : WinampColors.lcdDim,
                ),
              );
            }),
          ),
        ),
      );
    });
  }
}

class _WinampVSlider extends StatelessWidget {
  const _WinampVSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.range = 15.0,
  });
  final String label;
  final double value; // -range to +range dB
  final ValueChanged<double> onChanged;
  final double range;

  @override
  Widget build(BuildContext context) {
    final normalized = (value + range) / (range * 2);
    final seg = 14;
    final filled = (normalized * seg).round();
    final centerSeg = seg ~/ 2;
    return GestureDetector(
      onTapDown: (d) {
        final box = context.findRenderObject() as RenderBox;
        final local = box.globalToLocal(d.globalPosition);
        final h = box.size.height.clamp(1.0, double.infinity);
        final norm = 1.0 - (local.dy / h).clamp(0.0, 1.0);
        onChanged((norm * range * 2 - range).clamp(-range, range));
      },
      onVerticalDragUpdate: (d) {
        final box = context.findRenderObject() as RenderBox;
        final local = box.globalToLocal(d.globalPosition);
        final h = box.size.height.clamp(1.0, double.infinity);
        final norm = 1.0 - (local.dy / h).clamp(0.0, 1.0);
        onChanged((norm * range * 2 - range).clamp(-range, range));
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // LED segments (vertical)
          Container(
            width: 12, height: 56,
            decoration: BoxDecoration(
              color: WinampColors.lcdBg,
              border: Border.all(color: WinampColors.metalDark, width: 1)),
            child: Column(
              children: List.generate(seg, (i) {
                // i=0 is top (+12dB), i=seg-1 is bottom (-12dB)
                final isFilled = i < filled;
                final isCenter = i == centerSeg;
                return Expanded(child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 0.5, horizontal: 1),
                  color: isFilled
                    ? WinampColors.lcdText
                    : (isCenter ? WinampColors.lcdDim.withGreen(0x80) : WinampColors.lcdDim),
                ));
              }).reversed.toList(), // reversed so top = high
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: lcdStyle(size: 10, color: WinampColors.textMuted)),
        ],
      ),
    );
  }
}

class _WinampToggleButton extends StatelessWidget {
  const _WinampToggleButton({required this.label, required this.active, required this.onTap});
  final String label; final bool active; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 16,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: active ? Alignment.bottomCenter : Alignment.topCenter,
            end: active ? Alignment.topCenter : Alignment.bottomCenter,
            colors: [WinampColors.metalLight, WinampColors.metalMid, WinampColors.metalDark]),
          border: Border.all(color: WinampColors.metalDarker, width: 1)),
        child: Center(child: Text(label,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
            color: active ? WinampColors.lcdText : WinampColors.metalDarker,
            fontFamily: 'monospace'))),
      ),
    );
  }
}

class _WinampActionButton extends StatelessWidget {
  const _WinampActionButton({required this.label, required this.onTap});
  final String label; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [WinampColors.metalLight, WinampColors.metalMid, WinampColors.metalDark]),
          border: Border.all(color: WinampColors.metalDarker, width: 1)),
        child: Text(label,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
            color: WinampColors.metalDarker, fontFamily: 'monospace')),
      ),
    );
  }
}

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
      canvas.drawRect(Rect.fromLTWH(i * barW + 0.5, size.height - h, barW - 1, h), paint);
    }
  }
  @override
  bool shouldRepaint(_) => true;
}
