import 'dart:io';

import 'package:path_provider/path_provider.dart';

class DirectChatStorage {
  static const _fileName = 'ldesk_direct_chat_v1.json';
  static const _maxLockAttempts = 12;

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }

  Future<String?> read() async {
    final file = await _file();
    final lockFile = File('${file.path}.lock');
    Object? lastError;
    for (var attempt = 0; attempt < _maxLockAttempts; attempt++) {
      RandomAccessFile? lock;
      try {
        lock = await lockFile.open(mode: FileMode.append);
        await lock.lock(FileLock.shared);
        final value = await file.exists() ? await file.readAsString() : null;
        await lock.unlock();
        await lock.close();
        return value;
      } catch (error) {
        lastError = error;
        try {
          await lock?.unlock();
        } catch (_) {}
        try {
          await lock?.close();
        } catch (_) {}
        if (attempt == _maxLockAttempts - 1) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 30 * (attempt + 1)));
      }
    }
    throw lastError ?? StateError('Unable to read direct chat storage');
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
    for (var attempt = 0; attempt < _maxLockAttempts; attempt++) {
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
        if (attempt == _maxLockAttempts - 1) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 30 * (attempt + 1)));
      }
    }
    throw lastError ?? StateError('Unable to update direct chat storage');
  }
}
