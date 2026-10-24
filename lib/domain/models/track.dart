// ============================================================================
//  track.dart - immutable Track model
// ============================================================================
import 'package:flutter/foundation.dart';

@immutable
class Track {
  const Track({
    required this.id,
    required this.uri,
    required this.title,
    this.artist = '',
    this.albumArtist = '',
    this.album = '',
    this.genre = '',
    this.trackNumber = 0,
    this.discNumber = 0,
    this.year = 0,
    this.durationMs = 0,
    this.sizeBytes = 0,
    this.bitrateKbps = 0,
    this.sampleRateHz = 0,
    this.bitDepth = 0,
    this.mimeType = '',
    this.fileExtension = '',
    this.filePath = '',
    this.artUri = '',
    this.mediaStoreId,
    this.replayGainTrack,
    this.replayGainAlbum,
    this.dateAddedMs = 0,
  });

  final String id;
  final String uri;
  final String title;
  final String artist;
  final String albumArtist;
  final String album;
  final String genre;
  final int trackNumber;
  final int discNumber;
  final int year;
  final int durationMs;
  final int sizeBytes;
  final int bitrateKbps;
  final int sampleRateHz;
  final int bitDepth;
  final String mimeType;
  final String fileExtension;
  final String filePath;
  final String artUri;
  final int? mediaStoreId;
  final double? replayGainTrack;
  final double? replayGainAlbum;
  final int dateAddedMs;

  Track copyWith({
    String? id,
    String? uri,
    String? title,
    String? artist,
    String? albumArtist,
    String? album,
    String? genre,
    int? trackNumber,
    int? discNumber,
    int? year,
    int? durationMs,
    int? sizeBytes,
    int? bitrateKbps,
    int? sampleRateHz,
    int? bitDepth,
    String? mimeType,
    String? fileExtension,
    String? filePath,
    String? artUri,
    int? mediaStoreId,
    double? replayGainTrack,
    double? replayGainAlbum,
    int? dateAddedMs,
  }) {
    return Track(
      id: id ?? this.id,
      uri: uri ?? this.uri,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      albumArtist: albumArtist ?? this.albumArtist,
      album: album ?? this.album,
      genre: genre ?? this.genre,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      year: year ?? this.year,
      durationMs: durationMs ?? this.durationMs,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      bitDepth: bitDepth ?? this.bitDepth,
      mimeType: mimeType ?? this.mimeType,
      fileExtension: fileExtension ?? this.fileExtension,
      filePath: filePath ?? this.filePath,
      artUri: artUri ?? this.artUri,
      mediaStoreId: mediaStoreId ?? this.mediaStoreId,
      replayGainTrack: replayGainTrack ?? this.replayGainTrack,
      replayGainAlbum: replayGainAlbum ?? this.replayGainAlbum,
      dateAddedMs: dateAddedMs ?? this.dateAddedMs,
    );
  }

  bool get isHiRes => bitDepth >= 24 || sampleRateHz >= 96000;

  String get qualityLabel {
    if (bitDepth == 0 || sampleRateHz == 0) {
      return mimeType.isNotEmpty ? mimeType : fileExtension.toUpperCase();
    }
    return '${bitDepth}bit/${(sampleRateHz / 1000).toStringAsFixed(1)}kHz';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Track && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  Map<String, dynamic> toJson() => {
        'id': id,
        'uri': uri,
        'title': title,
        'artist': artist,
        'albumArtist': albumArtist,
        'album': album,
        'genre': genre,
        'trackNumber': trackNumber,
        'discNumber': discNumber,
        'year': year,
        'durationMs': durationMs,
        'sizeBytes': sizeBytes,
        'bitrateKbps': bitrateKbps,
        'sampleRateHz': sampleRateHz,
        'bitDepth': bitDepth,
        'mimeType': mimeType,
        'fileExtension': fileExtension,
        'filePath': filePath,
        'artUri': artUri,
        'mediaStoreId': mediaStoreId,
        'replayGainTrack': replayGainTrack,
        'replayGainAlbum': replayGainAlbum,
        'dateAddedMs': dateAddedMs,
      };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        uri: json['uri'] as String,
        title: json['title'] as String,
        artist: (json['artist'] as String?) ?? '',
        albumArtist: (json['albumArtist'] as String?) ?? '',
        album: (json['album'] as String?) ?? '',
        genre: (json['genre'] as String?) ?? '',
        trackNumber: (json['trackNumber'] as num?)?.toInt() ?? 0,
        discNumber: (json['discNumber'] as num?)?.toInt() ?? 0,
        year: (json['year'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        bitrateKbps: (json['bitrateKbps'] as num?)?.toInt() ?? 0,
        sampleRateHz: (json['sampleRateHz'] as num?)?.toInt() ?? 0,
        bitDepth: (json['bitDepth'] as num?)?.toInt() ?? 0,
        mimeType: (json['mimeType'] as String?) ?? '',
        fileExtension: (json['fileExtension'] as String?) ?? '',
        filePath: (json['filePath'] as String?) ?? '',
        artUri: (json['artUri'] as String?) ?? '',
        mediaStoreId: (json['mediaStoreId'] as num?)?.toInt(),
        replayGainTrack: (json['replayGainTrack'] as num?)?.toDouble(),
        replayGainAlbum: (json['replayGainAlbum'] as num?)?.toDouble(),
        dateAddedMs: (json['dateAddedMs'] as num?)?.toInt() ?? 0,
      );

  @override
  String toString() => 'Track(${artist.isNotEmpty ? '$artist - ' : ''}$title)';
}