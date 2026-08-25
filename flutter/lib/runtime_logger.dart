import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class RuntimeLogger {
  RuntimeLogger._();

  static final RuntimeLogger instance = RuntimeLogger._();
  static const Duration _flushInterval = Duration(seconds: 1);
  static const Duration _duplicateWindow = Duration(seconds: 30);
  static const int _maxEntriesPerWindow = 3;
  static const int _maxTrackedMessages = 256;

  IOSink? _sink;
  File? _logFile;
  bool _enabled = true;
  bool _hooksInstalled = false;
  Future<void> _pendingWrite = Future<void>.value();
  Timer? _flushTimer;
  final Map<int, _RuntimeLogWindow> _duplicateWindows =
      <int, _RuntimeLogWindow>{};

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
 final appData = Platform.environment['APPDATA'] ?? r'C:\LUODA';
 return path.join(appData, 'LUODA', 'logs');
 }
 if (Platform.isMacOS) {
 final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
 return path.join(home, 'Library', 'Logs', 'LUODA');
 }
 if (Platform.isLinux) {
 final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
 return path.join(home, '.local', 'share', 'LUODA', 'logs');
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
    final sink = _sink;
    if (!_enabled || sink == null) return;
    final now = DateTime.now().toUtc();
    final signature = Object.hash(level, tag, message.length, message.hashCode);
    final previous = _duplicateWindows[signature];
    if (previous != null &&
        now.difference(previous.startedAt) < _duplicateWindow) {
      previous.count++;
      if (previous.count == _maxEntriesPerWindow + 1) {
        _enqueueLine(
          sink,
          '[${now.toIso8601String()}] [WARN] [LOGGER] '
          'Further duplicate [$level] [$tag] entries suppressed for '
          '${_duplicateWindow.inSeconds} seconds',
        );
      }
      if (previous.count > _maxEntriesPerWindow) return;
    } else {
      _duplicateWindows.remove(signature);
      _duplicateWindows[signature] = _RuntimeLogWindow(now);
      if (_duplicateWindows.length > _maxTrackedMessages) {
        _duplicateWindows.remove(_duplicateWindows.keys.first);
      }
    }
    _enqueueLine(
      sink,
      '[${now.toIso8601String()}] [$level] [$tag] $message',
    );
  }

  void _enqueueLine(IOSink sink, String line) {
    _pendingWrite = _pendingWrite.then((_) async {
      sink.writeln(line);
    }).catchError((Object error, StackTrace _) {
      _enabled = false;
      debugPrint('Runtime logger write failed: $error');
    });
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(_flushInterval, _flush);
  }

  Future<void> _flush() async {
    _flushTimer = null;
    final sink = _sink;
    if (!_enabled || sink == null) return;
    _pendingWrite = _pendingWrite.then((_) => sink.flush()).catchError(
      (Object error, StackTrace _) {
        _enabled = false;
        debugPrint('Runtime logger flush failed: $error');
      },
    );
    await _pendingWrite;
  }

  void info(String tag, String message) => _write('INFO', tag, message);
  void warn(String tag, String message) => _write('WARN', tag, message);
  void error(String tag, String message) => _write('ERROR', tag, message);
  void debug(String tag, String message) => _write('DEBUG', tag, message);
}

class _RuntimeLogWindow {
  _RuntimeLogWindow(this.startedAt);

  final DateTime startedAt;
  int count = 1;
}
