// ============================================================================
//  equalizer_screen.dart - UI for the 5-band Android Equalizer
//  State holder only - gains saved to SharedPreferences.
//  Native EQ application is a TODO (next iteration).
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tube_colors.dart';
import '../providers/providers.dart';
import '../../services/equalizer_service.dart';

class EqualizerScreen extends ConsumerWidget {
  const EqualizerScreen({super.key});

  String _freqLabel(double hz) {
    if (hz >= 1000) {
      return '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}k';
    }
    return hz.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eq = ref.watch(equalizerServiceProvider);
    final bandsAsync = ref.watch(eqBandsProvider);
    final enabledAsync = ref.watch(eqEnabledProvider);

    final bands = bandsAsync.valueOrNull ?? eq.currentBands;
    final enabled = enabledAsync.valueOrNull ?? eq.isEnabled;

    return Scaffold(
      appBar: AppBar(
        title: const Text('\u042D\u043A\u0432\u0430\u043B\u0430\u0439\u0437\u0435\u0440'),
        actions: [
          Switch(
            value: enabled,
            onChanged: (v) => eq.setEnabled(v),
            activeColor: TubeColors.amberHot,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Presets row
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
                    value: EqPreset.flat,
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
                    onChanged: (preset) async {
                      if (preset == null) return;
                      for (var i = 0; i < preset.gains.length; i++) {
                        await eq.setBandGain(i, preset.gains[i]);
                      }
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: TubeColors.brass),
                  tooltip: '\u0421\u0431\u0440\u043E\u0441',
                  onPressed: () => eq.reset(),
                ),
              ],
            ),
          ),
          const Divider(),
          // Bands
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(kEqBandCount, (i) {
                  return _BandSlider(
                    label: _freqLabel(kEqBandFreqs[i]),
                    value: bands.length > i ? bands[i] : 0.0,
                    enabled: enabled,
                    onChanged: (v) => eq.setBandGain(i, v),
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