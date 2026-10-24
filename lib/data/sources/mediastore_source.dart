// ============================================================================
//  mediastore_source.dart - audio discovery
//
//  fetchAllTracks(): MediaStore query only - NO folder scanning (that broke
//  library scan in 0.4.1+). Used for the auto library scan.
//
//  pickDirectory()/pickAudioFiles(): SAF-based file picking. Since the user
//  explicitly granted access to this folder via FilePicker, we can safely
//  scan it for cover.jpg/folder.jpg/album.jpg without permission issues.
//  This is the ONLY place folder scanning happens.
// ============================================================================
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../domain/models/track.dart';
import 'tag_source.dart';

class MediaStoreSource {
  MediaStoreSource(this._query);

  final OnAudioQuery _query;

  /// Standard cover-art filenames (without extension).
  static const _coverBases = [
    'cover', 'folder', 'album', 'front',
    'albumart', 'coverart', 'art',
  ];

  /// Image extensions to try.
  static const _coverExts = ['jpg', 'jpeg', 'png', 'webp'];

  /// Look in [dirPath] for a cover image. Returns file:// URI or null.
  /// NEVER throws - all errors caught and return null.
  /// Only called from pickDirectory/pickAudioFiles (user-granted folders).
  static String? _findCoverInDir(String dirPath) {
    if (dirPath.isEmpty) return null;
    try {
      final dir = Directory(dirPath);
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
      // 1. Standard names: cover.jpg, folder.jpg, etc.
      for (final base in _coverBases) {
        for (final ext in _coverExts) {
          final path = byName['$base.$ext'];
          if (path != null) return Uri.file(path).toString();
        }
      }
      // 2. Files starting with cover/folder/album/front
      for (final name in byName.keys) {
        if ((name.startsWith('cover') ||
             name.startsWith('folder') ||
             name.startsWith('album') ||
             name.startsWith('front')) && _hasImageExt(name)) {
          return Uri.file(byName[name]!).toString();
        }
      }
      // 3. Any image file (except artist.*/back.*)
      for (final name in byName.keys) {
        if (_hasImageExt(name) &&
            !name.startsWith('artist') &&
            !name.startsWith('back')) {
          return Uri.file(byName[name]!).toString();
        }
      }
    } catch (_) {
      // Permissions, IO errors - return null, don't crash
    }
    return null;
  }

  static bool _hasImageExt(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return _coverExts.contains(name.substring(dot + 1));
  }

  static String _dirOf(String path) {
    final slash = path.lastIndexOf('/');
    if (slash < 0) return '';
    return path.substring(0, slash);
  }

  /// MediaStore query - NO folder scanning. Used for auto library scan.
  Future<List<Track>> fetchAllTracks() async {
    if (!await _query.permissionsStatus()) {
      final granted = await _query.permissionsRequest();
      if (!granted) return const <Track>[];
    }

    final songs = await _query.querySongs(
      sortType: SongSortType.DATE_ADDED,
      orderType: OrderType.DESC_OR_GREATER,
    );

    return songs.where(_isSupportedFormat).map(TagSource.fromSongModel).toList(growable: false);
  }

  OnAudioQuery get query => _query;

  Future<List<AlbumModel>> fetchAlbums() => _query.queryAlbums();
  Future<List<ArtistModel>> fetchArtists() => _query.queryArtists();

  Future<bool> hasPermission() async => _query.permissionsStatus();
  Future<bool> requestPermission() async => _query.permissionsRequest();

  /// Pick audio files via SAF. Scans each file's directory for cover art.
  Future<List<Track>> pickAudioFiles() async {
    final result = await FilePicker.pickFiles(type: FileType.audio);
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

  /// Pick a directory via SAF. Scans it ONCE for cover art and applies to all tracks.
  Future<List<Track>> pickDirectory() async {
    final dirPath = await FilePicker.getDirectoryPath();
    if (dirPath == null) return const <Track>[];

    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return const <Track>[];

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
    return _supportedExtensions.contains(data.substring(dot + 1));
  }
}

bool get isAndroid => Platform.isAndroid;