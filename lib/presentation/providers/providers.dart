// ============================================================================
//  providers.dart - central Riverpod wiring
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

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden in main()');
});

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

final playbackServiceProvider = Provider<PlaybackService>((ref) {
  final svc = JustAudioPlaybackService();
  ref.onDispose(svc.dispose);
  return svc;
});

final visualizerServiceProvider = Provider<VisualizerService>((ref) {
  final svc = VisualizerService();
  ref.onDispose(svc.dispose);
  return svc;
});

final stereoAmplitudeProvider = StreamProvider<StereoAmplitude>((ref) {
  return ref.watch(visualizerServiceProvider).amplitudes;
});

final equalizerServiceProvider = Provider<EqualizerService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final svc = AndroidEqualizerService(prefs);
  ref.onDispose(svc.dispose);
  return svc;
});

final audioBookServiceProvider = Provider<AudioBookService>((ref) {
  final svc = AudioBookService(
    playback: ref.watch(playbackServiceProvider),
    repo: ref.watch(audiobookRepositoryProvider),
  );
  ref.onDispose(svc.dispose);
  return svc;
});

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

final albumsProvider = Provider<List<Album>>((ref) {
  final tracks = ref.watch(libraryStateProvider).valueOrNull ?? const <Track>[];
  return ref.watch(libraryRepositoryProvider).groupAlbums(tracks);
});

final playbackSnapshotProvider = StreamProvider<PlaybackSnapshot>((ref) {
  return ref.watch(playbackServiceProvider).state;
});

final playbackPositionProvider = StreamProvider<Duration>((ref) {
  return ref.watch(playbackServiceProvider).positionStream;
});

final amplitudeProvider = StreamProvider<double>((ref) {
  return ref.watch(playbackServiceProvider).amplitudeStream;
});

final eqBandsProvider = StreamProvider<List<double>>((ref) {
  return ref.watch(equalizerServiceProvider).bandsStream;
});

final eqEnabledProvider = StreamProvider<bool>((ref) {
  return ref.watch(equalizerServiceProvider).enabledStream;
});

final replayGainModeProvider = StateProvider<ReplayGainMode>((ref) {
  return ReplayGainMode.off;
});

final isPlayingProvider = StateProvider<bool>((ref) => false);

final repeatModeProvider = StateProvider<RepeatMode>((ref) => RepeatMode.off);
final shuffleProvider = StateProvider<bool>((ref) => false);

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

final sleepRemainingProvider = StreamProvider<Duration?>((ref) {
  return ref.watch(audioBookServiceProvider).sleepRemaining;
});