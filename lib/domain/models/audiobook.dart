// ============================================================================
//  audiobook.dart — Audiobook model (one .m4b, .mp3 bundle, or large folder).
// ============================================================================
import 'package:flutter/foundation.dart';

@immutable
class Audiobook {
  const Audiobook({
    required this.id,
    required this.title,
    this.author = '',
    this.narrator = '',
    this.coverUri = '',
    this.filePaths = const <String>[],
    this.chapters = const <Chapter>[],
    this.totalDurationMs = 0,
    this.lastPositionMs = 0,
    this.playbackSpeed = 1.0,
    this.dateAddedMs = 0,
    this.lastPlayedMs = 0,
  });

  final String id;
  final String title;
  final String author;
  final String narrator;
  final String coverUri;
  final List<String> filePaths;
  final List<Chapter> chapters;
  final int totalDurationMs;
  final int lastPositionMs;
  final double playbackSpeed;
  final int dateAddedMs;
  final int lastPlayedMs;

  Chapter? chapterAt(int positionMs) {
    if (chapters.isEmpty) return null;
    for (var i = chapters.length - 1; i >= 0; i--) {
      if (positionMs >= chapters[i].startMs) return chapters[i];
    }
    return chapters.first;
  }

  Audiobook copyWith({
    String? id,
    String? title,
    String? author,
    String? narrator,
    String? coverUri,
    List<String>? filePaths,
    List<Chapter>? chapters,
    int? totalDurationMs,
    int? lastPositionMs,
    double? playbackSpeed,
    int? dateAddedMs,
    int? lastPlayedMs,
  }) {
    return Audiobook(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      narrator: narrator ?? this.narrator,
      coverUri: coverUri ?? this.coverUri,
      filePaths: filePaths ?? this.filePaths,
      chapters: chapters ?? this.chapters,
      totalDurationMs: totalDurationMs ?? this.totalDurationMs,
      lastPositionMs: lastPositionMs ?? this.lastPositionMs,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      dateAddedMs: dateAddedMs ?? this.dateAddedMs,
      lastPlayedMs: lastPlayedMs ?? this.lastPlayedMs,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Audiobook && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'narrator': narrator,
        'coverUri': coverUri,
        'filePaths': filePaths,
        'chapters': chapters
            .map((c) => {
                  'index': c.index,
                  'startMs': c.startMs,
                  'endMs': c.endMs,
                  'title': c.title,
                })
            .toList(),
        'totalDurationMs': totalDurationMs,
        'lastPositionMs': lastPositionMs,
        'playbackSpeed': playbackSpeed,
        'dateAddedMs': dateAddedMs,
        'lastPlayedMs': lastPlayedMs,
      };

  factory Audiobook.fromJson(Map<String, dynamic> json) => Audiobook(
        id: json['id'] as String,
        title: json['title'] as String,
        author: (json['author'] as String?) ?? '',
        narrator: (json['narrator'] as String?) ?? '',
        coverUri: (json['coverUri'] as String?) ?? '',
        filePaths: ((json['filePaths'] as List?) ?? const []).cast<String>(),
        chapters: ((json['chapters'] as List?) ?? const [])
            .map((c) => Chapter(
                  index: (c as Map)['index'] as int,
                  startMs: c['startMs'] as int,
                  endMs: c['endMs'] as int,
                  title: (c['title'] as String?) ?? '',
                ))
            .toList(growable: false),
        totalDurationMs: (json['totalDurationMs'] as num?)?.toInt() ?? 0,
        lastPositionMs: (json['lastPositionMs'] as num?)?.toInt() ?? 0,
        playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
        dateAddedMs: (json['dateAddedMs'] as num?)?.toInt() ?? 0,
        lastPlayedMs: (json['lastPlayedMs'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class Chapter {
  const Chapter({
    required this.index,
    required this.startMs,
    required this.endMs,
    this.title = '',
  });

  final int index;
  final int startMs;
  final int endMs;
  final String title;

  int get durationMs => endMs - startMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Chapter &&
          runtimeType == other.runtimeType &&
          index == other.index &&
          startMs == other.startMs;

  @override
  int get hashCode => Object.hash(index, startMs);
}
