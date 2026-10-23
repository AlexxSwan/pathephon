// ============================================================================
//  equalizer_screen.dart - 5-band EQ with REAL audio processing
//  Hooks EQ to playback's audioSessionId (via visualizer service pattern).
//  Local state for instant slider response, synced to native EQ.
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tube_colors.dart';
import '../providers/providers.dart';
import '../../services/equalizer_service.dart';

class EqualizerScreen extends ConsumerStatefulWidget {
  const EqualizerScreen({super.key});

  @override
  ConsumerState<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends ConsumerState<EqualizerScreen> {
  late List<double> _bands;
  late bool _enabled;
  EqPreset? _selectedPreset;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final eq = ref.read(equalizerServiceProvider);
      _bands = List.from(eq.currentBands);
      _enabled = eq.isEnabled;
      _initialized = true;
      // Hook EQ to the player's audio session id stream.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final playback = ref.read(playbackServiceProvider);
        playback.audioSessionIdStream.listen((sessionId) {
          eq.attachToSession(sessionId);
        });
      });
    }
  }

  String _freqLabel(double hz) {
    if (hz >= 1000) {
      return '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}k';
    }
    return hz.toStringAsFixed(0);
  }

  Future<void> _onBandChanged(int i, double v) async {
    setState(() {
      _bands[i] = v.clamp(-15.0, 15.0);
      _selectedPreset = null;
    });
    final eq = ref.read(equalizerServiceProvider);
    await eq.setBandGain(i, v);
  }

  Future<void> _onEnabledChanged(bool v) async {
    setState(() => _enabled = v);
    final eq = ref.read(equalizerServiceProvider);
    await eq.setEnabled(v);
  }

  Future<void> _onPresetSelected(EqPreset? preset) async {
    if (preset == null) return;
    setState(() {
      _selectedPreset = preset;
      _bands = List.from(preset.gains);
    });
    final eq = ref.read(equalizerServiceProvider);
    for (var i = 0; i < preset.gains.length; i++) {
      await eq.setBandGain(i, preset.gains[i]);
    }
  }

  Future<void> _onReset() async {
    setState(() {
      _bands = List.filled(kEqBandCount, 0.0);
      _selectedPreset = EqPreset.flat;
    });
    final eq = ref.read(equalizerServiceProvider);
    await eq.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('\u042D\u043A\u0432\u0430\u043B\u0430\u0439\u0437\u0435\u0440'),
        actions: [
          Switch(
            value: _enabled,
            onChanged: _onEnabledChanged,
            activeColor: TubeColors.amberHot,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  '\u041F\u0440\u0435\u0441\u0435\u0442: ',
                  style: TextStyle(color: TubeColors.textSecondary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<EqPreset>(
                    value: _selectedPreset ?? EqPreset.flat,
                    dropdownColor: TubeColors.surface,
                    items: EqPreset.all
                        .map((p) => DropdownMenuItem<EqPreset>(
                              value: p,
                              child: Text(
                                p.name,
                                style: const TextStyle(color: TubeColors.textPrimary),
                              ),
                            ))
                        .toList(),
                    onChanged: _onPresetSelected,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: TubeColors.brass),
                  tooltip: '\u0421\u0431\u0440\u043E\u0441',
                  onPressed: _onReset,
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(kEqBandCount, (i) {
                  return _BandSlider(
                    label: _freqLabel(kEqBandFreqs[i]),
                    value: _bands.length > i ? _bands[i] : 0.0,
                    enabled: _enabled,
                    onChanged: (v) => _onBandChanged(i, v),
                  );
                }),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '\u041F\u0435\u0440\u0435\u043C\u0435\u0449\u0430\u0439\u0442\u0435 \u043F\u043E\u043B\u0437\u0443\u043D\u043A\u0438 \u0434\u043B\u044F \u043D\u0430\u0441\u0442\u0440\u043E\u0439\u043A\u0438 \u0447\u0430\u0441\u0442\u043E\u0442',
              style: TextStyle(color: TubeColors.textMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value > 0 ? '+${value.toStringAsFixed(0)}' : value.toStringAsFixed(0),
          style: TextStyle(
            color: enabled ? TubeColors.amberHot : TubeColors.textMuted,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              value: value.clamp(-15.0, 15.0),
              min: -15,
              max: 15,
              divisions: 30,
              activeColor: enabled ? TubeColors.amberHot : TubeColors.textMuted,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: TubeColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Text(
          'Hz',
          style: TextStyle(color: TubeColors.textMuted, fontSize: 10),
        ),
      ],
    );
  }
}