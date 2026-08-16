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
  Set<String> _vibrationOffPeerIds = {};

  bool _loaded = false;

  static const _kMutedKey = 'chat_muted_peers';
  static const _kBlockedKey = 'chat_blocked_peers';
  static const _kVibrationOffKey = 'chat_vibration_off_peers';

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
    try {
      final vibRaw = gFFI.chatModel.getRawOption(_kVibrationOffKey);
      if (vibRaw.isNotEmpty) {
        _vibrationOffPeerIds = _decodePeerIds(vibRaw);
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

  /// 该会话是否关闭了震动（免打扰时同时关闭提示音与震动）。
  bool isVibrationOff(String peerId) {
    _ensureLoaded();
    return _vibrationOffPeerIds.contains(_canonicalPeerId(peerId));
  }

  /// 会话免打扰（静音）：不播提示音、不震动，横幅仍显示。
  bool isDoNotDisturb(String peerId) {
    _ensureLoaded();
    final id = _canonicalPeerId(peerId);
    return _mutedPeerIds.contains(id) || _blockedPeerIds.contains(id);
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

  /// 会话内关闭/恢复震动（提示音不受影响）。
  Future<void> toggleVibrationOff(String peerId) async {
    await load();
    final id = _canonicalPeerId(peerId);
    if (id.isEmpty) return;
    if (_vibrationOffPeerIds.contains(id)) {
      _vibrationOffPeerIds.remove(id);
    } else {
      _vibrationOffPeerIds.add(id);
    }
    await _saveVibrationOff();
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

  Future<void> _saveVibrationOff() async {
    gFFI.chatModel.setRawOption(
      key: _kVibrationOffKey,
      value: jsonEncode(_vibrationOffPeerIds.toList(growable: false)),
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
