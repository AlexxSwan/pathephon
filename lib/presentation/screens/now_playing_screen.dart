// ============================================================================
//  now_playing_screen.dart — full-screen now-playing with VU meter, art, controls
//  - No back arrow: this is the FIRST tab in IndexedStack, not a pushed route.
//  - VU meter drawn via CustomPaint + VUPainter directly (no extra widget layer).
//  - isPlaying comes from isPlayingProvider for instant toggle.
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tube_colors.dart';
import '../../core/theme/vu_painter.dart';
import '../../core/utils/duration_format.dart';
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
    // Watch isPlayingProvider so the screen rebuilds the moment user taps a track.
    ref.watch(isPlayingProvider);

    final track = snap?.current;
    final duration = snap?.duration ?? Duration.zero;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              // ---- Top bar (no back arrow — this is a tab, not a route) ----
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Empty leading slot keeps title centered.
                  const SizedBox(width: 48),
                  Text(
                    l.nowPlayingTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.queue_music),
                    onPressed: () {/* TODO: queue sheet */},
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ---- Album art (large) ----
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
                      child: track == null || track.artUri.isEmpty
                          ? const Icon(Icons.album, size: 120, color: TubeColors.brass)
                          : Image.network(track.artUri, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ---- VU meter (direct CustomPaint, no extra widget) ----
              CustomPaint(
                size: const Size(220, 154),
                painter: VUPainter(amplitude: amp, brightness: amp > 0.05 ? 1.0 : 0.0),
              ),

              const SizedBox(height: 8),

              // ---- Track info ----
              Text(
                track?.title ?? '—',
                style: Theme.of(context).textTheme.displaySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                [track?.artist, track?.album].whereType<String>().join(' \u00B7 '), // middot
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

              // ---- Seek bar (uses inMilliseconds directly) ----
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

              // ---- Controls ----
              const PlaybackControls(),
            ],
          ),
        ),
      ),
    );
  }
}
