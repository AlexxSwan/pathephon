// ============================================================================
//  main.dart — entry point с crash handling
//  Три слоя защиты: FlutterError.onError + PlatformDispatcher.onError + runZonedGuarded
// ============================================================================
import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'domain/models/track.dart';
import 'presentation/providers/providers.dart';
import 'services/crash_logger.dart';

final _intentChannel = MethodChannel('pathephon/launch_intent');
void Function(String uri, String name)? _onLaunchIntentCallback;

void setLaunchIntentCallback(void Function(String uri, String name) callback) {
  _onLaunchIntentCallback = callback;
  _intentChannel.setMethodCallHandler((call) async {
    try {
      if (call.method == 'onLaunchIntent') {
        final uri = call.arguments['uri'] as String?;
        final name = call.arguments['name'] as String? ?? '';
        if (uri != null) _onLaunchIntentCallback?.call(uri, name);
      }
    } catch (e, st) {
      crashLogger.error('setLaunchIntentCallback handler failed', e, st);
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await runZonedGuarded<Future<void>>(() async {
    await crashLogger.init();

    // 1. Ошибки widget tree (build/layout/paint)
    FlutterError.onError = (FlutterErrorDetails details) {
      crashLogger.error('FlutterError', details.exception, details.stack);
      FlutterError.presentError(details);
    };

    // 2. Unhandled ошибки UI thread
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      crashLogger.error('PlatformDispatcher', error, stack);
      return true;
    };

    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e, st) {
      crashLogger.error('SharedPreferences init failed', e, st);
      rethrow;
    }

    final initialLocale = readInitialLocale(prefs);
    crashLogger.log('App starting, locale=$initialLocale');

    runApp(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          localeProvider.overrideWith((_) => Locale(initialLocale)),
        ],
        child: const AudioPlayerX64App(),
      ),
    );
  }, (Object error, StackTrace stack) {
    // 3. Последняя линия — ловит ВСЕ необработанные async-исключения
    crashLogger.error('UNHANDLED ZONE ERROR', error, stack);
  });
}

Future<Track?> readLaunchIntent() async {
  try {
    final result = await _intentChannel.invokeMethod<Map>('getLaunchIntent');
    if (result == null) return null;
    final uri = result['uri'] as String? ?? '';
    final name = result['name'] as String? ?? '';
    if (uri.isEmpty) return null;
    var fileName = name;
    if (fileName.isEmpty) {
      final decoded = Uri.tryParse(uri);
      fileName = (decoded != null && decoded.pathSegments.isNotEmpty)
          ? Uri.decodeComponent(decoded.pathSegments.last)
          : 'Unknown';
    }
    final title = fileName.replaceAll(RegExp(r'\.(mp3|flac|ogg|m4a|wav|opus|aac)$'), '');
    return Track(id: uri, uri: uri, title: title, durationMs: 0);
  } catch (e, st) {
    crashLogger.error('readLaunchIntent failed', e, st);
    return null;
  }
}

String readInitialLocale(SharedPreferences prefs) {
  try {
    return prefs.getString('pathephon.locale') ?? 'ru';
  } catch (e, st) {
    crashLogger.error('readInitialLocale failed', e, st);
    return 'ru';
  }
}