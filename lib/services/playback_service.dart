// ============================================================================
//  playback_service.dart — воспроизведение через just_audio + audio_service
//
//  КРИТИЧЕСКИЙ ФИКС (v0.10.3+97): раньше этот сервис вызывал `_player.play()`
//  напрямую, минуя AudioHandler. Android-плагин audio_service запускает
//  foreground-сервис / показывает уведомление на экране блокировки /
//  подключает кнопки Bluetooth-гарнитуры ТОЛЬКО когда на самом хендлере
//  вызваны методы play/pause/skip и т.д. Пассивного обновления
//  playbackState через слушатель playbackEventStream недостаточно.
//
//  Теперь каждая команда воспроизведения идёт через `_handler?.play()` и т.д.
//  с fallback на `_player` если AudioService.init() упал.
//
//  COMPAT (v0.10.4+98): исправлены ошибки analyze — rxdart BehaviorSubject
//  cast для playbackState/mediaItem/queue (работает на 0.18.15 и 0.18.16+).
//
//  COMPAT (v0.10.6+100): восстановлены restoreSavedQueue() без аргументов
//  и audioSessionIdStream как Stream<int> (не int?) для совместимости с
//  equalizer_screen.dart и now_playing_screen.dart.
// ============================================================================
import 'dart:async';
import 'dart:convert' show jsonEncode, jsonDecode;
import 'dart:io' show File, IOSink, FileMode;
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/replaygain.dart';
import '../domain/enums/repeat_mode.dart';
import '../domain/models/track.dart';

/// Абстрактный интерфейс сервиса воспроизведения.
abstract class PlaybackService {
  Stream<PlaybackSnapshot> get state;
  Stream<Duration> get positionStream;
  Stream<double> get amplitudeStream;

  /// Стрим audioSessionId из just_audio — нужен эквалайзеру и визуализатору
  /// чтобы прикрепить нативный AudioEffect к сессии плеера.
  /// Возвращает Stream<int> (НЕ int?) — null-значения фильтруются.
  Stream<int> get audioSessionIdStream;

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

  /// Восстановить очередь из SharedPreferences. Вызывается один раз при
  /// старте приложения (см. providers.dart). Не запускает воспроизведение —
  /// только заполняет очередь чтобы пользователь мог тапнуть трек.
  Future<void> restoreSavedQueue();
}

/// Снапшот состояния плеера для UI.
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

/// Реальная реализация на just_audio + audio_service.
class JustAudioPlaybackService implements PlaybackService {
  /// prefs передаётся через конструктор — нужен для restoreSavedQueue().
  JustAudioPlaybackService(this._prefs) {
    _init();
  }

  final SharedPreferences _prefs;
  final _player = AudioPlayer();
  AudioHandler? _handler;

  /// Completer, который резолвится когда _init() отработал.
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

  @override
  Stream<PlaybackSnapshot> get state => _stateController.stream;
  @override
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Stream<double> get amplitudeStream => _ampController.stream;
  @override
  Stream<int> get audioSessionIdStream => _player.androidAudioSessionIdStream
      .where((id) => id != null)
      .map((id) => id!);

  // ---------------------------------------------------------------------------
  // Файловое логирование для диагностики.
  // debugPrint() в release-сборках Flutter молча выкидывает.
  // ---------------------------------------------------------------------------
  static IOSink? _logSink;
  static Future<void> _ensureLogSink() async {
    if (_logSink != null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/pathephon_diag.log');
      _logSink = file.openWrite(mode: FileMode.append);
      _logSink!.writeln('\n=== Pathephon session ${DateTime.now()} ===');
    } catch (_) {/* swallow */}
  }

  static void _log(String msg) {
    debugPrint('[pathephon] $msg');
    final sink = _logSink;
    if (sink != null) {
      try {
        sink.writeln('${DateTime.now().toIso8601String()} $msg');
      } catch (_) {/* swallow */}
    }
  }

  Future<void> _init() async {
    await _ensureLogSink();
    _log('_init() старт');

    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _log('AudioSession.configure OK');
    } catch (e) {
      _log('AudioSession.configure упал (не фатально): $e');
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
          fastForwardInterval: Duration(seconds: 10),
          rewindInterval: Duration(seconds: 10),
        ),
      );
      _log('AudioService.init OK — handler=${_handler?.runtimeType}');
    } catch (e, st) {
      _log('AudioService.init упал (не фатально): $e\n$st');
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
        _pushMediaItemToHandler();
      }
    });

    Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_queue.isNotEmpty) {
        _emitState(_player.playerState);
      }
    });

    _initCompleter.complete();
    _log('_init() завершён');
  }

  void _pushMediaItemToHandler() {
    final handler = _handler;
    if (handler == null || _queue.isEmpty) return;
    final idx = _player.currentIndex ?? _index;
    if (idx < 0 || idx >= _queue.length) return;
    final t = _queue[idx];
    final item = MediaItem(
      id: t.id,
      album: t.album,
      title: t.title,
      artist: t.artist,
      duration: Duration(milliseconds: t.durationMs),
      artUri: t.artUri.isEmpty ? null : Uri.parse(t.artUri),
    );
    try {
      (handler.mediaItem as BehaviorSubject<MediaItem?>).add(item);
      _log('mediaItem.add: "${t.title}" — "${t.artist}"');
    } catch (e) {
      _log('mediaItem.add упал: $e');
    }
  }

  void _pushQueueToHandler() {
    final handler = _handler;
    if (handler == null || _queue.isEmpty) return;
    final items = _queue.map((t) => MediaItem(
      id: t.id,
      album: t.album,
      title: t.title,
      artist: t.artist,
      duration: Duration(milliseconds: t.durationMs),
      artUri: t.artUri.isEmpty ? null : Uri.parse(t.artUri),
    )).toList();
    try {
      (handler.queue as BehaviorSubject<List<MediaItem>>).add(items);
      _log('queue.add: ${items.length} треков');
    } catch (e) {
      _log('queue.add упал: $e');
    }
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

  void _startAmplitudeLoopIfPlaying(bool playing) {
    if (playing) {
      _ampTimer ??= Timer.periodic(const Duration(milliseconds: 50), (_) {
        _ampPhase += 0.18;
        final base = 0.5 + 0.4 * _sinSum(_ampPhase);
        final noise = 0.1 * (DateTime.now().microsecondsSinceEpoch % 100) / 100;
        _ampController.add((base + noise).clamp(0.0, 1.0));
      });
    } else {
      _ampTimer?.cancel();
      _ampTimer = null;
      _ampController.add(0);
    }
  }

  double _sinSum(double t) =>
      0.5 * (1 + math.sin(t * 0.7) + 0.6 * math.sin(t * 2.3) + 0.4 * math.sin(t * 5.7)) / 2;

  @override
  Future<void> playQueue({required List<Track> tracks, required int startIndex}) async {
    await _initCompleter.future;

    if (tracks.isEmpty) {
      _log('playQueue: пустой список — игнорирую');
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

      _pushQueueToHandler();
      _pushMediaItemToHandler();

      _log('playQueue: вызываю _handler.play() для "${tracks[initial].title}"');

      if (_handler != null) {
        await _handler!.play();
      } else {
        await _player.play();
        _log('playQueue: _handler null — fallback на _player.play()');
      }

      await _saveQueue();
    } catch (e, st) {
      _log('playQueue упал: $e\n$st');
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
    _log('play(): _handler.play()');
    if (_handler != null) {
      await _handler!.play();
    } else {
      await _player.play();
    }
  }

  @override
  Future<void> pause() async {
    await _initCompleter.future;
    _log('pause(): _handler.pause()');
    if (_handler != null) {
      await _handler!.pause();
    } else {
      await _player.pause();
    }
  }

  @override
  Future<void> stop() async {
    await _initCompleter.future;
    _log('stop(): _handler.stop()');
    await _player.stop();
    await _handler?.stop();
    _queue = const [];
    _index = 0;
    _stateController.add(PlaybackSnapshot.empty);
    await _prefs.remove(_kQueueKey);
    await _prefs.remove(_kIndexKey);
  }

  @override
  Future<void> seekTo(Duration position) async {
    await _initCompleter.future;
    if (_handler != null) {
      await _handler!.seek(position);
    } else {
      await _player.seek(position);
    }
  }

  @override
  Future<void> skipToNext() async {
    await _initCompleter.future;
    if (_queue.isEmpty) return;
    _log('skipToNext(): _handler.skipToNext()');
    if (_handler != null) {
      await _handler!.skipToNext();
    } else if (_player.hasNext) {
      await _player.seekToNext();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    await _initCompleter.future;
    if (_queue.isEmpty) return;
    _log('skipToPrevious(): _handler.skipToPrevious()');
    if (_handler != null) {
      await _handler!.skipToPrevious();
    } else if (_player.hasPrevious) {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> setShuffle(bool enabled) async {
    await _initCompleter.future;
    _shuffle = enabled;
    await _player.setShuffleModeEnabled(enabled);
    if (_handler != null) {
      await _handler!.setShuffleMode(
        enabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      );
    }
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
    if (_handler != null) {
      final amSvc = switch (mode) {
        RepeatMode.off => AudioServiceRepeatMode.none,
        RepeatMode.all => AudioServiceRepeatMode.all,
        RepeatMode.one => AudioServiceRepeatMode.one,
      };
      await _handler!.setRepeatMode(amSvc);
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed.clamp(0.5, 3.0));
  }

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

  // ---------------------------------------------------------------------------
  // Persistency очереди. Ключ 'pathephon.queue.v1' совпадает с
  // libraryRestoreProvider в providers.dart.
  // ---------------------------------------------------------------------------
  static const _kQueueKey = 'pathephon.queue.v1';
  static const _kIndexKey = 'pathephon.queue.index.v1';

  Future<void> _saveQueue() async {
    try {
      if (_queue.isEmpty) {
        await _prefs.remove(_kQueueKey);
        await _prefs.remove(_kIndexKey);
        return;
      }
      final json = _queue.map(_trackToJson).toList();
      await _prefs.setString(_kQueueKey, jsonEncode(json));
      await _prefs.setInt(_kIndexKey, _index);
    } catch (e) {
      _log('_saveQueue упал: $e');
    }
  }

  Map<String, dynamic> _trackToJson(Track t) => {
    'id': t.id,
    'title': t.title,
    'artist': t.artist,
    'album': t.album,
    'filePath': t.filePath,
    'uri': t.uri,
    'durationMs': t.durationMs,
    'artUri': t.artUri,
  };

  Track _trackFromJson(Map<String, dynamic> j) => Track(
    id: j['id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    artist: j['artist'] as String? ?? '',
    album: j['album'] as String? ?? '',
    filePath: j['filePath'] as String? ?? '',
    uri: j['uri'] as String? ?? '',
    durationMs: j['durationMs'] as int? ?? 0,
    artUri: j['artUri'] as String? ?? '',
  );

  @override
  Future<void> restoreSavedQueue() async {
    await _initCompleter.future;
    try {
      final raw = _prefs.getString(_kQueueKey);
      if (raw == null || raw.isEmpty) {
        _log('restoreSavedQueue: сохранённой очереди нет');
        return;
      }
      final list = jsonDecode(raw) as List<dynamic>;
      final tracks = list
          .map((e) => _trackFromJson(e as Map<String, dynamic>))
          .where((t) => t.uri.isNotEmpty || t.filePath.isNotEmpty)
          .toList(growable: false);
      if (tracks.isEmpty) {
        _log('restoreSavedQueue: распарсилось 0 треков — игнорирую');
        return;
      }
      final savedIdx = _prefs.getInt(_kIndexKey) ?? 0;
      _queue = List.unmodifiable(tracks);
      _index = savedIdx.clamp(0, tracks.length - 1);
      _stateController.add(PlaybackSnapshot(
        current: _queue[_index],
        queue: _queue,
        index: _index,
        position: Duration.zero,
        duration: Duration(milliseconds: _queue[_index].durationMs),
        isPlaying: false,
        isBuffering: false,
        shuffle: false,
        repeatMode: RepeatMode.off,
        replayGainMode: ReplayGainMode.off,
      ));
      _log('restoreSavedQueue: восстановлено ${tracks.length} треков, idx=$_index');
    } catch (e, st) {
      _log('restoreSavedQueue упал: $e\n$st');
    }
  }

  void dispose() {
    _ampTimer?.cancel();
    _stateController.close();
    _ampController.close();
    _player.dispose();
    _logSink?.flush();
    _logSink?.close();
  }
}

// ============================================================================
//  _PathephonAudioHandler
//
//  Каждый метод lifecycle (play/pause/stop/skipToNext/skipToPrevious)
//  вызывает соответствующий метод just_audio. Default-реализации
//  BaseAudioHandler — NO-OP. Переопределяя их мы получаем ОБА эффекта:
//    1. just_audio выполняет реальное аудио-действие
//    2. framework запускает/останавливает foreground-сервис и обновляет
//       уведомление на блокировке
// ============================================================================
class _PathephonAudioHandler extends BaseAudioHandler with SeekHandler {
  _PathephonAudioHandler(this._player) {
    _player.playbackEventStream.listen(_broadcastState);
  }

  final AudioPlayer _player;

  void _broadcastState(PlaybackEvent event) {
    final state = _player.playerState;
    try {
      final bs = playbackState as BehaviorSubject<PlaybackState>;
      bs.add(PlaybackState(
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
    } catch (e) {
      debugPrint('[pathephon] _broadcastState каст упал: $e');
    }
  }

  @override
  Future<void> play() async => await _player.play();

  @override
  Future<void> pause() async => await _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) await _player.seekToPrevious();
  }

  @override
  Future<void> onTaskRemoved() async {
    await _player.stop();
    await super.onTaskRemoved();
  }
}