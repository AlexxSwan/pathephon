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
    final playback = ref.watch(playbackServiceProvider);
    final track = snap?.current;
    final duration = snap?.duration ?? Duration.zero;
    final isPlaying = snap?.isPlaying ?? false;

    return PopScope(
      canPop: true,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
                    Text(l.nowPlayingTitle, style: Theme.of(context).textTheme.titleMedium),
                    IconButton(icon: const Icon(Icons.queue_music), onPressed: () {}),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  flex: 4,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(border: Border.all(color: TubeColors.brass, width: 3)),
                        child: track == null || track.artUri.isEmpty
                          ? const Icon(Icons.album, size: 120, color: TubeColors.brass)
                          : Image.network(track.artUri, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.album, size: 120, color: TubeColors.brass)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const VUMeter(size: 220),
                const SizedBox(height: 8),
                Text(track?.title ?? "—", style: Theme.of(context).textTheme.displaySmall, textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text([track?.artist, track?.album].whereType<String>().join(" · "), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: TubeColors.textSecondary), textAlign: TextAlign.center),
                const SizedBox(height: 16),
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
                PlaybackControls(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}