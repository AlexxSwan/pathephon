// ============================================================================
//  track_list_tile.dart — list row for a Track with VU mini-indicator
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tube_colors.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/models/track.dart';
import '../providers/providers.dart';

class TrackListTile extends ConsumerWidget {
  const TrackListTile({
    super.key,
    required this.track,
    required this.index,
    required this.onTap,
  });

  final Track track;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(playbackSnapshotProvider).valueOrNull;
    final isCurrent = snapshot?.current?.id == track.id;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Track number OR playing indicator
            SizedBox(
              width: 32,
              child: isCurrent
                  ? _PlayingDots()
                  : Text(
                      (track.trackNumber > 0 ? track.trackNumber : index + 1)
                          .toString()
                          .padLeft(2, '0'),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
            ),

            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: isCurrent ? TubeColors.amber : TubeColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (track.artist.isNotEmpty) track.artist,
                      if (track.album.isNotEmpty) track.album,
                      if (track.isHiRes) track.qualityLabel,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TubeColors.textMuted,
                        ),
                  ),
                ],
              ),
            ),

            // Duration + RG indicator
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatDuration(Duration(milliseconds: track.durationMs)),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if (track.replayGainTrack != null)
                  Text(
                    'RG',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: TubeColors.phosphorGreen,
                          fontSize: 9,
                        ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayingDots extends StatefulWidget {
  @override
  State<_PlayingDots> createState() => _PlayingDotsState();
}

class _PlayingDotsState extends State<_PlayingDots> with TickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final phase = (_c.value * 3).floor() % 3;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final on = i == phase;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color: TubeColors.amberHot.withOpacity(on ? 1 : 0.3),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
