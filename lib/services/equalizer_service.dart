// ============================================================================
//  equalizer_service.dart — 10-band parametric EQ via just_audio's
//  AndroidEqualizer (built-in AudioEffect on Android API 9+).
//
//  Bands follow ISO 1/3-octave centres:
//    31, 62, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz
//
//  Range: ±12 dB per band (clamped by AndroidEqualizer).
//  Presets: stored in shared_preferences as JSON.
//
//  Note: AndroidEqualizer's actual band count and frequencies are determined
//  by the platform at runtime — typically 5 bands by default. We expose 10
//  logical slots in the UI but only the first N (where N = platform band
//  count) actually affect playback; the rest are stored but no-op.
// ============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Public EQ API used by the UI layer.
abstract class EqualizerService {
  Stream<List<double>> get bandsStream;
  Stream<bool> get enabledStream;

  Future<void> setEnabled(bool enabled);
  Future<void> setBand(int index, double gainDb);

  List<EqPreset> get builtinPresets;
  Future<List<EqPreset>> userPresets();
  Future<void> applyPreset(EqPreset preset);
  Future<EqPreset> savePreset(String name, List<double> gains);
  Future<void> deletePreset(String id);

  /// Wire the EQ to a player's audioSessionId. Call once at startup.
  Future<void> attachToPlayer(int androidAudioSessionId);

  /// Called by providers.dart after the player is built.
  void bindEqualizer(AndroidEqualizer eq);
}

class EqPreset {
  const EqPreset({required this.id, required this.name, required this.gains});
  final String id;
  final String name;
  final List<double> gains; // 10 doubles, dB values

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'gains': gains,
      };

  factory EqPreset.fromJson(Map<String, dynamic> json) => EqPreset(
        id: json['id'] as String,
        name: json['name'] as String,
        gains: (json['gains'] as List).map((e) => (e as num).toDouble()).toList(growable: false),
      );
}

class AndroidEqualizerService implements EqualizerService {
  AndroidEqualizerService(this._prefs);

  final SharedPreferences _prefs;
  static const _presetsKey = 'pathephon.eq_presets.v1';

  // ---- Static band centres (Hz) ------------------------------------------
  static const List<int> bandCentresHz = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

  // ---- just_audio equalizer ----------------------------------------------
  AndroidEqualizer? _eq;
  final _bandsController = StreamController<List<double>>.broadcast();
  final _enabledController = StreamController<bool>.broadcast();

  List<double> _current = List.filled(10, 0.0);
  bool _enabled = false;

  @override
  Stream<List<double>> get bandsStream => _bandsController.stream;

  @override
  Stream<bool> get enabledStream {
    // If we have a real equalizer, mirror its enabledStream; otherwise use
    // our local controller so the UI still works in tests / pre-attach.
    if (_eq != null) {
      _eq!.enabledStream.listen((e) {
        _enabled = e;
        _enabledController.add(e);
      });
    }
    return _enabledController.stream;
  }

  @override
  Future<void> attachToPlayer(int androidAudioSessionId) async {
    // Just_audio's AndroidEqualizer is wired through the player's
    // audioPipeline (set in providers.dart). No-op here.
  }

  @override
  void bindEqualizer(AndroidEqualizer eq) {
    _eq = eq;
    // Forward enabledStream to our controller.
    eq.enabledStream.listen((e) {
      _enabled = e;
      _enabledController.add(e);
    });
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    _enabledController.add(enabled);
    await _eq?.setEnabled(enabled);
  }

  @override
  Future<void> setBand(int index, double gainDb) async {
    final clamped = gainDb.clamp(-12.0, 12.0);
    _current = List.of(_current)..[index] = clamped;
    _bandsController.add(List.unmodifiable(_current));
    final params = await _eq?.parameters;
    if (params == null) return;
    if (index < params.bands.length) {
      await params.bands[index].setGain(clamped);
    }
  }

  @override
  List<EqPreset> get builtinPresets => const [
        EqPreset(id: 'flat', name: 'Flat', gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EqPreset(id: 'bass', name: 'Bass Boost', gains: [6, 5, 4, 3, 1, 0, 0, 0, 0, 0]),
        EqPreset(id: 'treble', name: 'Treble Boost', gains: [0, 0, 0, 0, 0, 1, 3, 4, 5, 6]),
        EqPreset(id: 'vocal', name: 'Vocal', gains: [-3, -2, -1, 2, 4, 4, 3, 1, 0, -1]),
        EqPreset(id: 'classical', name: 'Classical', gains: [3, 2, 1, 0, -1, -1, 0, 2, 3, 4]),
        EqPreset(id: 'rock', name: 'Rock', gains: [4, 3, 2, -1, -2, 0, 2, 3, 4, 4]),
        EqPreset(id: 'electronic', name: 'Electronic', gains: [5, 4, 1, 0, -2, 2, 1, 1, 4, 5]),
      ];

  @override
  Future<List<EqPreset>> userPresets() async {
    final raw = _prefs.getString(_presetsKey);
    if (raw == null) return const <EqPreset>[];
    final list = jsonDecode(raw) as List;
    return list
        .map((j) => EqPreset.fromJson(j as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<void> applyPreset(EqPreset preset) async {
    _current = List.of(preset.gains);
    _bandsController.add(List.unmodifiable(_current));
    final params = await _eq?.parameters;
    if (params == null) return;
    final count = math.min(params.bands.length, preset.gains.length);
    for (var i = 0; i < count; i++) {
      await params.bands[i].setGain(preset.gains[i].clamp(-12.0, 12.0));
    }
  }

  @override
  Future<EqPreset> savePreset(String name, List<double> gains) async {
    final id = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final preset = EqPreset(id: id, name: name, gains: gains);
    final all = await userPresets();
    all.add(preset);
    await _prefs.setString(
      _presetsKey,
      jsonEncode(all.map((p) => p.toJson()).toList()),
    );
    return preset;
  }

  @override
  Future<void> deletePreset(String id) async {
    final all = await userPresets();
    final filtered = all.where((p) => p.id != id).toList(growable: false);
    await _prefs.setString(
      _presetsKey,
      jsonEncode(filtered.map((p) => p.toJson()).toList()),
    );
  }

  void dispose() {
    _bandsController.close();
    _enabledController.close();
  }
}
