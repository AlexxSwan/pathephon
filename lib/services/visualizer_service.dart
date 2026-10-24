// ============================================================================
//  visualizer_service.dart - FFT spectrum analyzer
//  Streams List<double> of 32 frequency bin magnitudes (0..255).
// ============================================================================
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class SpectrumData {
  const SpectrumData(this.bins);
  final List<double> bins; // 32 bins, each 0..255
}

class VisualizerService {
  static const _method = MethodChannel('pathephon/visualizer');
  static const _events = EventChannel('pathephon/visualizer/events');

  StreamSubscription? _eventSub;
  final _controller = StreamController<SpectrumData>.broadcast();

  int? _activeSessionId;
  bool _permissionGranted = false;
  bool _permissionRequested = false;

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
    try {
      _eventSub ??= _events.receiveBroadcastStream().listen(
        (data) {
          if (data is List) {
            final bins = data.map((e) => (e as num).toDouble()).toList();
            _controller.add(SpectrumData(bins));
          }
        },
        onError: (Object e) => debugPrint('[pathephon] visualizer event error: $e'),
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
    _controller.add(const SpectrumData(<double>[]));
  }

  void dispose() {
    _eventSub?.cancel();
    _eventSub = null;
    _controller.close();
  }
}