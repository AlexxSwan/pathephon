// ============================================================================
//  mediastore_source.dart - Android MediaStore-backed audio discovery
//
//  IMPORTANT: on_audio_query's MediaStore only sees EMBEDDED art (ID3/Vorbis
//  tags). Many users keep cover.jpg/folder.jpg/album.jpg next to audio files
//  instead of embedding. We scan the track's directory for these files and
//  set track.artUri to the cover file URL if found.
// ============================================================================
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../domain/models/track.dart';
import 'tag_source.dart';

class MediaStoreSource {
  MediaStoreSource(this._query);

  final OnAudioQuery _query;

  /// Common cover-art filenames (lowercase, no extension).
  /// Searched in order — first match wins.
  static const _coverFileNames = [
    'cover', 'folder', 'album', 'front',
    'albumart', 'coverart', 'art',
    'cover.jpg', 'cover.jpeg', 'cover.png',
  ];

  /// Extensions to try for each cover filename.
  static const _coverExtensions = ['jpg', 'jpeg', 'png', 'webp'];

  /// Look in [trackDir] for a cover image. Returns file:// URI or null.
  static String? _findCoverInDir(String trackDir) {
    if (trackDir.isEmpty) return null;
    final dir = Directory(trackDir);
    try {
      if (!dir.existsSync()) return null;
      final entities = dir.listSync(recursive: false, followLinks: false);
      // Build a set of lowercase filenames (without path) for fast lookup.
      final byName = <String, String>{};
      for (final e in entities) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last.toLowerCase();
        byName[name] = e.path;
      }
      // 1. Try each base name with each extension
      for (final base in _coverFileNames) {
        for (final ext in _coverExtensions) {
          final fname = '$base.$ext';
          final path = byName[fname];
          if (path != null) {
            return Uri.file(path).toString();
          }
        }
      }
      // 2. Try files that START with "cover" / "folder" / "album" / "front"
      for (final name in byName.keys) {
        for (final base in ['cover', 'folder', 'album', 'front']) {
          if (name.startsWith(base) && _hasImageExt(name)) {
            return Uri.file(byName[name]!).toString();
          }
        }
      }
      // 3. Last resort: any image file in the directory
      for (final name in byName.keys) {
        if (_hasImageExt(name) && !name.contains('artist') && !name.contains('back')) {
          return Uri.file(byName[name]!).toString();
        }
      }
    } catch (_) {
      // Permissions, IO errors etc - just skip cover detection
    }
    return null;
  }

  static bool _hasImageExt(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    final ext = name.substring(dot + 1);
    return _coverExtensions.contains(ext);
  }

  /// Get the directory part of a file path.
  static String _dirOf(String path) {
    final slash = path.lastIndexOf('/');
    if (slash < 0) return '';
    return path.substring(0, slash);
  }

  Future<List<Track>> fetchAllTracks() async {
    if (!await _query.permissionsStatus()) {
      final granted = await _query.permissionsRequest();
      if (!granted) return const <Track>[];
    }

    final songs = await _query.querySongs(
      sortType: SongSortType.DATE_ADDED,
      orderType: OrderType.DESC_OR_GREATER,
    );

    final tracks = songs.where(_isSupportedFormat).map(TagSource.fromSongModel).toList();
    // For each track without an artUri, try to find cover.jpg/folder.jpg/etc
    // in the same directory. Cache per-directory to avoid re-scanning.
    final dirCoverCache = <String, String?>{};
    for (final t in tracks) {
      if (t.artUri.isNotEmpty) continue;
      final dir = _dirOf(t.filePath);
      if (dir.isEmpty) continue;
      final cover = dirCoverCache.putIfAbsent(dir, () => _findCoverInDir(dir));
      if (cover != null) {
        // Mutate via copyWith - Track is immutable
        // We need a mutable approach: build a new Track with artUri set.
        // Since tracks is List<Track> (mutable), we can replace.
        final idx = tracks.indexOf(t);
        tracks[idx] = t.copyWith(artUri: cover);
      }
    }
    return tracks.toList(growable: false);
  }

  OnAudioQuery get query => _query;

  Future<List<AlbumModel>> fetchAlbums() => _query.queryAlbums();
  Future<List<ArtistModel>> fetchArtists() => _query.queryArtists();

  Future<bool> hasPermission() async {
    return _query.permissionsStatus();
  }

  Future<bool> requestPermission() async {
    return _query.permissionsRequest();
  }

  Future<List<Track>> pickAudioFiles() async {
    final result = await FilePicker.pickFiles(
      type: FileType.audio,
    );
    if (result == null || result.isEmpty) return const <Track>[];

    final tracks = result.map((f) {
      final path = f.path ?? '';
      if (path.isEmpty) return null;
      final ext = path.toLowerCase().split('.').last;
      final uri = Uri.file(path).toString();
      return Track(
        id: uri,
        uri: uri,
        title: f.name,
        fileExtension: ext,
        filePath: path,
      );
    }).whereType<Track>().toList(growable: false);

    // Look for cover art in each track's directory
    return _enrichWithCoverArt(tracks);
  }

  Future<List<Track>> pickDirectory() async {
    final dirPath = await FilePicker.getDirectoryPath();
    if (dirPath == null) return const <Track>[];

    final dir = Directory(dirPath);
    if (!await dir.exists()) return const <Track>[];

    final tracks = <Track>[];
    final entities = dir.listSync(recursive: false, followLinks: false);
    entities.sort((a, b) => a.path.compareTo(b.path));
    // Find cover art for the picked directory ONCE
    final dirCover = _findCoverInDir(dirPath);
    for (final e in entities) {
      if (e is! File) continue;
      final path = e.path;
      final dot = path.lastIndexOf('.');
      if (dot < 0) continue;
      final ext = path.substring(dot + 1).toLowerCase();
      if (!_supportedExtensions.contains(ext)) continue;
      final name = e.uri.pathSegments.last;
      final uri = Uri.file(path).toString();
      tracks.add(Track(
        id: uri,
        uri: uri,
        title: Uri.decodeComponent(name),
        fileExtension: ext,
        filePath: path,
        artUri: dirCover ?? '',
      ));
    }
    return tracks;
  }

  /// For each track in the list, find cover art in its directory.
  /// Caches per-directory to avoid repeated scans.
  List<Track> _enrichWithCoverArt(List<Track> tracks) {
    final dirCoverCache = <String, String?>{};
    final result = <Track>[];
    for (final t in tracks) {
      if (t.artUri.isNotEmpty) {
        result.add(t);
        continue;
      }
      final dir = _dirOf(t.filePath);
      if (dir.isEmpty) {
        result.add(t);
        continue;
      }
      final cover = dirCoverCache.putIfAbsent(dir, () => _findCoverInDir(dir));
      result.add(cover == null ? t : t.copyWith(artUri: cover));
    }
    return result;
  }

  static const _supportedExtensions = {
    'mp3', 'flac', 'wav', 'ogg', 'opus', 'aac', 'm4a', 'alac',
    'ape', 'wv', 'tta', 'mpc',
    'mod', 's3m', 'xm', 'it',
    'dsf', 'dsd', 'dff', 'amr', '3gp', 'm4b', 'mka', 'ofr', 'spx',
  };

  bool _isSupportedFormat(SongModel s) {
    final data = s.data.toLowerCase();
    final dot = data.lastIndexOf('.');
    if (dot < 0) return false;
    final ext = data.substring(dot + 1);
    return _supportedExtensions.contains(ext);
  }
}

bool get isAndroid => Platform.isAndroid;