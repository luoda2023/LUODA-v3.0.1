import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/platform_model.dart';

enum DirectChatAudience { friendsOnly, everyone }

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
    return alwaysOn && autoReconnect && previouslyAccepted && isFriend(peerId);
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

  bool _loaded = false;
  bool _alwaysOn = true;
  bool _autoReconnect = true;
  DirectChatAudience _audience = DirectChatAudience.friendsOnly;
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
    _audience = bind.mainGetLocalOption(key: trustedOnlyKey) == 'N'
        ? DirectChatAudience.everyone
        : DirectChatAudience.friendsOnly;
    _peerPolicies = _readStringMap(peerPoliciesKey);
    _acceptedPeers = _readStringMap(acceptedPeersKey).keys.toSet();
    _loaded = true;
    if (notify) notifyListeners();
  }

  String policyFor(String peerId) {
    load();
    return _peerPolicies[peerId.trim()] ?? 'ask';
  }

  bool isFriend(String peerId) => policyFor(peerId) == 'allow';

  bool isDenied(String peerId) => policyFor(peerId) == 'deny';

  bool wasPreviouslyAccepted(String peerId) {
    load();
    return _acceptedPeers.contains(peerId.trim());
  }

  bool shouldAutoReconnect(String peerId) {
    load();
    return snapshot.shouldAutoReconnect(
      peerId,
      previouslyAccepted: wasPreviouslyAccepted(peerId),
    );
  }

  Set<String> get autoReconnectPeerIds {
    load();
    return _peerPolicies.keys.where(shouldAutoReconnect).toSet();
  }

  Future<void> setAudience(DirectChatAudience value) async {
    load();
    if (_audience == value && _alwaysOn) return;
    _audience = value;
    _alwaysOn = true;
    await bind.mainSetLocalOption(key: alwaysOnKey, value: 'Y');
    await bind.mainSetLocalOption(
      key: trustedOnlyKey,
      value: value == DirectChatAudience.friendsOnly ? 'Y' : 'N',
    );
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
    notifyListeners();
  }

  Future<void> setPeerPolicy(String peerId, String policy) async {
    load();
    final id = peerId.trim();
    if (id.isEmpty ||
        !const <String>{'allow', 'ask', 'deny'}.contains(policy)) {
      return;
    }
    if (policy == 'ask') {
      _peerPolicies.remove(id);
    } else {
      _peerPolicies[id] = policy;
    }
    if (policy == 'deny') _acceptedPeers.remove(id);
    await _writeStringMap(peerPoliciesKey, _peerPolicies);
    await _persistAcceptedPeers();
    notifyListeners();
  }

  Future<void> markAccepted(String peerId) async {
    load();
    final id = peerId.trim();
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

  Future<void> _persistAcceptedPeers() {
    final now = DateTime.now().toUtc().toIso8601String();
    return _writeStringMap(
      acceptedPeersKey,
      <String, String>{for (final peerId in _acceptedPeers) peerId: now},
    );
  }
}
