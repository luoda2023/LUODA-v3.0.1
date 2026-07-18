import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class DirectVoiceStorage {
  DirectVoiceStorage._();

  static final DirectVoiceStorage instance = DirectVoiceStorage._();
  static const int maxClipBytes = 8 * 1024 * 1024;

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  String _safeId(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');

  Future<Directory> _directory() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}ldesk_voice_messages',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<String> pathFor(String messageId) async {
    final directory = await _directory();
    return '${directory.path}${Platform.pathSeparator}${_safeId(messageId)}.wav';
  }

  Future<bool> exists(String messageId) async {
    return File(await pathFor(messageId)).exists();
  }

  Future<Uint8List?> read(String messageId) async {
    final file = File(await pathFor(messageId));
    if (!await file.exists()) return null;
    final length = await file.length();
    if (length <= 0 || length > maxClipBytes) return null;
    return file.readAsBytes();
  }

  Future<void> write(String messageId, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxClipBytes) {
      throw const FormatException('Invalid voice clip size');
    }
    await File(await pathFor(messageId)).writeAsBytes(bytes, flush: true);
    revision.value++;
  }

  Future<void> delete(String messageId) async {
    final file = File(await pathFor(messageId));
    if (await file.exists()) await file.delete();
    revision.value++;
  }
}
