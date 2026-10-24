import "package:flutter/material.dart";
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

  @override
  void initState() {
    super.initState();
    _checkDiagnostics();
  }

  Future<void> _checkDiagnostics() async {
    final buf = StringBuffer();
    final p = Preset.of(context);

    // 1. Notification permission
    final notifStatus = await Permission.notification.status;
    buf.writeln("Notification permission: $notifStatus");

    // 2. Audio permission
    final audioStatus = await Permission.audio.status;
    buf.writeln("Audio permission: $audioStatus");

    // 3. Photos permission
    final photosStatus = await Permission.photos.status;
    buf.writeln("Photos permission: $photosStatus");

    // 4. PlaybackService type
    final playback = ref.read(playbackServiceProvider);
    buf.writeln("PlaybackService type: ${playback.runtimeType}");

    // 5. Check if JustAudioPlaybackService has handler
    if (playback is JustAudioPlaybackService) {
      // Can't access _handler directly, but we can check if playback works
      buf.writeln("PlaybackService: JustAudioPlaybackService (OK)");
    } else {
      buf.writeln("PlaybackService: ${playback.runtimeType} (UNEXPECTED)");
    }

    // 6. SharedPreferences flag
    final prefs = ref.read(sharedPreferencesProvider);
    final flagGranted = prefs.getBool('pathephon.permissions.granted') ?? false;
    buf.writeln("Permissions flag: $flagGranted");

    // 7. Queue info
    final snap = ref.read(playbackSnapshotProvider).valueOrNull;
    buf.writeln("Queue length: ${snap?.queue.length ?? 0}");
    buf.writeln("Current track: ${snap?.current?.title ?? 'none'}");
    buf.writeln("Is playing: ${snap?.isPlaying ?? false}");

    setState(() {
      _diag = buf.toString();
      _checking = false;
    });
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
        Text("\u0412\u0435\u0440\u0441\u0438\u044F: 0.10.1 (95)", style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: p.textSecondary)),
        const SizedBox(height: 8),
        Text("\u0422\u0435\u043C\u0430: ${modeNames[themeModeIdx]}", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.textMuted)),
        const SizedBox(height: 24),
        Text("\u0410\u0432\u0442\u043E\u0440: SwanLab", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: p.brass)),
        const SizedBox(height: 8),
        Text("github.com/AlexxSwan/pathephon", style: TextStyle(color: p.textMuted)),
        const SizedBox(height: 32),
        // Diagnostic info
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
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () { setState(() => _checking = true); _checkDiagnostics(); },
                child: const Text("Обновить"),
              ),
            ),
          ]),
        ),
      ])),
      ),
    );
  }
}