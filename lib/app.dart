import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "dart:ui" show PlatformDispatcher;
import "package:shared_preferences/shared_preferences.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:flutter/services.dart";

import "core/l10n/generated/app_localizations.dart";
import "core/theme/retro_theme.dart";
import "presentation/screens/audiobooks_screen.dart";
import "presentation/screens/equalizer_screen.dart";
import "presentation/screens/library_screen.dart";
import "presentation/screens/now_playing_screen.dart";
import "presentation/screens/about_screen.dart";
import "presentation/widgets/permission_gate.dart";
import "presentation/providers/providers.dart";

final localeProvider = StateProvider<Locale>((ref) => const Locale("ru"));

class AudioPlayerX64App extends ConsumerWidget {
  const AudioPlayerX64App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final themeModeIdx = ref.watch(themeModeProvider);
    ref.watch(libraryRestoreProvider);
    ref.watch(launchIntentProvider);

    // Map index to ThemeMode: 0=dark, 1=light, 2=system
    final themeMode = switch (themeModeIdx) {
      0 => ThemeMode.dark,
      1 => ThemeMode.light,
      _ => ThemeMode.system,
    };

    // Determine effective brightness
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
      onGenerateRoute: (settings) {
        // Перехватываем ACTION_VIEW от Android.
        // Flutter сам вызывает pushNamed(uri) когда получает intent.
        // settings.name = Uri аудиофайла (content:// или file://).
        final uri = settings.name;
        if (uri.startsWith('content://') || uri.startsWith('file://')) {
          // Запускаем трек через addPostFrameCallback чтобы providers были готовы
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _handleOpenWith(uri, ref);
          });
          return MaterialPageRoute(builder: (_) => const SizedBox.shrink());
        }
        return null;
      },
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // Re-evaluate brightness in case system changed
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
    AudiobooksScreen(), AboutScreen(),
  ];

  static const _themeModeNames = ['Тёмная', 'Светлая', 'Системная'];
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
                  _NavButton(icon: Icons.menu_book_outlined, activeIcon: Icons.menu_book, label: l.navAudiobooks, selected: _index == 3, onTap: () => setState(() => _index = 3)),
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