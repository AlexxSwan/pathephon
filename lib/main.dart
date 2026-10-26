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
final _intentChannel = MethodChannel('pathephon/launch_intent');

/// Callback для push-модели (Kotlin сам вызывает когда есть intent).
void Function(String uri, String name)? _onLaunchIntentCallback;

void setLaunchIntentCallback(void Function(String uri, String name) callback) {
  _onLaunchIntentCallback = callback;
  _intentChannel.setMethodCallHandler((call) async {
    if (call.method == 'onLaunchIntent') {
      final uri = call.arguments['uri'] as String?;
      final name = call.arguments['name'] as String? ?? '';
      if (uri != null) _onLaunchIntentCallback?.call(uri, name);
    }
  });
}

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

/// Читает ACTION_VIEW intent при запуске (pull-модель).
/// Возвращает Track если был "Открыть с помощью Pathephon".
Future<Track?> readLaunchIntent() async {
  try {
    final result = await _intentChannel.invokeMethod<Map>('getLaunchIntent');
    if (result == null) return null;
    final uri = result['uri'] as String? ?? '';
    final name = result['name'] as String? ?? '';
    if (uri.isEmpty) return null;
    // Приоритет: name из Kotlin (правильное имя файла) > pathSegments > Unknown
    var fileName = name;
    if (fileName.isEmpty) {
      final decoded = Uri.tryParse(uri);
      fileName = (decoded != null && decoded.pathSegments.isNotEmpty)
          ? Uri.decodeComponent(decoded.pathSegments.last)
          : 'Unknown';
    }
    final title = fileName.replaceAll(RegExp(r'\.(mp3|flac|ogg|m4a|wav|opus|aac)$'), '');
    return Track(
      id: uri,
      uri: uri,
      title: title,
      durationMs: 0,
    );
  } catch (e) {
    print('[pathephon] readLaunchIntent failed: $e');
    return null;
  }
}