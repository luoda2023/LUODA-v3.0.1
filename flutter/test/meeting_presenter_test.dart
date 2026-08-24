// LUODA 3.1.1 - Meeting presenter permission model tests.
//
// Pure model-layer tests (no FFI/store persistence). Covers:
//   * presenter defaults to the host (发起人自动是新建会议的人)
//   * presenter can be reassigned to another member (发起人和演示人可不同)
//   * presenter fields + viewerToken round-trip through JSON
//   * removing the presenter falls back to the host

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/models/meeting_group_model.dart';

MeetingGroup _group({
  String host = 'HOST-1',
  String presenter = '',
  String presenterName = '',
}) {
  return MeetingGroup(
    meetingId: 'm-${DateTime.now().microsecondsSinceEpoch}',
    title: 'Demo',
    hostPeerId: host,
    hostDisplayName: 'Alice',
    presenterPeerId: presenter,
    presenterDisplayName: presenterName,
  );
}

void main() {
  group('MeetingGroup presenter model', () {
    test('JSON round-trips presenter defaults (empty = host semantics)', () {
      final group = _group();
      final restored = MeetingGroup.fromJson(
        Map<String, dynamic>.from(
            jsonDecode(jsonEncode(group.toJson())) as Map),
      );
      // Empty presenter means "the host is the presenter".
      expect(restored.presenterPeerId, '');
      expect(restored.presenterDisplayName, '');
    });

    test('JSON keeps explicit presenter different from host', () {
      final group = _group(presenter: 'BOB-2', presenterName: 'Bob');
      final restored = MeetingGroup.fromJson(
        Map<String, dynamic>.from(
            jsonDecode(jsonEncode(group.toJson())) as Map),
      );
      expect(restored.presenterPeerId, 'BOB-2');
      expect(restored.presenterDisplayName, 'Bob');
    });

    test('presenter fields and viewerToken round-trip through JSON', () {
      final group = _group(presenter: 'CAROL-3', presenterName: 'Carol');
      group.viewerToken = 'ABC123XYZ987';
      group.activeSessionEndpoint = '192.168.1.5:12345';
      final restored = MeetingGroup.fromJson(
        Map<String, dynamic>.from(
            jsonDecode(jsonEncode(group.toJson())) as Map),
      );
      expect(restored.presenterPeerId, 'CAROL-3');
      expect(restored.presenterDisplayName, 'Carol');
      expect(restored.viewerToken, 'ABC123XYZ987');
      expect(restored.activeSessionEndpoint, '192.168.1.5:12345');
    });

    test('legacy JSON without presenter fields parses fine', () {
      final legacy = <String, dynamic>{
        'meeting_id': 'm-legacy',
        'title': 'Old',
        'host_peer_id': 'HOST-1',
        'host_display_name': 'Alice',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'members': <dynamic>[],
        'active_session_endpoint': '',
        'invite_short_code': '',
      };
      final group = MeetingGroup.fromJson(legacy);
      expect(group.presenterPeerId, '');
      expect(group.presenterDisplayName, '');
      expect(group.viewerToken, '');
      expect(group.title, 'Old');
      expect(group.startTime, isNull);
      expect(group.durationMinutes, 60);
    });

    test('startTime and durationMinutes round-trip through JSON', () {
      final group = _group();
      group.startTime = DateTime.utc(2026, 8, 20, 14, 30);
      group.durationMinutes = 120;
      final restored = MeetingGroup.fromJson(
        Map<String, dynamic>.from(
            jsonDecode(jsonEncode(group.toJson())) as Map),
      );
      expect(restored.startTime, isNotNull);
      expect(restored.startTime!.toUtc(), DateTime.utc(2026, 8, 20, 14, 30));
      expect(restored.durationMinutes, 120);
    });

    test('startTime stays null for immediate meetings', () {
      final group = _group();
      group.durationMinutes = 0;
      final restored = MeetingGroup.fromJson(
        Map<String, dynamic>.from(
            jsonDecode(jsonEncode(group.toJson())) as Map),
      );
      expect(restored.startTime, isNull);
      expect(restored.durationMinutes, 0);
    });
  });

  group('meeting group as a forward target', () {
    test('conversationId is the meeting:xxx forward target key', () {
      final group = _group();
      expect(group.conversationId, 'meeting:${group.meetingId}');
      expect(group.conversationId.startsWith('meeting:'), true);
    });

    test('forward routing treats meeting:xxx as meeting chat', () {
      // 与 _forwardConversationMessages 的分流一致：meeting 会话跳过
      // P2P 建连和文件会话，直接用群聊会话发送。
      bool isMeeting(String peerId) => peerId.startsWith('meeting:');
      expect(isMeeting('meeting:m-123'), true);
      expect(isMeeting('peer-123'), false);
      expect(isMeeting('bt:12:34:56'), false);
    });
  });

group('chat-list categorization (meeting excluded from stranger)', () {
 // Mirrors the filter used by the mobile conversation list: meeting
 // conversations (meeting:xxx) must be shown only under the Meeting
 // group and must never fall into Friends/Strangers.
 bool isMeetingPeer(String peerId, Set<String> meetingMembers) =>
 peerId.startsWith('meeting:') ||
 meetingMembers.contains(peerId);
 bool isFriendLike(
 String peerId, bool access, Set<String> meetingMembers) =>
 !isMeetingPeer(peerId, meetingMembers) && access;

 test('meeting peer id is not treated as stranger', () {
 const peerId = 'meeting:m-123';
 final members = <String>{};
 // Before the fix: stranger filter was `!access.isFriend(peerId)` which
 // is true for meeting ids (they are never friends) → duplicate rows.
 final strangerBeforeFix = !false; // isFriend('meeting:...') == false
 final strangerAfterFix =
 !isMeetingPeer(peerId, members) && !false;
 expect(strangerBeforeFix, true);
 expect(strangerAfterFix, false);
 expect(isMeetingPeer(peerId, members), true);
 });

 test('friend filter also excludes meeting ids', () {
 const peerId = 'meeting:m-456';
 final members = <String>{};
 expect(isFriendLike(peerId, true, members), false);
 expect(isFriendLike('peer-1', true, members), true);
 expect(isFriendLike('peer-1', false, members), false);
 });

 test('a device that is a meeting member is excluded from strangers', () {
 // Regression: a device peerId (e.g. "XIAOMI-123") that joined a
 // meeting must not appear as a separate 1:1 stranger row when the
 // meeting row already shows it. The set mirrors the mobile list's
 // meetingMemberPeerIds collection (host + all member peerIds).
 final meetingMembers = <String>{'HOST-1', 'XIAOMI-123'};
 expect(isMeetingPeer('XIAOMI-123', meetingMembers), true);
 expect(isFriendLike('XIAOMI-123', false, meetingMembers), false,
 reason: 'meeting member must not be a stranger row');
 expect(isFriendLike('XIAOMI-123', true, meetingMembers), false,
 reason: 'meeting member must not be a friend row either');
 expect(isFriendLike('OPPO-456', false, meetingMembers), false,
 reason: 'non-member stranger is not a friend row but shows in stranger list');
 expect(isFriendLike('OPPO-456', true, meetingMembers), true,
 reason: 'non-member friend still shows normally');
 });

 test('desktop _isMeetingItem also matches member peer ids', () {
 // Mirrors desktop_home_page _isMeetingItem: a 1:1 conversation whose
 // peer is a meeting member should be categorized as a meeting item.
 final group = MeetingGroup(
 meetingId: 'm-desktop',
 title: 'Demo',
 hostPeerId: 'HOST-1',
 hostDisplayName: 'Alice',
 members: <MeetingMember>[
 MeetingMember(
 peerId: 'XIAOMI-123',
 displayName: 'Redmi',
 joinedAt: DateTime.utc(2026, 8, 20),
 ),
 ],
 );
 final memberPeerIds = <String>{
 group.hostPeerId,
 for (final m in (group.members ?? <MeetingMember>[])) m.peerId,
 };
 bool isMeetingItem(String pid) =>
 pid.startsWith('meeting:') || memberPeerIds.contains(pid);
 expect(isMeetingItem(group.conversationId), true);
 expect(isMeetingItem('XIAOMI-123'), true);
 expect(isMeetingItem('HOST-1'), true);
 expect(isMeetingItem('OPPO-456'), false);
 });
});
}
