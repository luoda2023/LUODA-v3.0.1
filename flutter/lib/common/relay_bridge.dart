import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'bt_service.dart';
import 'direct_chat.dart';
import 'direct_pairing.dart';

/// 蓝牙中继桥：让没有公网/网络条件的设备，借由已连接的蓝牙网关设备
/// （该设备有网络或公网可达），与外部设备进行聊天与文件传输。
///
/// 通信模型（行式信封协议，走同一条 RFCOMM 链路）：
/// - 出站：本机把发给外部目标（非本机蓝牙直连）的原始信封，封装成
///   `relay` 信封 `{from, to, envelope}` 经蓝牙发给网关，由网关用自己的
///   网络把原信封发给目标。
/// - 入站（蓝牙侧）：网关收到 relay 信封后解包——若 `to` 指向网关本机则
///   直接接收，否则用网关自己的网络把原信封发给目标。
/// - 入站（网络侧，反向回复）：外部设备可把发给蓝牙端设备的回复封装成
///   relay 信封经网络发到网关，网关按 `to`（蓝牙端账号ID）经蓝牙转发。
///
/// 避免环路：relay 信封只经蓝牙链路传输；收到 relay 时若 `to` 不是本机，
/// 只用本机「非蓝牙」通道转发（ChatModel._sendWireNonBluetooth 已跳过
/// 蓝牙路由）。
class RelayBridge {
  RelayBridge._();

  static final RelayBridge instance = RelayBridge._();

  static const String prefix = 'LDESK_RELAY_V1:';

  static bool isRelayLine(String line) => line.startsWith(prefix);

  /// 已学习的「蓝牙端账号ID → 蓝牙MAC」映射（网关侧，供反向回复路由）。
  final Map<String, String> _peerDialToMac = {};

  /// 把本机发往 [targetConversationId] 的原始信封，经蓝牙网关转发。
  /// 返回 true 表示已交给蓝牙链路。缺省网关时自动选择已连接的设备。
  bool sendViaBluetoothRelay({
    required String targetConversationId,
    required String envelopeLine,
    String? gatewayMac,
    String? fromDialId,
  }) {
    final bt = BluetoothService.instance;
    if (!bt.isBtPlatform || !bt.hasConnectedDevices) return false;
    final mac = gatewayMac ?? bt.firstConnectedMac;
    if (mac == null) return false;
    final payload = jsonEncode(<String, dynamic>{
      'from': (fromDialId ?? _myIdProvider?.call() ?? _cachedMyId).trim(),
      'to': targetConversationId,
      'envelope': envelopeLine,
    });
    final bytes = utf8.encode(payload);
    final line = '$prefix${base64UrlEncode(bytes)}';
    unawaited(bt.sendEnvelope(mac, line));
    return true;
  }

  /// 处理从蓝牙链路收到的一行数据。
  /// 返回 true 表示该行是 relay 信封（已被消费，不再走普通消息解析）。
  Future<bool> handleLine(String mac, String line) async {
    if (!line.startsWith(prefix)) return false;
    final decoded = _decode(line);
    if (decoded == null) return true;
    final from = (decoded['from'] ?? '').toString().trim();
    final to = (decoded['to'] ?? '').toString().trim();
    final inner = (decoded['envelope'] ?? '').toString().trim();
    // 学习蓝牙端设备的账号ID，网关据此把外网回复路由回该设备。
    if (from.isNotEmpty) {
      _peerDialToMac[DirectPairingStore.canonicalConversationId(from)] =
          _normMac(mac);
    }
    if (to.isEmpty || inner.isEmpty) return true;
    final envelope = DirectChatEnvelope.decode(inner);
    if (envelope == null) return true;
    if (_targetsThisDevice(to)) {
      // 本机是最终接收者：作为来自该会话的普通消息接收。
      await _receiveLocally(to, inner);
    } else {
      // 本机是中继网关：用自己的网络把原信封发给目标。
      await _forwardWithLocalNetwork(to, inner);
    }
    return true;
  }

  /// 处理从网络通道收到的一行（外网设备发给网关、要求转交蓝牙端设备的
  /// relay 信封）。返回 true 表示该行是 relay 信封且已按 `to` 处理。
  Future<bool> handleNetworkLine(String line) async {
    if (!line.startsWith(prefix)) return false;
    final decoded = _decode(line);
    if (decoded == null) return true;
    final from = (decoded['from'] ?? '').toString().trim();
    final to = (decoded['to'] ?? '').toString().trim();
    final inner = (decoded['envelope'] ?? '').toString().trim();
    if (to.isEmpty || inner.isEmpty) return true;
    final bt = BluetoothService.instance;
    final mac = bt.isBtPlatform
        ? _peerDialToMac[DirectPairingStore.canonicalConversationId(to)]
        : null;
    if (mac != null) {
      // 目标是本网关的蓝牙端设备：经 RFCOMM 转发。
      unawaited(bt.sendEnvelope(mac, line));
      return true;
    }
    // 目标不是本机蓝牙端设备：按本机普通消息处理（可能发给本机自己）。
    if (_targetsThisDevice(to)) {
      await _receiveLocally(to, inner);
      return true;
    }
    debugPrint('RelayBridge.handleNetworkLine: no route for to=$to from=$from');
    return true;
  }

  Map<String, dynamic>? _decode(String line) {
    try {
      final encoded = line.substring(prefix.length);
      return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(base64Url.decode(encoded))) as Map,
      );
    } catch (error, stackTrace) {
      debugPrint('RelayBridge decode failed: $error\n$stackTrace');
      return null;
    }
  }

  static String _normMac(String mac) => mac.trim().toUpperCase();

  bool _targetsThisDevice(String to) {
    final myId = _myIdProvider?.call() ?? _cachedMyId;
    if (myId.isEmpty) return true; // 无法判定时按本机接收处理
    final canonical = DirectPairingStore.canonicalConversationId(to);
    final myCanonical = DirectPairingStore.canonicalConversationId(myId);
    return canonical.isNotEmpty && canonical == myCanonical;
  }

  Future<void> _receiveLocally(String to, String inner) async {
    final receive = _chatModelReceive;
    if (receive != null) {
      await receive(inner, conversationId: to);
      return;
    }
    debugPrint('RelayBridge: chatModel receive not wired');
  }

  Future<void> _forwardWithLocalNetwork(String to, String inner) async {
    final forward = _chatModelSendWire;
    if (forward != null) {
      final sent = await forward(to, inner);
      if (!sent) {
        debugPrint('RelayBridge forward failed to=$to');
      }
      return;
    }
    debugPrint('RelayBridge: chatModel sendWire not wired');
  }

  // ---- 由 ChatModel 注入的桥接（避免循环依赖） ----

  static String _cachedMyId = '';

  static String Function()? _myIdProvider;

  static Future<void> Function(String envelopeLine,
      {String? conversationId})? _chatModelReceive;

  static Future<bool> Function(String peerId, String envelopeLine)?
      _chatModelSendWire;

  static void wire({
    String myId = '',
    String Function()? myIdProvider,
    required Future<void> Function(String envelopeLine,
        {String? conversationId}) receive,
    required Future<bool> Function(String peerId, String envelopeLine)
        sendWire,
  }) {
    _cachedMyId = myId;
    _myIdProvider = myIdProvider;
    _chatModelReceive = receive;
    _chatModelSendWire = sendWire;
  }
}
