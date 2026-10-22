// ============================================================================
//  bookmark.dart — saved position inside an audiobook.
// ============================================================================
import 'package:flutter/foundation.dart';

@immutable
class Bookmark {
  const Bookmark({
    required this.id,
    required this.audiobookId,
    required this.positionMs,
    this.label = '',
    this.note = '',
    this.createdAtMs = 0,
  });

  final String id;
  final String audiobookId;
  final int positionMs;
  final String label;
  final String note;
  final int createdAtMs;

  Bookmark copyWith({
    String? id,
    String? audiobookId,
    int? positionMs,
    String? label,
    String? note,
    int? createdAtMs,
  }) {
    return Bookmark(
      id: id ?? this.id,
      audiobookId: audiobookId ?? this.audiobookId,
      positionMs: positionMs ?? this.positionMs,
      label: label ?? this.label,
      note: note ?? this.note,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'audiobookId': audiobookId,
        'positionMs': positionMs,
        'label': label,
        'note': note,
        'createdAtMs': createdAtMs,
      };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
        id: json['id'] as String,
        audiobookId: json['audiobookId'] as String,
        positionMs: (json['positionMs'] as num).toInt(),
        label: (json['label'] as String?) ?? '',
        note: (json['note'] as String?) ?? '',
        createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Bookmark && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
