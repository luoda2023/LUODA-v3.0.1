// LUODA 3.1.24 - AI meeting minutes model tests.
//
// * Pure Dart tests for transcript builder + local digest + entry JSON.
// * SQLite-backed integration test for MeetingMinutesService.generate
//   (isolated temp DB, injected AI caller + KV overrides, no FFI).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_chat.dart';
import 'package:luoda_flutter/common/direct_chat_sqlite.dart';
import 'package:luoda_flutter/models/meeting_minutes_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DirectChatRecord _record({
  required String id,
  required DirectChatKind kind,
  required String text,
  required String sender,
  DateTime? at,
  String fileName = '',
}) {
  return DirectChatRecord(
    id: id,
    conversationId: 'meeting:m1',
    originDeviceId: 'dev',
    originSequence: 0,
    direction: DirectChatDirection.outgoing,
    kind: kind,
    text: text,
    senderId: sender,
    senderName: sender,
    senderAvatar: '',
    sentAt: at ?? DateTime.utc(2026, 9, 2, 10),
    delivery: DirectChatDelivery.delivered,
    fileName: fileName,
  );
}

void main() {
  group('MeetingTranscriptBuilder', () {
    test('sorts newest-first history into chronological order', () {
      final recs = [
        _record(id: 'a', kind: DirectChatKind.text, text: 'later', sender: 'A',
            at: DateTime.utc(2026, 9, 2, 11)),
        _record(id: 'b', kind: DirectChatKind.text, text: 'earlier', sender: 'A',
            at: DateTime.utc(2026, 9, 2, 9)),
      ];
      final sorted = MeetingTranscriptBuilder.normalizeOrder(recs);
      expect(sorted.map((e) => e.id).toList(), ['b', 'a']);
    });

    test('keeps text verbatim with speaker tag', () {
      final out = MeetingTranscriptBuilder.build([
        _record(id: 'a', kind: DirectChatKind.text, text: '我们讨论排期', sender: '小明'),
      ]);
      expect(out, contains('[小明] 我们讨论排期'));
    });

    test('media reduced to markers', () {
      final out = MeetingTranscriptBuilder.build([
        _record(id: 'f', kind: DirectChatKind.file, text: '', sender: 'A',
            fileName: '需求文档.docx'),
      ]);
      expect(out, contains('[A] 发送了文件:需求文档.docx'));
    });

    test('skips empty text', () {
      final out = MeetingTranscriptBuilder.build([
        _record(id: 'a', kind: DirectChatKind.text, text: '   ', sender: 'A'),
      ]);
      expect(out.trim(), isEmpty);
    });
  });

  group('LocalMinutesDigest', () {
    test('summarises participants and message stats', () {
      final recs = [
        _record(id: 'a', kind: DirectChatKind.text, text: '进度没问题', sender: 'Alice'),
        _record(id: 'b', kind: DirectChatKind.text, text: '预算要确认', sender: 'Bob'),
        _record(id: 'c', kind: DirectChatKind.image, text: '', sender: 'Carol'),
      ];
      final out = LocalMinutesDigest.build('周五例会', recs);
      expect(out, contains('周五例会'));
      expect(out, contains('Alice'));
      expect(out, contains('Bob'));
      expect(out, contains('文字 2 条'));
      expect(out, contains('图片 1'));
    });

    test('no-discussion note when no text messages', () {
      final out = LocalMinutesDigest.build('空会', []);
      expect(out, contains('暂无文字讨论记录'));
    });
  });

  group('MeetingMinutesEntry', () {
    test('JSON round-trips', () {
      final e = MeetingMinutesEntry(
        meetingId: 'm1',
        title: '例会',
        generatedAt: DateTime.utc(2026, 9, 2, 8),
        body: '## 议题\n- 排期',
        source: 'ai',
        messageCount: 12,
      );
      final restored = MeetingMinutesEntry.fromJson(
          Map<String, dynamic>.from(jsonDecode(jsonEncode(e.toJson())) as Map));
      expect(restored.meetingId, 'm1');
      expect(restored.source, 'ai');
      expect(restored.messageCount, 12);
      expect(restored.body, contains('排期'));
    });
  });

  group('MeetingMinutesService.generate (SQLite-backed)', () {
    late Directory tempDir;
    String? savedJson;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      tempDir = await Directory.systemTemp.createTemp('ldesk_minutes_test');
      DirectChatSqlite.debugDbDirOverride = tempDir.path;
      await DirectChatSqlite.instance.resetForTest();
      savedJson = null;
      MeetingMinutesService.kvGetOverride = (key) => savedJson ?? '';
      MeetingMinutesService.kvSetOverride =
          (key, value) async => savedJson = value;
      MeetingMinutesService.instance.aiCaller =
          (title, transcript) async => '## 议题\nAI 纪要:$title';
    });

    tearDown(() async {
      MeetingMinutesService.instance.aiCaller = null;
      MeetingMinutesService.kvGetOverride = null;
      MeetingMinutesService.kvSetOverride = null;
      await DirectChatSqlite.instance.resetForTest();
      DirectChatSqlite.debugDbDirOverride = null;
      await tempDir.delete(recursive: true);
    });

    test('uses injected AI caller and persists entry', () async {
      await DirectChatSqlite.instance.createOutgoing(
        conversationId: 'meeting:m1',
        kind: DirectChatKind.text,
        text: '我们确认了周五的排期',
        senderId: 'peerA',
        senderName: 'Alice',
        senderAvatar: '',
        connectionTarget: 'meeting:m1',
      );

      final entry = await MeetingMinutesService.instance.generate(
        meetingId: 'm1',
        title: '周五例会',
        conversationId: 'meeting:m1',
        persist: true,
      );
      expect(entry.source, 'ai');
      expect(entry.body, contains('AI 纪要:周五例会'));
      expect(entry.messageCount, 1);

      // Reload from the injected KV store.
      MeetingMinutesService.instance.load();
      final saved = MeetingMinutesService.instance.forMeeting('m1');
      expect(saved, isNotEmpty);
      expect(saved.first.title, '周五例会');
    });

    test('falls back to local digest when AI returns null', () async {
      MeetingMinutesService.instance.aiCaller = null;
      await DirectChatSqlite.instance.createOutgoing(
        conversationId: 'meeting:m1',
        kind: DirectChatKind.text,
        text: '进度没问题',
        senderId: 'peerA',
        senderName: 'Alice',
        senderAvatar: '',
        connectionTarget: 'meeting:m1',
      );

      final entry = await MeetingMinutesService.instance.generate(
        meetingId: 'm1',
        title: '周五例会',
        conversationId: 'meeting:m1',
        persist: false,
      );
      expect(entry.source, 'local');
      expect(entry.body, contains('本地整理'));
    });
  });
}
