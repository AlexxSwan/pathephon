// ============================================================================
//  equalizer_screen.dart — 10-band parametric EQ with knob controls
//  Plus ReplayGain mode toggle and preset chips.
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tube_colors.dart';
import '../../core/utils/replaygain.dart';
import '../../services/equalizer_service.dart';
import '../providers/providers.dart';
import '../widgets/tube_knob.dart';

class EqualizerScreen extends ConsumerWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final eq = ref.watch(equalizerServiceProvider);
    final bands = ref.watch(eqBandsProvider).valueOrNull ?? List.filled(10, 0.0);
    final enabled = ref.watch(eqEnabledProvider).valueOrNull ?? false;
    final rgMode = ref.watch(replayGainModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.eqTitle),
        actions: [
          Switch(
            value: enabled,
            onChanged: (v) => eq.setEnabled(v),
            activeTrackColor: TubeColors.amber.withOpacity(0.5),
            activeColor: TubeColors.amberHot,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ---- Knob row ----
            Expanded(
              flex: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: List.generate(10, (i) {
                  final hz = AndroidEqualizerService.bandCentresHz[i];
                  final label = hz >= 1000 ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}k' : '$hz';
                  // Map -12..+12 dB → 0..1 for the knob.
                  final v = ((bands[i] + 12) / 24).clamp(0.0, 1.0);
                  return TubeKnob(
                    value: v,
                    label: label,
                    onChanged: (newV) {
                      final db = (newV * 24 - 12).clamp(-12.0, 12.0);
                      eq.setBand(i, db);
                    },
                  );
                }),
              ),
            ),

            // ---- dB readout ----
            Text(
              bands.map((g) => g >= 0 ? '+${g.toStringAsFixed(1)}' : g.toStringAsFixed(1)).join(' / '),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: TubeColors.textMuted),
            ),

            const SizedBox(height: 20),

            // ---- Presets row ----
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.eqPresets, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final p in eq.builtinPresets) _PresetChip(preset: p),
                        // user presets appended at runtime via FutureBuilder — omitted for brevity
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(),

            // ---- ReplayGain ----
            Row(
              children: [
                Text(l.eqReplayGain, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                _RgToggle(
                  labels: [l.eqReplayGainOff, l.eqReplayGainTrack, l.eqReplayGainAlbum],
                  current: rgMode,
                  onChanged: (m) {
                    ref.read(replayGainModeProvider.notifier).state = m;
                    ref.read(playbackServiceProvider).setReplayGain(m);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends ConsumerWidget {
  const _PresetChip({required this.preset});
  final EqPreset preset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eq = ref.watch(equalizerServiceProvider);
    final current = ref.watch(eqBandsProvider).valueOrNull;
    final isActive = current != null && _listsEqual(current, preset.gains);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(preset.name),
        selected: isActive,
        onSelected: (_) => eq.applyPreset(preset),
        selectedColor: TubeColors.amber,
        labelStyle: TextStyle(
          color: isActive ? TubeColors.background : TubeColors.textPrimary,
        ),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    );
  }

  bool _listsEqual(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.01) return false;
    }
    return true;
  }
}

class _RgToggle extends StatelessWidget {
  const _RgToggle({required this.labels, required this.current, required this.onChanged});
  final List<String> labels;
  final ReplayGainMode current;
  final ValueChanged<ReplayGainMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ReplayGainMode>(
      segments: [
        for (var i = 0; i < labels.length; i++)
          ButtonSegment(value: ReplayGainMode.values[i], label: Text(labels[i])),
      ],
      selected: {current},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return TubeColors.amber;
          return TubeColors.surface;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return TubeColors.background;
          return TubeColors.textSecondary;
        }),
      ),
    );
  }
}
