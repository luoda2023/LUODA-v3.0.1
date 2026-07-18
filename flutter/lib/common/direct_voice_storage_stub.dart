import 'dart:typed_data';

import 'package:flutter/foundation.dart';

class DirectVoiceStorage {
  DirectVoiceStorage._();

  static final DirectVoiceStorage instance = DirectVoiceStorage._();
  static const int maxClipBytes = 8 * 1024 * 1024;

  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  final Map<String, Uint8List> _clips = <String, Uint8List>{};

  Future<String> pathFor(String messageId) async => messageId;

  Future<bool> exists(String messageId) async => _clips.containsKey(messageId);

  Future<Uint8List?> read(String messageId) async => _clips[messageId];

  Future<void> write(String messageId, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxClipBytes) {
      throw const FormatException('Invalid voice clip size');
    }
    _clips[messageId] = Uint8List.fromList(bytes);
    revision.value++;
  }

  Future<void> delete(String messageId) async {
    _clips.remove(messageId);
    revision.value++;
  }
}
