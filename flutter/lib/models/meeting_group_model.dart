import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import '../common.dart';
import '../common/direct_chat_sqlite.dart';
import 'platform_model.dart';

/// A P2P meeting group — created locally, persisted via key-value store.
///
/// No server involved. The host creates the group, generates invite links,
/// and each peer stores its own copy of the group metadata. Group messages
/// are delivered via the existing P2P direct chat infrastructure using a
/// shared conversation ID derived from this group's [meetingId].
class MeetingGroup {
  MeetingGroup({
    required this.meetingId,
    required this.title,
    required this.hostPeerId,
    required this.hostDisplayName,
    DateTime? createdAt,
    this.members,
    this.activeSessionEndpoint = '',
    this.inviteShortCode = '',
    this.presenterPeerId = '',
    this.presenterDisplayName = '',
    this.viewerToken = '',
    this.startTime,
    this.durationMinutes = 60,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Globally unique meeting ID (UUID v4).
  final String meetingId;

  /// Human-readable title, e.g. "周五例会".
  String title;

  /// The peer who created this group (the session host).
  final String hostPeerId;
  final String hostDisplayName;

  /// When the group was created (UTC).
  final DateTime createdAt;

  /// List of member peer IDs + display names.
  List<MeetingMember>? members;

  /// When the host is actively sharing a remote session, this is the
  /// endpoint viewers connect to (IP:port or DDNS domain).
  String activeSessionEndpoint;

  /// Current invite short code (Crockford base32). Empty if none active.
  String inviteShortCode;

  /// The peer who presents/demos the screen (the "演示人").
  /// Defaults to the host when empty. Only the host and the presenter
  /// may control the mouse/keyboard during a live session; everyone
  /// else joins as a read-only viewer.
  String presenterPeerId;
  String presenterDisplayName;

  /// Viewer invite token issued by the host when a live session starts.
  /// Members use this token to join as read-only viewers (进入观看); the
  /// host and the designated presenter keep full control.
  String viewerToken;

  /// 会议计划开始时间（UTC）。为空表示“立即开始”。
  DateTime? startTime;

  /// 会议时长（分钟）。0 表示不限时长，默认 60 分钟。
  int durationMinutes;

  bool get isHost => hostPeerId == gFFI.serverModel.id;

  /// True when the local user is allowed to control the session
  /// (host or the designated presenter).
  bool get isPresenter =>
      presenterPeerId.isNotEmpty
          ? presenterPeerId == gFFI.serverModel.id
          : isHost;
  bool get hasActiveSession => activeSessionEndpoint.isNotEmpty;
  bool get hasActiveInvite => inviteShortCode.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'meeting_id': meetingId,
    'title': title,
    'host_peer_id': hostPeerId,
    'host_display_name': hostDisplayName,
    'created_at': createdAt.toUtc().toIso8601String(),
    'members': (members ?? []).map((m) => m.toJson()).toList(),
    'active_session_endpoint': activeSessionEndpoint,
    'invite_short_code': inviteShortCode,
    'presenter_peer_id': presenterPeerId,
    'presenter_display_name': presenterDisplayName,
    'viewer_token': viewerToken,
    'start_time': startTime?.toUtc().toIso8601String(),
    'duration_minutes': durationMinutes,
  };

  factory MeetingGroup.fromJson(Map<String, dynamic> json) => MeetingGroup(
    meetingId: (json['meeting_id'] ?? '').toString(),
    title: (json['title'] ?? '').toString(),
    hostPeerId: (json['host_peer_id'] ?? '').toString(),
    hostDisplayName: (json['host_display_name'] ?? '').toString(),
    createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
    members: ((json['members'] as List?) ?? [])
        .map((m) => MeetingMember.fromJson(m as Map<String, dynamic>))
        .toList(),
    activeSessionEndpoint: (json['active_session_endpoint'] ?? '').toString(),
    inviteShortCode: (json['invite_short_code'] ?? '').toString(),
    presenterPeerId: (json['presenter_peer_id'] ?? '').toString(),
    presenterDisplayName: (json['presenter_display_name'] ?? '').toString(),
    viewerToken: (json['viewer_token'] ?? '').toString(),
    startTime: DateTime.tryParse((json['start_time'] ?? '').toString()),
    durationMinutes: int.tryParse('${json['duration_minutes'] ?? 60}') ?? 60,
  );

  /// The shared conversation ID used by all members for group chat messages.
  /// Derived deterministically from [meetingId] so every peer derives the same ID.
  String get conversationId => 'meeting:$meetingId';
}

class MeetingMember {
  final String peerId;
  final String displayName;
  final DateTime joinedAt;

  const MeetingMember({
    required this.peerId,
    required this.displayName,
    required this.joinedAt,
  });

  Map<String, dynamic> toJson() => {
    'peer_id': peerId,
    'display_name': displayName,
    'joined_at': joinedAt.toUtc().toIso8601String(),
  };

  factory MeetingMember.fromJson(Map<String, dynamic> json) => MeetingMember(
    peerId: (json['peer_id'] ?? '').toString(),
    displayName: (json['display_name'] ?? '').toString(),
    joinedAt: DateTime.tryParse((json['joined_at'] ?? '').toString())
        ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}

/// Thread-safe local store for meeting groups.
///
/// All data is stored exclusively in the local SQLite database
/// (`ldesk_chat.db`), so it survives app restarts with full transaction
/// safety. No server dependency. The in-memory `RxList` mirrors the DB
/// rows for UI binding. Every write goes through SQLite transactions —
/// there is no KV fallback path that could cause data desync ("错位").
class MeetingGroupStore {
 MeetingGroupStore._();

 static final RxList<MeetingGroup> _groups = <MeetingGroup>[].obs;

 /// All known groups. Read-only observable — bind UI with Obx.
 static List<MeetingGroup> get all => List.unmodifiable(_groups);
 static RxList<MeetingGroup> get reactive => _groups;

 /// Load from SQLite. Call once at app startup.
 static void load() {
 _loadAsync();
 }

 static Future<void> _loadAsync() async {
 try {
 final rows = await DirectChatSqlite.instance.loadAllMeetings();
 final groups = <MeetingGroup>[];
 for (final row in rows) {
 final meetingId = (row['meeting_id'] ?? '').toString();
 if (meetingId.isEmpty) continue;
 final membersRaw = (row['members'] as List?) ?? [];
 final members = membersRaw.map((m) => MeetingMember(
 peerId: (m['peer_id'] ?? '').toString(),
 displayName: (m['display_name'] ?? '').toString(),
 joinedAt: DateTime.tryParse((m['joined_at'] ?? '').toString()) ??
 DateTime.now(),
 )).toList();
 final group = MeetingGroup(
 meetingId: meetingId,
 title: (row['title'] ?? '').toString(),
 hostPeerId: (row['host_peer_id'] ?? '').toString(),
 hostDisplayName: (row['host_display_name'] ?? '').toString(),
 createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()) ??
 DateTime.now(),
 members: members,
 activeSessionEndpoint:
 (row['active_session_endpoint'] ?? '').toString(),
 inviteShortCode: (row['invite_short_code'] ?? '').toString(),
 presenterPeerId: (row['presenter_peer_id'] ?? '').toString(),
 presenterDisplayName:
 (row['presenter_display_name'] ?? '').toString(),
 viewerToken: (row['viewer_token'] ?? '').toString(),
 startTime: DateTime.tryParse(
 (row['start_time'] ?? '').toString()),
 durationMinutes:
 int.tryParse('${row['duration_minutes']}') ?? 60,
 );
 groups.add(group);
 }
 _groups.assignAll(groups);
 } catch (e) {
 debugPrint('Failed to load meeting groups from SQLite: $e');
 // No KV fallback — SQLite is the single source of truth. If the DB
 // is unavailable the in-memory list stays empty until the next
 // successful load, rather than showing stale KV data that could
 // desync from what other processes have written.
 }
 }

 /// Persist a single meeting group to SQLite (transaction-safe).
 static Future<void> _persistGroup(MeetingGroup g) async {
 await DirectChatSqlite.instance.upsertMeeting({
 'meeting_id': g.meetingId,
 'title': g.title,
 'host_peer_id': g.hostPeerId,
 'host_display_name': g.hostDisplayName,
 'created_at': g.createdAt.toUtc().toIso8601String(),
 'active_session_endpoint': g.activeSessionEndpoint,
 'invite_short_code': g.inviteShortCode,
 'presenter_peer_id': g.presenterPeerId,
 'presenter_display_name': g.presenterDisplayName,
 'viewer_token': g.viewerToken,
 'start_time': g.startTime?.toUtc().toIso8601String() ?? '',
 'duration_minutes': g.durationMinutes,
 });
 final members = (g.members ?? <MeetingMember>[])
 .map((m) => <String, dynamic>{
 'peer_id': m.peerId,
 'display_name': m.displayName,
 'joined_at': m.joinedAt.toUtc().toIso8601String(),
 })
 .toList();
 await DirectChatSqlite.instance.replaceMeetingMembers(
 g.meetingId, members);
 _groups.refresh();
 }

 /// Persist all groups (bulk save). Used when migrating or syncing.
 static Future<void> _saveAll() async {
 for (final g in _groups) {
 await _persistGroup(g);
 }
 _groups.refresh();
 }

 /// Public save (bridges to private _persistGroup for external callers).
 static Future<void> save() async => _saveAll();

/// Create a new meeting group. Returns the new [MeetingGroup].
 static MeetingGroup create({
 required String title,
 required String hostPeerId,
 required String hostDisplayName,
 String? presenterPeerId,
 String? presenterDisplayName,
 DateTime? startTime,
 int durationMinutes = 60,
 }) {
 final group = MeetingGroup(
 meetingId: const Uuid().v4(),
 title: title.trim().isNotEmpty ? title.trim() : hostDisplayName,
 hostPeerId: hostPeerId,
 hostDisplayName: hostDisplayName,
 // The presenter defaults to the host (发起人自动是新建会议的人),
 // but can be reassigned to another member afterwards.
 presenterPeerId: presenterPeerId ?? hostPeerId,
 presenterDisplayName: presenterDisplayName ?? hostDisplayName,
 // The host is rendered separately in the member list, so do not
 // duplicate the host inside [members] (older builds persisted the
 // host as a member and showed the host twice).
 members: const [],
 startTime: startTime,
 durationMinutes: durationMinutes,
 );
 _groups.add(group);
 unawaited(_persistGroup(group));
 return group;
 }

  /// Find a group by [meetingId].
  static MeetingGroup? find(String meetingId) {
    try {
      return _groups.firstWhere((g) => g.meetingId == meetingId);
    } catch (_) {
      return null;
    }
  }

  /// Find the group a peer belongs to by [peerId].
  static List<MeetingGroup> findByPeer(String peerId) {
    return _groups.where((g) =>
        g.members?.any((m) => m.peerId == peerId) ?? false
    ).toList();
  }

/// Add a member to an existing group.
 static void addMember(String meetingId, String peerId, String displayName) {
 final group = find(meetingId);
 if (group == null) return;
 if (peerId == group.hostPeerId) return;
 if (group.members?.any((m) => m.peerId == peerId) ?? false) return;
 group.members ??= [];
 group.members!.add(MeetingMember(
 peerId: peerId,
 displayName: displayName,
 joinedAt: DateTime.now(),
 ));
 final idx = _groups.indexWhere((g) => g.meetingId == meetingId);
 if (idx >= 0) _groups[idx] = group;
 unawaited(_persistGroup(group));
 }

 /// Remove a member from an existing group. No-op if not found.
 static void removeMember(String meetingId, String peerId) {
 final group = find(meetingId);
 if (group == null) return;
 if (group.members == null || group.members!.isEmpty) return;
 group.members!.removeWhere((m) => m.peerId == peerId);
 // If the removed member was the presenter, fall back to the host.
 if (group.presenterPeerId == peerId) {
 group.presenterPeerId = group.hostPeerId;
 group.presenterDisplayName = group.hostDisplayName;
 }
 final idx = _groups.indexWhere((g) => g.meetingId == meetingId);
 if (idx >= 0) _groups[idx] = group;
 unawaited(_persistGroup(group));
 }

 /// Assign (or change) the presenter for a meeting. Only meaningful on the
 /// host side, but harmless elsewhere. Returns true on success.
 static bool setPresenter(String meetingId, String peerId, String displayName) {
 final group = find(meetingId);
 if (group == null) return false;
 group.presenterPeerId = peerId;
 group.presenterDisplayName =
 displayName.trim().isNotEmpty ? displayName : peerId;
 final idx = _groups.indexWhere((g) => g.meetingId == meetingId);
 if (idx >= 0) _groups[idx] = group;
 unawaited(_persistGroup(group));
 return true;
 }

 /// Store the viewer invite token issued by the host for the live session.
 static void setViewerToken(String meetingId, String token) {
 final group = find(meetingId);
 if (group == null) return;
 group.viewerToken = token.trim();
 final idx = _groups.indexWhere((g) => g.meetingId == meetingId);
 if (idx >= 0) _groups[idx] = group;
 unawaited(_persistGroup(group));
 }

 /// Update the active session endpoint (host starts sharing).
 static void setSessionEndpoint(String meetingId, String endpoint) {
 final group = find(meetingId);
 if (group == null) return;
 group.activeSessionEndpoint = endpoint;
 final idx = _groups.indexWhere((g) => g.meetingId == meetingId);
 if (idx >= 0) _groups[idx] = group;
 unawaited(_persistGroup(group));
 }

 /// Update the invite short code (host regenerates invite).
 static void setInviteCode(String meetingId, String shortCode) {
 final group = find(meetingId);
 if (group == null) return;
 group.inviteShortCode = shortCode;
 final idx = _groups.indexWhere((g) => g.meetingId == meetingId);
 if (idx >= 0) _groups[idx] = group;
 unawaited(_persistGroup(group));
 }

 /// Remove a meeting group entirely.
 static void delete(String meetingId) {
 _groups.removeWhere((g) => g.meetingId == meetingId);
 unawaited(DirectChatSqlite.instance.deleteMeeting(meetingId));
 }

  /// Alias for delete.
  static Future<void> remove(String meetingId) async => delete(meetingId);
}
