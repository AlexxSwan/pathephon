// ============================================================================
//  tag_source.dart — read-only tag metadata via on_audio_query.
//
//  We use on_audio_query's MediaStore-backed fields (already available after
//  querySongs). No separate audiotags dependency needed for MVP.
//
//  For the tag editor screen, we delegate to on_audio_query's queryWithFilters
//  for read, and tag write-back is deferred to a future native MethodChannel.
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

  /// Returns genre name for a track (requires a separate genre query).
  Future<String> fetchGenre(int trackId) async {
    // on_audio_query doesn't directly map track → genre in MVP scope.
    // Returning empty string is acceptable; UI gracefully handles missing genre.
    return '';
  }

  /// Heuristic ReplayGain extraction: parse filename for "RG_-6.4dB" patterns
  /// or read ID3 TXXX frames. For MVP we return null — ReplayGain is applied
  /// manually via the EQ screen toggle.
  static double? parseReplayGainFromComments(Map<String, String>? comments) {
    if (comments == null) return null;
    final raw = comments['REPLAYGAIN_TRACK_GAIN'] ??
        comments['replaygain_track_gain'] ??
        comments['replaygain_track_gain'];
    if (raw == null) return null;
    final match =
        RegExp(r'([+-]?\d+(?:\.\d+)?)\s*dB', caseSensitive: false).firstMatch(raw);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  /// Build a Track from on_audio_query's SongModel.
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
      dateAddedMs: (s.dateAdded ?? 0) * 1000,
    );
  }
}
