import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_chat.dart';
import 'package:luoda_flutter/common/direct_chat_storage.dart';

/// Verifies that a file delivered by the transfer subsystem can be linked
/// back to the chat record that announced it, so tapping the message shows
/// the preview (files > 5 MB bypass the inline-bytes path).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ldesk_link_test');
    DirectChatRepository.debugStorageOverride = _TempStorage(tempDir);
    await DirectChatRepository.instance.resetForTest();
  });

  tearDown(() async {
    DirectChatRepository.debugStorageOverride = null;
    await tempDir.delete(recursive: true);
  });

  test('linkReceivedTransferFile updates the matching record', () async {
    final saved = File('${tempDir.path}${Platform.pathSeparator}plan.docx');
    await saved.writeAsBytes(List<int>.filled(64, 7));

    await DirectChatRepository.instance.createOutgoing(
      conversationId: 'peer-1',
      kind: DirectChatKind.file,
      text: 'Sent file: plan.docx',
      senderId: 'me',
      senderName: 'Me',
      senderAvatar: '',
      fileName: 'plan.docx',
      fileSize: 64,
      connectionTarget: 'peer-1',
    );

    final linked = await DirectChatRepository.instance.linkReceivedTransferFile(
      conversationId: 'peer-1',
      fileName: 'plan.docx',
      fileSize: 64,
      localPath: saved.path,
    );
    expect(linked, isTrue);

    final records = await DirectChatRepository.instance.forConversation('peer-1');
    expect(records, hasLength(1));
    expect(records.single.localPath, saved.path);
  });

  test('linkReceivedTransferFile ignores wrong conversation or name', () async {
    await DirectChatRepository.instance.createOutgoing(
      conversationId: 'peer-1',
      kind: DirectChatKind.file,
      text: 'Sent file: a.pdf',
      senderId: 'me',
      senderName: 'Me',
      senderAvatar: '',
      fileName: 'a.pdf',
      fileSize: 10,
      connectionTarget: 'peer-1',
    );

    expect(
      await DirectChatRepository.instance.linkReceivedTransferFile(
        conversationId: 'peer-2',
        fileName: 'a.pdf',
        fileSize: 10,
        localPath: 'C:\\x\\a.pdf',
      ),
      isFalse,
    );
    expect(
      await DirectChatRepository.instance.linkReceivedTransferFile(
        conversationId: 'peer-1',
        fileName: 'other.pdf',
        fileSize: 10,
        localPath: 'C:\\x\\a.pdf',
      ),
      isFalse,
    );
  });
}

/// File-backed storage inside the test's temp dir.
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
