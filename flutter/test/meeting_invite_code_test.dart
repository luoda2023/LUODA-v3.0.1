// LUODA 3.1.1 - Meeting invite short code persistence contract tests.
//
// 回归防护：inviteShortCode 曾在重启后丢失。根因是两层：
//   1. 模型层：invite_short_code 未随 toJson/fromJson 完整 round-trip；
//   2. SQLite 层：旧库从未 ALTER 出 invite_short_code 列，写入被吞。
// 本文件锁定模型层契约（SQLite 迁移由 _ensureMeetingsColumns 保障），
// 确保邀请码一旦设置，序列化/反序列化（= 启动加载）后不退化。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/models/meeting_group_model.dart';

MeetingGroup _group() {
  return MeetingGroup(
    meetingId: 'm-${DateTime.now().microsecondsSinceEpoch}',
    title: 'Demo',
    hostPeerId: 'HOST-1',
    hostDisplayName: 'Alice',
  );
}

Map<String, dynamic> _roundTrip(MeetingGroup group) {
  return Map<String, dynamic>.from(
    jsonDecode(jsonEncode(group.toJson())) as Map,
  );
}

void main() {
  group('MeetingGroup invite short code JSON contract', () {
    test('empty invite short code round-trips as empty', () {
      final restored = MeetingGroup.fromJson(_roundTrip(_group()));
      expect(restored.inviteShortCode, '');
      expect(restored.hasActiveInvite, false);
    });

    test('non-empty invite short code survives JSON round-trip', () {
      final group = _group();
      group.inviteShortCode = 'J6K29P47NQXR';
      final restored = MeetingGroup.fromJson(_roundTrip(group));
      expect(restored.inviteShortCode, 'J6K29P47NQXR');
      expect(restored.hasActiveInvite, true);
    });

    test('legacy JSON without invite_short_code parses to empty (no throw)', () {
      final legacy = <String, dynamic>{
        'meeting_id': 'm-legacy',
        'title': 'Old',
        'host_peer_id': 'HOST-1',
        'host_display_name': 'Alice',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'members': <dynamic>[],
        'active_session_endpoint': '',
        // 旧数据缺 invite_short_code 字段，反序列化不能抛异常。
      };
      final group = MeetingGroup.fromJson(legacy);
      expect(group.inviteShortCode, '');
      expect(group.hasActiveInvite, false);
    });

    test('invite_short_code key name is stable (do not rename)', () {
      final group = _group();
      group.inviteShortCode = 'ABCD2345';
      final json = group.toJson();
      // SQLite 列名 / 加载读回都依赖这个 key，重命名会导致丢失。
      expect(json.containsKey('invite_short_code'), true);
      expect(json['invite_short_code'], 'ABCD2345');
    });

    test('short code keeps full 8+ chars, no truncation on round-trip', () {
      final group = _group();
      // 短码生成 = 6 位 Crockford 字符 + 2 位微秒尾缀 = 8 位。
      final code = 'ABCDEF12';
      group.inviteShortCode = code;
      final restored = MeetingGroup.fromJson(_roundTrip(group));
      expect(restored.inviteShortCode, code);
      expect(restored.inviteShortCode.length, 8);
    });
  });
}
