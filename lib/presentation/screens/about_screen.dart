import "dart:io";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:share_plus/share_plus.dart";
import "../../core/theme/retro_theme.dart";
import "../../services/crash_logger.dart";
import "../providers/providers.dart";

class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});
  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  String _version = "";
  String _buildNumber = "";
  String _logPreview = "";
  bool _logLoading = false;

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

  Future<void> _showLogDialog() async {
    setState(() { _logLoading = true; });
    final log = await crashLogger.readLog();
    setState(() {
      _logPreview = log.isEmpty ? "(лог пуст)" : log;
      _logLoading = false;
    });
    if (!mounted) return;
    final p = Preset.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surfaceVariant,
        title: Text("Лог крашей", style: TextStyle(color: p.accent, fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: _logLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: SelectableText(
                  _logPreview,
                  style: TextStyle(color: p.textPrimary, fontSize: 11, fontFamily: 'monospace', height: 1.3),
                ),
              ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text("Закрыть", style: TextStyle(color: p.brass)),
          ),
          TextButton(
            onPressed: () async {
              await _shareLog();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text("Поделиться", style: TextStyle(color: p.accentHot)),
          ),
          TextButton(
            onPressed: () async {
              await crashLogger.clear();
              if (ctx.mounted) Navigator.of(ctx).pop();
              setState(() { _logPreview = ""; });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Лог очищен")),
              );
            },
            child: Text("Очистить", style: TextStyle(color: p.textMuted)),
          ),
        ],
      ),
    );
  }

  Future<void> _shareLog() async {
    try {
      final logPath = crashLogger.publicLogPath;
      if (logPath != null && File(logPath).existsSync()) {
        // Шарим файл (можно отправить в Telegram/email/сохранить)
        await Share.shareXFiles([XFile(logPath)], subject: 'Pathephon crash log');
      } else {
        // Файл недоступен — шарим текст
        final log = await crashLogger.readLog();
        await Share.share(log, subject: 'Pathephon crash log');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Не удалось поделиться: $e")),
        );
      }
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
      appBar: AppBar(
        title: const Text("О программе"),
        actions: [
          Consumer(builder: (context, ref, _) {
            final themeModeIdx = ref.watch(themeModeProvider);
            const icons = [Icons.dark_mode, Icons.light_mode, Icons.brightness_auto];
            const names = ['Тёмная', 'Светлая', 'Системная'];
            return IconButton(
              icon: Icon(icons[themeModeIdx], size: 20),
              tooltip: names[themeModeIdx],
              onPressed: () {
                final next = (themeModeIdx + 1) % 3;
                ref.read(themeModeProvider.notifier).state = next;
                ref.read(sharedPreferencesProvider).setInt('pathephon.theme_mode', next);
              },
            );
          }),
        ],
      ),
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
        // === Кнопка просмотра/шаринга лога крашей ===
        OutlinedButton.icon(
          onPressed: _showLogDialog,
          icon: Icon(Icons.bug_report, size: 18, color: p.accentHot),
          label: Text("Лог крашей", style: TextStyle(color: p.accentHot)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: p.accentHot.withOpacity(0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ]))),
    );
  }
}