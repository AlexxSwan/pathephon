// ============================================================================
//  playback_service.dart — v0.10.16+110 — БЕЗ audio_service
//
//  audio_service plugin автоматически создавал 2-ю MediaSession 'media-session'
//  которая перехватывала BT-события у нашего нативного MediaSessionPlugin.
//  Решение: полностью вырезали audio_service. Теперь только:
//    - just_audio для воспроизведения
//    - MediaSessionPlugin (нативный Kotlin) для BT + lock-screen
// ============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show MethodChannel;
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

  /// Нативный MediaSession channel — для BT + lock-screen.
  /// MediaSessionPlugin.kt создаёт MediaSession с TAG "Pathephon" и
  /// переадресует BT Callback'и сюда.
  static const _nativeChannel = MethodChannel('pathephon/native_media_session');

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
    print('[pathephon] _init() START');

    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      // Запрашиваем audio focus — это даёт системе сигнал что мы —
      // активный media player. Без этого другая MediaSession (например
      // Яндекс Музыка) может перехватить приоритет на часах/локскрине.
      await session.setActive(true);
      print('[pathephon] AudioSession OK + active');
    } catch (e) { print('[pathephon] AudioSession failed: $e'); }

    _stateController.add(PlaybackSnapshot.empty);

    _player.playerStateStream.listen((st) {
      _emitState(st);
      _savePosition();
      _notifyNativePlaybackState(st.playing);
    });

    _player.sequenceStateStream.listen((seqState) {
      if (seqState != null && seqState.currentIndex >= 0) {
        _index = seqState.currentIndex;
        _emitState(_player.playerState);
        _updateMediaItem();
      }
    });

    // Когда just_audio загрузил аудио и узнал duration — пере-пушим metadata
    // в натив. На старте трека _player.duration ещё null, поэтому первый
    // setMediaItem шлёт dur=0. После загрузки аудио durationStream эмитит
    // реальное значение — пушим заново. Без этого lock-screen показывает --:--
    // пока не переключишь трек.
    _player.durationStream.listen((duration) {
      if (duration != null && _queue.isNotEmpty) {
        print('[pathephon] durationStream: ${duration.inMilliseconds}ms — re-push metadata');
        _updateMediaItem();
      }
    });

    _player.androidAudioSessionIdStream.listen((id) {
      if (id != null) _sessionIdController.add(id);
    });

    Timer.periodic(const Duration(seconds: 5), (_) {
      if (_queue.isNotEmpty) { _savePosition(); _emitState(_player.playerState); }
    });

    // Обрабатываем BT события от нативного MediaSessionPlugin.
    // Plugin создаёт MediaSession с TAG "Pathephon" и переадресует
    // Callback.onPlay/onPause/onSkipToNext сюда.
    _nativeChannel.setMethodCallHandler((call) async {
      print('[pathephon] BT event from native: ${call.method}');
      try {
        switch (call.method) {
          case 'play':
          case 'play_pause':
            if (_player.playing) {
              await _player.pause();
            } else {
              await _player.play();
      // Повторно активируем audio session когда реально играем —
      // это переключает active MediaSession на нас.
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
      } catch (e) {
        print('[pathephon] BT handler error: $e');
      }
    });
    print('[pathephon] native channel handler set');

    // Пушим начальный PlaybackState (paused, position=0) чтобы система
    // увидела что MediaSession готова — без этого часы/локскрин не отображают трек.
    _notifyNativePlaybackState(false);
    print('[pathephon] initial playbackState pushed');

    _initCompleter.complete();
    print('[pathephon] _init() DONE');
  }

  void _notifyNativePlaybackState(bool playing) {
    try {
      _nativeChannel.invokeMethod('setPlaybackState', {
        'playing': playing,
        'position': _player.position.inMilliseconds,
        'hasNext': _player.hasNext,
        'hasPrev': _player.hasPrevious,
      });
    } catch (_) {/* swallow — плагин мог ещё не инициализироваться */}
  }

  void _updateMediaItem() {
    if (_queue.isEmpty) return;
    final idx = _player.currentIndex ?? _index;
    if (idx < 0 || idx >= _queue.length) return;
    final t = _queue[idx];
    // Если durationMs=0 (треки из file_picker без тегов) — берём из _player.duration
    final durationMs = (t.durationMs > 0)
        ? t.durationMs
        : (_player.duration?.inMilliseconds ?? 0);
    // Title: если пустой или = имя файла с .mp3 — улучшаем
    var title = t.title;
    if (title.isEmpty || title.endsWith('.mp3') || title.endsWith('.flac') ||
        title.endsWith('.ogg') || title.endsWith('.m4a') || title.endsWith('.wav')) {
      // Убираем расширение и путь
      title = title.replaceAll(RegExp(r'\.(mp3|flac|ogg|m4a|wav|opus|aac)$'), '');
      // Берём только имя файла если есть слэш
      final slashIdx = title.lastIndexOf('/');
      if (slashIdx >= 0) title = title.substring(slashIdx + 1);
      // Убираем "NN - " префикс (номер трека)
      title = title.replaceAll(RegExp(r'^\d+\s*[-\.]\s*'), '');
    }
    try {
      _nativeChannel.invokeMethod('setMediaItem', {
        'title': title,
        'artist': t.artist.isNotEmpty ? t.artist : 'Pathephon',
        'album': t.album.isNotEmpty ? t.album : '',
        'durationMs': durationMs,
        'artUri': t.artUri,
      });
    } catch (_) {/* swallow */}
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
      _updateMediaItem();
      // Пушим metadata в нативную MediaSession — иначе часы/локскрин
      // не увидят трек после восстановления очереди.
      _notifyNativePlaybackState(false);
      _stateController.add(PlaybackSnapshot(
        current: _queue[initial], queue: _queue, index: initial,
        position: savedPos, duration: _player.duration ?? Duration.zero,
        isPlaying: false, isBuffering: false,
        shuffle: _shuffle, repeatMode: _repeat, replayGainMode: _rg,
      ));
    } catch (e) { print('[pathephon] restoreSavedQueue failed: $e'); }
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
      _updateMediaItem();
      _notifyNativePlaybackState(false);
      await _player.play();
      // Повторно активируем audio session когда реально играем —
      // это переключает active MediaSession на нас.
      try {
        final s = await AudioSession.instance;
        await s.setActive(true);
      } catch (_) {}
      // После play() пушим playing=true чтобы система отрисовала виджет
      await Future.delayed(const Duration(milliseconds: 100));
      _notifyNativePlaybackState(true);
      print('[pathephon] playQueue: playing "${tracks[initial].title}"');
      await _saveQueue();
    } catch (e) {
      print('[pathephon] playQueue FAILED: $e');
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
    // Освобождаем audio focus — другая MediaSession может стать active.
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