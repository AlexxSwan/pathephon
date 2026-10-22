// ============================================================================
//  now_playing_screen.dart — full-screen now-playing with VU meter, art, controls
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tube_colors.dart';
import '../../core/utils/duration_format.dart';
import '../providers/providers.dart';
import '../widgets/playback_controls.dart';
import '../widgets/vu_meter.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final snap = ref.watch(playbackSnapshotProvider).valueOrNull;
    final pos = ref.watch(playbackPositionProvider).valueOrNull ?? Duration.zero;
    final playback = ref.watch(playbackServiceProvider);

    final track = snap?.current;
    final duration = snap?.duration ?? Duration.zero;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              // ---- Top bar ----
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
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

              // ---- VU meter ----
              const VUMeter(size: 220),

              const SizedBox(height: 8),

              // ---- Track info ----
              Text(
                track?.title ?? '—',
                style: Theme.of(context).textTheme.displaySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                [track?.artist, track?.album].whereType<String>().join(' · '),
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

              // ---- Seek bar ----
              Row(
                children: [
                  Text(formatDuration(pos), style: Theme.of(context).textTheme.labelSmall),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: duration.inMs.toDouble(),
                      value: pos.inMs.toDouble().clamp(0, duration.inMs.toDouble()),
                      onChanged: (v) => playback.seekTo(Duration(milliseconds: v.toInt())),
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

extension on Duration {
  int get inMs => inMilliseconds;
}
