import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_chat_sqlite.dart';

void main() {
  group('legacy history halfwidth migration', () {
    test('normalizes fullwidth call timestamp and legacy separator', () {
      expect(
        DirectChatSqlite.normalizeLegacyCallBubble(
          '[call] 语音通话 · ０４：０５',
        ),
        '[call] 语音通话 - 04:05',
      );
    });

    test('normalizes fullwidth ISO timestamp without changing its meaning', () {
      expect(
        DirectChatSqlite.normalizeLegacyHistoryTimestamp(
          '２０２６-０９-０９T１２：３４：５６Z',
        ),
        '2026-09-09T12:34:56Z',
      );
    });

    test('does not rewrite ordinary Chinese message text', () {
      const text = '你好，会议时间是下午三点。';
      expect(DirectChatSqlite.normalizeLegacyCallBubble(text), text);
    });

    test('does not rewrite non-call machine-like text as a call bubble', () {
      const text = '[location]３１．２,１２１．５|家';
      expect(DirectChatSqlite.normalizeLegacyCallBubble(text), text);
    });

    test('migration normalization is idempotent', () {
      const legacy = '[call] 视频通话 · ０１：０９';
      final once = DirectChatSqlite.normalizeLegacyCallBubble(legacy);
      final twice = DirectChatSqlite.normalizeLegacyCallBubble(once);
      expect(once, '[call] 视频通话 - 01:09');
      expect(twice, once);
    });
  });
}
