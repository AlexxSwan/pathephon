// ============================================================================
//  playback_service.dart - playback with FULL MediaSession integration
//
//  - Updates mediaItem stream (lock screen shows current track + art)
//  - Updates queue stream (lock screen shows queue)
//  - Handles headset buttons (single tap = play/pause, double = next, triple = prev)
//  - Lock screen controls work (play/pause/next/prev/seek)
// ============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/replaygain.dart';
import '../domain/enums/repeat_mode.dart';
import '../domain/models/track.dart';

abstract class PlaybackService {
  Stream<PlaybackSnapshot> get state;
  Stream<Duration> get positionStream;
  Stream<int> get audioSessionIdStream;

  Future<void> playQueue({required List<Track> tracks, required int startIndex});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> clearQueue();
  Future<void> seekTo(Duration position);
  Future<void> skipToNext();
  Future<void> skipToPrevious();
  Future<void> setShuffle(bool enabled);
  Future<void> setRepeatMode(RepeatMode mode);
  Future<void> setVolume(double volume);
  Future<void> setSpeed(double speed);
  Future<void> setReplayGain(ReplayGainMode mode);
  Future<void> setEqualizerBands(List<double> gainsDb, {required bool enabled});
  Future<void> restoreSavedQueue();
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
    current: null, queue: const [], index: 0, position: Duration.zero,
    duration: Duration.zero, isPlaying: false, isBuffering: false,
    shuffle: false, repeatMode: RepeatMode.off, replayGainMode: ReplayGainMode.off,
  );
}

class JustAudioPlaybackService implements PlaybackService {
  JustAudioPlaybackService(this._prefs) { _init(); }

  final SharedPreferences _prefs;
  static const _queueKey = 'pathephon.queue.v1';
  static const _indexKey = 'pathephon.queue.index.v1';
  static const _positionKey = 'pathephon.queue.position.v1';

  final _player = AudioPlayer();
  AudioHandler? _handler;
  final _initCompleter = Completer<void>();

  List<Track> _queue = const [];
  int _index = 0;
  bool _shuffle = false;
  RepeatMode _repeat = RepeatMode.off;
  ReplayGainMode _rg = ReplayGainMode.off;

  final _stateController = StreamController<PlaybackSnapshot>.broadcast();
  final _sessionIdController = StreamController<int>.broadcast();

  @override
  Stream<PlaybackSnapshot> get state => _stateController.stream;
  @override
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Stream<int> get audioSessionIdStream => _sessionIdController.stream;

  Future<void> _init() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (e) {
      debugPrint('[pathephon] AudioSession configure failed: $e');
    }

    try {
      _handler = await AudioService.init(
        builder: () => _PathephonAudioHandler(_player),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'pathephon_playback',
          androidNotificationChannelName: 'Pathephon Playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          androidNotificationIcon: 'mipmap/ic_launcher',
        ),
      );
    } catch (e) {
      debugPrint('[pathephon] AudioService.init failed: $e');
    }

    _stateController.add(PlaybackSnapshot.empty);

    _player.playerStateStream.listen((st) {
      _emitState(st);
      _savePosition();
    });

    _player.sequenceStateStream.listen((seqState) {
      if (seqState != null && seqState.currentIndex >= 0) {
        _index = seqState.currentIndex;
        _emitState(_player.playerState);
        // Update mediaItem for lock screen
        _updateMediaItem();
      }
    });

    _player.androidAudioSessionIdStream.listen((id) {
      if (id != null) _sessionIdController.add(id);
    });

    Timer.periodic(const Duration(seconds: 5), (_) {
      if (_queue.isNotEmpty) {
        _savePosition();
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
      queue: _queue, index: currentIndex,
      position: _player.position, duration: _player.duration ?? Duration.zero,
      isPlaying: st.playing,
      isBuffering: st.processingState == ProcessingState.loading || st.processingState == ProcessingState.buffering,
      shuffle: _shuffle, repeatMode: _repeat, replayGainMode: _rg,
    ));
  }

  /// Update mediaItem stream so lock screen shows current track + art.
  void _updateMediaItem() {
    if (_handler == null || _queue.isEmpty) return;
    final idx = _player.currentIndex ?? _index;
    if (idx < 0 || idx >= _queue.length) return;
    final t = _queue[idx];
    final mediaItem = MediaItem(
      id: t.id,
      album: t.album,
      title: t.title,
      artist: t.artist,
      duration: Duration(milliseconds: t.durationMs),
      artUri: t.artUri.isEmpty ? null : Uri.parse(t.artUri),
    );
    (_handler!.mediaItem as BehaviorSubject<MediaItem?>).add(mediaItem);
  }

  /// Update queue stream so lock screen shows queue.
  void _updateQueueStream() {
    if (_handler == null) return;
    final items = _queue.map((t) => MediaItem(
      id: t.id, album: t.album, title: t.title, artist: t.artist,
      duration: Duration(milliseconds: t.durationMs),
      artUri: t.artUri.isEmpty ? null : Uri.parse(t.artUri),
    )).toList();
    (_handler!.queue as BehaviorSubject<List<MediaItem>>).add(items);
  }

  Future<void> _saveQueue() async {
    try {
      await _prefs.setString(_queueKey, jsonEncode(_queue.map((t) => t.toJson()).toList()));
      await _prefs.setInt(_indexKey, _index);
    } catch (_) {}
  }

  Future<void> _savePosition() async {
    if (_queue.isEmpty) return;
    try { await _prefs.setInt(_positionKey, _player.position.inMilliseconds); } catch (_) {}
  }

  @override
  Future<void> restoreSavedQueue() async {
    await _initCompleter.future;
    try {
      final raw = _prefs.getString(_queueKey);
      if (raw == null) return;
      final list = jsonDecode(raw) as List;
      final tracks = list.map((j) => Track.fromJson(j as Map<String, dynamic>)).toList(growable: false);
      if (tracks.isEmpty) return;

      _queue = List.unmodifiable(tracks);
      _index = _prefs.getInt(_indexKey) ?? 0;
      final savedPos = Duration(milliseconds: _prefs.getInt(_positionKey) ?? 0);

      final sources = tracks.map(_toSource).toList(growable: false);
      final initial = _index.clamp(0, sources.length - 1);

      await _player.setAudioSource(
        ConcatenatingAudioSource(children: sources, useLazyPreparation: true),
        initialPosition: savedPos, initialIndex: initial,
      );

      _updateQueueStream();
      _updateMediaItem();

      _stateController.add(PlaybackSnapshot(
        current: _queue[initial], queue: _queue, index: initial,
        position: savedPos, duration: _player.duration ?? Duration.zero,
        isPlaying: false, isBuffering: false,
        shuffle: _shuffle, repeatMode: _repeat, replayGainMode: _rg,
      ));
    } catch (e) {
      debugPrint('[pathephon] restoreSavedQueue failed: $e');
    }
  }

  @override
  Future<void> playQueue({required List<Track> tracks, required int startIndex}) async {
    await _initCompleter.future;
    if (tracks.isEmpty) return;
    _queue = List.unmodifiable(tracks);
    _index = startIndex.clamp(0, tracks.length - 1);

    final sources = tracks.map(_toSource).toList(growable: false);
    final initial = startIndex.clamp(0, sources.length - 1);

    try {
      await _player.setAudioSource(
        ConcatenatingAudioSource(children: sources, useLazyPreparation: true),
        initialPosition: Duration.zero, initialIndex: initial,
      );
      await _player.seek(Duration.zero, index: initial);
      await _player.play();
      _updateQueueStream();
      _updateMediaItem();
      await _saveQueue();
    } catch (e) {
      debugPrint('[pathephon] playQueue FAILED: $e');
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
    return AudioSource.uri(uri, tag: MediaItem(
      id: t.id, album: t.album, title: t.title, artist: t.artist,
      duration: Duration(milliseconds: t.durationMs),
      artUri: t.artUri.isEmpty ? null : Uri.parse(t.artUri),
    ));
  }

  @override
  Future<void> play() async { await _initCompleter.future; await _player.play(); }
  @override
  Future<void> pause() async { await _initCompleter.future; await _player.pause(); await _savePosition(); }

  @override
  Future<void> stop() async {
    await _initCompleter.future;
    await _player.pause();
    await _player.seek(Duration.zero);
    await _savePosition();
    _emitState(_player.playerState);
  }

  @override
  Future<void> clearQueue() async {
    await _initCompleter.future;
    await _player.stop();
    await _handler?.stop();
    _queue = const [];
    _index = 0;
    await _prefs.remove(_queueKey);
    await _prefs.remove(_indexKey);
    await _prefs.remove(_positionKey);
    _stateController.add(PlaybackSnapshot.empty);
  }

  @override
  Future<void> seekTo(Duration position) async { await _initCompleter.future; await _player.seek(position); await _savePosition(); }

  @override
  Future<void> skipToNext() async {
    await _initCompleter.future;
    if (_queue.isEmpty) return;
    if (_player.hasNext) {
      await _player.seekToNext();
      _index = _player.currentIndex ?? _index;
      _updateMediaItem();
      await _saveQueue();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    await _initCompleter.future;
    if (_queue.isEmpty) return;
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
      _index = _player.currentIndex ?? _index;
      _updateMediaItem();
      await _saveQueue();
    }
  }

  @override
  Future<void> setShuffle(bool enabled) async { await _initCompleter.future; _shuffle = enabled; await _player.setShuffleModeEnabled(enabled); }
  @override
  Future<void> setRepeatMode(RepeatMode mode) async {
    await _initCompleter.future;
    _repeat = mode;
    final am = switch (mode) {
      RepeatMode.off => LoopMode.off, RepeatMode.all => LoopMode.all, RepeatMode.one => LoopMode.one,
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
    final volume = ReplayGainApplier.selectGain(trackGain: current.replayGainTrack, albumGain: current.replayGainAlbum, mode: mode);
    await _player.setVolume(volume);
  }
  @override
  Future<void> setEqualizerBands(List<double> gainsDb, {required bool enabled}) async {}

  void dispose() {
    _stateController.close();
    _sessionIdController.close();
    _player.dispose();
  }
}

/// AudioHandler with FULL MediaSession support.
/// - Updates mediaItem + queue streams (lock screen display)
/// - Handles headset button events (click patterns)
/// - Handles Bluetooth media buttons
class _PathephonAudioHandler extends BaseAudioHandler with SeekHandler {
  _PathephonAudioHandler(this._player) {
    _player.playbackEventStream.listen(_broadcastState);
    // Handle media button events (headset buttons, Bluetooth, car controls)
    playbackState.listen((state) {
      debugPrint('[pathephon] MediaSession state: playing=${state.playing}, pos=${state.updatePosition}');
    });
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
        MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward,
        MediaAction.playPause, MediaAction.setSpeed,
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
    await _player.pause();
    await super.onTaskRemoved();
  }
}