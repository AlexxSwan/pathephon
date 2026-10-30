// ============================================================================
//  crash_logger.dart — файловое логирование + logcat + public Downloads copy
//
//  ТРИ канала вывода:
//  1. <documentsDir>/pathephon_crash.log — внутренний файл (только для debug-сборок через run-as)
//  2. logcat tag "PathephonCrash" — виден через `adb logcat -s PathephonCrash:V`
//  3. /sdcard/Download/pathephon_crash.log — публичный файл, доступен через
//     `adb pull /sdcard/Download/pathephon_crash.log` БЕЗ root и в release-сборках
//
//  Третий канал критически важен потому что `adb shell run-as` не работает
//  в release-сборках (package not debuggable).
// ============================================================================
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

class CrashLogger {
  static final CrashLogger _instance = CrashLogger._();
  factory CrashLogger() => _instance;
  CrashLogger._();

  static const _maxFileSize = 1024 * 1024; // 1 МБ
  static const _fileName = 'pathephon_crash.log';
  static const _oldFileName = 'pathephon_crash.log.1';
  static const _logcatTag = 'PathephonCrash';
  static const _publicDir = 'Pathephon'; // /sdcard/Download/Pathephon/

  File? _logFile;
  File? _publicLogFile;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      // 1. Внутренний файл в documentsDir
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/$_fileName');

      // 2. Публичный файл в /sdcard/Download/Pathephon/
      // Этот каталог читается без root через adb pull и без run-as.
      // Также доступен через любой файловый менеджер на телефоне.
      try {
        final downloadsDir = Directory('/storage/emulated/0/Download/$_publicDir');
        if (!downloadsDir.existsSync()) {
          downloadsDir.createSync(recursive: true);
        }
        _publicLogFile = File('${downloadsDir.path}/$_fileName');
      } catch (e) {
        // На некоторых OEM /storage/emulated/0 может быть недоступен для записи
        // без MANAGE_EXTERNAL_STORAGE. В этом случае лог пишется только во
        // внутренний файл + logcat.
        debugPrint('[CrashLogger] public Downloads dir not accessible: $e');
      }

      _initialized = true;
      log('=== Pathephon crash logger initialized ===');
      log('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
      log('Dart: ${Platform.version}');
      if (_publicLogFile != null) {
        log('Public log: ${_publicLogFile!.path}');
      } else {
        log('Public log: not available (only internal + logcat)');
      }
    } catch (e) {
      debugPrint('[CrashLogger] init failed: $e');
    }
  }

  /// Основной метод — пишет запись во все доступные каналы.
  void log(String message, {StackTrace? stackTrace, String level = 'INFO'}) {
    // 2. ВСЕГДА пишем в logcat — это работает в release-сборках тоже
    try {
      developer.log(message, name: _logcatTag, level: _levelToInt(level), error: stackTrace != null ? message : null, stackTrace: stackTrace);
    } catch (_) {}

    if (_logFile == null) return;
    final ts = DateTime.now().toIso8601String();
    final sb = StringBuffer()
      ..writeln('[$ts] [$level] $message');
    if (stackTrace != null) {
      sb.writeln(stackTrace.toString());
    }
    final entry = sb.toString();

    // 1. Внутренний файл с ротацией
    try {
      if (_logFile!.existsSync() && _logFile!.lengthSync() > _maxFileSize) {
        final oldFile = File('${_logFile!.parent.path}/$_oldFileName');
        if (oldFile.existsSync()) oldFile.deleteSync();
        _logFile!.renameSync(oldFile.path);
        _logFile = File('${_logFile!.parent.path}/$_fileName');
      }
      _logFile!.writeAsStringSync(entry, mode: FileMode.append, flush: true);
    } catch (e) {
      debugPrint('[CrashLogger] internal write failed: $e');
    }

    // 3. Публичный файл (если доступен)
    if (_publicLogFile != null) {
      try {
        // Тоже с ротацией, но чуть меньшим лимитом (это ж /sdcard)
        if (_publicLogFile!.existsSync() && _publicLogFile!.lengthSync() > _maxFileSize) {
          final oldPub = File('${_publicLogFile!.parent.path}/$_oldFileName');
          if (oldPub.existsSync()) oldPub.deleteSync();
          _publicLogFile!.renameSync(oldPub.path);
          _publicLogFile = File('${_publicLogFile!.parent.path}/$_fileName');
        }
        _publicLogFile!.writeAsStringSync(entry, mode: FileMode.append, flush: true);
      } catch (e) {
        // Если публичный файл вдруг стал недоступен (пользователь отозвал
        // права или вынул SD) — не падаем, пишем только во внутренний.
        _publicLogFile = null;
      }
    }
  }

  int _levelToInt(String level) {
    switch (level) {
      case 'ERROR': return 1000;
      case 'WARN':  return 800;
      case 'INFO':  return 500;
      default:      return 500;
    }
  }

  void error(String message, Object error, [StackTrace? stackTrace]) {
    log('$message: $error', stackTrace: stackTrace ?? StackTrace.current, level: 'ERROR');
  }

  void warning(String message) { log(message, level: 'WARN'); }

  /// Прочитать лог (для отображения в About screen / share).
  /// Сначала пытается публичный, потом внутренний.
  Future<String> readLog() async {
    try {
      if (_publicLogFile != null && _publicLogFile!.existsSync()) {
        return _publicLogFile!.readAsStringSync();
      }
      if (_logFile != null && _logFile!.existsSync()) {
        return _logFile!.readAsStringSync();
      }
    } catch (e) {
      return '[read failed: $e]';
    }
    return '';
  }

  /// Получить путь публичного файла (для share intent).
  String? get publicLogPath => _publicLogFile?.path;

  /// Очистить лог (оба файла).
  Future<void> clear() async {
    try {
      if (_logFile?.existsSync() == true) _logFile!.deleteSync();
      final oldInternal = File('${_logFile!.parent.path}/$_oldFileName');
      if (oldInternal.existsSync()) oldInternal.deleteSync();
    } catch (_) {}
    try {
      if (_publicLogFile?.existsSync() == true) _publicLogFile!.deleteSync();
      final oldPub = File('${_publicLogFile!.parent.path}/$_oldFileName');
      if (oldPub.existsSync()) oldPub.deleteSync();
    } catch (_) {}
    log('=== Log cleared ===');
  }
}

final crashLogger = CrashLogger();