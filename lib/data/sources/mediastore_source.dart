// ============================================================================
//  mediastore_source.dart - RECURSIVE folder scan with per-folder cover art
//
//  When picking a folder, scans ALL subfolders. Each audio file gets its own
//  cover URI from its parent folder, so different albums show different covers.
// ============================================================================
import 'dart:io';
import 'dart:typed_data';

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
    return path.startsWith('content://') || path.startsWith('content%3A') || path.contains('%2Ftree%2F');
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

  static String _dirOf(String path) {
    String decoded;
    try { decoded = Uri.decodeComponent(path); } catch (_) { decoded = path; }
    final slash = decoded.lastIndexOf('/');
    if (slash < 0) return '';
    return decoded.substring(0, slash);
  }

  static bool _isAudio(String path) => _supportedAudioExts.contains(_ext(path));
  static bool _hasImageExt(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return _coverExts.contains(name.substring(dot + 1));
  }

  /// Find cover art in a filesystem directory.
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

  Future<void> _cacheCoverBytes(String artUri) async {
    if (artUri.isEmpty || _coverBytesCache.containsKey(artUri)) return;
    try {
      if (artUri.startsWith('file://')) {
        final path = Uri.parse(artUri).toFilePath();
        final bytes = await File(path).readAsBytes();
        _coverBytesCache[artUri] = bytes;
      } else if (artUri.startsWith('content://')) {
        final result = await _folderScanner.invokeMethod('readFileBytes', {'uri': artUri});
        if (result is Uint8List) _coverBytesCache[artUri] = result;
      }
    } catch (e) {
      debugPrint('[pathephon] cacheCoverBytes FAILED: $e');
    }
  }

  Uint8List? getCoverBytes(String? artUri) {
    if (artUri == null || artUri.isEmpty) return null;
    return _coverBytesCache[artUri];
  }

  Future<List<Track>> fetchAllTracks() async {
    if (!await _query.permissionsStatus()) {
      final granted = await _query.permissionsRequest();
      if (!granted) return const <Track>[];
    }
    final songs = await _query.querySongs(sortType: SongSortType.DATE_ADDED, orderType: OrderType.DESC_OR_GREATER);
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
        final dir = _dirOf(path);
        String artUri = '';
        if (dir.isNotEmpty && !_isContentUri(dir)) {
          final cover = dirCoverCache.putIfAbsent(dir, () => _findCoverInDir(dir));
          if (cover != null) {
            artUri = cover;
            await _cacheCoverBytes(cover);
          }
        }
        tracks.add(Track(id: Uri.file(path).toString(), uri: Uri.file(path).toString(),
            title: f.name, fileExtension: _ext(path), filePath: path, artUri: artUri));
      } catch (_) { continue; }
    }
    return tracks;
  }

  /// Pick a directory and RECURSIVELY scan all subfolders.
  /// Each audio file gets its own cover URI from its parent folder.
  Future<({List<Track> tracks, String diagnostic})> pickDirectoryWithDiagnostic() async {
    final dirPath = await FilePicker.getDirectoryPath();
    if (dirPath == null) return (tracks: const <Track>[], diagnostic: 'FilePicker returned null');

    final buf = StringBuffer();
    buf.writeln('Raw path: $dirPath');

    // SAF path - use native recursive scan
    if (_isContentUri(dirPath)) {
      buf.writeln('Trying SAF recursive scan...');
      try {
        final result = await _folderScanner.invokeMethod('scanFolder', {'treeUri': dirPath});
        if (result is! List) {
          buf.writeln('SAF returned non-list');
          return (tracks: const <Track>[], diagnostic: buf.toString());
        }
        final tracks = <Track>[];
        final uniqueCovers = <String>{};
        for (final item in result) {
          if (item is! Map) continue;
          final uri = item['uri'] as String;
          final name = item['name'] as String;
          final artUri = (item['artUri'] as String?) ?? '';
          if (artUri.isNotEmpty && !uniqueCovers.contains(artUri)) {
            uniqueCovers.add(artUri);
            await _cacheCoverBytes(artUri);
          }
          tracks.add(Track(id: uri, uri: uri, title: name,
              fileExtension: _ext(name), filePath: dirPath, artUri: artUri));
        }
        buf.writeln('SAF recursive: ${tracks.length} tracks, ${uniqueCovers.length} unique covers');
        return (tracks: tracks, diagnostic: buf.toString());
      } catch (e) {
        buf.writeln('SAF FAILED: $e');
        return (tracks: const <Track>[], diagnostic: buf.toString());
      }
    }

    // Filesystem path - recursive dart:io scan
    buf.writeln('Trying dart:io recursive scan...');
    try {
      final rootDir = Directory(dirPath);
      if (!await rootDir.exists()) {
        buf.writeln('Directory does not exist');
        return (tracks: const <Track>[], diagnostic: buf.toString());
      }

      final tracks = <Track>[];
      final dirCoverCache = <String, String?>{};
      int folderCount = 0;

      // Recursive walk
      Future<void> walkDir(Directory dir) async {
        folderCount++;
        final entities = dir.listSync(recursive: false, followLinks: false);
        final dirPath = dir.path;
        final coverUri = dirCoverCache.putIfAbsent(dirPath, () => _findCoverInDir(dirPath));
        if (coverUri != null) await _cacheCoverBytes(coverUri);

        for (final e in entities) {
          if (e is Directory) {
            await walkDir(e);
          } else if (e is File) {
            try {
              final path = e.path;
              if (!_isAudio(path)) continue;
              final name = _fileName(path);
              tracks.add(Track(
                id: Uri.file(path).toString(),
                uri: Uri.file(path).toString(),
                title: name,
                fileExtension: _ext(path),
                filePath: path,
                artUri: coverUri ?? '',
              ));
            } catch (_) { continue; }
          }
        }
      }

      await walkDir(rootDir);
      tracks.sort((a, b) => a.filePath.compareTo(b.filePath));
      buf.writeln('Recursive: ${tracks.length} tracks in $folderCount folders');
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