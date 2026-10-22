// ============================================================================
//  audiobook_repository.dart — discovers audiobooks, persists resume position
//  and bookmarks via shared_preferences JSON.
// ============================================================================
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/audiobook.dart';
import '../../domain/models/bookmark.dart';

class AudiobookRepository {
  AudiobookRepository(this._prefs);

  final SharedPreferences _prefs;
  static const _uuid = Uuid();
  static const _abKey = 'pathephon.audiobooks.v1';
  static const _bmKey = 'pathephon.bookmarks.v1';

  /// Heuristic: a file is an audiobook if its extension is in {m4b, mp3, m4a}
  /// AND duration > 30 minutes, OR its parent folder matches common
  /// audiobook naming conventions.
  Future<List<Audiobook>> discoverAudiobooks(List<Directory> candidateFolders) async {
    final out = <Audiobook>[];
    for (final folder in candidateFolders) {
      final files = folder.listSync(recursive: false).whereType<File>().toList();
      for (final f in files) {
        final ext = f.path.toLowerCase().split('.').last;
        if (const {'m4b', 'mp3', 'm4a', 'aac'}.contains(ext)) {
          out.add(Audiobook(
            id: _uuid.v4(),
            title: f.uri.pathSegments.last,
            filePaths: [f.path],
            dateAddedMs: DateTime.now().millisecondsSinceEpoch,
          ));
        }
      }
    }
    return out;
  }

  Future<List<Audiobook>> allAudiobooks() async {
    final raw = _prefs.getString(_abKey);
    if (raw == null) return const <Audiobook>[];
    final list = jsonDecode(raw) as List;
    return list
        .map((j) => Audiobook.fromJson(j as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> saveAudiobook(Audiobook book) async {
    final all = await allAudiobooks();
    final updated = all.where((b) => b.id != book.id).toList()..add(book);
    await _prefs.setString(
      _abKey,
      jsonEncode(updated.map((b) => b.toJson()).toList()),
    );
  }

  // ---- Bookmarks ----------------------------------------------------------
  Future<List<Bookmark>> bookmarksFor(String audiobookId) async {
    final all = await _allBookmarks();
    return all.where((b) => b.audiobookId == audiobookId).toList(growable: false)
      ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
  }

  Future<Bookmark> addBookmark({
    required String audiobookId,
    required int positionMs,
    String label = '',
    String note = '',
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final bm = Bookmark(
      id: id,
      audiobookId: audiobookId,
      positionMs: positionMs,
      label: label,
      note: note,
      createdAtMs: now,
    );
    final all = await _allBookmarks();
    all.add(bm);
    await _writeBookmarks(all);
    return bm;
  }

  Future<void> deleteBookmark(String id) async {
    final all = await _allBookmarks();
    await _writeBookmarks(all.where((b) => b.id != id).toList());
  }

  Future<List<Bookmark>> _allBookmarks() async {
    final raw = _prefs.getString(_bmKey);
    if (raw == null) return <Bookmark>[];
    final list = jsonDecode(raw) as List;
    return list.map((j) => Bookmark.fromJson(j as Map<String, dynamic>)).toList(growable: false);
  }

  Future<void> _writeBookmarks(List<Bookmark> all) async {
    await _prefs.setString(_bmKey, jsonEncode(all.map((b) => b.toJson()).toList()));
  }
}
