// ============================================================================
//  playback_service.dart — v0.11.39+233
//  Фиксы: auto-advance on track complete + position clamp + shuffle/repeat persist
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
  Map<String, dynamic> getStatistics();
  void saveStatistics();
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
  static const _shuffleKey = 'pathephon.shuffle.v1';
  static const _repeatKey = 'pathephon.repeat.v1';
  static const _batteryChannel = MethodChannel('pathephon/battery');

  final _player = AudioPlayer();
  final _initCompleter = Completer<void>();

  static const _nativeChannel = MethodChannel('pathephon/native_media_session');
  static const _tagChannel = MethodChannel('pathephon/tag_reader');

  List<Track> _queue = const [];
  int _index = 0;
  bool _shuffle = false;
  RepeatMode _repeat = RepeatMode.off;
  ReplayGainMode _rg = ReplayGainMode.off;

  bool _isReadingTags = false;
  int? _lastDurationMs;
  DateTime _sessionStart = DateTime.now();
  int _sessionTracksPlayed = 0;
  int _sessionPlayTimeMs = 0;
  DateTime? _playStartTime;
  int _allTimePlayMs = 0;
  int _allTimeTracks = 0;

  final _stateController = StreamController<PlaybackSnapshot>.broadcast();
  final _sessionIdController = StreamController<int>.broadcast();

  @override
  Stream<PlaybackSnapshot> get state => _stateController.stream;
  @override
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Stream<int> get audioSessionIdStream => _sessionIdController.stream;

  Future<void> _init() async {
    crashLogger.log('_init() START');
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);
      crashLogger.log('AudioSession OK + active');

      session.interruptionEventStream.listen((event) {
        crashLogger.log('Audio interruption: type=${event.type}, begin=${event.begin}');
      });
      session.devicesChangedEventStream.listen((devices) {
        crashLogger.log('Audio devices changed: ${devices.devicesRemoved.length} removed, ${devices.devicesAdded.length} added');
        for (final d in devices.devicesRemoved) { crashLogger.log('  Device REMOVED: ${d.name}'); }
        for (final d in devices.devicesAdded) { crashLogger.log('  Device ADDED: ${d.name}'); }
      });
    } catch (e, st) {
      crashLogger.error('AudioSession failed', e, st);
    }

    _stateController.add(PlaybackSnapshot.empty);

    _player.playerStateStream.listen((st) {
      if (st.processingState == ProcessingState.completed) {
        crashLogger.log('Track completed, auto-advancing');
        if (_player.hasNext) {
          _player.seekToNext().then((_) {
            _player.play();
            _notifyNativePlaybackState(true);
          });
        } else {
          _player.seek(Duration.zero);
          _notifyNativePlaybackState(false);
        }
        return;
      }
      _emitState(st);
      _savePosition();
      _notifyNativePlaybackState(st.playing);
    });

    _player.sequenceStateStream.listen((seqState) {
      if (seqState != null && seqState.currentIndex >= 0) {
        if (seqState.currentIndex != _index) { _sessionTracksPlayed++; }
        _index = seqState.currentIndex;
        _emitState(_player.playerState);
        _updateMediaItem();
      }
    });

    _player.durationStream.listen((duration) {
      if (duration == null || _queue.isEmpty) return;
      final ms = duration.inMilliseconds;
      if (ms == _lastDurationMs) return;
      _lastDurationMs = ms;
      crashLogger.log('durationStream: ${ms}ms');
      _updateMediaItem();
    });

    _player.androidAudioSessionIdStream.listen((id) {
      if (id != null) _sessionIdController.add(id);
    });

    Timer.periodic(const Duration(seconds: 5), (_) {
      if (_queue.isNotEmpty) { _savePosition(); _emitState(_player.playerState); saveStatistics(); }
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
    if (playing && _playStartTime == null) { _playStartTime = DateTime.now(); }
    else if (!playing && _playStartTime != null) { _sessionPlayTimeMs += DateTime.now().difference(_playStartTime!).inMilliseconds; _playStartTime = null; }
    try {
      var posMs = _player.position.inMilliseconds;
      final durMs = _player.duration?.inMilliseconds ?? 0;
      if (durMs > 0 && posMs >= durMs) {
        posMs = (durMs - 500).clamp(0, durMs);
      }
      _nativeChannel.invokeMethod('setPlaybackState', {
        'playing': playing,
        'position': posMs,
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
    if (t.artist.isEmpty && t.filePath.isNotEmpty && !_isReadingTags) {
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
    if (_isReadingTags) {
      crashLogger.log('_readTagsAndUpdate: already in progress, skipping');
      return;
    }
    _isReadingTags = true;
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
    } finally {
      _isReadingTags = false;
    }
  }

  void _emitState(PlayerState st) {
    try {
      final currentIndex = _player.currentIndex ?? _index;
      _index = currentIndex;
      var pos = _player.position;
      final dur = _player.duration ?? Duration.zero;
      if (dur.inMilliseconds > 0 && pos.inMilliseconds >= dur.inMilliseconds) {
        pos = Duration(milliseconds: (dur.inMilliseconds - 500).clamp(0, dur.inMilliseconds));
      }
      _stateController.add(PlaybackSnapshot(
        current: _queue.isEmpty ? null : _queue[currentIndex.clamp(0, _queue.length - 1)],
        queue: _queue, index: currentIndex,
        position: pos, duration: dur,
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
      _shuffle = _prefs.getBool(_shuffleKey) ?? false;
      _repeat = RepeatMode.values[_prefs.getInt(_repeatKey) ?? 0];
      try { await _player.setShuffleModeEnabled(_shuffle); } catch (_) {}
      try {
        final am = switch (_repeat) {
          RepeatMode.off => LoopMode.off, RepeatMode.all => LoopMode.all, RepeatMode.one => LoopMode.one,
        };
        await _player.setLoopMode(am);
      } catch (_) {}
      crashLogger.log('Restored: shuffle=$_shuffle, repeat=$_repeat');

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
      final sources = tracks.map(_toSource).toList();
      final currentSource = _player.audioSource;
      if (currentSource is ConcatenatingAudioSource) {
        for (final s in sources) { await currentSource.add(s); }
      }
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
      await _player.play();
      try {
        final s = await AudioSession.instance;
        await s.setActive(true);
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 100));
      _notifyNativePlaybackState(true);
      crashLogger.log('playQueue: playing "${tracks[initial].title}"');
      await _saveQueue();
      _requestBatteryExemptionIfNeeded();
    } catch (e, st) {
      crashLogger.error('playQueue(startIndex=$startIndex, count=${tracks.length}) FAILED', e, st);
      _stateController.add(PlaybackSnapshot.empty);
      try { _notifyNativePlaybackState(false); } catch (_) {}
    }
  }

  Future<void> _requestBatteryExemptionIfNeeded() async {
    try {
      final alreadyAsked = _prefs.getBool('pathephon.battery_exempt_requested') ?? false;
      if (alreadyAsked) return;
      final isIgnoring = await _batteryChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
      if (isIgnoring) {
        await _prefs.setBool('pathephon.battery_exempt_requested', true);
        crashLogger.log('Battery optimization already exempt');
        return;
      }
      crashLogger.log('Requesting battery optimization exemption...');
      await _batteryChannel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      await _prefs.setBool('pathephon.battery_exempt_requested', true);
      crashLogger.log('Battery optimization exemption requested');
    } catch (e, st) {
      crashLogger.error('_requestBatteryExemptionIfNeeded failed', e, st);
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
      await _savePosition();
      saveStatistics();
      try { await _prefs.setString('pathephon.last_exit', 'clean'); } catch (_) {}
    } catch (e, st) { crashLogger.error('pause() failed', e, st); }
  }

  @override
  Future<void> stop() async {
    try {
      await _initCompleter.future;
      await _player.pause();
      await _player.seek(Duration.zero);
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
      try { await _prefs.setBool(_shuffleKey, enabled); } catch (_) {}
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
      try { await _prefs.setInt(_repeatKey, mode.index); } catch (_) {}
    } catch (e, st) { crashLogger.error('setRepeatMode($mode) failed', e, st); }
  }

  @override
  Future<void> setVolume(double volume) async {
    try {
      await _player.setVolume(volume.clamp(0.0, 1.0));
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
      final volume = ReplayGainApplier.selectGain(
        trackGain: current.replayGainTrack,
        albumGain: current.replayGainAlbum,
        mode: mode,
      );
      await _player.setVolume(volume);
    } catch (e, st) { crashLogger.error('setReplayGain($mode) failed', e, st); }
  }

  @override
  Future<void> setEqualizerBands(List<double> gainsDb, {required bool enabled}) async {}

  Map<String, dynamic> getStatistics() {
    var totalPlayMs = _sessionPlayTimeMs;
    if (_playStartTime != null) { totalPlayMs += DateTime.now().difference(_playStartTime!).inMilliseconds; }
    final allTimeMs = _prefs.getInt('pathephon.stats.playtime_ms') ?? 0;
    final allTimeTracks = _prefs.getInt('pathephon.stats.tracks_played') ?? 0;
    return { 'session_play_ms': totalPlayMs, 'session_tracks': _sessionTracksPlayed, 'alltime_play_ms': allTimeMs + totalPlayMs, 'alltime_tracks': allTimeTracks + _sessionTracksPlayed };
  }

  void saveStatistics() {
    try {
      var totalPlayMs = _sessionPlayTimeMs;
      if (_playStartTime != null) { totalPlayMs += DateTime.now().difference(_playStartTime!).inMilliseconds; }
      _prefs.setInt('pathephon.stats.playtime_ms', _allTimePlayMs + totalPlayMs);
      _prefs.setInt('pathephon.stats.tracks_played', _allTimeTracks + _sessionTracksPlayed);
    } catch (_) {}
  }

  void dispose() {
    saveStatistics();
    _stateController.close();
    _sessionIdController.close();
    _player.dispose();
  }
}