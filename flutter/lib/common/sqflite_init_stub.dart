/// Web/mobile stub: no FFI initialization needed.
/// On mobile the native sqflite plugin handles database access;
/// on web there is no filesystem so chat storage is unused.
Future<void> initSqfliteForPlatform() async {}
