// ============================================================================
//  mediastore_source.dart - audio discovery with robust extension parsing
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

  // Audio extensions - case-insensitive matching via .toLowerCase()
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

  /// Robust extension extraction - handles Cyrillic, multiple dots, etc.
  /// Returns lowercase extension without dot, or '' if no extension.
  static String _ext(String path) {
    // URL-decode first (in case path has %2E etc)
    String decoded;
    try {
      decoded = Uri.decodeComponent(path);
    } catch (_) {
      decoded = path;
    }
    final dot = decoded.lastIndexOf('.');
    if (dot < 0 || dot >= decoded.length - 1) return '';
    return decoded.substring(dot + 1).toLowerCase();
  }

  static String _fileName(String path) {
    String decoded;
    try {
      decoded = Uri.decodeComponent(path);
    } catch (_) {
      decoded = path;
    }
    final slash = decoded.lastIndexOf('/');
    if (slash < 0) return decoded;
    return decoded.substring(slash + 1);
  }

  static bool _isAudio(String path) {
    final ext = _ext(path);
    return _supportedAudioExts.contains(ext);
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
    } catch (_) {}
    return null;
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
    final result = await FilePicker.pickFiles(type: FileType.audio);
    if (result == null || result.isEmpty) return const <Track>[];

    final tracks = <Track>[];
    for (final f in result) {
      try {
        final path = f.path ?? '';
        if (path.isEmpty) continue;
        final ext = _ext(path);
        final uri = Uri.file(path).toString();
        tracks.add(Track(
          id: uri,
          uri: uri,
          title: f.name,
          fileExtension: ext,
          filePath: path,
        ));
      } catch (_) {
        continue;
      }
    }
    return tracks;
  }

  Future<({List<Track> tracks, String diagnostic})> pickDirectoryWithDiagnostic() async {
    final dirPath = await FilePicker.getDirectoryPath();
    if (dirPath == null) {
      return (tracks: const <Track>[], diagnostic: 'FilePicker returned null');
    }

    final buf = StringBuffer();
    buf.writeln('Raw path: $dirPath');
    buf.writeln('Is content://: ${_isContentUri(dirPath)}');

    if (_isContentUri(dirPath)) {
      buf.writeln('Trying SAF scan...');
      try {
        final result = await _folderScanner.invokeMethod('scanFolder', {'treeUri': dirPath});
        if (result is! List) {
          buf.writeln('SAF returned non-list');
          return (tracks: const <Track>[], diagnostic: buf.toString());
        }
        final tracks = <Track>[];
        for (final item in result) {
          if (item is! Map) continue;
          final uri = item['uri'] as String;
          final name = item['name'] as String;
          final artUri = (item['artUri'] as String?) ?? '';
          final ext = _ext(name);
          tracks.add(Track(
            id: uri,
            uri: uri,
            title: name,
            fileExtension: ext,
            filePath: dirPath,
            artUri: artUri,
          ));
        }
        buf.writeln('SAF: ${tracks.length} tracks');
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
      buf.writeln('--- Entries ---');
      var listedCount = 0;
      for (final e in entities) {
        if (listedCount >= 20) {
          buf.writeln('... (${entities.length - 20} more)');
          break;
        }
        final isFile = e is File;
        final name = _fileName(e.path);
        final ext = isFile ? _ext(e.path) : '(dir)';
        final isAudio = isFile && _isAudio(e.path);
        buf.writeln('  ${isAudio ? "[OK]" : "[--]"} "$name" (ext: "$ext", isAudio: $isAudio)');
        listedCount++;
      }
      buf.writeln('---------------');

      final dirCover = _findCoverInDir(dirPath);
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
            id: uri,
            uri: uri,
            title: name,
            fileExtension: _ext(path),
            filePath: path,
            artUri: dirCover ?? '',
          ));
        } catch (_) {
          continue;
        }
      }
      buf.writeln('Created ${tracks.length} tracks');
      return (tracks: tracks, diagnostic: buf.toString());
    } catch (e, st) {
      buf.writeln('dart:io FAILED: $e');
      buf.writeln('Stack: $st');
      return (tracks: const <Track>[], diagnostic: buf.toString());
    }
  }

  Future<List<Track>> pickDirectory() async {
    final result = await pickDirectoryWithDiagnostic();
    return result.tracks;
  }

  bool _isSupportedFormat(SongModel s) {
    return _isAudio(s.data);
  }
}

bool get isAndroid => Platform.isAndroid;