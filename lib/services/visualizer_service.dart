// ============================================================================
//  visualizer_service.dart - PPM with proper dB-domain peak hold/decay
//
//  Receives peak in dBFS (-60..0) from native Visualizer.
//  Implements BBC PPM integration:
//    - Attack: 10ms to reach peak (instant for our 50ms capture rate)
//    - Hold: 1 second at peak
//    - Decay: 12 dB per second after hold
//  Output: stream of double in dBFS, mapped later to needle position.
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

  // PPM state in dBFS
  double _peakDb = -60.0;        // current displayed peak (after decay)
  DateTime _lastPeakTime = DateTime.now();
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
    _peakDb = -60.0;
    _lastPeakTime = DateTime.now();
    try {
      _eventSub ??= _events.receiveBroadcastStream().listen(
        (data) {
          if (data is num) {
            final rawDb = data.toDouble().clamp(-60.0, 0.0);
            // Attack: instant — if new peak is louder, jump up immediately.
            if (rawDb > _peakDb) {
              _peakDb = rawDb;
              _lastPeakTime = DateTime.now();
            } else if (rawDb > _peakDb - 1.0) {
              // Hold refresh: if peak is within 1 dB, refresh hold time
              _lastPeakTime = DateTime.now();
            }
            _controller.add(_peakDb);
          }
        },
        onError: (Object e) => debugPrint('[pathephon] PPM event error: $e'),
      );
      await _method.invokeMethod('start', {'sessionId': sessionId});
      debugPrint('[pathephon] PPM attached to session $sessionId');

      // Decay timer: every 50ms, decrease peak if hold expired.
      // BBC PPM: ~12 dB/sec decay = 0.6 dB per 50ms.
      _decayTimer?.cancel();
      _decayTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        final holdElapsed = DateTime.now().difference(_lastPeakTime).inMilliseconds;
        if (holdElapsed > 1000 && _peakDb > -60.0) {
          _peakDb -= 0.6;  // 12 dB/sec
          if (_peakDb < -60.0) _peakDb = -60.0;
          _controller.add(_peakDb);
        }
      });
    } catch (e) {
      debugPrint('[pathephon] PPM start failed (non-fatal): $e');
    }
  }

  Future<void> detach() async {
    if (_activeSessionId == null) return;
    _activeSessionId = null;
    _peakDb = -60.0;
    _decayTimer?.cancel();
    _decayTimer = null;
    try {
      await _method.invokeMethod('stop');
    } catch (e) {
      debugPrint('[pathephon] PPM stop failed (non-fatal): $e');
    }
    _controller.add(-60.0);
  }

  void dispose() {
    _eventSub?.cancel();
    _eventSub = null;
    _decayTimer?.cancel();
    _decayTimer = null;
    _controller.close();
  }
}