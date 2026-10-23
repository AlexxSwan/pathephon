// ============================================================================
//  tag_source.dart - read-only tag metadata via on_audio_query.
// ============================================================================
import 'dart:typed_data';

import 'package:on_audio_query/on_audio_query.dart';

import '../../domain/models/track.dart';

class TagSource {
  TagSource(this._query);

  final OnAudioQuery _query;

  /// Returns cover-art bytes for a track (decoded from embedded art via
  /// on_audio_query's MediaStore access).
  Future<Uint8List?> fetchArt(int trackId) async {
    return _query.queryArtwork(trackId, ArtworkType.AUDIO, size: 600);
  }

  Future<String> fetchGenre(int trackId) async {
    return '';
  }

  static double? parseReplayGainFromComments(Map<String, String>? comments) {
    if (comments == null) return null;
    final raw = comments['REPLAYGAIN_TRACK_GAIN'] ??
        comments['replaygain_track_gain'];
    if (raw == null) return null;
    final match =
        RegExp(r'([+-]?\d+(?:\.\d+)?)\s*dB', caseSensitive: false).firstMatch(raw);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  /// Build a Track from on_audio_query's SongModel.
  /// mediaStoreId is set so the UI can lazy-fetch artwork via queryArtwork.
  static Track fromSongModel(SongModel s) {
    final path = s.data;
    final ext = path.toLowerCase().substring(path.lastIndexOf('.') + 1);
    return Track(
      id: s.id.toString(),
      uri: s.uri ?? 'content://media/external/audio/media/${s.id}',
      title: s.title,
      artist: s.artist ?? '',
      albumArtist: s.artist ?? '',
      album: s.album ?? '',
      genre: '',
      trackNumber: s.track ?? 0,
      year: 0,
      durationMs: s.duration ?? 0,
      sizeBytes: s.size,
      fileExtension: ext,
      filePath: path,
      mediaStoreId: s.id,
      dateAddedMs: (s.dateAdded ?? 0) * 1000,
    );
  }
}