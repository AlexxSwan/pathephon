// ============================================================================
//  playback_controls.dart — Play/Pause/Next/Prev/Shuffle/Repeat cluster
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tube_colors.dart';
import '../../domain/enums/repeat_mode.dart' as app;
import '../providers/providers.dart';
import 'retro_button.dart';

class PlaybackControls extends ConsumerWidget {
  const PlaybackControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(playbackSnapshotProvider).valueOrNull;
    final isPlaying = snap?.isPlaying ?? false;
    final shuffle = ref.watch(shuffleProvider);
    final repeat = ref.watch(repeatModeProvider);
    final playback = ref.watch(playbackServiceProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        RetroButton(
          icon: Icons.shuffle_rounded,
          active: shuffle,
          onPressed: () {
            final next = !shuffle;
            ref.read(shuffleProvider.notifier).state = next;
            playback.setShuffle(next);
          },
        ),
        RetroButton(
          icon: Icons.skip_previous_rounded,
          size: 56,
          onPressed: () => playback.skipToPrevious(),
        ),
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: TubeColors.brass, width: 2),
            boxShadow: isPlaying
                ? [
                    BoxShadow(
                      color: TubeColors.amberHot.withOpacity(0.5),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ]
                : [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => isPlaying ? playback.pause() : playback.play(),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 48,
                color: TubeColors.amberHot,
              ),
            ),
          ),
        ),
        RetroButton(
          icon: Icons.skip_next_rounded,
          size: 56,
          onPressed: () => playback.skipToNext(),
        ),
        RetroButton(
          icon: switch (repeat) {
            app.RepeatMode.off => Icons.repeat_rounded,
            app.RepeatMode.all => Icons.repeat_rounded,
            app.RepeatMode.one => Icons.repeat_one_rounded,
          },
          active: repeat != app.RepeatMode.off,
          onPressed: () {
            final next = repeat.next;
            ref.read(repeatModeProvider.notifier).state = next;
            playback.setRepeatMode(next);
          },
        ),
      ],
    );
  }
}
