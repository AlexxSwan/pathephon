import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "dart:ui" show PlatformDispatcher;
import "package:shared_preferences/shared_preferences.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:flutter/services.dart";

import "core/l10n/generated/app_localizations.dart";
import "core/theme/retro_theme.dart";
import "domain/models/track.dart";

import "presentation/screens/equalizer_screen.dart";
import "presentation/screens/library_screen.dart";
import "presentation/screens/now_playing_screen.dart";
import "presentation/screens/about_screen.dart";
import "presentation/screens/search_screen.dart";
import "presentation/widgets/permission_gate.dart";
import "presentation/providers/providers.dart";

final localeProvider = StateProvider<Locale>((ref) => const Locale("ru"));

/// Глобальный callback для ACTION_VIEW.
/// Flutter через SystemChannels.navigation вызывает didPushRouteInformation
/// на WidgetsBinding, а не на MaterialApp. onGenerateRoute не перехватывает
/// эти вызовы. Поэтому используем WidgetsBindingObserver.
/// Channel для получения name файла из Kotlin (push-модель).
/// Kotlin сам вызывает onLaunchIntent когда есть intent.
final _launchChannel = MethodChannel('pathephon/launch_intent');

class _OpenWithObserver extends WidgetsBindingObserver {
  static String? pendingUri;
  static ProviderContainer? container;

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async {
    final uri = routeInformation.uri.toString();
    if (uri.startsWith('content://') || uri.startsWith('file://')) {
      // НЕ запускаем трек здесь — name неизвестен.
      // Kotlin push (onLaunchIntent) придёт с правильным name.
      // Только перехватываем чтобы Navigator не упал.
      return true;
    }
    return super.didPushRouteInformation(routeInformation);
  }

  static void _handleOpenWith(String uri, [String name = '', String content = '']) {
    try {
      // Проверяем — это .m3u файл?
      final isM3u = name.endsWith('.m3u') || name.endsWith('.m3u8') || uri.contains('.m3u');
      if (isM3u && content.isNotEmpty) {
        _handleM3uContent(uri, name, content);
        return;
      }

      // Обычный аудиофайл
      var fileName = name;
      if (fileName.isEmpty) {
        final decoded = Uri.parse(uri);
        fileName = decoded.pathSegments.isNotEmpty
            ? Uri.decodeComponent(decoded.pathSegments.last)
            : 'Unknown';
      }
      final title = fileName.replaceAll(RegExp(r'\.(mp3|flac|ogg|m4a|wav|opus|aac)$'), '');
      final track = Track(
        id: uri,
        uri: uri,
        title: title,
        durationMs: 0,
      );
      print('[pathephon] open-with: $title ($uri)');
      final c = container;
      if (c != null) {
        c.read(libraryStateProvider.notifier).setPickedTracks([track]);
        c.read(playbackServiceProvider).playSingle(track);
      } else {
        pendingUri = uri;
        print('[pathephon] open-with: container not ready, pending');
      }
    } catch (e) {
      print('[pathephon] open-with failed: $e');
    }
  }

  /// Парсит .m3u контент и запускает очередь.
  static void _handleM3uContent(String uri, String name, String content) {
    try {
      print('[pathephon] open-with m3u: $name (${content.length} chars)');
      final lines = content.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      final tracks = <Track>[];
      String? pendingTitle;
      String? pendingArtist;
      int? pendingDuration;

      // Базовый путь для относительных путей в .m3u
      final basePath = uri.startsWith('content://')
          ? ''
          : uri.substring(0, uri.lastIndexOf('/') + 1);

      for (final line in lines) {
        if (line.startsWith('#EXTM3U')) continue;
        if (line.startsWith('#EXTINF:')) {
          final rest = line.substring(8);
          final commaIdx = rest.indexOf(',');
          if (commaIdx > 0) {
            final durStr = rest.substring(0, commaIdx);
            pendingDuration = int.tryParse(durStr);
            final info = rest.substring(commaIdx + 1);
            final dashIdx = info.indexOf(' - ');
            if (dashIdx > 0) {
              pendingArtist = info.substring(0, dashIdx);
              pendingTitle = info.substring(dashIdx + 3);
            } else {
              pendingTitle = info;
            }
          }
          continue;
        }
        if (line.startsWith('#')) continue;
        // Путь к файлу
        String trackUri;
        String filePath;
        if (line.startsWith('file://') || line.startsWith('content://')) {
          trackUri = line;
          filePath = line.startsWith('file://') ? Uri.parse(line).toFilePath() : '';
        } else if (line.startsWith('/')) {
          trackUri = Uri.file(line).toString();
          filePath = line;
        } else {
          // Относительный путь — добавляем базовый
          final full = basePath + line;
          trackUri = full.startsWith('file://') ? full : Uri.file(full).toString();
          filePath = full.startsWith('file://') ? Uri.parse(full).toFilePath() : full;
        }
        tracks.add(Track(
          id: trackUri,
          uri: trackUri,
          filePath: filePath,
          title: pendingTitle ?? line.split('/').last.replaceAll(RegExp(r'\.(mp3|flac|ogg|m4a|wav|opus|aac)$'), ''),
          artist: pendingArtist ?? '',
          durationMs: (pendingDuration ?? 0) * 1000,
        ));
        pendingTitle = null;
        pendingArtist = null;
        pendingDuration = null;
      }

      if (tracks.isEmpty) {
        print('[pathephon] m3u: no tracks found');
        return;
      }
      print('[pathephon] m3u: ${tracks.length} tracks, starting playback');
      final c = container;
      if (c != null) {
        c.read(libraryStateProvider.notifier).setPickedTracks(tracks);
        c.read(playbackServiceProvider).playQueue(tracks: tracks, startIndex: 0);
      }
    } catch (e) {
      print('[pathephon] m3u parse failed: $e');
    }
  }
}

class AudioPlayerX64App extends ConsumerWidget {
  const AudioPlayerX64App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Регистрируем observer + сохраняем container
    WidgetsBinding.instance.addObserver(_OpenWithObserver());
    // Регистрируем handler для получения name файла из Kotlin
    _launchChannel.setMethodCallHandler((call) async {
      if (call.method == 'onLaunchIntent') {
        final uri = call.arguments['uri'] as String? ?? '';
        final name = call.arguments['name'] as String? ?? '';
        final content = call.arguments['content'] as String? ?? '';
        if (uri.isNotEmpty) {
          _OpenWithObserver._handleOpenWith(uri, name, content);
        }
      }
    });
    _OpenWithObserver.container = ProviderScope.containerOf(context);
    // Kotlin push (onLaunchIntent) обрабатывает open-with с правильным name

    final locale = ref.watch(localeProvider);
    final themeModeIdx = ref.watch(themeModeProvider);
    ref.watch(libraryRestoreProvider);

    final themeMode = switch (themeModeIdx) {
      0 => ThemeMode.dark,
      1 => ThemeMode.light,
      _ => ThemeMode.system,
    };

    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            View.of(context).platformDispatcher.platformBrightness == Brightness.dark);
    final preset = isDark ? ThemePreset.dark : ThemePreset.light;

    return MaterialApp(
      title: "\u041F\u0430\u0442\u0435\u0444\u043E\u043D",
      debugShowCheckedModeBanner: false,
      theme: RetroTheme.lightTheme,
      darkTheme: RetroTheme.darkTheme,
      themeMode: themeMode,
      // onGenerateRoute НЕ нужен — перехватываем через WidgetsBindingObserver
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final brightness = Theme.of(context).brightness;
        final p = brightness == Brightness.dark ? ThemePreset.dark : ThemePreset.light;
        return Preset(preset: p, child: child!);
      },
      home: const PermissionGate(child: _Shell()),
    );
  }
}

Locale readInitialLocale(SharedPreferences prefs) {
  final saved = prefs.getString("ui_locale");
  if (saved == null || saved == "system") {
    final sys = PlatformDispatcher.instance.locale.languageCode;
    if (sys == "ru" || sys == "en") return Locale(sys);
    return const Locale("ru");
  }
  return Locale(saved);
}

class _Shell extends ConsumerStatefulWidget {
  const _Shell();
  @override
  ConsumerState<_Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<_Shell> {
  int _index = 0;
  final _screens = const <Widget>[
    NowPlayingScreen(), LibraryScreen(), EqualizerScreen(),
    SearchScreen(), AboutScreen(),
  ];

  static const _themeModeNames = ['\u0422\u0451\u043C\u043D\u0430\u044F', '\u0421\u0432\u0435\u0442\u043B\u0430\u044F', '\u0421\u0438\u0441\u0442\u0435\u043C\u043D\u0430\u044F'];
  static const _themeModeIcons = [Icons.dark_mode, Icons.light_mode, Icons.brightness_auto];

  void _cycleTheme() {
    final current = ref.read(themeModeProvider);
    final next = (current + 1) % 3;
    ref.read(themeModeProvider.notifier).state = next;
    ref.read(sharedPreferencesProvider).setInt('pathephon.theme_mode', next);
  }

  Future<void> _handleBack() async {
    if (_index != 0) { setState(() => _index = 0); return; }
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Text("\u0412\u044B\u0439\u0442\u0438 \u0438\u0437 \u043F\u0440\u0438\u043B\u043E\u0436\u0435\u043D\u0438\u044F?",
            style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface, fontSize: 18)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false),
              child: Text("\u041E\u0442\u043C\u0435\u043D\u0430", style: TextStyle(color: Theme.of(ctx).colorScheme.secondary))),
          TextButton(onPressed: () { Navigator.of(ctx).pop(true); SystemNavigator.pop(); },
              child: Text("\u0412\u044B\u0439\u0442\u0438", style: TextStyle(color: Theme.of(ctx).colorScheme.primary))),
        ],
      ),
    ) ?? false;
    if (shouldExit) SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = Preset.of(context);
    final themeModeIdx = ref.watch(themeModeProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _handleBack(); },
      child: Scaffold(
        body: Stack(children: [
          IndexedStack(index: _index, children: _screens),
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            left: 4,
            child: Container(
              decoration: BoxDecoration(
                color: p.surface.withOpacity(0.8),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(_themeModeIcons[themeModeIdx], color: p.accent, size: 20),
                tooltip: _themeModeNames[themeModeIdx],
                onPressed: _cycleTheme,
                iconSize: 20,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ),
          ),
        ]),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(top: BorderSide(color: p.outline, width: 1)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavButton(icon: Icons.graphic_eq_outlined, activeIcon: Icons.graphic_eq, label: l.navNowPlaying, selected: _index == 0, onTap: () => setState(() => _index = 0)),
                  _NavButton(icon: Icons.library_music_outlined, activeIcon: Icons.library_music, label: l.navLibrary, selected: _index == 1, onTap: () => setState(() => _index = 1)),
                  _NavButton(icon: Icons.equalizer_outlined, activeIcon: Icons.equalizer, label: l.navEqualizer, selected: _index == 2, onTap: () => setState(() => _index = 2)),
                  _NavButton(icon: Icons.search_outlined, activeIcon: Icons.search, label: "Поиск", selected: _index == 3, onTap: () => setState(() => _index = 3)),
                  _NavButton(icon: Icons.info_outline, activeIcon: Icons.info, label: "\u041E \u043F\u0440\u043E\u0433\u0440\u0430\u043C\u043C\u0435", selected: _index == 4, onTap: () => setState(() => _index = 4)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.activeIcon, required this.label, required this.selected, required this.onTap});
  final IconData icon; final IconData activeIcon; final String label;
  final bool selected; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Preset.of(context);
    final color = selected ? p.accent : p.brass;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: selected ? 12 : 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? p.accent.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected ? [BoxShadow(color: p.accent.withOpacity(0.3), blurRadius: 8, spreadRadius: 1)] : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? activeIcon : icon, color: color, size: selected ? 26 : 22),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              child: selected
                  ? Padding(padding: const EdgeInsets.only(left: 6), child: Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)))
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}