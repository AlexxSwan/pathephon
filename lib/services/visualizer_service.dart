// ============================================================================
//  visualizer_service.dart - PPM bridge with peak hold + decay
//
//  PPM behavior:
//   - Attack: instant (peak caught immediately)
//   - Hold: 1 second at peak level
//   - Decay: 12 dB per second (smooth fall after hold)
//  This produces the characteristic PPM needle movement: fast up, slow down.
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

  // PPM state
  double _peak = 0;           // current displayed peak (with decay)
  double _rawPeak = 0;        // last raw peak from Visualizer
  DateTime _lastPeakTime = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _decayTimer;

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
      debugPrint('[pathephon] PPM: microphone permission denied');
      return;
    }

    _activeSessionId = sessionId;
    _peak = 0;
    _rawPeak = 0;
    try {
      _eventSub ??= _events.receiveBroadcastStream().listen(
        (data) {
          if (data is num) {
            final rawPeak = data.toDouble();
            _rawPeak = rawPeak;
            // Attack: instant. If new peak is higher, jump up immediately.
            if (rawPeak > _peak) {
              _peak = rawPeak;
              _lastPeakTime = DateTime.now();
            } else if (rawPeak >= _peak * 0.95) {
              // Hold: refresh hold time if peak is sustained
              _lastPeakTime = DateTime.now();
            }
            _controller.add(_peak);
          }
        },
        onError: (e) => debugPrint('[pathephon] PPM event error: $e'),
      );
      await _method.invokeMethod('start', {'sessionId': sessionId});
      debugPrint('[pathephon] PPM attached to session $sessionId');

      // Decay timer: every 50ms, decrease peak if hold time expired
      _decayTimer?.cancel();
      _decayTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        final now = DateTime.now();
        final holdElapsed = now.difference(_lastPeakTime).inMilliseconds;
        if (holdElapsed > 1000 && _peak > 0) {
          // Decay: ~12 dB/sec. In linear: factor of ~4 per second,
          // so per 50ms: ~0.97 multiplier (slow exponential decay).
          _peak *= 0.97;
          if (_peak < 0.005) _peak = 0;
          _controller.add(_peak);
        }
      });
    } catch (e) {
      debugPrint('[pathephon] PPM start failed (non-fatal): $e');
    }
  }

  Future<void> detach() async {
    if (_activeSessionId == null) return;
    _activeSessionId = null;
    _peak = 0;
    _rawPeak = 0;
    _decayTimer?.cancel();
    _decayTimer = null;
    try {
      await _method.invokeMethod('stop');
    } catch (e) {
      debugPrint('[pathephon] PPM stop failed (non-fatal): $e');
    }
    _controller.add(0);
  }

  void dispose() {
    _eventSub?.cancel();
    _eventSub = null;
    _decayTimer?.cancel();
    _decayTimer = null;
    _controller.close();
  }
}