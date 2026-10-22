// ============================================================================
//  playlist.dart — user-curated playlist (stored in shared_preferences as JSON)
// ============================================================================
import 'package:flutter/foundation.dart';

@immutable
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.trackIds = const <String>[],
    this.createdAtMs = 0,
    this.updatedAtMs = 0,
    this.artUri = '',
  });

  final String id;
  final String name;
  final List<String> trackIds;
  final int createdAtMs;
  final int updatedAtMs;
  final String artUri;

  int get length => trackIds.length;

  Playlist copyWith({
    String? id,
    String? name,
    List<String>? trackIds,
    int? createdAtMs,
    int? updatedAtMs,
    String? artUri,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      trackIds: trackIds ?? this.trackIds,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      artUri: artUri ?? this.artUri,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackIds': trackIds,
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
        'artUri': artUri,
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String,
        trackIds: (json['trackIds'] as List).cast<String>(),
        createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
        updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
        artUri: (json['artUri'] as String?) ?? '',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Playlist && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
