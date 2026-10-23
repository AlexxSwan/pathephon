// ============================================================================
//  visualizer_service.dart - bridge to native Android Visualizer AudioEffect
//
//  Captures real waveform data from the audio output (via the audio session
//  id just_audio exposes) and streams per-channel RMS amplitudes.
//  Falls back to (0, 0) when native plugin unavailable or session id not yet
//  known.
// ============================================================================
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

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

  Stream<StereoAmplitude> get amplitudes => _controller.stream;

  /// Start visualizing the given audio session id.
  /// Pass null to stop. Idempotent: if the same id is already active, no-op.
  Future<void> attach(int? sessionId) async {
    if (sessionId == null || sessionId == 0) {
      await detach();
      return;
    }
    if (sessionId == _activeSessionId) return;
    _activeSessionId = sessionId;

    try {
      // Subscribe before starting so we don't miss the first event.
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