import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_chat.dart';

/// DirectChatCall（通话记录灰气泡）单元测试：
/// 锁定「半角连字符分隔 + MM:SS 半角时长 + missed 标记」格式，
/// 并验证对旧版 ` · `（U+00B7）记录的向后兼容解析，防格式退化。
void main() {
  group('encode（新格式锁定）', () {
    test('语音通话带时长：半角连字符 + MM:SS 半角冒号', () {
      const call = DirectChatCall(label: '语音通话', duration: '04:52');
      expect(call.encode(), '[call]语音通话 - 04:52');
      // 锁定分隔符：必须是半角连字符，绝不回退到 U+00B7 中间点。
      expect(call.encode(), isNot(contains('·')));
      // 锁定时长：半角冒号 + 半角数字。
      expect(call.duration, matches(RegExp(r'^\d{2}:\d{2}$')));
    });

    test('视频通话带时长', () {
      const call = DirectChatCall(label: '视频通话', duration: '01:23');
      expect(call.encode(), '[call]视频通话 - 01:23');
    });

    test('未接来电（missed）：无时长、无分隔符', () {
      const call = DirectChatCall(label: '未接来电', missed: true);
      expect(call.encode(), '[call]未接来电');
      expect(call.encode(), isNot(contains(' - ')));
    });

    test('空时长时不输出多余分隔符', () {
      const call = DirectChatCall(label: '语音通话');
      expect(call.encode(), '[call]语音通话');
    });
  });

  group('tryParse（新旧分隔符兼容）', () {
    test('新格式 ` - ` 半角连字符', () {
      final call = DirectChatCall.tryParse('[call]语音通话 - 04:52');
      expect(call, isNotNull);
      expect(call!.label, '语音通话');
      expect(call.duration, '04:52');
      expect(call.missed, isFalse);
    });

    test('旧格式 ` · `（U+00B7 中间点）仍可解析', () {
      final call = DirectChatCall.tryParse('[call]语音通话 · 04:52');
      expect(call, isNotNull);
      expect(call!.label, '语音通话');
      expect(call.duration, '04:52');
      expect(call.missed, isFalse);
    });

    test('旧格式视频通话 · 时长', () {
      final call = DirectChatCall.tryParse('[call]视频通话 · 01:23');
      expect(call, isNotNull);
      expect(call!.label, '视频通话');
      expect(call.duration, '01:23');
    });

    test('落库实际格式（[call] 后带空格）可解析', () {
      // _recordVoiceCallBubble 生成 '[call] 语音通话 - 04:52'（call 后有空格）。
      final call = DirectChatCall.tryParse('[call] 语音通话 - 04:52');
      expect(call, isNotNull);
      expect(call!.label, '语音通话');
      expect(call.duration, '04:52');
    });

    test('missed 标记：未接来电', () {
      final call = DirectChatCall.tryParse('[call]未接来电');
      expect(call, isNotNull);
      expect(call!.missed, isTrue);
      expect(call.duration, '');
      expect(call.label, '未接来电');
    });

    test('非通话文本返回 null', () {
      expect(DirectChatCall.tryParse('普通消息'), isNull);
      expect(DirectChatCall.tryParse(''), isNull);
      expect(DirectChatCall.tryParse('[location]31.2,121.5|家'), isNull);
    });

    test('duration 含空格时 trim', () {
      final call = DirectChatCall.tryParse('[call]语音通话 - 04:52 ');
      expect(call, isNotNull);
      expect(call!.duration, '04:52');
    });
  });

  group('round-trip（encode → tryParse 一致）', () {
    test('语音通话', () {
      const call = DirectChatCall(label: '语音通话', duration: '04:52');
      final parsed = DirectChatCall.tryParse(call.encode());
      expect(parsed!.label, call.label);
      expect(parsed.duration, call.duration);
      expect(parsed.missed, call.missed);
    });

    test('未接来电', () {
      const call = DirectChatCall(label: '未接来电', missed: true);
      final parsed = DirectChatCall.tryParse(call.encode());
      expect(parsed!.label, call.label);
      expect(parsed.missed, isTrue);
    });
  });

  group('格式防回归（全角字符禁令）', () {
    test('duration 必须是半角 MM:SS', () {
      const call = DirectChatCall(label: '语音通话', duration: '04:52');
      // 全角冒号/全角数字不得进入编码结果。
      expect(call.encode(), isNot(contains('：')));
      expect(call.encode(), isNot(contains(RegExp(r'[０-９]'))));
    });

    test('encode 与落库源头格式一致（[call] 前缀容忍空格差异）', () {
      const call = DirectChatCall(label: '语音通话', duration: '04:52');
      // _recordVoiceCallBubble 生成 '[call] 语音通话 - 04:52'；
      // 两种前缀空格都能被 tryParse 归一化解析。
      final fromBubble = DirectChatCall.tryParse('[call] 语音通话 - 04:52');
      final fromEncode = DirectChatCall.tryParse(call.encode());
      expect(fromBubble!.label, fromEncode!.label);
      expect(fromBubble.duration, fromEncode.duration);
    });
  });

  group('落库源头源码契约（_recordVoiceCallBubble 半角锁定）', () {
    test('时长格式化使用半角 padLeft 冒号，落库分隔符为半角连字符', () {
      final src = File('lib/models/chat_model.dart').readAsStringSync();
      // 时长 MM:SS：半角冒号拼接（padLeft 之后紧跟半角冒号）。
      expect(src, contains("padLeft(2, '0')}:"));
      expect(src, contains("seconds.toString().padLeft(2, '0')}'"));
      // 落库分隔符：半角连字符；禁止中间点版本。
      expect(src, contains("'[call] \$label - \$dur'"));
      expect(src, isNot(contains("'[call] \$label · \$dur'")));
    });
  });
}