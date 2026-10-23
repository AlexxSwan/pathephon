// ============================================================================
//  visualizer_service.dart - bridge to native Android Visualizer AudioEffect
//
//  Requests RECORD_AUDIO permission (required on Android 14+) before
//  attaching to the audio session. Streams stereo RMS amplitudes.
// ============================================================================
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class StereoAmplitude {
  const StereoAmplitude(this.left, this.right);
  final double left;
  final double right;
  @override
  String toString() => 'Stereo(L=$left, R=$right)';
}

class VisualizerService {
  static const _method = MethodChannel('pathephon/visualizer');
  static const _events = EventChannel('pathephon/visualizer/events');

  StreamSubscription? _eventSub;
  final _controller = StreamController<StereoAmplitude>.broadcast();

  int? _activeSessionId;
  bool _permissionGranted = false;
  bool _permissionRequested = false;

  Stream<StereoAmplitude> get amplitudes => _controller.stream;

  Future<bool> _ensurePermission() async {
    if (_permissionGranted) return true;
    if (!_permissionRequested) {
      _permissionRequested = true;
      try {
        final status = await Permission.recordAudio.request();
        _permissionGranted = status.isGranted;
        debugPrint('[pathephon] RECORD_AUDIO permission: $status');
      } catch (e) {
        debugPrint('[pathephon] permission request failed: $e');
        _permissionGranted = false;
      }
    }
    return _permissionGranted;
  }

  Future<void> attach(int? sessionId) async {
    if (sessionId == null || sessionId == 0) {
      await detach();
      return;
    }
    if (sessionId == _activeSessionId) return;

    final granted = await _ensurePermission();
    if (!granted) {
      debugPrint('[pathephon] visualizer: RECORD_AUDIO denied, cannot capture audio');
      return;
    }

    _activeSessionId = sessionId;
    try {
      _eventSub ??= _events.receiveBroadcastStream().listen(
        (data) {
          if (data is List && data.length == 2) {
            final l = (data[0] as num).toDouble();
            final r = (data[1] as num).toDouble();
            _controller.add(StereoAmplitude(l, r));
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
    _controller.add(const StereoAmplitude(0, 0));
  }

  void dispose() {
    _eventSub?.cancel();
    _eventSub = null;
    _controller.close();
  }
}