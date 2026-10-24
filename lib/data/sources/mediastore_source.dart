// ============================================================================
//  mediastore_source.dart - with READ_MEDIA_IMAGES permission + cover bytes cache
// ============================================================================
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/models/track.dart';
import 'tag_source.dart';

class MediaStoreSource {
  MediaStoreSource(this._query);

  final OnAudioQuery _query;
  static const _folderScanner = MethodChannel('pathephon/folder_scanner');

  // In-memory cache: artUri -> image bytes.
  // Populated at scan time when we have file access.
  final Map<String, Uint8List> _coverBytesCache = {};

  static const _coverBases = ['cover', 'folder', 'album', 'front', 'albumart', 'coverart', 'art'];
  static const _coverExts = ['jpg', 'jpeg', 'png', 'webp'];

  static const _supportedAudioExts = {
    'mp3', 'flac', 'wav', 'ogg', 'opus', 'aac', 'm4a', 'alac',
    'ape', 'wv', 'tta', 'mpc',
    'mod', 's3m', 'xm', 'it',
    'dsf', 'dsd', 'dff', 'amr', '3gp', 'm4b', 'mka', 'ofr', 'spx',
    'mp2', 'mid', 'midi', 'aiff', 'aif', 'wma', 'asf',
  };

  static bool _isContentUri(String path) {
    return path.startsWith('content://') ||
           path.startsWith('content%3A') ||
           path.contains('%2Ftree%2F');
  }

  static String _ext(String path) {
    String decoded;
    try { decoded = Uri.decodeComponent(path); } catch (_) { decoded = path; }
    final dot = decoded.lastIndexOf('.');
    if (dot < 0 || dot >= decoded.length - 1) return '';
    return decoded.substring(dot + 1).toLowerCase();
  }

  static String _fileName(String path) {
    String decoded;
    try { decoded = Uri.decodeComponent(path); } catch (_) { decoded = path; }
    final slash = decoded.lastIndexOf('/');
    if (slash < 0) return decoded;
    return decoded.substring(slash + 1);
  }

  static bool _isAudio(String path) => _supportedAudioExts.contains(_ext(path));
  static bool _hasImageExt(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return _coverExts.contains(name.substring(dot + 1));
  }

  /// Request READ_MEDIA_IMAGES permission (needed on Android 13+ to read cover.jpg).
  Future<void> _ensureImagePermission() async {
    try {
      var status = await Permission.photos.status;
      if (!status.isGranted) {
        status = await Permission.photos.request();
        debugPrint('[pathephon] photos permission: $status');
      }
    } catch (e) {
      debugPrint('[pathephon] photos permission failed: $e');
    }
  }

  /// Read cover image bytes and cache them.
  Future<void> _cacheCoverBytes(String artUri) async {
    if (artUri.isEmpty || _coverBytesCache.containsKey(artUri)) return;
    try {
      if (artUri.startsWith('file://')) {
        final path = Uri.parse(artUri).toFilePath();
        final bytes = await File(path).readAsBytes();
        _coverBytesCache[artUri] = bytes;
        debugPrint('[pathephon] cached cover bytes: $path (${bytes.length} bytes)');
      } else if (artUri.startsWith('content://')) {
        final result = await _folderScanner.invokeMethod('readFileBytes', {'uri': artUri});
        if (result is Uint8List) {
          _coverBytesCache[artUri] = result;
          debugPrint('[pathephon] cached cover bytes from content URI (${result.length} bytes)');
        }
      }
    } catch (e) {
      debugPrint('[pathephon] cacheCoverBytes FAILED: $e (uri: $artUri)');
    }
  }

  /// Get cached cover bytes for an artUri.
  Uint8List? getCoverBytes(String? artUri) {
    if (artUri == null || artUri.isEmpty) return null;
    return _coverBytesCache[artUri];
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
          final name = _fileName(e.path).toLowerCase();
          byName[name] = e.path;
        } catch (_) { continue; }
      }
      for (final base in _coverBases) {
        for (final ext in _coverExts) {
          final path = byName['$base.$ext'];
          if (path != null) return Uri.file(path).toString();
        }
      }
      for (final name in byName.keys) {
        if ((name.startsWith('cover') || name.startsWith('folder') ||
             name.startsWith('album') || name.startsWith('front')) && _hasImageExt(name)) {
          return Uri.file(byName[name]!).toString();
        }
      }
      for (final name in byName.keys) {
        if (_hasImageExt(name) && !name.startsWith('artist') && !name.startsWith('back')) {
          return Uri.file(byName[name]!).toString();
        }
      }
    } catch (_) {}
    return null;
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
    return songs.where(_isSupportedFormat).map(TagSource.fromSongModel).toList(growable: false);
  }

  OnAudioQuery get query => _query;
  Future<List<AlbumModel>> fetchAlbums() => _query.queryAlbums();
  Future<List<ArtistModel>> fetchArtists() => _query.queryArtists();
  Future<bool> hasPermission() async => _query.permissionsStatus();
  Future<bool> requestPermission() async => _query.permissionsRequest();

  Future<List<Track>> pickAudioFiles() async {
    await _ensureImagePermission();
    final result = await FilePicker.pickFiles(type: FileType.audio);
    if (result == null || result.isEmpty) return const <Track>[];

    final dirCoverCache = <String, String?>{};
    final tracks = <Track>[];
    for (final f in result) {
      try {
        final path = f.path ?? '';
        if (path.isEmpty) continue;
        final ext = _ext(path);
        final uri = Uri.file(path).toString();
        var artUri = '';
        final dir = _dirOf(path);
        if (dir.isNotEmpty && !_isContentUri(dir)) {
          final cover = dirCoverCache.putIfAbsent(dir, () => _findCoverInDir(dir));
          if (cover != null) {
            artUri = cover;
            await _cacheCoverBytes(cover);
          }
        }
        tracks.add(Track(
          id: uri, uri: uri, title: f.name,
          fileExtension: ext, filePath: path, artUri: artUri,
        ));
      } catch (_) { continue; }
    }
    return tracks;
  }

  Future<({List<Track> tracks, String diagnostic})> pickDirectoryWithDiagnostic() async {
    await _ensureImagePermission();
    final dirPath = await FilePicker.getDirectoryPath();
    if (dirPath == null) {
      return (tracks: const <Track>[], diagnostic: 'FilePicker returned null');
    }

    final buf = StringBuffer();
    buf.writeln('Raw path: $dirPath');

    if (_isContentUri(dirPath)) {
      buf.writeln('Trying SAF scan...');
      try {
        final result = await _folderScanner.invokeMethod('scanFolder', {'treeUri': dirPath});
        if (result is! List) {
          buf.writeln('SAF returned non-list');
          return (tracks: const <Track>[], diagnostic: buf.toString());
        }
        final tracks = <Track>[];
        String? cachedCoverUri;
        for (final item in result) {
          if (item is! Map) continue;
          final uri = item['uri'] as String;
          final name = item['name'] as String;
          final artUri = (item['artUri'] as String?) ?? '';
          if (artUri.isNotEmpty && cachedCoverUri != artUri) {
            cachedCoverUri = artUri;
            await _cacheCoverBytes(artUri);
          }
          tracks.add(Track(
            id: uri, uri: uri, title: name,
            fileExtension: _ext(name), filePath: dirPath, artUri: artUri,
          ));
        }
        buf.writeln('SAF: ${tracks.length} tracks, cover: ${tracks.isNotEmpty ? tracks.first.artUri : "none"}');
        return (tracks: tracks, diagnostic: buf.toString());
      } catch (e) {
        buf.writeln('SAF FAILED: $e');
        return (tracks: const <Track>[], diagnostic: buf.toString());
      }
    }

    buf.writeln('Trying dart:io...');
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        buf.writeln('Directory does not exist');
        return (tracks: const <Track>[], diagnostic: buf.toString());
      }
      final entities = dir.listSync(recursive: false, followLinks: false);
      buf.writeln('Found ${entities.length} entities');

      final dirCover = _findCoverInDir(dirPath);
      buf.writeln('Cover art: $dirCover');
      if (dirCover != null) {
        await _cacheCoverBytes(dirCover);
        buf.writeln('Cover bytes cached: ${_coverBytesCache.containsKey(dirCover)}');
      }

      final tracks = <Track>[];
      entities.sort((a, b) => a.path.compareTo(b.path));
      for (final e in entities) {
        if (e is! File) continue;
        try {
          final path = e.path;
          if (!_isAudio(path)) continue;
          final name = _fileName(path);
          final uri = Uri.file(path).toString();
          tracks.add(Track(
            id: uri, uri: uri, title: name,
            fileExtension: _ext(path), filePath: path,
            artUri: dirCover ?? '',
          ));
        } catch (_) { continue; }
      }
      buf.writeln('Created ${tracks.length} tracks');
      return (tracks: tracks, diagnostic: buf.toString());
    } catch (e, st) {
      buf.writeln('dart:io FAILED: $e\n$st');
      return (tracks: const <Track>[], diagnostic: buf.toString());
    }
  }

  Future<List<Track>> pickDirectory() async {
    final result = await pickDirectoryWithDiagnostic();
    return result.tracks;
  }

  bool _isSupportedFormat(SongModel s) => _isAudio(s.data);
}

bool get isAndroid => Platform.isAndroid;