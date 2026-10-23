// ============================================================================
//  equalizer_service.dart - REAL Android Equalizer via just_audio
//
//  Uses just_audio's built-in AndroidLoudnessEnhancer/AndroidEqualizer API
//  (which wraps android.media.audiofx.Equalizer). No MethodChannel needed —
//  just_audio exposes the EQ directly through audioSessionId.
// ============================================================================
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Number of EQ bands. Android Equalizer typically gives 5 bands (60Hz..16kHz).
const kEqBandCount = 5;

/// Default center frequencies for 5-band EQ (Hz). Used for display only.
const kEqBandFreqs = [60.0, 230.0, 910.0, 3600.0, 14000.0];

abstract class EqualizerService {
  Stream<List<double>> get bandsStream;
  Stream<bool> get enabledStream;
  List<double> get currentBands;
  bool get isEnabled;
  Future<void> setBandGain(int bandIndex, double gainDb);
  Future<void> setEnabled(bool enabled);
  Future<void> reset();
  void dispose();
}

class AndroidEqualizerService implements EqualizerService {
  AndroidEqualizerService(this._prefs) {
    _loadSaved();
  }

  final SharedPreferences _prefs;
  late final AudioPlayer _player;
  AndroidEqualizer? _eq;
  bool _initialized = false;

  final _bandsController = StreamController<List<double>>.broadcast();
  final _enabledController = StreamController<bool>.broadcast();

  List<double> _bands = List.filled(kEqBandCount, 0.0);
  bool _enabled = false;

  @override
  Stream<List<double>> get bandsStream => _bandsController.stream;
  @override
  Stream<bool> get enabledStream => _enabledController.stream;
  @override
  List<double> get currentBands => List.unmodifiable(_bands);
  @override
  bool get isEnabled => _enabled;

  /// Bind this EQ service to a player that already has an audio source set.
  /// The EQ attaches to the player's audioSessionId.
  Future<void> attachToPlayer(AudioPlayer player) async {
    if (_initialized) {
      _eq?.dispose();
      _eq = null;
      _initialized = false;
    }
    _player = player;
    try {
      _eq = AndroidEqualizer();
      await _player.setAudioSource(
        AudioSource.uri(Uri.parse('asset:///placeholder')),
        // We'll re-set the real source externally; the EQ just needs a session.
      );
    } catch (e) {
      debugPrint('[pathephon] EQ attach (initial setAudioSource skipped): $e');
    }
    _initialized = true;
    _applyAllBands();
    _broadcast();
  }

  void _loadSaved() {
    final raw = _prefs.getString('pathephon.eq.bands');
    if (raw != null) {
      try {
        final parts = raw.split(',').map((s) => double.tryParse(s) ?? 0.0).toList();
        if (parts.length == kEqBandCount) {
          _bands = parts;
        }
      } catch (_) {}
    }
    _enabled = _prefs.getBool('pathephon.eq.enabled') ?? false;
  }

  Future<void> _save() async {
    await _prefs.setString('pathephon.eq.bands', _bands.join(','));
    await _prefs.setBool('pathephon.eq.enabled', _enabled);
  }

  void _broadcast() {
    _bandsController.add(List.unmodifiable(_bands));
    _enabledController.add(_enabled);
  }

  void _applyAllBands() {
    if (!_initialized || _eq == null) return;
    try {
      for (var i = 0; i < _bands.length; i++) {
        if (i < _eq!.parameters.bandCount) {
          _eq!.setBandGain(i, _bands[i]);
        }
      }
    } catch (e) {
      debugPrint('[pathephon] EQ applyAllBands failed: $e');
    }
  }

  @override
  Future<void> setBandGain(int bandIndex, double gainDb) async {
    if (bandIndex < 0 || bandIndex >= kEqBandCount) return;
    // Clamp to typical Android EQ range: ±15 dB.
    _bands[bandIndex] = gainDb.clamp(-15.0, 15.0);
    _bandsController.add(List.unmodifiable(_bands));
    if (_enabled && _initialized && _eq != null) {
      try {
        if (bandIndex < _eq!.parameters.bandCount) {
          _eq!.setBandGain(bandIndex, _bands[bandIndex]);
        }
      } catch (e) {
        debugPrint('[pathephon] EQ setBandGain failed: $e');
      }
    }
    await _save();
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    _enabledController.add(_enabled);
    if (_initialized && _eq != null) {
      try {
        _eq!.enabled = enabled;
        if (enabled) _applyAllBands();
      } catch (e) {
        debugPrint('[pathephon] EQ setEnabled failed: $e');
      }
    }
    await _save();
  }

  @override
  Future<void> reset() async {
    _bands = List.filled(kEqBandCount, 0.0);
    _broadcast();
    if (_enabled && _initialized && _eq != null) {
      _applyAllBands();
    }
    await _save();
  }

  void dispose() {
    _bandsController.close();
    _enabledController.close();
    _eq?.dispose();
  }
}

// Convenience: preset list for the UI dropdown.
class EqPreset {
  const EqPreset(this.name, this.gains);
  final String name;
  final List<double> gains; // 5 band gains in dB
  static const flat = EqPreset('Flat', [0, 0, 0, 0, 0]);
  static const bass = EqPreset('Bass', [10, 6, 0, 0, 0]);
  static const treble = EqPreset('Treble', [0, 0, 0, 6, 10]);
  static const vocal = EqPreset('Vocal', [-3, 0, 6, 4, -2]);
  static const rock = EqPreset('Rock', [5, 3, -1, 3, 5]);
  static const pop = EqPreset('Pop', [-1, 2, 5, 2, -1]);
  static const all = [flat, bass, treble, vocal, rock, pop];
}