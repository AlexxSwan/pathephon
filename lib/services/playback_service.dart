// ============================================================================
//  playback_service.dart - REAL playback via just_audio + audio_service
// ============================================================================
import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_audio/just_audio.dart';

import '../core/utils/replaygain.dart';
import '../domain/enums/repeat_mode.dart';
import '../domain/models/track.dart';

abstract class PlaybackService {
  Stream<PlaybackSnapshot> get state;
  Stream<Duration> get positionStream;
  Stream<double> get amplitudeStream;

  Future<void> playQueue({required List<Track> tracks, required int startIndex});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seekTo(Duration position);
  Future<void> skipToNext();
  Future<void> skipToPrevious();
  Future<void> setShuffle(bool enabled);
  Future<void> setRepeatMode(RepeatMode mode);
  Future<void> setVolume(double volume);
  Future<void> setSpeed(double speed);
  Future<void> setReplayGain(ReplayGainMode mode);
  Future<void> setEqualizerBands(List<double> gainsDb, {required bool enabled});
}

class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.current,
    required this.queue,
    required this.index,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.isBuffering,
    required this.shuffle,
    required this.repeatMode,
    required this.replayGainMode,
  });

  final Track? current;
  final List<Track> queue;
  final int index;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isBuffering;
  final bool shuffle;
  final RepeatMode repeatMode;
  final ReplayGainMode replayGainMode;

  static PlaybackSnapshot empty = PlaybackSnapshot(
    current: null,
    queue: const [],
    index: 0,
    position: Duration.zero,
    duration: Duration.zero,
    isPlaying: false,
    isBuffering: false,
    shuffle: false,
    repeatMode: RepeatMode.off,
    replayGainMode: ReplayGainMode.off,
  );
}

class JustAudioPlaybackService implements PlaybackService {
  JustAudioPlaybackService() {
    _init();
  }

  final _player = AudioPlayer();
  AudioHandler? _handler;

  final _initCompleter = Completer<void>();

  List<Track> _queue = const [];
  int _index = 0;
  bool _shuffle = false;
  RepeatMode _repeat = RepeatMode.off;
  ReplayGainMode _rg = ReplayGainMode.off;

  final _stateController = StreamController<PlaybackSnapshot>.broadcast();
  final _ampController = StreamController<double>.broadcast();

  Timer? _ampTimer;
  double _ampPhase = 0;
  double _ampSmoothed = 0;

  @override
  Stream<PlaybackSnapshot> get state => _stateController.stream;
  @override
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Stream<double> get amplitudeStream => _ampController.stream;

  Future<void> _init() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (e) {
      debugPrint('[pathephon] AudioSession configure failed (non-fatal): $e');
    }

    try {
      _handler = await AudioService.init(
        builder: () => _PathephonAudioHandler(_player),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'pathephon_playback',
          androidNotificationChannelName: 'Playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (e) {
      debugPrint('[pathephon] AudioService.init failed (non-fatal): $e');
    }

    _stateController.add(PlaybackSnapshot.empty);

    _player.playerStateStream.listen((st) {
      _emitState(st);
      _startAmplitudeLoopIfPlaying(st.playing);
    });

    _player.sequenceStateStream.listen((seqState) {
      if (seqState != null && seqState.currentIndex >= 0) {
        _index = seqState.currentIndex;
        _emitState(_player.playerState);
      }
    });

    Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_queue.isNotEmpty) {
        _emitState(_player.playerState);
      }
    });

    _initCompleter.complete();
  }

  void _emitState(PlayerState st) {
    final currentIndex = _player.currentIndex ?? _index;
    _index = currentIndex;
    _stateController.add(PlaybackSnapshot(
      current: _queue.isEmpty ? null : _queue[currentIndex.clamp(0, _queue.length - 1)],
      queue: _queue,
      index: currentIndex,
      position: _player.position,
      duration: _player.duration ?? Duration.zero,
      isPlaying: st.playing,
      isBuffering: st.processingState == ProcessingState.loading ||
          st.processingState == ProcessingState.buffering,
      shuffle: _shuffle,
      repeatMode: _repeat,
      replayGainMode: _rg,
    ));
  }

  /// Simulated VU needle amplitude.
  ///
  /// Output range: 0.05..0.55 (LINEAR, mapped directly by VUPainter).
  /// With VUPainter using linear mapping:
  ///   0.55 -> ~55% of the arc -> stays in the yellow zone (BEFORE red)
  ///   0.30 -> ~30% of the arc -> middle green
  ///
  /// Exponential smoothing makes the needle swing naturally without jitter.
  void _startAmplitudeLoopIfPlaying(bool playing) {
    if (playing) {
      _ampTimer ??= Timer.periodic(const Duration(milliseconds: 50), (_) {
        _ampPhase += 0.10;
        // Two slow sine waves around 0.30 with swing +/- 0.20
        final target = 0.30 + 0.20 * _sinSum(_ampPhase);
        // Exponential smoothing toward target (slow attack, slow release)
        _ampSmoothed += (target - _ampSmoothed) * 0.15;
        // Small noise for organic feel
        final noise = 0.02 * (DateTime.now().microsecondsSinceEpoch % 100) / 100;
        final amp = (_ampSmoothed + noise).clamp(0.05, 0.55);
        _ampController.add(amp);
      });
    } else {
      _ampTimer?.cancel();
      _ampTimer = null;
      // Smoothly return to 0
      _ampSmoothed = 0;
      _ampController.add(0);
    }
  }

  double _sinSum(double t) =>
      0.5 * (1 + math.sin(t * 0.6) + 0.5 * math.sin(t * 1.7)) / 2;

  @override
  Future<void> playQueue({required List<Track> tracks, required int startIndex}) async {
    await _initCompleter.future;

    if (tracks.isEmpty) {
      debugPrint('[pathephon] playQueue: empty tracks list');
      return;
    }
    _queue = List.unmodifiable(tracks);
    _index = startIndex.clamp(0, tracks.length - 1);

    final sources = tracks.map(_toSource).toList(growable: false);
    final initial = startIndex.clamp(0, sources.length - 1);

    try {
      await _player.setAudioSource(
        ConcatenatingAudioSource(
          children: sources,
          useLazyPreparation: true,
        ),
        initialPosition: Duration.zero,
        initialIndex: initial,
      );

      await _player.seek(Duration.zero, index: initial);
      await _player.play();
      debugPrint('[pathephon] playQueue: playing "${tracks[initial].title}"');
    } catch (e, st) {
      debugPrint('[pathephon] playQueue FAILED: $e\n$st');
      _stateController.add(PlaybackSnapshot.empty);
      rethrow;
    }
  }

  AudioSource _toSource(Track t) {
    Uri uri;
    if (t.uri.startsWith('file://') || t.uri.startsWith('content://') ||
        t.uri.startsWith('http://') || t.uri.startsWith('https://')) {
      uri = Uri.parse(t.uri);
    } else if (t.filePath.isNotEmpty) {
      uri = Uri.file(t.filePath);
    } else {
      uri = Uri.parse(t.uri);
    }
    return AudioSource.uri(
      uri,
      tag: MediaItem(
        id: t.id,
        album: t.album,
        title: t.title,
        artist: t.artist,
        duration: Duration(milliseconds: t.durationMs),
        artUri: t.artUri.isEmpty ? null : Uri.parse(t.artUri),
      ),
    );
  }

  @override
  Future<void> play() async {
    await _initCompleter.future;
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _initCompleter.future;
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    await _initCompleter.future;
    await _player.stop();
    await _handler?.stop();
    _queue = const [];
    _index = 0;
    _stateController.add(PlaybackSnapshot.empty);
  }

  @override
  Future<void> seekTo(Duration position) async {
    await _initCompleter.future;
    await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    await _initCompleter.future;
    if (_queue.isEmpty) return;
    if (_player.hasNext) {
      await _player.seekToNext();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    await _initCompleter.future;
    if (_queue.isEmpty) return;
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> setShuffle(bool enabled) async {
    await _initCompleter.future;
    _shuffle = enabled;
    await _player.setShuffleModeEnabled(enabled);
  }

  @override
  Future<void> setRepeatMode(RepeatMode mode) async {
    await _initCompleter.future;
    _repeat = mode;
    final am = switch (mode) {
      RepeatMode.off => LoopMode.off,
      RepeatMode.all => LoopMode.all,
      RepeatMode.one => LoopMode.one,
    };
    await _player.setLoopMode(am);
  }

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume.clamp(0.0, 1.0));

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed.clamp(0.5, 3.0));

  @override
  Future<void> setReplayGain(ReplayGainMode mode) async {
    _rg = mode;
    if (_queue.isEmpty) return;
    final current = _queue[_index];
    final volume = ReplayGainApplier.selectGain(
      trackGain: current.replayGainTrack,
      albumGain: current.replayGainAlbum,
      mode: mode,
    );
    await _player.setVolume(volume);
  }

  @override
  Future<void> setEqualizerBands(List<double> gainsDb, {required bool enabled}) async {}

  void dispose() {
    _ampTimer?.cancel();
    _stateController.close();
    _ampController.close();
    _player.dispose();
  }
}

class _PathephonAudioHandler extends BaseAudioHandler with SeekHandler {
  _PathephonAudioHandler(this._player) {
    _player.playbackEventStream.listen(_broadcastState);
  }

  final AudioPlayer _player;

  void _broadcastState(PlaybackEvent event) {
    final state = _player.playerState;
    playbackState.add(PlaybackState(
      controls: [
        if (_player.hasPrevious) MediaControl.skipToPrevious,
        if (state.playing) MediaControl.pause else MediaControl.play,
        if (_player.hasNext) MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.playPause,
        MediaAction.setSpeed,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (state.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: state.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _player.currentIndex,
    ));
  }

  @override
  Future<void> onTaskRemoved() async {
    await _player.stop();
    await super.onTaskRemoved();
  }
}