// ============================================================================
//  mediastore_source.dart - audio discovery with SAF fallback for folders
//
//  pickDirectory(): if FilePicker returns a content:// tree URI, calls
//  native FolderScannerPlugin to enumerate via DocumentFile API.
//  Otherwise (filesystem path), uses dart:io Directory.
// ============================================================================
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../domain/models/track.dart';
import 'tag_source.dart';

class MediaStoreSource {
  MediaStoreSource(this._query);

  final OnAudioQuery _query;
  static const _folderScanner = MethodChannel('pathephon/folder_scanner');

  static const _coverBases = ['cover', 'folder', 'album', 'front', 'albumart', 'coverart', 'art'];
  static const _coverExts = ['jpg', 'jpeg', 'png', 'webp'];

  static bool _isContentUri(String path) {
    return path.startsWith('content://') ||
           path.startsWith('content%3A') ||
           path.contains('%2Ftree%2F');
  }

  static String? _findCoverInDir(String dirPath) {
    if (dirPath.isEmpty || _isContentUri(dirPath)) return null;
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
      for (final base in _coverBases) {
        for (final ext in _coverExts) {
          final path = byName['$base.$ext'];
          if (path != null) return Uri.file(path).toString();
        }
      }
      for (final name in byName.keys) {
        if ((name.startsWith('cover') ||
             name.startsWith('folder') ||
             name.startsWith('album') ||
             name.startsWith('front')) && _hasImageExt(name)) {
          return Uri.file(byName[name]!).toString();
        }
      }
      for (final name in byName.keys) {
        if (_hasImageExt(name) &&
            !name.startsWith('artist') &&
            !name.startsWith('back')) {
          return Uri.file(byName[name]!).toString();
        }
      }
    } catch (e) {
      debugPrint('[pathephon] _findCoverInDir failed: $e');
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

  Future<List<Track>> fetchAllTracks() async {
    debugPrint('[pathephon] fetchAllTracks: starting');
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
        if (dir.isNotEmpty && !_isContentUri(dir)) {
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

  /// Pick a directory. Works with both filesystem paths and SAF tree URIs.
  Future<List<Track>> pickDirectory() async {
    debugPrint('[pathephon] pickDirectory: starting');
    final dirPath = await FilePicker.getDirectoryPath();
    if (dirPath == null) return const <Track>[];
    debugPrint('[pathephon] pickDirectory: picked path = $dirPath');

    // SAF tree URI: use native FolderScannerPlugin
    if (_isContentUri(dirPath)) {
      debugPrint('[pathephon] pickDirectory: SAF URI detected, calling FolderScannerPlugin');
      try {
        final result = await _folderScanner.invokeMethod('scanFolder', {'treeUri': dirPath});
        if (result is! List) {
          debugPrint('[pathephon] pickDirectory: unexpected result type');
          return const <Track>[];
        }
        final tracks = <Track>[];
        for (final item in result) {
          if (item is! Map) continue;
          final uri = item['uri'] as String;
          final name = item['name'] as String;
          final artUri = (item['artUri'] as String?) ?? '';
          final ext = name.toLowerCase().split('.').last;
          tracks.add(Track(
            id: uri,
            uri: uri,
            title: name,
            fileExtension: ext,
            filePath: dirPath,
            artUri: artUri,
          ));
        }
        debugPrint('[pathephon] pickDirectory: SAF scan returned ${tracks.length} tracks');
        return tracks;
      } catch (e, st) {
        debugPrint('[pathephon] pickDirectory SAF scan FAILED: $e\n$st');
        return const <Track>[];
      }
    }

    // Filesystem path: use dart:io Directory
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
      debugPrint('[pathephon] pickDirectory: dart:io scan returned ${tracks.length} tracks');
      return tracks;
    } catch (e, st) {
      debugPrint('[pathephon] pickDirectory dart:io FAILED: $e\n$st');
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