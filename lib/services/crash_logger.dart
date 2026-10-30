// ============================================================================
//  crash_logger.dart — файловое логирование крашей и ошибок
//  Пишет в <documentsDir>/pathephon_crash.log с авто-ротацией 1 МБ.
//  Чтение: adb shell run-as com.swanlab.audiox64 cat files/pathephon_crash.log
// ============================================================================
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

class CrashLogger {
  static final CrashLogger _instance = CrashLogger._();
  factory CrashLogger() => _instance;
  CrashLogger._();

  static const _maxFileSize = 1024 * 1024;
  static const _fileName = 'pathephon_crash.log';
  static const _oldFileName = 'pathephon_crash.log.1';

  File? _logFile;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/$_fileName');
      _initialized = true;
      log('=== Pathephon crash logger initialized ===');
      log('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
      log('Dart: ${Platform.version}');
    } catch (e) {
      debugPrint('[CrashLogger] init failed: $e');
    }
  }

  void log(String message, {StackTrace? stackTrace, String level = 'INFO'}) {
    if (_logFile == null) return;
    try {
      if (_logFile!.existsSync() && _logFile!.lengthSync() > _maxFileSize) {
        final oldFile = File('${_logFile!.parent.path}/$_oldFileName');
        if (oldFile.existsSync()) oldFile.deleteSync();
        _logFile!.renameSync(oldFile.path);
        _logFile = File('${_logFile!.parent.path}/$_fileName');
      }
      final ts = DateTime.now().toIso8601String();
      final sb = StringBuffer()..writeln('[$ts] [$level] $message');
      if (stackTrace != null) sb.writeln(stackTrace.toString());
      _logFile!.writeAsStringSync(sb.toString(), mode: FileMode.append, flush: true);
    } catch (e) {
      debugPrint('[CrashLogger] write failed: $e');
    }
  }

  void error(String message, Object error, [StackTrace? stackTrace]) {
    log('$message: $error', stackTrace: stackTrace ?? StackTrace.current, level: 'ERROR');
  }

  void warning(String message) { log(message, level: 'WARN'); }

  Future<String> readLog() async {
    if (_logFile == null || !_logFile!.existsSync()) return '';
    try { return _logFile!.readAsStringSync(); } catch (e) { return '[read failed: $e]'; }
  }

  Future<void> clear() async {
    if (_logFile == null) return;
    try {
      if (_logFile!.existsSync()) _logFile!.deleteSync();
      final oldFile = File('${_logFile!.parent.path}/$_oldFileName');
      if (oldFile.existsSync()) oldFile.deleteSync();
      log('=== Log cleared ===');
    } catch (e) { debugPrint('[CrashLogger] clear failed: $e'); }
  }
}

final crashLogger = CrashLogger();