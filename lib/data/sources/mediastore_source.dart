// ============================================================================
//  mediastore_source.dart - audio discovery with diagnostic dialog
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

    final dirCoverCache = <String, String?>{};
    final tracks = <Track>[];
    for (final f in result) {
      try {
        final path = f.path ?? '';
        if (path.isEmpty) continue;
        final ext = path.toLowerCase().split('.').last;
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

  /// Pick a directory. Returns (tracks, diagnosticInfo).
  /// The diagnosticInfo is shown to user via dialog if tracks is empty.
  Future<({List<Track> tracks, String diagnostic})> pickDirectoryWithDiagnostic() async {
    final dirPath = await FilePicker.getDirectoryPath();
    if (dirPath == null) {
      return (tracks: const <Track>[], diagnostic: 'FilePicker.getDirectoryPath() returned null (user cancelled or permission denied)');
    }

    final buf = StringBuffer();
    buf.writeln('Raw path: $dirPath');
    buf.writeln('Starts with content://: ${dirPath.startsWith("content://")}');
    buf.writeln('Contains %2Ftree%2F: ${dirPath.contains("%2Ftree%2F")}');
    buf.writeln('Looks like filesystem: ${dirPath.startsWith("/storage/") || dirPath.startsWith("/sdcard/")}');

    // Try SAF if content URI
    if (_isContentUri(dirPath)) {
      buf.writeln('Trying SAF scan...');
      try {
        final result = await _folderScanner.invokeMethod('scanFolder', {'treeUri': dirPath});
        if (result is! List) {
          buf.writeln('SAF returned non-list: ${result.runtimeType}');
          return (tracks: const <Track>[], diagnostic: buf.toString());
        }
        buf.writeln('SAF returned ${result.length} items');
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
        buf.writeln('Created ${tracks.length} Track objects');
        return (tracks: tracks, diagnostic: buf.toString());
      } catch (e, st) {
        buf.writeln('SAF scan FAILED: $e');
        buf.writeln('Stack: $st');
        return (tracks: const <Track>[], diagnostic: buf.toString());
      }
    }

    // Filesystem path - try dart:io
    buf.writeln('Trying dart:io Directory.listSync...');
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        buf.writeln('Directory does not exist: $dirPath');
        return (tracks: const <Track>[], diagnostic: buf.toString());
      }
      buf.writeln('Directory exists, listing...');
      final entities = dir.listSync(recursive: false, followLinks: false);
      buf.writeln('Found ${entities.length} entities');
      final dirCover = _findCoverInDir(dirPath);
      final tracks = <Track>[];
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
      buf.writeln('Created ${tracks.length} tracks from filesystem');
      return (tracks: tracks, diagnostic: buf.toString());
    } catch (e, st) {
      buf.writeln('dart:io FAILED: $e');
      buf.writeln('Stack: $st');
      return (tracks: const <Track>[], diagnostic: buf.toString());
    }
  }

  /// Legacy pickDirectory - returns just tracks (uses diagnostic version internally).
  Future<List<Track>> pickDirectory() async {
    final result = await pickDirectoryWithDiagnostic();
    return result.tracks;
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