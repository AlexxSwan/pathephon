// ============================================================================
//  media_session_service.dart - native MediaSession bridge
//
//  Replaces audio_service. Uses native Kotlin MediaSessionHelper for:
//  - Lock screen widget
//  - Headset button events (play/pause/next/prev)
//  - Bluetooth media buttons
//  - Notification with transport controls
// ============================================================================
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

class MediaSessionService {
  static const _method = MethodChannel('pathephon/media_session');
  static const _events = EventChannel('pathephon/media_session/events');

  StreamSubscription? _eventSub;
  final _controller = StreamController<String>.broadcast();
  bool _started = false;

  /// Stream of media button events: "play", "pause", "next", "prev", "stop"
  Stream<String> get events => _controller.stream;

  /// Start the MediaSession. Call once when playback begins.
  Future<void> start() async {
    if (_started) return;
    try {
      _eventSub ??= _events.receiveBroadcastStream().listen(
        (data) {
          if (data is String) {
            debugPrint('[pathephon] MediaSession event: $data');
            _controller.add(data);
          }
        },
        onError: (e) => debugPrint('[pathephon] MediaSession event error: $e'),
      );
      await _method.invokeMethod('start');
      _started = true;
      debugPrint('[pathephon] MediaSession started');
    } catch (e) {
      debugPrint('[pathephon] MediaSession start failed: $e');
    }
  }

  /// Update metadata (title, artist, album) for lock screen display.
  Future<void> updateMetadata({
    required String title,
    required String artist,
    required String album,
    required int durationMs,
  }) async {
    if (!_started) return;
    try {
      await _method.invokeMethod('updateMetadata', {
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': durationMs,
      });
    } catch (e) {
      debugPrint('[pathephon] MediaSession updateMetadata failed: $e');
    }
  }

  /// Update playback state for lock screen controls.
  /// state: "playing", "paused", "stopped"
  Future<void> updatePlaybackState({
    required String state,
    required int positionMs,
  }) async {
    if (!_started) return;
    try {
      await _method.invokeMethod('updatePlaybackState', {
        'state': state,
        'positionMs': positionMs,
      });
    } catch (e) {
      debugPrint('[pathephon] MediaSession updatePlaybackState failed: $e');
    }
  }

  /// Stop the MediaSession and remove notification.
  Future<void> stop() async {
    if (!_started) return;
    try {
      await _method.invokeMethod('stop');
      _started = false;
    } catch (e) {
      debugPrint('[pathephon] MediaSession stop failed: $e');
    }
  }

  void dispose() {
    _eventSub?.cancel();
    _eventSub = null;
    _controller.close();
  }
}