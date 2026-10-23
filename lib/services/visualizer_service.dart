// ============================================================================
//  visualizer_service.dart - bridge to native Android Visualizer AudioEffect
//
//  Adds exponential smoothing (attack/release) so the VU needle swings
//  naturally without jitter. Real Visualizer values come in 0..0.85 range.
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

  // Smoothing state — exponential moving average per channel.
  double _smoothedL = 0;
  double _smoothedR = 0;
  // Smoothing factor: 0.2 = slow attack/release (looks natural on vintage VU).
  static const _smoothFactor = 0.2;

  Stream<StereoAmplitude> get amplitudes => _controller.stream;

  Future<bool> _ensurePermission() async {
    if (_permissionGranted) return true;
    if (!_permissionRequested) {
      _permissionRequested = true;
      try {
        final status = await Permission.microphone.request();
        _permissionGranted = status.isGranted;
        debugPrint('[pathephon] microphone permission: $status');
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
      debugPrint('[pathephon] visualizer: microphone permission denied, no VU data');
      return;
    }

    _activeSessionId = sessionId;
    try {
      _eventSub ??= _events.receiveBroadcastStream().listen(
        (data) {
          if (data is List && data.length == 2) {
            final rawL = (data[0] as num).toDouble();
            final rawR = (data[1] as num).toDouble();
            // Exponential smoothing — natural VU needle behavior.
            _smoothedL += (rawL - _smoothedL) * _smoothFactor;
            _smoothedR += (rawR - _smoothedR) * _smoothFactor;
            _controller.add(StereoAmplitude(_smoothedL, _smoothedR));
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
    _smoothedL = 0;
    _smoothedR = 0;
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