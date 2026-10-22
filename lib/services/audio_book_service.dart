// ============================================================================
//  audio_book_service.dart — audiobook-specific playback features
//
//  Adds on top of PlaybackService:
//    * speed 0.5x..3.0x
//    * bookmark CRUD (via AudiobookRepository)
//    * sleep timer (15/30/60 min or end-of-chapter)
//    * auto-resume last position on app restart
// ============================================================================
import 'dart:async';

import '../data/repositories/audiobook_repository.dart';
import '../domain/models/audiobook.dart';
import '../domain/models/bookmark.dart';
import 'playback_service.dart';

class AudioBookService {
  AudioBookService({
    required this.playback,
    required this.repo,
  });

  final PlaybackService playback;
  final AudiobookRepository repo;

  // ---- Sleep timer -------------------------------------------------------
  Timer? _sleepTimer;
  final _sleepRemaining = StreamController<Duration?>.broadcast();
  Stream<Duration?> get sleepRemaining => _sleepRemaining.stream;

  /// Schedule a fixed-duration sleep timer.
  void startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    var remaining = duration;
    _sleepRemaining.add(remaining);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      remaining -= const Duration(seconds: 1);
      if (remaining <= Duration.zero) {
        playback.pause();
        cancelSleepTimer();
      } else {
        _sleepRemaining.add(remaining);
      }
    });
  }

  /// "End of chapter" sleep — listens to chapter changes; pauses on transition.
  Future<void> enableSleepAtEndOfChapter(Audiobook book) async {
    cancelSleepTimer();
    final currentChapter = book.chapterAt(await _currentPositionMs());
    if (currentChapter == null) return;

    // Watch position; if it crosses chapter boundary → pause.
    late StreamSubscription subHolder;
    subHolder = playback.positionStream.listen((pos) {
      final ch = book.chapterAt(pos.inMilliseconds);
      if (ch != null && ch.index != currentChapter.index) {
        playback.pause();
        cancelSleepTimer();
        subHolder.cancel();
      }
    });
    // Keep the subscription alive via a no-op timer (cancelled in cancelSleepTimer).
    _sleepTimer = Timer(const Duration(days: 365), () {});
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepRemaining.add(null);
  }

  // ---- Bookmarks ---------------------------------------------------------
  Future<List<Bookmark>> bookmarks(String audiobookId) =>
      repo.bookmarksFor(audiobookId);

  Future<Bookmark> addBookmark({
    required String audiobookId,
    String label = '',
    String note = '',
  }) async {
    final pos = await _currentPositionMs();
    return repo.addBookmark(
      audiobookId: audiobookId,
      positionMs: pos,
      label: label,
      note: note,
    );
  }

  Future<void> deleteBookmark(String id) => repo.deleteBookmark(id);

  Future<void> jumpToBookmark(Bookmark b) => playback.seekTo(
        Duration(milliseconds: b.positionMs),
      );

  // ---- Auto-resume -------------------------------------------------------
  /// Persisted at the provider level; this hook just sets the speed.
  Future<void> resumeAt({
    required Audiobook book,
    required int positionMs,
    required double speed,
  }) async {
    await playback.playQueue(
      tracks: const [], // audiobook queue is constructed by the provider
      startIndex: 0,
    );
    await playback.seekTo(Duration(milliseconds: positionMs));
    await playback.setSpeed(speed);
  }

  // ---- Helpers -----------------------------------------------------------
  Future<int> _currentPositionMs() async {
    final snap = await playback.state.first;
    return snap.position.inMilliseconds;
  }

  void dispose() {
    _sleepTimer?.cancel();
    _sleepRemaining.close();
  }
}
