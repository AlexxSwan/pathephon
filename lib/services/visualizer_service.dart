// ============================================================================
//  visualizer_service.dart - PPM with strict peak hold/decay
//
//  Hold: only refresh if rawDb >= peakDb (peak must actually reach current level)
//  Decay: 12 dB/sec after 1 second hold
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
  double _peakDb = -60.0;
  DateTime _lastPeakTime = DateTime.now();
  Timer? _decayTimer;
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
      debugPrint('[pathephon] PPM: microphone permission denied');
      return;
    }

    _activeSessionId = sessionId;
    _peakDb = -60.0;
    _lastPeakTime = DateTime.now();
    _eventCount = 0;
    try {
      _eventSub ??= _events.receiveBroadcastStream().listen(
        (data) {
          if (data is num) {
            final rawDb = data.toDouble().clamp(-60.0, 0.0);
            _eventCount++;
            if (_eventCount % 100 == 1) {
              debugPrint('[pathephon] PPM event #$_eventCount: raw=$rawDb dBFS, peak=$_peakDb dBFS');
            }
            // Attack: instant — if new peak is louder OR equal, jump up.
            if (rawDb >= _peakDb) {
              _peakDb = rawDb;
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
      // 12 dB/sec = 0.6 dB per 50ms.
      _decayTimer?.cancel();
      _decayTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        final holdElapsed = DateTime.now().difference(_lastPeakTime).inMilliseconds;
        if (holdElapsed > 1000 && _peakDb > -60.0) {
          _peakDb -= 0.6;
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