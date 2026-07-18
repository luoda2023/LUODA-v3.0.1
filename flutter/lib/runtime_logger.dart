import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class RuntimeLogger {
  RuntimeLogger._();

  static final RuntimeLogger instance = RuntimeLogger._();

  IOSink? _sink;
  File? _logFile;
  bool _enabled = true;
  bool _hooksInstalled = false;

  String? get logPath => _logFile?.path;

  Future<void> init() async {
    if (_sink != null || !_enabled) return;
    try {
      final directory = Directory(await _resolveLogDirectory());
      await directory.create(recursive: true);
      final day = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      _logFile = File(path.join(directory.path, 'ldesk-flutter-$day.log'));
      _sink = _logFile!.openWrite(mode: FileMode.append);
      info('SYSTEM', 'Flutter runtime logger initialized');
      info('SYSTEM', 'Platform: ${Platform.operatingSystem}');
    } catch (error) {
      _enabled = false;
      debugPrint('Runtime logger initialization failed: $error');
    }
  }

  Future<String> _resolveLogDirectory() async {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? r'C:\LDesk';
      return path.join(appData, 'LDesk', 'logs');
    }
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
      return path.join(home, 'Library', 'Logs', 'LDesk');
    }
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
      return path.join(home, '.local', 'share', 'LDesk', 'logs');
    }
    final support = await getApplicationSupportDirectory();
    return path.join(support.path, 'logs');
  }

  void installErrorHooks() {
    if (_hooksInstalled) return;
    _hooksInstalled = true;

    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      error(
        'FLUTTER',
        '${details.exceptionAsString()}\n${details.stack ?? StackTrace.empty}',
      );
      previousFlutterError?.call(details);
    };

    final previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (exception, stack) {
      error('UNCAUGHT', '$exception\n$stack');
      return previousPlatformError?.call(exception, stack) ?? false;
    };
  }

  void _write(String level, String tag, String message) {
    if (!_enabled || _sink == null) return;
    final timestamp = DateTime.now().toUtc().toIso8601String();
    _sink!.writeln('[$timestamp] [$level] [$tag] $message');
    unawaited(_sink!.flush().catchError((_) {}));
  }

  void info(String tag, String message) => _write('INFO', tag, message);
  void warn(String tag, String message) => _write('WARN', tag, message);
  void error(String tag, String message) => _write('ERROR', tag, message);
  void debug(String tag, String message) => _write('DEBUG', tag, message);
}
