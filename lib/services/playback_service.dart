// ============================================================================
//  playback_service.dart - playback with NATIVE MediaSession integration
//
//  Uses MediaSessionService (native Kotlin) instead of audio_service.
//  - _player.play() for playback (always works)
//  - MediaSessionService for lock screen + headset + Bluetooth
//  - Listens to media button events and forwards to _player
// ============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/replaygain.dart';
import '../domain/enums/repeat_mode.dart';
import '../domain/models/track.dart';
import '../services/media_session_service.dart';

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
    required this.current, required this.queue, required this.index,
    required this.position, required this.duration, required this.isPlaying,
    required this.isBuffering, required this.shuffle,
    required this.repeatMode, required this.replayGainMode,
  });

  final Track? current; final List<Track> queue; final int index;
  final Duration position; final Duration duration;
  final bool isPlaying; final bool isBuffering; final bool shuffle;
  final RepeatMode repeatMode; final ReplayGainMode replayGainMode;

  static PlaybackSnapshot empty = PlaybackSnapshot(
    current: null, queue: const [], index: 0, position: Duration.zero,
    duration: Duration.zero, isPlaying: false, isBuffering: false,
    shuffle: false, repeatMode: RepeatMode.off, replayGainMode: ReplayGainMode.off,
  );
}

class JustAudioPlaybackService implements PlaybackService {
  JustAudioPlaybackService(this._prefs, this._mediaSession) { _init(); }

  final SharedPreferences _prefs;
  final MediaSessionService _mediaSession;
  static const _queueKey = 'pathephon.queue.v1';
  static const _indexKey = 'pathephon.queue.index.v1';
  static const _positionKey = 'pathephon.queue.position.v1';

  final _player = AudioPlayer();
  final _initCompleter = Completer<void>();
  StreamSubscription? _mediaButtonSub;

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
    } catch (e) { debugPrint('[pathephon] AudioSession failed: $e'); }

    _stateController.add(PlaybackSnapshot.empty);

    _player.playerStateStream.listen((st) {
      _emitState(st);
      _savePosition();
      // Update MediaSession playback state
      _updateMediaSessionState(st);
    });

    _player.sequenceStateStream.listen((seqState) {
      if (seqState != null && seqState.currentIndex >= 0) {
        _index = seqState.currentIndex;
        _emitState(_player.playerState);
        _updateMediaSessionMetadata();
      }
    });

    _player.androidAudioSessionIdStream.listen((id) {
      if (id != null) _sessionIdController.add(id);
    });

    // Listen to media button events (headset, Bluetooth, lock screen)
    _mediaButtonSub = _mediaSession.events.listen((event) {
      debugPrint('[pathephon] Media button event: $event');
      switch (event) {
        case 'play':
          _player.play();
          break;
        case 'pause':
          _player.pause();
          break;
        case 'next':
          if (_player.hasNext) {
            _player.seekToNext();
            _index = _player.currentIndex ?? _index;
            _updateMediaSessionMetadata();
            _saveQueue();
          }
          break;
        case 'prev':
          if (_player.hasPrevious) {
            _player.seekToPrevious();
            _index = _player.currentIndex ?? _index;
            _updateMediaSessionMetadata();
            _saveQueue();
          }
          break;
        case 'stop':
          _player.pause();
          break;
        case 'seek:pos':
          final posMs = int.tryParse(event.split(':').last) ?? 0;
          _player.seek(Duration(milliseconds: posMs));
          break;
      }
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

  /// Update MediaSession metadata (title, artist, album) for lock screen.
  void _updateMediaSessionMetadata() {
    if (_queue.isEmpty) return;
    final idx = _player.currentIndex ?? _index;
    if (idx < 0 || idx >= _queue.length) return;
    final t = _queue[idx];
    _mediaSession.updateMetadata(
      title: t.title,
      artist: t.artist,
      album: t.album,
      durationMs: t.durationMs,
    );
  }

  /// Update MediaSession playback state for lock screen controls.
  void _updateMediaSessionState(PlayerState st) {
    final stateStr = st.playing ? 'playing' : 'paused';
    _mediaSession.updatePlaybackState(
      state: stateStr,
      positionMs: _player.position.inMilliseconds,
    );
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

      _stateController.add(PlaybackSnapshot(
        current: _queue[initial], queue: _queue, index: initial,
        position: savedPos, duration: _player.duration ?? Duration.zero,
        isPlaying: false, isBuffering: false,
        shuffle: _shuffle, repeatMode: _repeat, replayGainMode: _rg,
      ));
    } catch (e) { debugPrint('[pathephon] restoreSavedQueue failed: $e'); }
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

      // Start MediaSession (creates notification + lock screen widget)
      await _mediaSession.start();
      _updateMediaSessionMetadata();

      await _player.play();
      await _saveQueue();
      debugPrint('[pathephon] playQueue: started');
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
    return AudioSource.uri(uri);
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
    await _mediaSession.stop();
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
      _updateMediaSessionMetadata();
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
      _updateMediaSessionMetadata();
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
    _mediaButtonSub?.cancel();
    _stateController.close();
    _sessionIdController.close();
    _player.dispose();
  }
}