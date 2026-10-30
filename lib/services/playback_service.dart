// ============================================================================
//  playback_service.dart — v0.11.9+203 — БЕЗ audio_service, С DJ mode
// ============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/replaygain.dart';
import '../domain/enums/repeat_mode.dart';
import '../domain/models/track.dart';
import 'crash_logger.dart';

abstract class PlaybackService {
  Stream<PlaybackSnapshot> get state;
  Stream<Duration> get positionStream;
  Stream<int> get audioSessionIdStream;

  Future<void> playQueue({required List<Track> tracks, required int startIndex});
  Future<void> playSingle(Track track);
  Future<void> addToQueue(List<Track> tracks);
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
  void setDjMode(bool enabled);
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
  JustAudioPlaybackService(this._prefs) { _init(); }
  final SharedPreferences _prefs;
  static const _queueKey = 'pathephon.queue.v1';
  static const _indexKey = 'pathephon.queue.index.v1';
  static const _positionKey = 'pathephon.queue.position.v1';

  final _player = AudioPlayer();
  final _initCompleter = Completer<void>();

  static const _nativeChannel = MethodChannel('pathephon/native_media_session');
  static const _tagChannel = MethodChannel('pathephon/tag_reader');

  List<Track> _queue = const [];
  int _index = 0;
  bool _shuffle = false;
  RepeatMode _repeat = RepeatMode.off;
  ReplayGainMode _rg = ReplayGainMode.off;

  // === DJ mode ===
  bool _djMode = false;
  bool _isFadingOut = false;
  Timer? _fadeTimer;
  double _baseVolume = 1.0;
  double _fadeMultiplier = 1.0;
  StreamSubscription<Duration>? _djPositionSub;

  final _stateController = StreamController<PlaybackSnapshot>.broadcast();
  final _sessionIdController = StreamController<int>.broadcast();

  @override
  Stream<PlaybackSnapshot> get state => _stateController.stream;
  @override
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Stream<int> get audioSessionIdStream => _sessionIdController.stream;

  // === DJ: применить итоговую громкость = base * fade ===
  void _applyVolume() {
    try {
      final v = (_baseVolume * _fadeMultiplier).clamp(0.0, 1.0);
      _player.setVolume(v);
    } catch (_) {}
  }

  void _checkDjFadeOut(Duration pos) {
    if (!_djMode || _isFadingOut) return;
    try {
      final duration = _player.duration;
      if (duration == null || duration.inMilliseconds == 0) return;
      final remaining = duration - pos;
      if (remaining.inMilliseconds <= 3000 && remaining.inMilliseconds > 200) {
        _startDjFadeOut();
      }
    } catch (_) {}
  }

  void _startDjFadeOut() {
    _isFadingOut = true;
    _fadeTimer?.cancel();
    _fadeMultiplier = 1.0;
    _applyVolume();
    const steps = 30;
    const stepMs = 100;
    final decrement = 1.0 / steps;
    var i = 0;
    _fadeTimer = Timer.periodic(const Duration(milliseconds: stepMs), (t) {
      try {
        i++;
        _fadeMultiplier = (1.0 - i * decrement).clamp(0.0, 1.0);
        _applyVolume();
        if (i >= steps) {
          _fadeMultiplier = 0.0;
          _applyVolume();
          t.cancel();
        }
      } catch (_) { t.cancel(); }
    });
  }

  void _startDjFadeIn() {
    _isFadingOut = false;
    _fadeTimer?.cancel();
    _fadeMultiplier = 0.0;
    _applyVolume();
    const steps = 20;
    const stepMs = 100;
    final increment = 1.0 / steps;
    var i = 0;
    _fadeTimer = Timer.periodic(const Duration(milliseconds: stepMs), (t) {
      try {
        i++;
        _fadeMultiplier = (i * increment).clamp(0.0, 1.0);
        _applyVolume();
        if (i >= steps) {
          _fadeMultiplier = 1.0;
          _applyVolume();
          t.cancel();
        }
      } catch (_) { t.cancel(); }
    });
  }

  @override
  void setDjMode(bool enabled) {
    try {
      _djMode = enabled;
      _fadeTimer?.cancel();
      _isFadingOut = false;
      _fadeMultiplier = 1.0;
      _applyVolume();
      crashLogger.log('DJ mode ${enabled ? 'ON' : 'OFF'}');
    } catch (e, st) {
      crashLogger.error('setDjMode failed', e, st);
    }
  }

  Future<void> _init() async {
    crashLogger.log('_init() START');
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);
      crashLogger.log('AudioSession OK + active');
    } catch (e, st) {
      crashLogger.error('AudioSession failed', e, st);
    }

    _stateController.add(PlaybackSnapshot.empty);

    _player.playerStateStream.listen((st) {
      _emitState(st);
      _savePosition();
      _notifyNativePlaybackState(st.playing);
    });

    _player.sequenceStateStream.listen((seqState) {
      if (seqState != null && seqState.currentIndex >= 0) {
        if (_djMode) _startDjFadeIn();
        _index = seqState.currentIndex;
        _emitState(_player.playerState);
        _updateMediaItem();
      }
    });

    _player.durationStream.listen((duration) {
      if (duration != null && _queue.isNotEmpty) {
        crashLogger.log('durationStream: ${duration.inMilliseconds}ms');
        _updateMediaItem();
      }
    });

    _player.androidAudioSessionIdStream.listen((id) {
      if (id != null) _sessionIdController.add(id);
    });

    // DJ: мониторим позицию для fade out
    _djPositionSub = _player.positionStream.listen((pos) {
      _checkDjFadeOut(pos);
    });

    Timer.periodic(const Duration(seconds: 5), (_) {
      if (_queue.isNotEmpty) { _savePosition(); _emitState(_player.playerState); }
    });

    _nativeChannel.setMethodCallHandler((call) async {
      crashLogger.log('BT event from native: ${call.method}');
      try {
        switch (call.method) {
          case 'play':
          case 'play_pause':
            if (_player.playing) {
              await _player.pause();
            } else {
              await _player.play();
              try {
                final s = await AudioSession.instance;
                await s.setActive(true);
              } catch (_) {}
            }
            break;
          case 'pause': await _player.pause(); break;
          case 'next':  if (_player.hasNext) await _player.seekToNext(); break;
          case 'prev':  if (_player.hasPrevious) await _player.seekToPrevious(); break;
          case 'stop':  await _player.stop(); break;
          case 'fast_forward':
            await _player.seek(_player.position + const Duration(seconds: 10));
            break;
          case 'rewind':
            await _player.seek(_player.position - const Duration(seconds: 10));
            break;
          case 'seek':
            final pos = call.arguments['position'] as int?;
            if (pos != null) await _player.seek(Duration(milliseconds: pos));
            break;
        }
      } catch (e, st) {
        crashLogger.error('BT handler error (${call.method})', e, st);
      }
    });
    crashLogger.log('native channel handler set');

    _notifyNativePlaybackState(false);
    crashLogger.log('initial playbackState pushed');

    _initCompleter.complete();
    crashLogger.log('_init() DONE');
  }

  void _notifyNativePlaybackState(bool playing) {
    try {
      _nativeChannel.invokeMethod('setPlaybackState', {
        'playing': playing,
        'position': _player.position.inMilliseconds,
        'hasNext': _player.hasNext,
        'hasPrev': _player.hasPrevious,
      });
    } catch (_) {}
  }

  void _updateMediaItem() {
    if (_queue.isEmpty) return;
    final idx = _player.currentIndex ?? _index;
    if (idx < 0 || idx >= _queue.length) return;
    final t = _queue[idx];
    final durationMs = (t.durationMs > 0)
        ? t.durationMs
        : (_player.duration?.inMilliseconds ?? 0);
    if (t.artist.isEmpty && t.filePath.isNotEmpty) {
      _readTagsAndUpdate(t.filePath);
    }
    try {
      _nativeChannel.invokeMethod('setMediaItem', {
        'title': t.title,
        'artist': t.artist.isNotEmpty ? t.artist : 'Pathephon',
        'album': t.album,
        'durationMs': durationMs,
        'artUri': t.artUri,
      });
    } catch (_) {}
  }

  Future<void> _readTagsAndUpdate(String filePath) async {
    try {
      final tags = await _tagChannel.invokeMethod<Map>('readTags', {'path': filePath});
      if (tags == null) return;
      final title = tags['title'] as String? ?? '';
      final artist = tags['artist'] as String? ?? '';
      final album = tags['album'] as String? ?? '';
      final durationMs = int.tryParse(tags['durationMs'] as String? ?? '0') ?? 0;
      crashLogger.log('tags loaded: title="$title" artist="$artist" dur=$durationMs');
      final idx = _player.currentIndex ?? _index;
      if (idx >= 0 && idx < _queue.length) {
        final old = _queue[idx];
        if (old.artist.isEmpty) {
          final newList = List<Track>.from(_queue);
          newList[idx] = old.copyWith(
            title: title.isNotEmpty ? title : old.title,
            artist: artist,
            album: album,
            albumArtist: tags['albumArtist'] as String? ?? '',
            durationMs: durationMs > 0 ? durationMs : old.durationMs,
          );
          _queue = List.unmodifiable(newList);
          _emitState(_player.playerState);
        }
      }
      _nativeChannel.invokeMethod('setMediaItem', {
        'title': title.isNotEmpty ? title : '',
        'artist': artist.isNotEmpty ? artist : 'Pathephon',
        'album': album,
        'durationMs': durationMs,
        'artUri': _queue[idx].artUri,
      });
    } catch (e, st) {
      crashLogger.error('_readTagsAndUpdate failed', e, st);
    }
  }

  void _emitState(PlayerState st) {
    try {
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
    } catch (e, st) {
      crashLogger.error('_emitState failed', e, st);
    }
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
    try {
      await _initCompleter.future;
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
      _updateMediaItem();
      _notifyNativePlaybackState(false);
      _stateController.add(PlaybackSnapshot(
        current: _queue[initial], queue: _queue, index: initial,
        position: savedPos, duration: _player.duration ?? Duration.zero,
        isPlaying: false, isBuffering: false,
        shuffle: _shuffle, repeatMode: _repeat, replayGainMode: _rg,
      ));
    } catch (e, st) {
      crashLogger.error('restoreSavedQueue failed', e, st);
    }
  }

  @override
  Future<void> addToQueue(List<Track> tracks) async {
    try {
      if (tracks.isEmpty) return;
      _queue = List.unmodifiable([..._queue, ...tracks]);
      await _saveQueue();
    } catch (e, st) {
      crashLogger.error('addToQueue failed', e, st);
    }
  }

  @override
  Future<void> playSingle(Track track) async {
    try { await playQueue(tracks: [track], startIndex: 0); }
    catch (e, st) { crashLogger.error('playSingle failed', e, st); }
  }

  @override
  Future<void> playQueue({required List<Track> tracks, required int startIndex}) async {
    try {
      await _initCompleter.future;
      if (tracks.isEmpty) return;
      _queue = List.unmodifiable(tracks);
      _index = startIndex.clamp(0, tracks.length - 1);
      final sources = tracks.map(_toSource).toList(growable: false);
      final initial = startIndex.clamp(0, sources.length - 1);
      await _player.setAudioSource(
        ConcatenatingAudioSource(children: sources, useLazyPreparation: true),
        initialPosition: Duration.zero, initialIndex: initial,
      );
      await _player.seek(Duration.zero, index: initial);
      _updateMediaItem();
      _notifyNativePlaybackState(false);
      // DJ: fade in на старте
      if (_djMode) _startDjFadeIn();
      await _player.play();
      try {
        final s = await AudioSession.instance;
        await s.setActive(true);
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 100));
      _notifyNativePlaybackState(true);
      crashLogger.log('playQueue: playing "${tracks[initial].title}"');
      await _saveQueue();
    } catch (e, st) {
      crashLogger.error('playQueue(startIndex=$startIndex, count=${tracks.length}) FAILED', e, st);
      _stateController.add(PlaybackSnapshot.empty);
      try { _notifyNativePlaybackState(false); } catch (_) {}
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
  Future<void> play() async {
    try {
      await _initCompleter.future;
      await _player.play();
    } catch (e, st) { crashLogger.error('play() failed', e, st); }
  }

  @override
  Future<void> pause() async {
    try {
      await _initCompleter.future;
      await _player.pause();
      _fadeTimer?.cancel();
      _isFadingOut = false;
      _fadeMultiplier = 1.0;
      _applyVolume();
      await _savePosition();
    } catch (e, st) { crashLogger.error('pause() failed', e, st); }
  }

  @override
  Future<void> stop() async {
    try {
      await _initCompleter.future;
      await _player.pause();
      await _player.seek(Duration.zero);
      _fadeTimer?.cancel();
      _isFadingOut = false;
      _fadeMultiplier = 1.0;
      _applyVolume();
      await _savePosition();
      _emitState(_player.playerState);
    } catch (e, st) { crashLogger.error('stop() failed', e, st); }
  }

  @override
  Future<void> clearQueue() async {
    try {
      await _initCompleter.future;
      await _player.stop();
      try {
        final s = await AudioSession.instance;
        await s.setActive(false);
      } catch (_) {}
      _queue = const [];
      _index = 0;
      await _prefs.remove(_queueKey);
      await _prefs.remove(_indexKey);
      await _prefs.remove(_positionKey);
      _stateController.add(PlaybackSnapshot.empty);
    } catch (e, st) { crashLogger.error('clearQueue() failed', e, st); }
  }

  @override
  Future<void> seekTo(Duration position) async {
    try {
      await _initCompleter.future;
      await _player.seek(position);
      await _savePosition();
    } catch (e, st) { crashLogger.error('seekTo($position) failed', e, st); }
  }

  @override
  Future<void> skipToNext() async {
    try {
      await _initCompleter.future;
      if (_queue.isEmpty) return;
      if (_player.hasNext) {
        await _player.seekToNext();
        _index = _player.currentIndex ?? _index;
        _updateMediaItem();
        await _saveQueue();
      }
    } catch (e, st) { crashLogger.error('skipToNext() failed', e, st); }
  }

  @override
  Future<void> skipToPrevious() async {
    try {
      await _initCompleter.future;
      if (_queue.isEmpty) return;
      if (_player.hasPrevious) {
        await _player.seekToPrevious();
        _index = _player.currentIndex ?? _index;
        _updateMediaItem();
        await _saveQueue();
      }
    } catch (e, st) { crashLogger.error('skipToPrevious() failed', e, st); }
  }

  @override
  Future<void> setShuffle(bool enabled) async {
    try {
      await _initCompleter.future;
      _shuffle = enabled;
      await _player.setShuffleModeEnabled(enabled);
    } catch (e, st) { crashLogger.error('setShuffle($enabled) failed', e, st); }
  }

  @override
  Future<void> setRepeatMode(RepeatMode mode) async {
    try {
      await _initCompleter.future;
      _repeat = mode;
      final am = switch (mode) {
        RepeatMode.off => LoopMode.off, RepeatMode.all => LoopMode.all, RepeatMode.one => LoopMode.one,
      };
      await _player.setLoopMode(am);
    } catch (e, st) { crashLogger.error('setRepeatMode($mode) failed', e, st); }
  }

  @override
  Future<void> setVolume(double volume) async {
    try {
      _baseVolume = volume.clamp(0.0, 1.0);
      _applyVolume();
    } catch (e, st) { crashLogger.error('setVolume($volume) failed', e, st); }
  }

  @override
  Future<void> setSpeed(double speed) async {
    try {
      await _player.setSpeed(speed.clamp(0.5, 3.0));
    } catch (e, st) { crashLogger.error('setSpeed($speed) failed', e, st); }
  }

  @override
  Future<void> setReplayGain(ReplayGainMode mode) async {
    try {
      _rg = mode;
      if (_queue.isEmpty) return;
      final current = _queue[_index];
      _baseVolume = ReplayGainApplier.selectGain(
        trackGain: current.replayGainTrack,
        albumGain: current.replayGainAlbum,
        mode: mode,
      );
      _applyVolume();
    } catch (e, st) { crashLogger.error('setReplayGain($mode) failed', e, st); }
  }

  @override
  Future<void> setEqualizerBands(List<double> gainsDb, {required bool enabled}) async {}

  void dispose() {
    _fadeTimer?.cancel();
    _djPositionSub?.cancel();
    _stateController.close();
    _sessionIdController.close();
    _player.dispose();
  }
}