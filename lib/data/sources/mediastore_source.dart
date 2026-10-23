// ============================================================================
//  mediastore_source.dart - Android MediaStore-backed audio discovery
//
//  Scans track directories for cover.jpg/folder.jpg/album.jpg when the track
//  has no embedded art. All directory scans are wrapped in try-catch so a
//  permission/IO error on one folder never breaks the whole library scan.
// ============================================================================
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../domain/models/track.dart';
import 'tag_source.dart';

class MediaStoreSource {
  MediaStoreSource(this._query);

  final OnAudioQuery _query;

  /// Look in [trackDir] for a cover image. Returns file:// URI or null.
  /// NEVER throws - all errors are caught and return null.
  static String? _findCoverInDir(String trackDir) {
    if (trackDir.isEmpty) return null;
    try {
      final dir = Directory(trackDir);
      if (!dir.existsSync()) return null;
      final entities = dir.listSync(recursive: false, followLinks: false);
      final byName = <String, String>{};
      for (final e in entities) {
        if (e is! File) continue;
        try {
          final name = e.uri.pathSegments.last.toLowerCase();
          byName[name] = e.path;
        } catch (_) {
          continue;
        }
      }
      // 1. Try standard names
      const bases = ['cover', 'folder', 'album', 'front', 'albumart', 'coverart', 'art'];
      const exts = ['jpg', 'jpeg', 'png', 'webp'];
      for (final base in bases) {
        for (final ext in exts) {
          final fname = '$base.$ext';
          final path = byName[fname];
          if (path != null) {
            return Uri.file(path).toString();
          }
        }
      }
      // 2. Try files starting with "cover" / "folder" / "album" / "front"
      for (final name in byName.keys) {
        if ((name.startsWith('cover') ||
             name.startsWith('folder') ||
             name.startsWith('album') ||
             name.startsWith('front')) && _hasImageExt(name)) {
          return Uri.file(byName[name]!).toString();
        }
      }
      // 3. Last resort: any image file (except artist.*/back.*)
      for (final name in byName.keys) {
        if (_hasImageExt(name) &&
            !name.startsWith('artist') &&
            !name.startsWith('back')) {
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
    return const ['jpg', 'jpeg', 'png', 'webp'].contains(ext);
  }

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

    // Map each song to a Track, then enrich with cover art from folder.
    // Build a NEW list (no in-place mutation) - safer.
    final dirCoverCache = <String, String?>{};
    final tracks = <Track>[];
    for (final s in songs) {
      if (!_isSupportedFormat(s)) continue;
      try {
        var t = TagSource.fromSongModel(s);
        if (t.artUri.isEmpty) {
          final dir = _dirOf(t.filePath);
          if (dir.isNotEmpty) {
            // putIfAbsent caches per-directory so we only scan once per folder
            final cover = dirCoverCache.putIfAbsent(dir, () => _findCoverInDir(dir));
            if (cover != null) {
              t = t.copyWith(artUri: cover);
            }
          }
        }
        tracks.add(t);
      } catch (_) {
        // Skip individual bad tracks instead of failing the whole scan
        continue;
      }
    }
    return tracks;
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

    final dirCoverCache = <String, String?>{};
    final tracks = <Track>[];
    for (final f in result) {
      try {
        final path = f.path ?? '';
        if (path.isEmpty) continue;
        final ext = path.toLowerCase().split('.').last;
        final uri = Uri.file(path).toString();
        var artUri = '';
        final dir = _dirOf(path);
        if (dir.isNotEmpty) {
          final cover = dirCoverCache.putIfAbsent(dir, () => _findCoverInDir(dir));
          if (cover != null) artUri = cover;
        }
        tracks.add(Track(
          id: uri,
          uri: uri,
          title: f.name,
          fileExtension: ext,
          filePath: path,
          artUri: artUri,
        ));
      } catch (_) {
        continue;
      }
    }
    return tracks;
  }

  Future<List<Track>> pickDirectory() async {
    final dirPath = await FilePicker.getDirectoryPath();
    if (dirPath == null) return const <Track>[];

    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return const <Track>[];

      // Find cover art for the picked directory ONCE
      final dirCover = _findCoverInDir(dirPath);
      final tracks = <Track>[];
      final entities = dir.listSync(recursive: false, followLinks: false);
      entities.sort((a, b) => a.path.compareTo(b.path));
      for (final e in entities) {
        if (e is! File) continue;
        try {
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
        } catch (_) {
          continue;
        }
      }
      return tracks;
    } catch (_) {
      return const <Track>[];
    }
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