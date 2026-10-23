import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../core/l10n/generated/app_localizations.dart";
import "../../core/theme/tube_colors.dart";
import "../../core/utils/duration_format.dart";
import "../providers/providers.dart";
import "../widgets/playback_controls.dart";
import "../widgets/vu_meter.dart";

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});
  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final snap = ref.watch(playbackSnapshotProvider).valueOrNull;
    final pos = ref.watch(playbackPositionProvider).valueOrNull ?? Duration.zero;
    final amp = ref.watch(amplitudeProvider).valueOrNull ?? 0.0;
    final playback = ref.watch(playbackServiceProvider);
    final track = snap?.current;
    final duration = snap?.duration ?? Duration.zero;
    final isPlaying = ref.watch(isPlayingProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              // Title bar
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(l.nowPlayingTitle, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 16),

              // Album art
              Expanded(
                flex: 3,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: TubeColors.brass, width: 3),
                        boxShadow: isPlaying ? [
                          BoxShadow(color: TubeColors.amberHot.withOpacity(0.25), blurRadius: 40, spreadRadius: 6)
                        ] : [],
                      ),
                      child: track == null || track.artUri.isEmpty
                        ? const Icon(Icons.album, size: 120, color: TubeColors.brass)
                        : Image.network(track.artUri, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.album, size: 120, color: TubeColors.brass)),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // VU meter with direct amplitude value
              CustomPaint(
                size: Size(220, 154),
                painter: VUPainter(amplitude: amp, brightness: isPlaying ? 1.0 : 0.0),
              ),

              const SizedBox(height: 8),

              // Track info
              Text(
                track?.title ?? "\u2014",
                style: Theme.of(context).textTheme.displaySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                [track?.artist, track?.album].whereType<String>().join(" \u00B7 "),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: TubeColors.textSecondary),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Seek bar
              Row(
                children: [
                  Text(formatDuration(pos), style: Theme.of(context).textTheme.labelSmall),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                      value: pos.inMilliseconds.toDouble().clamp(0, duration.inMilliseconds.toDouble()),
                      onChanged: duration.inMilliseconds > 0 ? (v) => playback.seekTo(Duration(milliseconds: v.toInt())) : null,
                    ),
                  ),
                  Text(formatDuration(duration), style: Theme.of(context).textTheme.labelSmall),
                ],
              ),

              const SizedBox(height: 16),

              // Controls
              const PlaybackControls(),
            ],
          ),
        ),
      ),
    );
  }
}