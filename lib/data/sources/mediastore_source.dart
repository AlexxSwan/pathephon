// ============================================================================
//  mediastore_source.dart - Android MediaStore-backed audio discovery
//  Simple version: NO folder scanning (that broke library scan in 0.4.1+).
// ============================================================================
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../domain/models/track.dart';
import 'tag_source.dart';

class MediaStoreSource {
  MediaStoreSource(this._query);

  final OnAudioQuery _query;

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

    return result.map((f) {
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
  }

  Future<List<Track>> pickDirectory() async {
    final dirPath = await FilePicker.getDirectoryPath();
    if (dirPath == null) return const <Track>[];

    final dir = Directory(dirPath);
    if (!await dir.exists()) return const <Track>[];

    final tracks = <Track>[];
    final entities = dir.listSync(recursive: false, followLinks: false);
    entities.sort((a, b) => a.path.compareTo(b.path));
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
      ));
    }
    return tracks;
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