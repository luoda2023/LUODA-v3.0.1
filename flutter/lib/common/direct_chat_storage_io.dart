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
    final lock = await lockFile.open(mode: FileMode.append);
    await lock.lock(FileLock.exclusive);
    try {
      final current = await file.exists() ? await file.readAsString() : null;
      final next = await transform(current);
      await file.writeAsString(next, flush: true);
      return next;
    } finally {
      await lock.unlock();
      await lock.close();
    }
  }
}
