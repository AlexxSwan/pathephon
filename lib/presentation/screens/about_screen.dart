import "dart:io";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:share_plus/share_plus.dart";
import "../../core/theme/retro_theme.dart";
import "../../services/crash_logger.dart";
import "../../services/playback_service.dart";
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

  Future<void> _showStatistics() async {
    final playback = ref.read(playbackServiceProvider);
    final stats = playback.getStatistics();
    final p = Preset.of(context);
    String fmt(int ms) {
      final s = ms ~/ 1000;
      final y = s ~/ 31536000; final mo = (s % 31536000) ~/ 2592000;
      final d = (s % 2592000) ~/ 86400; final h = (s % 86400) ~/ 3600;
      final mi = (s % 3600) ~/ 60; final se = s % 60;
      final parts = <String>[];
      if (y > 0) parts.add('$y г.'); if (mo > 0) parts.add('$mo мес.');
      if (d > 0) parts.add('$d дн.'); if (h > 0) parts.add('$h ч.');
      if (mi > 0) parts.add('$mi мин.'); parts.add('$se сек.');
      return parts.join(' ');
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surfaceVariant,
        title: Text('Статистика', style: TextStyle(color: p.accent, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('За всё время:', style: TextStyle(color: p.brass, fontSize: 13, fontWeight: FontWeight.bold)),
          Text('Время: ${fmt(stats['alltime_play_ms'] as int)}', style: TextStyle(color: p.textPrimary, fontSize: 12, fontFamily: 'monospace')),
          Text('Треков: ${stats['alltime_tracks']}', style: TextStyle(color: p.textPrimary, fontSize: 12, fontFamily: 'monospace')),
          SizedBox(height: 16),
          SizedBox(height: 16),
          Text('За текущую сессию:', style: TextStyle(color: p.brass, fontSize: 13, fontWeight: FontWeight.bold)),
          Text('Время: ${fmt(stats['session_play_ms'] as int)}', style: TextStyle(color: p.textPrimary, fontSize: 12, fontFamily: 'monospace')),
          Text('Треков: ${stats['session_tracks']}', style: TextStyle(color: p.textPrimary, fontSize: 12, fontFamily: 'monospace')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Закрыть', style: TextStyle(color: p.brass)))],
      ),
    );
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
        title: Text("Лог", style: TextStyle(color: p.accent, fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: _logLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: SelectableText(
                  _logPreview,
                  style: TextStyle(color: p.textPrimary, fontSize: 11, fontFamily: "monospace", height: 1.3),
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

  void _showDescription() {
    final p = Preset.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surfaceVariant,
        title: Text("Описание", style: TextStyle(color: p.accent, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Патефон — ретро-трубный аудиоплеер для Android.", style: TextStyle(color: p.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              Text("Возможности:", style: TextStyle(color: p.brass, fontSize: 12, fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text("\u2022 Воспроизведение всех аудиоформатов (MP3, FLAC, OGG, M4A, WAV, AAC, Opus)\n"
                   "\u2022 Управление очередью воспроизведения\n"
                   "\u2022 Случайный порядок (Shuffle) и повтор (Repeat all/one)\n"
                   "\u2022 Эквалайзер (5 полос)\n"
                   "\u2022 Поиск по библиотеке\n"
                   "\u2022 Импорт/экспорт плейлистов .m3u\n"
                   "\u2022 Открытие аудио файлов из других приложений\n"
                   "\u2022 Bluetooth-управление (play/pause/next/prev)\n"
                   "\u2022 Блокировка экрана и виджет управления\n"
                   "\u2022 Тёмная и светлая темы\n"
                   "\u2022 Датчик загрузки процессора в реальном времени\n"
                   "\u2022 Поделиться текущим треком\n"
                   "\u2022 Статистика прослушивания\n"
                   "\u2022 Сохранение состояния при закрытии (очередь, позиция, настройки)",
                style: TextStyle(color: p.textSecondary, fontSize: 11, height: 1.5)),
              SizedBox(height: 12),
              Text("Интерфейс:", style: TextStyle(color: p.brass, fontSize: 12, fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text("\u2022 Таб 'Сейчас играет' — обложка, контролы, плейлист, датчик CPU\n"
                   "\u2022 Таб 'Библиотека' — все треки, выбор папок\n"
                   "\u2022 Таб 'Эквалайзер' — 5-полосный EQ с пресетами\n"
                   "\u2022 Таб 'Поиск' — поиск по названию/артисту/альбому\n"
                   "\u2022 Тап по CPU% — диалог состояния (память, время работы, лог)\n"
                   "\u2022 Тап по названию трека в плейлисте — путь к файлу\n"
                   "\u2022 Кнопка Share — отправка файла текущего трека",
                style: TextStyle(color: p.textSecondary, fontSize: 11, height: 1.5)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text("Закрыть", style: TextStyle(color: p.brass)),
          ),
        ],
      ),
    );
  }

  Future<void> _shareLog() async {
    try {
      final logPath = crashLogger.publicLogPath;
      if (logPath != null && File(logPath).existsSync()) {
        await Share.shareXFiles([XFile(logPath)], subject: "Pathephon log");
      } else {
        final log = await crashLogger.readLog();
        await Share.share(log, subject: "Pathephon log");
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
        OutlinedButton.icon(
          onPressed: _showStatistics,
          icon: Icon(Icons.bar_chart, size: 18, color: p.brass),
          label: Text("Статистика", style: TextStyle(color: p.brass)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: p.brass.withOpacity(0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _showLogDialog,
          icon: Icon(Icons.bug_report, size: 18, color: p.accentHot),
          label: Text("Лог", style: TextStyle(color: p.accentHot)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: p.accentHot.withOpacity(0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _showDescription,
          icon: Icon(Icons.info_outline, size: 18, color: p.textMuted),
          label: Text("Описание", style: TextStyle(color: p.textMuted)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: p.textMuted.withOpacity(0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ]))),
    );
  }
}