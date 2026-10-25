import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:permission_handler/permission_handler.dart";
import "../../core/theme/retro_theme.dart";
import "../providers/providers.dart";
import "../../services/playback_service.dart";

class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});
  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  String _diag = "Checking...";
  bool _checking = true;
  String _version = "";
  String _buildNumber = "";

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _checkDiagnostics();
  }

  /// Читает версию из pubspec.yaml через PackageInfo.fromPlatform().
  /// Требует зависимость package_info_plus (добавлена в pubspec.yaml).
  /// Возвращает version (например "0.10.9") и buildNumber (например "103").
  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    } catch (e) {
      setState(() {
        _version = "?";
        _buildNumber = "?";
      });
    }
  }

  Future<void> _checkDiagnostics() async {
    final buf = StringBuffer();
    final notifStatus = await Permission.notification.status;
    buf.writeln("Notification: $notifStatus");
    final audioStatus = await Permission.audio.status;
    buf.writeln("Audio: $audioStatus");
    final playback = ref.read(playbackServiceProvider);
    buf.writeln("Service: ${playback.runtimeType}");
    final prefs = ref.read(sharedPreferencesProvider);
    final flagGranted = prefs.getBool("pathephon.permissions.granted") ?? false;
    buf.writeln("Perms flag: $flagGranted");
    final snap = ref.read(playbackSnapshotProvider).valueOrNull;
    buf.writeln("Queue: ${snap?.queue.length ?? 0}");
    buf.writeln("Track: ${snap?.current?.title ?? 'none'}");
    buf.writeln("Playing: ${snap?.isPlaying ?? false}");
    setState(() { _diag = buf.toString(); _checking = false; });
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
        const SizedBox(height: 32),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.surfaceVariant,
            border: Border.all(color: p.outline),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Диагностика:", style: TextStyle(color: p.brass, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_checking)
              const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())
            else
              Text(_diag, style: TextStyle(color: p.textSecondary, fontFamily: "monospace", fontSize: 12)),
          ]),
        ),
      ]))),
    );
  }
}