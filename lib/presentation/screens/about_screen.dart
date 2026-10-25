import "package:flutter/material.dart";
import "package:flutter/services.dart" show PackageInfo;
import "package:flutter_riverpod/flutter_riverpod.dart";
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
  String _appVersion = "loading...";

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _checkDiagnostics();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() => _appVersion = "${info.version} (${info.buildNumber})");
    } catch (e) {
      setState(() => _appVersion = "err: $e");
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
    final flagGranted = prefs.getBool('pathephon.permissions.granted') ?? false;
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
    const modeNames = ['Тёмная', 'Светлая', 'Системная'];
    return Scaffold(
      appBar: AppBar(title: const Text("\u041E \u043F\u0440\u043E\u0433\u0440\u0430\u043C\u043C\u0435")),
      body: Center(child: SingleChildScrollView(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.graphic_eq, size: 80, color: p.accent),
        const SizedBox(height: 24),
        Text("\u041F\u0430\u0442\u0435\u0444\u043E\u043D", style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 8),
        Text("Версия: import "package:flutter/material.dart";
import "package:flutter/services.dart" show PackageInfo;
import "package:flutter_riverpod/flutter_riverpod.dart";
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
  String _appVersion = "loading...";

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _checkDiagnostics();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() => _appVersion = "${info.version} (${info.buildNumber})");
    } catch (e) {
      setState(() => _appVersion = "err: $e");
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
    final flagGranted = prefs.getBool('pathephon.permissions.granted') ?? false;
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
    const modeNames = ['Тёмная', 'Светлая', 'Системная'];
    return Scaffold(
      appBar: AppBar(title: const Text("\u041E \u043F\u0440\u043E\u0433\u0440\u0430\u043C\u043C\u0435")),
      body: Center(child: SingleChildScrollView(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.graphic_eq, size: 80, color: p.accent),
        const SizedBox(height: 24),
        Text("\u041F\u0430\u0442\u0435\u0444\u043E\u043D", style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 8),
        Text("\u0412\u0435\u0440\u0441\u0438\u044F: 0.10.2 (96)", style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: p.textSecondary)),
        const SizedBox(height: 8),
        Text("\u0422\u0435\u043C\u0430: ${modeNames[themeModeIdx]}", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.textMuted)),
        const SizedBox(height: 24),
        Text("\u0410\u0432\u0442\u043E\u0440: SwanLab", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: p.brass)),
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
            Text("Диагностика:", style: TextStyle(color: p.accent, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_checking)
              const Center(child: CircularProgressIndicator())
            else
              Text(_diag, style: TextStyle(color: p.textPrimary, fontSize: 11, fontFamily: 'monospace', height: 1.5)),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () { setState(() => _checking = true); _checkDiagnostics(); },
              child: const Text("Обновить"),
            )),
          ]),
        ),
      ]))),
    );
  }
}appVersion", style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: p.textSecondary)),
        const SizedBox(height: 8),
        Text("\u0422\u0435\u043C\u0430: ${modeNames[themeModeIdx]}", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.textMuted)),
        const SizedBox(height: 24),
        Text("\u0410\u0432\u0442\u043E\u0440: SwanLab", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: p.brass)),
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
            Text("Диагностика:", style: TextStyle(color: p.accent, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_checking)
              const Center(child: CircularProgressIndicator())
            else
              Text(_diag, style: TextStyle(color: p.textPrimary, fontSize: 11, fontFamily: 'monospace', height: 1.5)),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () { setState(() => _checking = true); _checkDiagnostics(); },
              child: const Text("Обновить"),
            )),
          ]),
        ),
      ]))),
    );
  }
}