import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../core/theme/tube_colors.dart";

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text("\u041E \u043F\u0440\u043E\u0433\u0440\u0430\u043C\u043C\u0435")),
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.graphic_eq, size: 80, color: TubeColors.amber),
        const SizedBox(height: 24),
        Text("\u041F\u0430\u0442\u0435\u0444\u043E\u043D", style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 8),
        Text("\u0412\u0435\u0440\u0441\u0438\u044F: 0.8.6 (80)", style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: TubeColors.textSecondary)),
        const SizedBox(height: 24),
        Text("\u0410\u0432\u0442\u043E\u0440: SwanLab", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: TubeColors.brass)),
        const SizedBox(height: 8),
        const Text("github.com/AlexxSwan/pathephon", style: TextStyle(color: TubeColors.textMuted)),
        const SizedBox(height: 32),
        const Text("All-format retro-tube audio player", style: TextStyle(color: TubeColors.textMuted)),
        const Text("for modern Android x64", style: TextStyle(color: TubeColors.textMuted)),
      ])),
    );
  }
}