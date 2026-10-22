// ============================================================================
//  mediastore_source.dart — Android MediaStore-backed audio discovery
// ============================================================================
import "dart:io";

import "package:file_picker/file_picker.dart";
import "package:on_audio_query/on_audio_query.dart";

import "../../domain/models/track.dart";
import "tag_source.dart";

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

  /// Pick audio files manually via file_picker.
  Future<List<Track>> pickAudioFiles() async {
    final result = await FilePicker.pickFiles(
      type: FileType.audio,
    );
    if (result == null || result.isEmpty) return const <Track>[];

    return result.map((f) {
      final path = f.path ?? "";
      final ext = path.toLowerCase().split(".").last;
      // Use Uri.file() for proper file:// URI encoding
      final uri = Uri.file(path).toString();
      return Track(
        id: uri,
        uri: uri,
        title: f.name,
        fileExtension: ext,
        filePath: path,
      );
    }).toList(growable: false);
  }

  /// Pick a directory and scan for audio files.
  Future<List<Track>> pickDirectory() async {
    final dirPath = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ["mp3", "flac", "wav", "ogg", "m4a", "aac"],
    );
    // file_picker 13.x doesn't support directory picking directly.
    // We use getDirectoryPath from file_picker if available.
    // For now, fall back to pickAudioFiles.
    return pickAudioFiles();
  }

  static const _supportedExtensions = {
    "mp3", "flac", "wav", "ogg", "opus", "aac", "m4a", "alac",
    "ape", "wv", "tta", "mpc",
    "mod", "s3m", "xm", "it",
    "dsf", "dsd", "dff", "amr", "3gp", "m4b", "mka", "ofr", "spx",
  };

  bool _isSupportedFormat(SongModel s) {
    final data = s.data.toLowerCase();
    final dot = data.lastIndexOf(".");
    if (dot < 0) return false;
    final ext = data.substring(dot + 1);
    return _supportedExtensions.contains(ext);
  }
}

bool get isAndroid => Platform.isAndroid;