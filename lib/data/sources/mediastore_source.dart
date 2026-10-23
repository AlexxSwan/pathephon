// ============================================================================
//  mediastore_source.dart — Android MediaStore-backed audio discovery
//  Uses on_audio_query (Android-only) to query MediaStore.Audio.Media.
// ============================================================================
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../domain/models/track.dart';
import 'tag_source.dart'; // for TagSource.fromSongModel

class MediaStoreSource {
  MediaStoreSource(this._query);

  final OnAudioQuery _query;

  /// Permissions must be granted by the caller (see PermissionsGate).
  Future<List<Track>> fetchAllTracks() async {
    // Auto-request permission if not granted. on_audio_query will return an
    // empty list on permission denial, so we ask first to give the user a
    // chance before falling back to "library empty".
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

  /// Expose underlying query for TagSource (read-only).
  OnAudioQuery get query => _query;

  Future<List<AlbumModel>> fetchAlbums() => _query.queryAlbums();
  Future<List<ArtistModel>> fetchArtists() => _query.queryArtists();

  /// True if the device grants READ_MEDIA_AUDIO (or legacy READ_EXTERNAL_STORAGE).
  Future<bool> hasPermission() async {
    return _query.permissionsStatus();
  }

  Future<bool> requestPermission() async {
    return _query.permissionsRequest();
  }

  /// Pick audio files manually via file_picker — fallback when MediaStore
  /// returns empty (e.g. permission denied, or user wants specific files).
  Future<List<Track>> pickAudioFiles() async {
    final result = await FilePicker.pickFiles(
      type: FileType.audio,
    );
    if (result == null || result.isEmpty) return const <Track>[];

    return result.map((f) {
      final path = f.path ?? '';
      final ext = path.toLowerCase().split('.').last;
      return Track(
        id: 'file://$path',
        uri: 'file://$path',
        title: f.name,
        fileExtension: ext,
        filePath: path,
      );
    }).toList(growable: false);
  }

  /// Pick a directory and scan it for audio files.
  /// Returns tracks sorted by filename. Used as a fallback when the user
  /// wants to play from a folder that MediaStore doesn't expose.
  Future<List<Track>> pickDirectory() async {
    final dirPath = await FilePicker.getDirectoryPath();
    if (dirPath == null) return const <Track>[];

    final dir = Directory(dirPath);
    if (!await dir.exists()) return const <Track>[];

    final tracks = <Track>[];
    final entities = dir.listSync(recursive: false, followLinks: false);
    // Sort by filename for stable ordering.
    entities.sort((a, b) => a.path.compareTo(b.path));
    for (final e in entities) {
      if (e is! File) continue;
      final path = e.path;
      final dot = path.lastIndexOf('.');
      if (dot < 0) continue;
      final ext = path.substring(dot + 1).toLowerCase();
      if (!_supportedExtensions.contains(ext)) continue;
      final name = e.uri.pathSegments.last;
      tracks.add(Track(
        id: 'file://$path',
        uri: 'file://$path',
        title: Uri.decodeComponent(name),
        fileExtension: ext,
        filePath: path,
      ));
    }
    return tracks;
  }

  // ---- Format safelist (matches README "all-formats" claim) ---------------
  static const _supportedExtensions = {
    // Base+ — these are natively supported by ExoPlayer via just_audio.
    'mp3', 'flac', 'wav', 'ogg', 'opus', 'aac', 'm4a', 'alac',
    // Audiophile / exotic — playback may fail for unsupported codecs;
    // UI gracefully reports the error.
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

/// Detected platform — used by repository to pick the right source.
bool get isAndroid => Platform.isAndroid;
