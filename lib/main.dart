// ============================================================================
//  main.dart — entry point
//  - Initializes shared prefs before UI starts
//  - Читает saved UI locale
//  - Обрабатывает ACTION_VIEW intent ("Открыть с помощью Pathephon")
// ============================================================================
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'domain/models/track.dart';
import 'presentation/providers/providers.dart';

/// MethodChannel для чтения launch intent.
const _intentChannel = MethodChannel('pathephon/launch_intent');

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

/// Читает ACTION_VIEW intent при запуске приложения.
/// Возвращает Track если был "Открыть с помощью Pathephon" на аудиофайле.
Future<Track?> readLaunchIntent() async {
  try {
    final result = await _intentChannel.invokeMethod<String>('getLaunchIntent');
    if (result == null || result.isEmpty) return null;
    final uri = Uri.parse(result);
    final fileName = uri.pathSegments.isNotEmpty
        ? Uri.decodeComponent(uri.pathSegments.last)
        : 'Unknown';
    final title = fileName.replaceAll(RegExp(r'\.(mp3|flac|ogg|m4a|wav|opus|aac)$'), '');
    return Track(
      id: result,
      uri: result,
      title: title,
      durationMs: 0,
    );
  } catch (_) {
    return null;
  }
}