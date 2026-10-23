// ============================================================================
//  library_repository.dart - orchestrates MediaStore scan, grouping into
//  Albums, and persistence of user playlists (shared_preferences JSON).
// ============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/album.dart';
import '../../domain/models/playlist.dart';
import '../../domain/models/track.dart';
import '../sources/mediastore_source.dart';
import '../sources/tag_source.dart';

String _stableHash(String input) {
  var h = 0xcbf29ce484222325;
  for (final c in input.codeUnits) {
    h ^= c;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return h.toRadixString(16);
}

class LibraryRepository {
  LibraryRepository({
    required MediaStoreSource mediaStore,
    required TagSource tagSource,
    required SharedPreferences prefs,
  })  : _mediaStore = mediaStore,
        _tagSource = tagSource,
        _prefs = prefs;

  final MediaStoreSource _mediaStore;
  final TagSource _tagSource;
  final SharedPreferences _prefs;

  final _scanController = StreamController<ScanProgress>.broadcast();
  Stream<ScanProgress> get scanProgress => _scanController.stream;

  Future<List<Track>> scanLibrary() async {
    final tracks = await _mediaStore.fetchAllTracks();
    _scanController.add(ScanProgress(1.0, tracks.length));
    return tracks;
  }

  /// Group tracks into albums by (albumArtist, album).
  /// Tracks within each album are sorted by (discNumber, trackNumber) so
  /// they appear in the correct playback order — no more random shuffling
  /// when the user taps an album.
  List<Album> groupAlbums(List<Track> tracks) {
    final map = <String, Album>{};
    for (final t in tracks) {
      final artist = (t.albumArtist.isEmpty ? t.artist : t.albumArtist);
      final key = '$artist\u{1F}\u{1F}${t.album}';
      final id = _stableHash(key);
      final album = map.putIfAbsent(
        id,
        () => Album(
          id: id,
          title: t.album,
          albumArtist: artist,
          year: t.year,
          artUri: t.artUri,
          tracks: [],
        ),
      );
      map[id] = album.copyWith(tracks: [...album.tracks, t]);
    }
    // Sort tracks within each album by disc, then track number.
    // Tracks without trackNumber stay at the end (sorted by title).
    for (final album in map.values) {
      album.tracks.sort((a, b) {
        final discCmp = a.discNumber.compareTo(b.discNumber);
        if (discCmp != 0) return discCmp;
        if (a.trackNumber != 0 || b.trackNumber != 0) {
          return a.trackNumber.compareTo(b.trackNumber);
        }
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    }
    return map.values.toList(growable: false)
      ..sort((a, b) => a.albumArtist.toLowerCase().compareTo(b.albumArtist.toLowerCase()));
  }

  static const _playlistsKey = 'pathephon.playlists.v1';

  Future<List<Playlist>> allPlaylists() async {
    final raw = _prefs.getString(_playlistsKey);
    if (raw == null) return const <Playlist>[];
    final list = jsonDecode(raw) as List;
    return list.map((j) => Playlist.fromJson(j as Map<String, dynamic>)).toList(growable: false);
  }

  Future<Playlist> createPlaylist(String name) async {
    final all = await allPlaylists();
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final now = DateTime.now().millisecondsSinceEpoch;
    final pl = Playlist(id: id, name: name, createdAtMs: now, updatedAtMs: now);
    await _writePlaylists([...all, pl]);
    return pl;
  }

  Future<void> renamePlaylist(String id, String name) async {
    final all = await allPlaylists();
    final updated = all.map((p) => p.id == id ? p.copyWith(name: name, updatedAtMs: DateTime.now().millisecondsSinceEpoch) : p).toList();
    await _writePlaylists(updated);
  }

  Future<void> deletePlaylist(String id) async {
    final all = await allPlaylists();
    await _writePlaylists(all.where((p) => p.id != id).toList());
  }

  Future<void> addTrackToPlaylist(String playlistId, String trackId) async {
    final all = await allPlaylists();
    final updated = all.map((p) {
      if (p.id != playlistId) return p;
      if (p.trackIds.contains(trackId)) return p;
      return p.copyWith(
        trackIds: [...p.trackIds, trackId],
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    }).toList();
    await _writePlaylists(updated);
  }

  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    final all = await allPlaylists();
    final updated = all.map((p) {
      if (p.id != playlistId) return p;
      return p.copyWith(
        trackIds: p.trackIds.where((id) => id != trackId).toList(),
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    }).toList();
    await _writePlaylists(updated);
  }

  Future<void> _writePlaylists(List<Playlist> pls) async {
    final json = jsonEncode(pls.map((p) => p.toJson()).toList());
    await _prefs.setString(_playlistsKey, json);
  }

  void dispose() => _scanController.close();
}

class ScanProgress {
  const ScanProgress(this.fraction, this.count);
  final double fraction;
  final int count;
  @override
  String toString() => 'ScanProgress($fraction, $count tracks)';
}