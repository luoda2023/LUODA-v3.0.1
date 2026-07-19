import 'dart:io';

import 'package:path_provider/path_provider.dart';

class DirectChatStorage {
  static const _fileName = 'ldesk_direct_chat_v1.json';

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }

  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<void> write(String value) async {
    final file = await _file();
    await file.writeAsString(value, flush: true);
  }

  Future<String> update(
    Future<String> Function(String? current) transform,
  ) async {
    final file = await _file();
    final lockFile = File('${file.path}.lock');
    Object? lastError;
    for (var attempt = 0; attempt < 8; attempt++) {
      RandomAccessFile? lock;
      try {
        lock = await lockFile.open(mode: FileMode.append);
        await lock.lock(FileLock.exclusive);
        final current = await file.exists() ? await file.readAsString() : null;
        final next = await transform(current);
        await file.writeAsString(next, flush: true);
        await lock.unlock();
        await lock.close();
        return next;
      } catch (error) {
        lastError = error;
        try {
          await lock?.unlock();
        } catch (_) {}
        try {
          await lock?.close();
        } catch (_) {}
        if (attempt == 7) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 25 * (attempt + 1)));
      }
    }
    throw lastError ?? StateError('Unable to update direct chat storage');
  }
}
