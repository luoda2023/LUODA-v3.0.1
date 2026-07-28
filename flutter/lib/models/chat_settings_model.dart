import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/generated_bridge.dart';

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
    if (_loaded) return;
    try {
      final mutedRaw = await bind.mainGetLocalOption(key: _kMutedKey);
      if (mutedRaw.isNotEmpty) {
        _mutedPeerIds = Set<String>.from(jsonDecode(mutedRaw) as List);
      }
    } catch (_) { /* ignore corrupt data */ }
    try {
      final blockedRaw = await bind.mainGetLocalOption(key: _kBlockedKey);
      if (blockedRaw.isNotEmpty) {
        _blockedPeerIds = Set<String>.from(jsonDecode(blockedRaw) as List);
      }
    } catch (_) { /* ignore corrupt data */ }
    _loaded = true;
  }

  bool isMuted(String peerId) => _mutedPeerIds.contains(peerId);
  bool isBlocked(String peerId) => _blockedPeerIds.contains(peerId);

  Future<void> toggleMute(String peerId) async {
    await load();
    if (_mutedPeerIds.contains(peerId)) {
      _mutedPeerIds.remove(peerId);
    } else {
      _mutedPeerIds.add(peerId);
    }
    await _saveMuted();
    notifyListeners();
  }

  Future<void> toggleBlock(String peerId) async {
    await load();
    if (_blockedPeerIds.contains(peerId)) {
      _blockedPeerIds.remove(peerId);
    } else {
      _blockedPeerIds.add(peerId);
    }
    await _saveBlocked();
    notifyListeners();
  }

  Future<void> _saveMuted() async {
    await bind.mainSetLocalOption(
      key: _kMutedKey,
      value: jsonEncode(_mutedPeerIds.toList(growable: false)),
    );
  }

  Future<void> _saveBlocked() async {
    await bind.mainSetLocalOption(
      key: _kBlockedKey,
      value: jsonEncode(_blockedPeerIds.toList(growable: false)),
    );
  }
}
