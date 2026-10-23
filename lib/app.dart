import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "dart:ui" show PlatformDispatcher;
import "package:shared_preferences/shared_preferences.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:flutter/services.dart";

import "core/l10n/generated/app_localizations.dart";
import "core/theme/retro_theme.dart";
import "presentation/screens/audiobooks_screen.dart";
import "presentation/screens/library_screen.dart";
import "presentation/screens/now_playing_screen.dart";
import "presentation/screens/about_screen.dart";

final localeProvider = StateProvider<Locale>((ref) => const Locale("ru"));

class AudioPlayerX64App extends ConsumerWidget {
  const AudioPlayerX64App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return MaterialApp(
      title: "\u041F\u0430\u0442\u0435\u0444\u043E\u043D",
      debugShowCheckedModeBanner: false,
      theme: RetroTheme.dark,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Shell(),
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

class _Shell extends StatefulWidget {
  const _Shell();
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _index = 0;

  final _screens = const <Widget>[
    NowPlayingScreen(),
    LibraryScreen(),
    AudiobooksScreen(),
    AboutScreen(),
  ];

  Future<void> _handleBack() async {
    if (_index != 0) {
      setState(() => _index = 0);
      return;
    }
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1410),
        title: Text(
          "\u0412\u044B\u0439\u0442\u0438 \u0438\u0437 \u043F\u0440\u0438\u043B\u043E\u0436\u0435\u043D\u0438\u044F?",
          style: const TextStyle(color: Color(0xFFF4E9D2), fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              "\u041E\u0442\u043C\u0435\u043D\u0430",
              style: const TextStyle(color: Color(0xFFB89968)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(true);
              SystemNavigator.pop();
            },
            child: Text(
              "\u0412\u044B\u0439\u0442\u0438",
              style: const TextStyle(color: Color(0xFFFF6B1A)),
            ),
          ),
        ],
      ),
    ) ?? false;
    if (shouldExit) {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: _screens,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.graphic_eq_outlined),
              selectedIcon: const Icon(Icons.graphic_eq),
              label: l.navNowPlaying,
            ),
            NavigationDestination(
              icon: const Icon(Icons.library_music_outlined),
              selectedIcon: const Icon(Icons.library_music),
              label: l.navLibrary,
            ),
            NavigationDestination(
              icon: const Icon(Icons.menu_book_outlined),
              selectedIcon: const Icon(Icons.menu_book),
              label: l.navAudiobooks,
            ),
            NavigationDestination(
              icon: const Icon(Icons.info_outline),
              selectedIcon: const Icon(Icons.info),
              label: "\u041E \u043F\u0440\u043E\u0433\u0440\u0430\u043C\u043C\u0435",
            ),
          ],
        ),
      ),
    );
  }
}