import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import '../common.dart';
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

  bool get isHost => hostPeerId == gFFI.serverModel.id;
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
/// All data is stored in the local key-value config store (same backend as
/// contact categories), so it survives app restarts. No server dependency.
class MeetingGroupStore {
  MeetingGroupStore._();
  static const _storageKey = 'meeting_groups_v1';

  static final RxList<MeetingGroup> _groups = <MeetingGroup>[].obs;

  /// All known groups. Read-only observable — bind UI with Obx.
  static List<MeetingGroup> get all => List.unmodifiable(_groups);
  static RxList<MeetingGroup> get reactive => _groups;

  /// Load from persistent storage. Call once at app startup.
  static void load() {
    final raw = bind.mainGetLocalOption(key: _storageKey);
    if (raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _groups.assignAll(
          decoded
              .map((item) => MeetingGroup.fromJson(item as Map<String, dynamic>))
              .where((g) => g.meetingId.isNotEmpty),
        );
      }
    } catch (e) {
      debugPrint('Failed to load meeting groups: $e');
    }
  }

  static void _save() {
    bind.mainSetLocalOption(
      key: _storageKey,
      value: jsonEncode(_groups.map((g) => g.toJson()).toList()),
    );
  }

  /// Create a new meeting group. Returns the new [MeetingGroup].
  static MeetingGroup create({
    required String title,
    required String hostPeerId,
    required String hostDisplayName,
  }) {
    final group = MeetingGroup(
      meetingId: const Uuid().v4(),
      title: title.trim().isNotEmpty ? title.trim() : hostDisplayName,
      hostPeerId: hostPeerId,
      hostDisplayName: hostDisplayName,
      members: [
        MeetingMember(
          peerId: hostPeerId,
          displayName: hostDisplayName,
          joinedAt: DateTime.now(),
        ),
      ],
    );
    _groups.add(group);
    _save();
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
    if (group.members?.any((m) => m.peerId == peerId) ?? false) return;
    group.members ??= [];
    group.members!.add(MeetingMember(
      peerId: peerId,
      displayName: displayName,
      joinedAt: DateTime.now(),
    ));
    final idx = _groups.indexWhere((g) => g.meetingId == meetingId);
    if (idx >= 0) _groups[idx] = group;
    _save();
  }

  /// Update the active session endpoint (host starts sharing).
  static void setSessionEndpoint(String meetingId, String endpoint) {
    final group = find(meetingId);
    if (group == null) return;
    group.activeSessionEndpoint = endpoint;
    final idx = _groups.indexWhere((g) => g.meetingId == meetingId);
    if (idx >= 0) _groups[idx] = group;
    _save();
  }

  /// Update the invite short code (host regenerates invite).
  static void setInviteCode(String meetingId, String shortCode) {
    final group = find(meetingId);
    if (group == null) return;
    group.inviteShortCode = shortCode;
    final idx = _groups.indexWhere((g) => g.meetingId == meetingId);
    if (idx >= 0) _groups[idx] = group;
    _save();
  }

  /// Remove a meeting group entirely.
  static void delete(String meetingId) {
    _groups.removeWhere((g) => g.meetingId == meetingId);
    _save();
  }
}
