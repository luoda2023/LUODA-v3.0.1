import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'backup_restore.dart';
import 'direct_pairing.dart';
import '../models/platform_model.dart';

enum DirectChatAudience { friendsOnly, everyone }

const directChatPermissionDeniedKey = 'direct-chat-permission-denied';
const _legacyDirectChatPermissionDenied =
    'Direct messages rejected by this contact';

bool isDirectChatPermissionDenied(Object? message) {
  final text = message?.toString().trim() ?? '';
  return text == directChatPermissionDeniedKey ||
      text == _legacyDirectChatPermissionDenied;
}

bool isDirectChatSessionReady({
  required bool closed,
  required bool peerInfoReady,
  Object? connectionError,
}) {
  return !closed &&
      peerInfoReady &&
      (connectionError?.toString().trim().isEmpty ?? true);
}

class DirectChatPolicySnapshot {
  const DirectChatPolicySnapshot({
    required this.audience,
    required this.peerPolicies,
    this.alwaysOn = true,
    this.autoReconnect = true,
  });

  final DirectChatAudience audience;
  final Map<String, String> peerPolicies;
  final bool alwaysOn;
  final bool autoReconnect;

  String policyFor(String peerId) => peerPolicies[peerId.trim()] ?? 'ask';

  bool isFriend(String peerId) => policyFor(peerId) == 'allow';

  bool isDenied(String peerId) => policyFor(peerId) == 'deny';

  bool acceptsIncomingChat(
    String peerId, {
    required bool identityVerified,
    bool companionVerified = false,
  }) {
    if (!alwaysOn) return false;
    if (companionVerified) return true;
    if (!identityVerified || isDenied(peerId)) return false;
    if (isFriend(peerId)) return true;
    return audience == DirectChatAudience.everyone;
  }

  bool shouldAutoReconnect(
    String peerId, {
    required bool previouslyAccepted,
  }) {
    return alwaysOn && autoReconnect && previouslyAccepted && !isDenied(peerId);
  }
}

class DirectChatAccessController extends ChangeNotifier {
  DirectChatAccessController._();

  static final DirectChatAccessController instance =
      DirectChatAccessController._();

  static const alwaysOnKey = 'direct-chat-always-on';
  static const trustedOnlyKey = 'direct-chat-trusted-only';
  static const autoReconnectKey = 'direct-chat-auto-reconnect';
  static const peerPoliciesKey = 'direct-chat-contact-policies';
  static const acceptedPeersKey = 'direct-chat-accepted-peers-v1';
  static const audienceMtimeKey = 'direct-chat-audience-mtime';
  // Last-writer timestamp for the audience choice. A companion device that
  // never touched its own audience must not silently downgrade this device's
  // explicit setting.

  bool _loaded = false;
  bool _alwaysOn = true;
  bool _autoReconnect = true;
  DirectChatAudience _audience = DirectChatAudience.friendsOnly;
  String _audienceMtime = '';
  Map<String, String> _peerPolicies = <String, String>{};
  Set<String> _acceptedPeers = <String>{};

  bool get alwaysOn => _alwaysOn;
  bool get autoReconnect => _autoReconnect;
  DirectChatAudience get audience => _audience;
  Map<String, String> get peerPolicies =>
      Map<String, String>.unmodifiable(_peerPolicies);

  DirectChatPolicySnapshot get snapshot => DirectChatPolicySnapshot(
        audience: _audience,
        peerPolicies: _peerPolicies,
        alwaysOn: _alwaysOn,
        autoReconnect: _autoReconnect,
      );

  void load() {
    if (_loaded) return;
    reload(notify: false);
  }

  void reload({bool notify = true}) {
    _alwaysOn = bind.mainGetLocalOption(key: alwaysOnKey) != 'N';
    _autoReconnect = bind.mainGetLocalOption(key: autoReconnectKey) != 'N';
    _audience = bind.mainGetLocalOption(key: trustedOnlyKey) == 'Y'
        ? DirectChatAudience.friendsOnly
        : DirectChatAudience.everyone;
    _audienceMtime = bind.mainGetLocalOption(key: audienceMtimeKey);
    _peerPolicies = _readStringMap(peerPoliciesKey);
    _acceptedPeers = _readStringMap(acceptedPeersKey).keys.toSet();
    _loaded = true;
    if (notify) notifyListeners();
  }

  String policyFor(String peerId) {
    load();
    final id = DirectPairingStore.canonicalConversationId(peerId);
    final accountPolicy = _peerPolicies[id];
    if (accountPolicy != null) return accountPolicy;
    for (final device in DirectPairingStore.boundDevices(id)) {
      final devicePolicy = _peerPolicies[device.peerId];
      if (devicePolicy != null) return devicePolicy;
    }
    return 'ask';
  }

  bool isFriend(String peerId) => policyFor(peerId) == 'allow';

  bool isDenied(String peerId) => policyFor(peerId) == 'deny';

  bool wasPreviouslyAccepted(String peerId) {
    load();
    final id = DirectPairingStore.canonicalConversationId(peerId);
    return _acceptedPeers.contains(id) ||
        DirectPairingStore.boundDevices(id).any(
          (device) => _acceptedPeers.contains(device.peerId),
        );
  }

  bool shouldAutoReconnect(String peerId) {
    load();
    return _alwaysOn &&
        _autoReconnect &&
        wasPreviouslyAccepted(peerId) &&
        !isDenied(peerId);
  }

  Set<String> get autoReconnectPeerIds {
    load();
    return _acceptedPeers
        .map(DirectPairingStore.canonicalConversationId)
        .where(shouldAutoReconnect)
        .toSet();
  }

  Future<void> setAudience(DirectChatAudience value) async {
    load();
    if (_audience == value && _alwaysOn) return;
    _audience = value;
    _alwaysOn = true;
    _audienceMtime = DateTime.now().toUtc().toIso8601String();
    await bind.mainSetLocalOption(key: alwaysOnKey, value: 'Y');
    await bind.mainSetLocalOption(
      key: trustedOnlyKey,
      value: value == DirectChatAudience.friendsOnly ? 'Y' : 'N',
    );
    await bind.mainSetLocalOption(key: audienceMtimeKey, value: _audienceMtime);
    DotChatBackup.schedule();
    notifyListeners();
  }

  Future<void> setAlwaysOn(bool value) async {
    load();
    if (_alwaysOn == value) return;
    _alwaysOn = value;
    await bind.mainSetLocalOption(
      key: alwaysOnKey,
      value: value ? 'Y' : 'N',
    );
    DotChatBackup.schedule();
    notifyListeners();
  }

  Future<void> setAutoReconnect(bool value) async {
    load();
    if (_autoReconnect == value) return;
    _autoReconnect = value;
    await bind.mainSetLocalOption(
      key: autoReconnectKey,
      value: value ? 'Y' : 'N',
    );
    DotChatBackup.schedule();
    notifyListeners();
  }

  Future<void> setPeerPolicy(String peerId, String policy) async {
    DotChatBackup.schedule();
    load();
    final id = DirectPairingStore.canonicalConversationId(peerId);
    if (id.isEmpty ||
        !const <String>{'allow', 'ask', 'deny'}.contains(policy)) {
      return;
    }
    if (policy == 'ask') {
      _peerPolicies.remove(id);
    } else {
      _peerPolicies[id] = policy;
    }
    for (final device in DirectPairingStore.boundDevices(id)) {
      _peerPolicies.remove(device.peerId);
    }
    if (policy == 'deny') _acceptedPeers.remove(id);
    await _writeStringMap(peerPoliciesKey, _peerPolicies);
    await _persistAcceptedPeers();
    notifyListeners();
  }

  Future<void> markAccepted(String peerId) async {
    load();
    final id = DirectPairingStore.canonicalConversationId(peerId);
    if (id.isEmpty || !_acceptedPeers.add(id)) return;
    await _persistAcceptedPeers();
    notifyListeners();
  }

  Map<String, String> _readStringMap(String key) {
    try {
      final raw = bind.mainGetLocalOption(key: key);
      if (raw.isEmpty) return <String, String>{};
      return Map<String, dynamic>.from(jsonDecode(raw) as Map).map(
        (mapKey, value) => MapEntry(mapKey, value.toString()),
      );
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _writeStringMap(String key, Map<String, String> value) {
    return bind.mainSetLocalOption(key: key, value: jsonEncode(value));
  }

  /// 输出可同步的分类信息（好友/陌生人策略），供伴侣设备间同步。
  Map<String, dynamic> toSyncJson() => <String, dynamic>{
        'audience': _audience.name,
        'audience_mtime': _audienceMtime,
        'policies': Map<String, String>.of(_peerPolicies),
      };

  /// 合并伴侣设备同步过来的分类信息。
  Future<void> mergeSyncData(Map<String, dynamic> data) async {
    load();
        final incomingAudience = data['audience']?.toString();
    if (incomingAudience == DirectChatAudience.everyone.name ||
        incomingAudience == DirectChatAudience.friendsOnly.name) {
      // Last-writer-wins: only apply the companion's audience when its mtime
      // is newer than ours, or when neither side has an mtime (legacy peers).
      final incomingMtime = data['audience_mtime']?.toString().trim() ?? '';
      final localMtime = _audienceMtime.trim();
      final apply = localMtime.isEmpty ||
          (incomingMtime.isNotEmpty && incomingMtime.compareTo(localMtime) > 0);
      if (apply) {
        _audience = incomingAudience == DirectChatAudience.everyone.name
            ? DirectChatAudience.everyone
            : DirectChatAudience.friendsOnly;
        if (incomingMtime.isNotEmpty) _audienceMtime = incomingMtime;
        await bind.mainSetLocalOption(
          key: trustedOnlyKey,
          value: _audience == DirectChatAudience.friendsOnly ? 'Y' : 'N',
        );
        if (incomingMtime.isNotEmpty) {
          await bind.mainSetLocalOption(
            key: audienceMtimeKey,
            value: _audienceMtime,
          );
        }
      }
    }
    final incomingPolicies = data['policies'];
    var changed = false;
    if (incomingPolicies is Map) {
      for (final entry in incomingPolicies.entries) {
        final policy = entry.value.toString();
        if (!const <String>{'allow', 'ask', 'deny'}.contains(policy)) continue;
        final id = entry.key.toString().trim();
        if (id.isEmpty) continue;
        if (policy == 'ask') {
          changed = _peerPolicies.containsKey(id) || changed;
          _peerPolicies.remove(id);
        } else if (_peerPolicies[id] != policy) {
          _peerPolicies[id] = policy;
          changed = true;
        }
      }
      if (changed) await _writeStringMap(peerPoliciesKey, _peerPolicies);
    }
    await _persistAcceptedPeers();
    notifyListeners();
  }

  Future<void> _persistAcceptedPeers() {
    final now = DateTime.now().toUtc().toIso8601String();
    return _writeStringMap(
      acceptedPeersKey,
      <String, String>{for (final peerId in _acceptedPeers) peerId: now},
    );
  }
}
