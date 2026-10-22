// ============================================================================
//  main.dart — entry point
//  - Initializes shared prefs before UI starts (so providers can read them
//    synchronously).
//  - Reads saved UI locale and seeds the localeProvider override.
//  - Triggers initial library scan when LibraryScreen first builds.
//  - just_audio + audio_service start on first playback command.
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'presentation/providers/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final initialLocale = readInitialLocale(prefs);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        localeProvider.overrideWith((_) => initialLocale),
      ],
      child: const AudioPlayerX64App(),
    ),
  );
}
