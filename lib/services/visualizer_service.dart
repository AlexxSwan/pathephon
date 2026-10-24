// ============================================================================
//  visualizer_service.dart - REAL Android Visualizer AudioEffect
//
//  Attaches to the player's audio session id (just_audio exposes it).
//  Streams real RMS amplitude 0..1 captured from the audio output.
//  Requires RECORD_AUDIO permission on Android 14+.
// ============================================================================
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class VisualizerService {
  static const _method = MethodChannel('pathephon/visualizer');
  static const _events = EventChannel('pathephon/visualizer/events');

  StreamSubscription? _eventSub;
  final _controller = StreamController<double>.broadcast();

  int? _activeSessionId;
  bool _permissionGranted = false;
  bool _permissionRequested = false;
  int _eventCount = 0;

  Stream<double> get amplitudes => _controller.stream;

  Future<bool> _ensurePermission() async {
    if (_permissionGranted) return true;
    if (!_permissionRequested) {
      _permissionRequested = true;
      try {
        var status = await Permission.microphone.status;
        if (!status.isGranted) {
          status = await Permission.microphone.request();
        }
        _permissionGranted = status.isGranted;
        debugPrint('[pathephon] microphone permission: $status (granted=$_permissionGranted)');
      } catch (e) {
        debugPrint('[pathephon] permission request failed: $e');
        _permissionGranted = false;
      }
    }
    return _permissionGranted;
  }

  Future<void> attach(int? sessionId) async {
    if (sessionId == null || sessionId == 0) return;
    if (sessionId == _activeSessionId) return;

    final granted = await _ensurePermission();
    if (!granted) {
      debugPrint('[pathephon] visualizer: microphone permission denied');
      return;
    }

    _activeSessionId = sessionId;
    _eventCount = 0;
    try {
      _eventSub ??= _events.receiveBroadcastStream().listen(
        (data) {
          if (data is num) {
            _eventCount++;
            final amp = data.toDouble();
            if (_eventCount % 100 == 1) {
              debugPrint('[pathephon] visualizer event #$_eventCount: amp=$amp');
            }
            _controller.add(amp);
          }
        },
        onError: (e) => debugPrint('[pathephon] visualizer event error: $e'),
      );
      await _method.invokeMethod('start', {'sessionId': sessionId});
      debugPrint('[pathephon] visualizer attached to session $sessionId');
    } catch (e) {
      debugPrint('[pathephon] visualizer start failed (non-fatal): $e');
    }
  }

  Future<void> detach() async {
    if (_activeSessionId == null) return;
    _activeSessionId = null;
    try {
      await _method.invokeMethod('stop');
    } catch (e) {
      debugPrint('[pathephon] visualizer stop failed (non-fatal): $e');
    }
    _controller.add(0);
  }

  void dispose() {
    _eventSub?.cancel();
    _eventSub = null;
    _controller.close();
  }
}