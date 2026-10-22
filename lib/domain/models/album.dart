// ============================================================================
//  album.dart — Album model. One album = (albumArtist, album) tuple.
// ============================================================================
import 'package:flutter/foundation.dart';

import 'track.dart';

@immutable
class Album {
  const Album({
    required this.id,
    required this.title,
    required this.albumArtist,
    this.genre = '',
    this.year = 0,
    this.artUri = '',
    this.tracks = const <Track>[],
  });

  final String id;
  final String title;
  final String albumArtist;
  final String genre;
  final int year;
  final String artUri;
  final List<Track> tracks;

  int get totalDurationMs => tracks.fold(0, (s, t) => s + t.durationMs);

  Album copyWith({
    String? id,
    String? title,
    String? albumArtist,
    String? genre,
    int? year,
    String? artUri,
    List<Track>? tracks,
  }) {
    return Album(
      id: id ?? this.id,
      title: title ?? this.title,
      albumArtist: albumArtist ?? this.albumArtist,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      artUri: artUri ?? this.artUri,
      tracks: tracks ?? this.tracks,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Album && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
