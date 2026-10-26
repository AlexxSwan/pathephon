import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:package_info_plus/package_info_plus.dart";
import "../../core/theme/retro_theme.dart";
import "../providers/providers.dart";

class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});
  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  String _version = "";
  String _buildNumber = "";

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    } catch (_) {
      setState(() { _version = "?"; _buildNumber = "?"; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeModeIdx = ref.watch(themeModeProvider);
    final p = Preset.of(context);
    const modeNames = ["Тёмная", "Светлая", "Системная"];
    final versionStr = _version.isEmpty
        ? "Загрузка..."
        : "Версия: $_version ($_buildNumber)";
    return Scaffold(
      appBar: AppBar(title: const Text("О программе")),
      body: Center(child: SingleChildScrollView(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.graphic_eq, size: 80, color: p.accent),
        const SizedBox(height: 24),
        Text("Патефон", style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 8),
        Text(versionStr, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: p.textSecondary)),
        const SizedBox(height: 8),
        Text("Тема: ${modeNames[themeModeIdx]}", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.textMuted)),
        const SizedBox(height: 24),
        Text("Автор: SwanLab", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: p.brass)),
        const SizedBox(height: 8),
        Text("github.com/AlexxSwan/pathephon", style: TextStyle(color: p.textMuted)),
      ]))),
    );
  }
}