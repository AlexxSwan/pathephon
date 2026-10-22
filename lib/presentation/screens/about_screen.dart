import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../core/theme/tube_colors.dart";

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text("Р С› Р С—РЎР‚Р С•Р С–РЎР‚Р В°Р СР СР Вµ")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.graphic_eq, size: 80, color: TubeColors.amber),
            const SizedBox(height: 24),
            Text("Р СџР В°РЎвЂљР ВµРЎвЂћР С•Р Р…", style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 8),
            Text("Р вЂ™Р ВµРЎР‚РЎРѓР С‘РЎРЏ: 0.1.1 (2)", style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: TubeColors.textSecondary)),
            const SizedBox(height: 24),
            Text("Р С’Р Р†РЎвЂљР С•РЎР‚: SwanLab", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: TubeColors.brass)),
            const SizedBox(height: 8),
            Text("github.com/AlexxSwan/pathephon", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TubeColors.textMuted)),
            const SizedBox(height: 32),
            Text("All-format retro-tube audio player", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TubeColors.textMuted)),
            Text("for modern Android x64", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TubeColors.textMuted)),
          ],
        ),
      ),
    );
  }
}