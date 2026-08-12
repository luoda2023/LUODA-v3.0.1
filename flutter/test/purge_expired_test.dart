import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_chat.dart';
import 'package:luoda_flutter/common/direct_chat_storage.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ldesk_purge_test');
    DirectChatRepository.debugStorageOverride = _TempStorage(tempDir);
    await DirectChatRepository.instance.resetForTest();
  });

  tearDown(() async {
    DirectChatRepository.debugStorageOverride = null;
    await tempDir.delete(recursive: true);
  });

  test('purgeExpired removes only self-destructed records', () async {
    final active = await DirectChatRepository.instance.createOutgoing(
      conversationId: 'peer-1',
      kind: DirectChatKind.text,
      text: 'keep me',
      senderId: 'me',
      senderName: 'Me',
      senderAvatar: '',
      connectionTarget: 'peer-1',
    );

    final doomed = await DirectChatRepository.instance.createOutgoing(
      conversationId: 'peer-1',
      kind: DirectChatKind.text,
      text: 'burn me',
      senderId: 'me',
      senderName: 'Me',
      senderAvatar: '',
      connectionTarget: 'peer-1',
    );
    await DirectChatRepository.instance
        .setSelfDestruct('peer-1', doomed.id, const Duration(milliseconds: 1));

    // Give the expiry a moment to pass.
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final purged = await DirectChatRepository.instance.purgeExpired();
    expect(purged, 1);

    final records =
        await DirectChatRepository.instance.forConversation('peer-1');
    expect(records.map((r) => r.id), [active.id]);
  });

  test('purgeExpired is a no-op when nothing expired', () async {
    await DirectChatRepository.instance.createOutgoing(
      conversationId: 'peer-1',
      kind: DirectChatKind.text,
      text: 'still fresh',
      senderId: 'me',
      senderName: 'Me',
      senderAvatar: '',
      connectionTarget: 'peer-1',
    );

    expect(await DirectChatRepository.instance.purgeExpired(), 0);
    final records =
        await DirectChatRepository.instance.forConversation('peer-1');
    expect(records, hasLength(1));
  });
}

/// File-backed storage inside the test's temp dir (mirrors the production
/// DirectChatStorage contract without touching real user data).
class _TempStorage implements DirectChatStorage {
  _TempStorage(this.dir);

  final Directory dir;
  File get _file => File('${dir.path}${Platform.pathSeparator}ldesk_test.json');

  @override
  Future<DateTime?> modifiedTime() async {
    if (!await _file.exists()) return null;
    return (await _file.stat()).modified;
  }

  @override
  Future<String?> read() async {
    if (!await _file.exists()) return null;
    return _file.readAsString();
  }

  @override
  Future<void> write(String value) async {
    await _file.writeAsString(value, flush: true);
  }

  @override
  Future<String> update(
    Future<String> Function(String? current) transform,
  ) async {
    final current = await read();
    final next = await transform(current);
    if (next != current) await write(next);
    return next;
  }
}
