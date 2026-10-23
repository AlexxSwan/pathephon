import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../core/theme/tube_colors.dart";

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text("\u041E \u043F\u0440\u043E\u0433\u0440\u0430\u043C\u043C\u0435")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.graphic_eq, size: 80, color: TubeColors.amber),
            SizedBox(height: 24),
            Text("\u041F\u0430\u0442\u0435\u0444\u043E\u043D", style: Theme.of(context).textTheme.displaySmall),
            SizedBox(height: 8),
            Text("\u0412\u0435\u0440\u0441\u0438\u044F: 0.1.5 (6)", style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: TubeColors.textSecondary)),
            SizedBox(height: 24),
            Text("\u0410\u0432\u0442\u043E\u0440: SwanLab", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: TubeColors.brass)),
            SizedBox(height: 8),
            Text("github.com/AlexxSwan/pathephon", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TubeColors.textMuted)),
            SizedBox(height: 32),
            Text("All-format retro-tube audio player", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TubeColors.textMuted)),
            Text("for modern Android x64", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TubeColors.textMuted)),
          ],
        ),
      ),
    );
  }
}