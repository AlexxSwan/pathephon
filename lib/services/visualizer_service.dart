// ============================================================================
//  visualizer_service.dart - FFT spectrum with temporal smoothing
// ============================================================================
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class SpectrumData {
  const SpectrumData(this.bins);
  final List<double> bins;
}

class VisualizerService {
  static const _method = MethodChannel('pathephon/visualizer');
  static const _events = EventChannel('pathephon/visualizer/events');

  StreamSubscription? _eventSub;
  final _controller = StreamController<SpectrumData>.broadcast();

  int? _activeSessionId;
  bool _permissionGranted = false;
  bool _permissionRequested = false;

  // Smoothing: each bin eases toward its target value
  final List<double> _smoothed = List.filled(32, 0.0);

  Stream<SpectrumData> get spectrum => _controller.stream;

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
      } catch (e) {
        _permissionGranted = false;
      }
    }
    return _permissionGranted;
  }

  Future<void> attach(int? sessionId) async {
    if (sessionId == null || sessionId == 0) return;
    if (sessionId == _activeSessionId) return;

    final granted = await _ensurePermission();
    if (!granted) return;

    _activeSessionId = sessionId;
    for (var i = 0; i < _smoothed.length; i++) {
      _smoothed[i] = 0.0;
    }
    try {
      _eventSub ??= _events.receiveBroadcastStream().listen(
        (data) {
          if (data is List) {
            final raw = data.map((e) => (e as num).toDouble()).toList();
            // Exponential smoothing: each bin eases toward target
            // factor 0.3 = smooth but responsive
            for (var i = 0; i < _smoothed.length && i < raw.length; i++) {
              _smoothed[i] += (raw[i] - _smoothed[i]) * 0.3;
            }
            _controller.add(SpectrumData(List.from(_smoothed)));
          }
        },
        onError: (Object e) => debugPrint('[pathephon] visualizer error: $e'),
      );
      await _method.invokeMethod('start', {'sessionId': sessionId});
    } catch (e) {
      debugPrint('[pathephon] visualizer start failed: $e');
    }
  }

  Future<void> detach() async {
    if (_activeSessionId == null) return;
    _activeSessionId = null;
    try {
      await _method.invokeMethod('stop');
    } catch (_) {}
    _controller.add(const SpectrumData(<double>[]));
  }

  void dispose() {
    _eventSub?.cancel();
    _eventSub = null;
    _controller.close();
  }
}