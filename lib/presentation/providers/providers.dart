// ============================================================================
//  providers.dart - central Riverpod wiring (single file for MVP clarity)
// ============================================================================
import 'dart:io' show Directory;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/replaygain.dart';
import '../../data/repositories/audiobook_repository.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/sources/mediastore_source.dart';
import '../../data/sources/tag_source.dart';
import '../../domain/enums/repeat_mode.dart';
import '../../domain/models/album.dart';
import '../../domain/models/audiobook.dart';
import '../../domain/models/track.dart';
import '../../services/audio_book_service.dart';
import '../../services/equalizer_service.dart';
import '../../services/playback_service.dart';
import '../../services/visualizer_service.dart';

// ---- SharedPreferences ---------------------------------------------------
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden in main()');
});

// ---- Singletons ----------------------------------------------------------
final mediaStoreSourceProvider = Provider<MediaStoreSource>((ref) {
  return MediaStoreSource(OnAudioQuery());
});

final tagSourceProvider = Provider<TagSource>((ref) {
  return TagSource(ref.watch(mediaStoreSourceProvider).query);
});

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final repo = LibraryRepository(
    mediaStore: ref.watch(mediaStoreSourceProvider),
    tagSource: ref.watch(tagSourceProvider),
    prefs: prefs,
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final audiobookRepositoryProvider = Provider<AudiobookRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AudiobookRepository(prefs);
});

// ---- Playback service ----------------------------------------------------
final playbackServiceProvider = Provider<PlaybackService>((ref) {
  final svc = JustAudioPlaybackService();
  ref.onDispose(svc.dispose);
  return svc;
});

// ---- Visualizer service (single instance) -------------------------------
final visualizerServiceProvider = Provider<VisualizerService>((ref) {
  final svc = VisualizerService();
  ref.onDispose(svc.dispose);
  return svc;
});

// ---- Stereo amplitude stream (L, R) from real Visualizer -----------------
final stereoAmplitudeProvider = StreamProvider<StereoAmplitude>((ref) {
  return ref.watch(visualizerServiceProvider).amplitudes;
});

// ---- EQ service ----------------------------------------------------------
final equalizerServiceProvider = Provider<EqualizerService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final svc = AndroidEqualizerService(prefs);
  ref.onDispose(svc.dispose);
  return svc;
});

// ---- Audio book service --------------------------------------------------
final audioBookServiceProvider = Provider<AudioBookService>((ref) {
  final svc = AudioBookService(
    playback: ref.watch(playbackServiceProvider),
    repo: ref.watch(audiobookRepositoryProvider),
  );
  ref.onDispose(svc.dispose);
  return svc;
});

// ---- Library state -------------------------------------------------------
final libraryStateProvider =
    StateNotifierProvider<LibraryNotifier, AsyncValue<List<Track>>>((ref) {
  return LibraryNotifier(ref.watch(libraryRepositoryProvider));
});

class LibraryNotifier extends StateNotifier<AsyncValue<List<Track>>> {
  LibraryNotifier(this._repo) : super(const AsyncValue.loading());

  final LibraryRepository _repo;

  Future<void> scan() async {
    state = const AsyncValue.loading();
    try {
      final tracks = await _repo.scanLibrary();
      state = AsyncValue.data(tracks);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void setPickedTracks(List<Track> tracks) {
    state = AsyncValue.data(tracks);
  }
}

// Group derived state
final albumsProvider = Provider<List<Album>>((ref) {
  final tracks = ref.watch(libraryStateProvider).valueOrNull ?? const <Track>[];
  return ref.watch(libraryRepositoryProvider).groupAlbums(tracks);
});

// ---- Playback snapshot ---------------------------------------------------
final playbackSnapshotProvider = StreamProvider<PlaybackSnapshot>((ref) {
  return ref.watch(playbackServiceProvider).state;
});

final playbackPositionProvider = StreamProvider<Duration>((ref) {
  return ref.watch(playbackServiceProvider).positionStream;
});

// Keep amplitudeProvider for backward compat (returns L channel amplitude).
final amplitudeProvider = StreamProvider<double>((ref) {
  return ref.watch(playbackServiceProvider).amplitudeStream;
});

// ---- EQ state ------------------------------------------------------------
final eqBandsProvider = StreamProvider<List<double>>((ref) {
  return ref.watch(equalizerServiceProvider).bandsStream;
});

final eqEnabledProvider = StreamProvider<bool>((ref) {
  return ref.watch(equalizerServiceProvider).enabledStream;
});

// ---- ReplayGain mode (UI toggle) ----------------------------------------
final replayGainModeProvider = StateProvider<ReplayGainMode>((ref) {
  return ReplayGainMode.off;
});

// ---- isPlaying (instant toggle) -----------------------------------------
final isPlayingProvider = StateProvider<bool>((ref) => false);

// ---- Repeat / shuffle (UI mirrors snapshot) -----------------------------
final repeatModeProvider = StateProvider<RepeatMode>((ref) => RepeatMode.off);
final shuffleProvider = StateProvider<bool>((ref) => false);

// ---- Audiobooks state ---------------------------------------------------
final audiobooksStateProvider =
    StateNotifierProvider<AudiobooksNotifier, AsyncValue<List<Audiobook>>>((ref) {
  return AudiobooksNotifier(ref.watch(audiobookRepositoryProvider));
});

class AudiobooksNotifier extends StateNotifier<AsyncValue<List<Audiobook>>> {
  AudiobooksNotifier(this._repo) : super(const AsyncValue.data(<Audiobook>[]));

  final AudiobookRepository _repo;

  Future<void> discover(List<Directory> folders) async {
    state = const AsyncValue.loading();
    try {
      final books = await _repo.discoverAudiobooks(folders);
      state = AsyncValue.data(books);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadStored() async {
    state = const AsyncValue.loading();
    try {
      final books = await _repo.allAudiobooks();
      state = AsyncValue.data(books);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

// ---- Sleep timer state --------------------------------------------------
final sleepRemainingProvider = StreamProvider<Duration?>((ref) {
  return ref.watch(audioBookServiceProvider).sleepRemaining;
});