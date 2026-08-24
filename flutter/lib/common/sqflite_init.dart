/// Conditional platform initialization for the SQLite database factory.
///
/// On all native platforms (Windows/Linux/macOS/Android) we use
/// `sqflite_common_ffi` which accesses the SQLite C library via
/// dart:ffi — this gives consistent behavior and avoids plugin
/// registration timing issues on Android.
/// On web there is no filesystem so chat storage is unused.
library;

export 'sqflite_init_stub.dart'
 if (dart.library.io) 'sqflite_init_io.dart';