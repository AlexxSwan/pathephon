// ============================================================================
//  now_playing_screen.dart - Now Playing with spectrum + FIXED artwork loading
//
//  CRITICAL FIX: Image.network cannot load file:// URIs. Use Image.file
//  for local files, Image.network for http(s):// only.
// ============================================================================
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/spectrum_painter.dart';
import '../../core/theme/tube_colors.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/models/track.dart';
import '../providers/providers.dart';
import '../widgets/playback_controls.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.power_settings_new),
                    tooltip: '\u0412\u044B\u0445\u043E\u0434',
                    onPressed: () => _showExitDialog(context),
                  ),
                  Text(
                    l.nowPlayingTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 48),
                ],
              ),

              const SizedBox(height: 8),

              Expanded(
                flex: 3,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: TubeColors.brass, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: TubeColors.amberHot.withOpacity(0.25),
                            blurRadius: 30,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: _ArtworkImage(track: track),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Text(
                track?.title ?? '\u2014',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                [track?.artist, track?.album].whereType<String>().join(' \u00B7 '),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TubeColors.textSecondary,
                    ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 8),

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

              const SizedBox(height: 8),

              const PlaybackControls(),

              const SizedBox(height: 12),

              Expanded(
                flex: 2,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0805),
                    border: Border.all(color: TubeColors.brass.withOpacity(0.5), width: 1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ClipRect(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: SpectrumPainter(bins: bins, brightness: brightness),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showExitDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1410),
        title: Text(
          '\u0412\u044B\u0439\u0442\u0438 \u0438\u0437 \u043F\u0440\u0438\u043B\u043E\u0436\u0435\u043D\u0438\u044F?',
          style: const TextStyle(color: Color(0xFFF4E9D2), fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('\u041E\u0442\u043C\u0435\u043D\u0430',
                style: TextStyle(color: Color(0xFFB89968))),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              SystemNavigator.pop();
            },
            child: const Text('\u0412\u044B\u0439\u0442\u0438',
                style: TextStyle(color: Color(0xFFFF6B1A))),
          ),
        ],
      ),
    );
  }
}

/// Artwork widget - CRITICAL: uses Image.file for file:// URIs, Image.network for http(s).
class _ArtworkImage extends ConsumerWidget {
  const _ArtworkImage({required this.track});
  final Track? track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = track;
    if (t == null) return _appIconFallback();

    // Resolve artUri: track's own, or album fallback
    String? artUri = t.artUri;
    if (artUri.isEmpty) {
      artUri = ref.watch(albumArtIndexProvider)[
          '${t.albumArtist.isEmpty ? t.artist : t.albumArtist}||${t.album}'];
    }

    if (artUri != null && artUri.isNotEmpty) {
      // file:// URI -> use Image.file
      if (artUri.startsWith('file://')) {
        final filePath = Uri.parse(artUri).toFilePath();
        return Image.file(
          File(filePath),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _appIconFallback(),
        );
      }
      // content:// URI -> use Image.network (Flutter can load content URIs this way on Android)
      if (artUri.startsWith('content://')) {
        return Image.network(
          artUri,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _appIconFallback(),
        );
      }
      // http(s):// URI -> Image.network
      if (artUri.startsWith('http://') || artUri.startsWith('https://')) {
        return Image.network(
          artUri,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _appIconFallback(),
        );
      }
    }

    return _appIconFallback();
  }

  Widget _appIconFallback() {
    return Container(
      color: TubeColors.surfaceVariant,
      alignment: Alignment.center,
      child: Image.asset(
        'assets/app_icon.png',
        fit: BoxFit.contain,
        width: 100,
        height: 100,
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.album,
          size: 100,
          color: TubeColors.brass,
        ),
      ),
    );
  }
}