// ============================================================================
//  equalizer_service.dart - 5-band EQ state holder (UI-side)
//
//  Stores band gains in SharedPreferences. VisualizerService-style: this is
//  the source of truth for the UI. Actual audio processing happens via
//  just_audio's AndroidEqualizer when the player is initialized — see
//  EqualizerBindingWidget which subscribes to this service and pushes gains
//  to the live player.
// ============================================================================
import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

const kEqBandCount = 5;
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

  @override
  Future<void> setBandGain(int bandIndex, double gainDb) async {
    if (bandIndex < 0 || bandIndex >= kEqBandCount) return;
    _bands[bandIndex] = gainDb.clamp(-15.0, 15.0);
    _bandsController.add(List.unmodifiable(_bands));
    await _save();
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    _enabledController.add(_enabled);
    await _save();
  }

  @override
  Future<void> reset() async {
    _bands = List.filled(kEqBandCount, 0.0);
    _broadcast();
    await _save();
  }

  void dispose() {
    _bandsController.close();
    _enabledController.close();
  }
}

class EqPreset {
  const EqPreset(this.name, this.gains);
  final String name;
  final List<double> gains;
  static const flat = EqPreset('Flat', [0, 0, 0, 0, 0]);
  static const bass = EqPreset('Bass', [10, 6, 0, 0, 0]);
  static const treble = EqPreset('Treble', [0, 0, 0, 6, 10]);
  static const vocal = EqPreset('Vocal', [-3, 0, 6, 4, -2]);
  static const rock = EqPreset('Rock', [5, 3, -1, 3, 5]);
  static const pop = EqPreset('Pop', [-1, 2, 5, 2, -1]);
  static const all = [flat, bass, treble, vocal, rock, pop];
}