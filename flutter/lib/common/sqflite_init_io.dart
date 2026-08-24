/// Desktop and mobile implementation.
///
/// We use `sqflite_common_ffi` across all platforms — it loads the SQLite
/// C library via dart:ffi, giving consistent behavior on Windows, Linux,
/// macOS, and Android. This avoids plugin registration timing issues
/// that cause "databaseFactory not initialized" errors on Android when
/// the native sqflite plugin hasn't registered its platform channel in
/// time (common when the app is launched as a foreground service or
/// restored after a kill).
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../runtime_logger.dart';

Future<void> initSqfliteForPlatform() async {
  try {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    RuntimeLogger.instance.info('SQLITE', 'FFI backend initialized');
  } catch (e, st) {
    debugPrint('Failed to init sqflite FFI: $e\n$st');
  }
}
