// ============================================================================
//  visualizer_service.dart - bridge to native Android Visualizer AudioEffect
//
//  Attaches ONLY to the player's audio session (never session 0 / global mix).
//  Logs heartbeat every 2s so we can verify events are flowing.
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

  double _smoothedL = 0;
  double _smoothedR = 0;
  static const _smoothFactor = 0.25;

  int _eventCount = 0;
  Timer? _heartbeatTimer;

  Stream<StereoAmplitude> get amplitudes => _controller.stream;

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
        if (!_permissionGranted) {
          debugPrint('[pathephon] microphone denied — VU will stay at 0. '
              'User can enable in Settings -> Apps -> Pathephon -> Microphone');
        }
      } catch (e) {
        debugPrint('[pathephon] permission request failed: $e');
        _permissionGranted = false;
      }
    }
    return _permissionGranted;
  }

  Future<void> attach(int? sessionId) async {
    if (sessionId == null || sessionId == 0) {
      // Don't detach if we already have an active session — androidAudioSessionIdStream
      // can emit 0 transiently. Only detach on explicit null.
      debugPrint('[pathephon] visualizer: sessionId is null/0, ignoring (waiting for real id)';
      return;
    }
    if (sessionId == _activeSessionId) return;

    final granted = await _ensurePermission();
    if (!granted) {
      debugPrint('[pathephon] visualizer: microphone permission denied, no VU data');
      return;
    }

    _activeSessionId = sessionId;
    _eventCount = 0;
    try {
      _eventSub ??= _events.receiveBroadcastStream().listen(
        (data) {
          if (data is List && data.length == 2) {
            _eventCount++;
            final rawL = (data[0] as num).toDouble();
            final rawR = (data[1] as num).toDouble();
            _smoothedL += (rawL - _smoothedL) * _smoothFactor;
            _smoothedR += (rawR - _smoothedR) * _smoothFactor;
            _controller.add(StereoAmplitude(_smoothedL, _smoothedR));
          }
        },
        onError: (e) => debugPrint('[pathephon] visualizer event error: $e'),
      );
      await _method.invokeMethod('start', {'sessionId': sessionId});
      debugPrint('[pathephon] visualizer attached to player session $sessionId');

      // Heartbeat: log every 2s whether events are flowing.
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        debugPrint('[pathephon] visualizer heartbeat: $_eventCount events received so far');
      });
    } catch (e) {
      debugPrint('[pathephon] visualizer start failed (non-fatal): $e');
    }
  }

  Future<void> detach() async {
    if (_activeSessionId == null) return;
    _activeSessionId = null;
    _smoothedL = 0;
    _smoothedR = 0;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
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
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _controller.close();
  }
}