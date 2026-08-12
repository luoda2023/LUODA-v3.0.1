import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:luoda_flutter/common.dart';

import '../common/direct_pairing.dart';

class ChatSettingsModel extends ChangeNotifier {
  static final ChatSettingsModel _instance = ChatSettingsModel._();
  factory ChatSettingsModel() => _instance;
  ChatSettingsModel._();

  Set<String> _mutedPeerIds = {};
  Set<String> _blockedPeerIds = {};

  bool _loaded = false;

  static const _kMutedKey = 'chat_muted_peers';
  static const _kBlockedKey = 'chat_blocked_peers';

  Future<void> load() async {
    _ensureLoaded();
  }

  void _ensureLoaded() {
    if (_loaded) return;
    try {
      final mutedRaw = gFFI.chatModel.getRawOption(_kMutedKey);
      if (mutedRaw.isNotEmpty) {
        _mutedPeerIds = _decodePeerIds(mutedRaw);
      }
    } catch (_) {/* ignore corrupt data */}
    try {
      final blockedRaw = gFFI.chatModel.getRawOption(_kBlockedKey);
      if (blockedRaw.isNotEmpty) {
        _blockedPeerIds = _decodePeerIds(blockedRaw);
      }
    } catch (_) {/* ignore corrupt data */}
    _loaded = true;
  }

  bool isMuted(String peerId) {
    _ensureLoaded();
    return _mutedPeerIds.contains(_canonicalPeerId(peerId));
  }

  bool isBlocked(String peerId) {
    _ensureLoaded();
    return _blockedPeerIds.contains(_canonicalPeerId(peerId));
  }

  Future<void> toggleMute(String peerId) async {
    await load();
    final id = _canonicalPeerId(peerId);
    if (id.isEmpty) return;
    if (_mutedPeerIds.contains(id)) {
      _mutedPeerIds.remove(id);
    } else {
      _mutedPeerIds.add(id);
    }
    await _saveMuted();
    notifyListeners();
  }

  Future<void> toggleBlock(String peerId) async {
    await load();
    final id = _canonicalPeerId(peerId);
    if (id.isEmpty) return;
    if (_blockedPeerIds.contains(id)) {
      _blockedPeerIds.remove(id);
    } else {
      _blockedPeerIds.add(id);
    }
    await _saveBlocked();
    notifyListeners();
  }

  Future<void> _saveMuted() async {
    gFFI.chatModel.setRawOption(
      key: _kMutedKey,
      value: jsonEncode(_mutedPeerIds.toList(growable: false)),
    );
  }

  Future<void> _saveBlocked() async {
    gFFI.chatModel.setRawOption(
      key: _kBlockedKey,
      value: jsonEncode(_blockedPeerIds.toList(growable: false)),
    );
  }

  Set<String> _decodePeerIds(String raw) {
    return (jsonDecode(raw) as List<dynamic>)
        .map((value) => _canonicalPeerId(value.toString()))
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  String _canonicalPeerId(String peerId) =>
      DirectPairingStore.canonicalConversationId(peerId.trim());
}
