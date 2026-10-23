// ============================================================================
//  now_playing_screen.dart - full-screen now-playing with VU meter, art, controls
// ============================================================================
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tube_colors.dart';
import '../../core/theme/vu_painter.dart';
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
    final amp = ref.watch(amplitudeProvider).valueOrNull ?? 0.0;
    final playback = ref.watch(playbackServiceProvider);
    ref.watch(isPlayingProvider);

    final track = snap?.current;
    final duration = snap?.duration ?? Duration.zero;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 48),
                  Text(
                    l.nowPlayingTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.queue_music),
                    onPressed: () {},
                  ),
                ],
              ),

              const SizedBox(height: 16),

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

              const SizedBox(height: 16),

              CustomPaint(
                size: const Size(220, 154),
                painter: VUPainter(amplitude: amp, brightness: amp > 0.05 ? 1.0 : 0.0),
              ),

              const SizedBox(height: 8),

              Text(
                track?.title ?? '\u2014',
                style: Theme.of(context).textTheme.displaySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                [track?.artist, track?.album].whereType<String>().join(' \u00B7 '),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TubeColors.textSecondary,
                    ),
                textAlign: TextAlign.center,
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

              const SizedBox(height: 16),

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

              const SizedBox(height: 16),

              const PlaybackControls(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtworkImage extends ConsumerStatefulWidget {
  const _ArtworkImage({required this.track});
  final Track? track;

  @override
  ConsumerState<_ArtworkImage> createState() => _ArtworkImageState();
}

class _ArtworkImageState extends ConsumerState<_ArtworkImage> {
  Uint8List? _bytes;
  int? _loadingId;

  @override
  void didUpdateWidget(_ArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final t = widget.track;
    if (t == null) {
      _bytes = null;
      _loadingId = null;
      return;
    }
    if (t.mediaStoreId != null && t.mediaStoreId != _loadingId) {
      _loadingId = t.mediaStoreId;
      _bytes = null;
      _fetchArt(t.mediaStoreId!);
    } else if (t.mediaStoreId == null) {
      _bytes = null;
      _loadingId = null;
    }
  }

  Future<void> _fetchArt(int id) async {
    try {
      final ms = ref.read(mediaStoreSourceProvider);
      final bytes = await ms.query.queryArtwork(id, ArtworkType.AUDIO, size: 600);
      if (mounted && _loadingId == id) {
        setState(() => _bytes = bytes);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    if (t == null) {
      return const Icon(Icons.album, size: 120, color: TubeColors.brass);
    }
    if (t.artUri.isNotEmpty) {
      return Image.network(t.artUri, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
          const Icon(Icons.album, size: 120, color: TubeColors.brass));
    }
    if (_bytes != null) {
      return Image.memory(_bytes!, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
          const Icon(Icons.album, size: 120, color: TubeColors.brass));
    }
    if (t.mediaStoreId != null) {
      return const Center(
        child: SizedBox(width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: TubeColors.brass)));
    }
    return const Icon(Icons.album, size: 120, color: TubeColors.brass);
  }
}