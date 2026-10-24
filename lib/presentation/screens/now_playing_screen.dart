// ============================================================================
//  now_playing_screen.dart - Now Playing with spectrum/playlist toggle
//
//  Top bar: centered title | toggle button (spectrum <-> playlist) on right.
//  No power button - back button handles exit (via PopScope in app.dart).
//
//  Bottom area toggles between:
//    - Spectrum bars (FFT visualizer)
//    - Playlist (current track highlighted)
// ============================================================================
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/spectrum_painter.dart';
import '../../core/theme/tube_colors.dart';
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
  bool _showPlaylist = false;

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
    final spectrum = ref.watch(spectrumProvider).valueOrNull;
    final playback = ref.watch(playbackServiceProvider);
    ref.watch(isPlayingProvider);

    final track = snap?.current;
    final queue = snap?.queue ?? const <Track>[];
    final currentIndex = snap?.index ?? 0;
    final duration = snap?.duration ?? Duration.zero;
    final bins = spectrum?.bins ?? const <double>[];
    final isPlaying = snap?.isPlaying ?? false;
    final brightness = isPlaying ? 1.0 : 0.0;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              // ---- Top bar: title centered + toggle button right ----
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 48),
                  Text(l.nowPlayingTitle, style: Theme.of(context).textTheme.titleMedium),
                  IconButton(
                    icon: Icon(_showPlaylist ? Icons.graphic_eq : Icons.queue_music),
                    tooltip: _showPlaylist
                        ? '\u0410\u043D\u0430\u043B\u0438\u0437\u0430\u0442\u043E\u0440'
                        : '\u041E\u0447\u0435\u0440\u0435\u0434\u044C',
                    onPressed: () => setState(() => _showPlaylist = !_showPlaylist),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ---- Album art (flex 3) ----
              Expanded(
                flex: 3,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: TubeColors.brass, width: 3),
                        boxShadow: [BoxShadow(color: TubeColors.amberHot.withOpacity(0.25), blurRadius: 30, spreadRadius: 4)],
                      ),
                      child: _ArtworkImage(track: track),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ---- Track title + artist ----
              Text(track?.title ?? '\u2014', style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text([track?.artist, track?.album].whereType<String>().join(' \u00B7 '),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: TubeColors.textSecondary),
                  textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),

              const SizedBox(height: 8),

              // ---- Seek bar ----
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

              // ---- Controls ----
              const PlaybackControls(),

              const SizedBox(height: 12),

              // ---- Bottom area: toggle between spectrum and playlist ----
              Expanded(
                flex: 2,
                child: _showPlaylist
                    ? _buildPlaylist(queue, currentIndex, playback)
                    : _buildSpectrum(bins, brightness),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpectrum(List<double> bins, double brightness) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0805),
        border: Border.all(color: TubeColors.brass.withOpacity(0.5), width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRect(
        child: CustomPaint(size: Size.infinite, painter: SpectrumPainter(bins: bins, brightness: brightness)),
      ),
    );
  }

  Widget _buildPlaylist(List<Track> queue, int currentIndex, PlaybackService playback) {
    if (queue.isEmpty) {
      return Center(child: Text('\u041E\u0447\u0435\u0440\u0435\u0434\u044C \u043F\u0443\u0441\u0442\u0430',
          style: const TextStyle(color: TubeColors.textMuted)));
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1410),
        border: Border.all(color: TubeColors.brass.withOpacity(0.3), width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: queue.length,
        itemExtent: 44,
        itemBuilder: (_, i) {
          final t = queue[i];
          final isCurrent = i == currentIndex;
          return InkWell(
            onTap: () => playback.playQueue(tracks: queue, startIndex: i),
            child: Container(
              color: isCurrent ? TubeColors.amberHot.withOpacity(0.15) : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(children: [
                SizedBox(width: 28, child: isCurrent
                    ? const Icon(Icons.play_arrow, size: 20, color: TubeColors.amberHot)
                    : Text('${i + 1}', style: const TextStyle(color: TubeColors.textMuted, fontSize: 13), textAlign: TextAlign.center)),
                const SizedBox(width: 8),
                Expanded(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: isCurrent ? TubeColors.amberHot : TubeColors.textPrimary,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, fontSize: 14, height: 1.15)),
                    if (t.artist.isNotEmpty)
                      Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: TubeColors.textSecondary, fontSize: 11, height: 1.15)),
                  ],
                )),
                const SizedBox(width: 8),
                if (t.durationMs > 0)
                  Text(formatDuration(Duration(milliseconds: t.durationMs)),
                      style: const TextStyle(color: TubeColors.textMuted, fontSize: 11)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// Artwork: tries cached bytes first, then file/network, then icon.
class _ArtworkImage extends ConsumerWidget {
  const _ArtworkImage({required this.track});
  final Track? track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = track;
    if (t == null) return _appIconFallback();

    String? artUri = t.artUri;
    if (artUri.isEmpty) {
      artUri = ref.watch(albumArtIndexProvider)['${t.albumArtist.isEmpty ? t.artist : t.albumArtist}||${t.album}'];
    }

    if (artUri != null && artUri.isNotEmpty) {
      final ms = ref.read(mediaStoreSourceProvider);
      final cachedBytes = ms.getCoverBytes(artUri);
      if (cachedBytes != null) {
        return Image.memory(cachedBytes, fit: BoxFit.cover, errorBuilder: (_, e, __) => _appIconFallback());
      }
      if (artUri.startsWith('file://')) {
        return Image.file(File(Uri.parse(artUri).toFilePath()), fit: BoxFit.cover, errorBuilder: (_, e, __) => _appIconFallback());
      }
      return Image.network(artUri, fit: BoxFit.cover, errorBuilder: (_, e, __) => _appIconFallback());
    }
    return _appIconFallback();
  }

  Widget _appIconFallback() {
    return Container(
      color: TubeColors.surfaceVariant,
      alignment: Alignment.center,
      child: Image.asset('assets/app_icon.png', fit: BoxFit.contain, width: 100, height: 100,
          errorBuilder: (_, e, __) => const Icon(Icons.album, size: 100, color: TubeColors.brass)),
    );
  }
}