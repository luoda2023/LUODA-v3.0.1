import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../common.dart';
import '../models/chat_model.dart';
import 'direct_chat.dart';
import 'relay_bridge.dart';

/// A Bluetooth peer discovered by scanning or from the paired list.
///
/// Only DotChat devices are surfaced: the native side filters out any
/// Bluetooth device whose advertised name does not start with the `LD:`
/// prefix, and parses the DotChat nickname + device ID out of the name
/// (`LD:<昵称>:<ID>`). [name] keeps the combined `昵称:ID` form so existing
/// conversation/history keys stay stable, while [displayName] / [deviceId]
/// give the parsed parts for rendering.
class BtDevice {
  const BtDevice({
    required this.name,
    required this.mac,
    this.displayName = '',
    this.deviceId = '',
    this.paired = false,
  });

  /// Combined `昵称:ID` (native side already parsed it).
  final String name;
  final String mac;

  /// DotChat nickname parsed from the advertised name.
  final String displayName;

  /// DotChat device ID parsed from the advertised name.
  final String deviceId;
  final bool paired;

  String get peerId => 'bt:${mac.toUpperCase().replaceAll(':', '')}';

  BtDevice copyWith({bool? paired}) => BtDevice(
        name: name,
        mac: mac,
        displayName: displayName,
        deviceId: deviceId,
        paired: paired ?? this.paired,
      );

  @override
  bool operator ==(Object other) =>
      other is BtDevice && other.mac == mac;

  @override
  int get hashCode => mac.hashCode;
}

/// Bridges Dart chat to the native Bluetooth (RFCOMM) link on Android
/// and Windows.
///
/// - Envelopes sent to a `bt:<mac>` conversation are routed through
///   [btWireSink] to the native socket.
/// - Incoming lines are fed into [ChatModel.receive] with the same
///   `bt:<mac>` conversation id so PC and phone history share one format.
class BluetoothService {
  BluetoothService._();

  static final BluetoothService instance = BluetoothService._();

  static const MethodChannel _channel = MethodChannel('bluetooth_channel');
  static const EventChannel _events = EventChannel('bluetooth_channel_events');

  final _deviceFound = StreamController<BtDevice>.broadcast();
  final _connected = StreamController<String>.broadcast(); // mac
  final _disconnected = StreamController<String>.broadcast(); // mac
  final _errors = StreamController<String>.broadcast();

  final Set<String> _connectedMacs = <String>{};
  StreamSubscription<dynamic>? _eventSub;
  bool _initialized = false;
  bool _scanning = false;

  bool get isAndroidPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get isBtPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
       defaultTargetPlatform == TargetPlatform.windows);

  Stream<BtDevice> get onDeviceFound => _deviceFound.stream;
  Stream<String> get onConnected => _connected.stream;
  Stream<String> get onDisconnected => _disconnected.stream;
  Stream<String> get onError => _errors.stream;

  bool isConnected(String mac) => _connectedMacs.contains(_norm(mac));

  /// 已连接蓝牙设备的 MAC 列表（供中继桥选择网关）。
  Set<String> get connectedMacs => Set<String>.unmodifiable(_connectedMacs);

  bool get hasConnectedDevices => _connectedMacs.isNotEmpty;

  String? get firstConnectedMac => _connectedMacs.isEmpty
      ? null
      : _connectedMacs.first;

  /// 向指定蓝牙设备发送一行信封（聊天或中继转发通用）。
  Future<void> sendEnvelope(String mac, String line) async {
    if (!isBtPlatform || !_connectedMacs.contains(_norm(mac))) return;
    try {
      await _channel.invokeMethod<void>('sendEnvelope', <String, dynamic>{
        'mac': mac,
        'envelope': line,
      });
    } catch (error) {
      debugPrint('BluetoothService sendEnvelope failed: $error');
    }
  }

  /// Registers the wire sink and starts listening for native events.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    btWireSink = _routeWire;
    if (!isBtPlatform) return;
    _eventSub ??= _events.receiveBroadcastStream().listen(_onEvent);
    try {
      await _channel.invokeMethod<void>('startListening');
    } catch (_) {}
  }

  void dispose() {
    btWireSink = null;
    _eventSub?.cancel();
    _eventSub = null;
    _initialized = false;
  }

  bool _routeWire(String conversationId, String envelope) {
    // 仅处理本机蓝牙直连目标：中继（借网关流量）是 ChatModel 网络发送
    // 失败后的兜底，不在这里抢占，否则网关设备自己的联网消息会被
    // 错误劫持到蓝牙链路。
    if (!isBtPlatform) return false;
    final mac = _macOf(conversationId);
    if (mac != null && _connectedMacs.contains(_norm(mac))) {
      unawaited(sendEnvelope(mac, envelope));
      return true;
    }
    return false;
  }

  static String? _macOf(String conversationId) {
    final value = conversationId.trim().toUpperCase();
    if (!value.startsWith('BT:')) return null;
    final raw = value.substring(3);
    if (raw.isEmpty) return null;
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i += 2) {
      if (i + 1 < raw.length) buffer.write('${raw[i]}${raw[i + 1]}');
    }
    if (buffer.length != 12) return null;
    final parts = <String>[];
    for (var i = 0; i < 12; i += 2) {
      parts.add(buffer.toString().substring(i, i + 2));
    }
    return parts.join(':');
  }

  static String _norm(String mac) =>
      mac.trim().toUpperCase().replaceAll(':', '');

  Future<bool> isSupported() async {
    if (!isBtPlatform) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isEnabled() async {
    if (!isBtPlatform) return false;
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Asks the user to turn Bluetooth on.
  Future<void> enable() async {
    if (!isBtPlatform) return;
    try {
      await _channel.invokeMethod<void>('enable');
    } catch (_) {}
  }

  Future<List<BtDevice>> pairedDevices() async {
    if (!isBtPlatform) return const <BtDevice>[];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('pairedDevices');
      if (raw == null) return const <BtDevice>[];
      return <BtDevice>[
        for (final item in raw)
          if (item is Map)
            BtDevice(
              name: (item['name'] ?? '').toString(),
              mac: (item['mac'] ?? '').toString(),
              displayName: (item['displayName'] ?? '').toString(),
              deviceId: (item['deviceId'] ?? '').toString(),
              paired: true,
            ),
      ];
    } catch (_) {
      return const <BtDevice>[];
    }
  }

  bool get scanning => _scanning;

  Future<void> startScan() async {
    if (!isBtPlatform || _scanning) return;
    _scanning = true;
    try {
      await _channel.invokeMethod<void>('startScan');
    } catch (error) {
      _scanning = false;
      _errors.add('扫描失败: $error');
    }
  }

  Future<void> stopScan() async {
    _scanning = false;
    if (!isBtPlatform) return;
    try {
      await _channel.invokeMethod<void>('stopScan');
    } catch (_) {}
  }

  Future<bool> connect(String mac, String name) async {
    if (!isBtPlatform) return false;
    try {
      await _channel.invokeMethod<void>('connect', <String, dynamic>{
        'mac': mac,
        'name': name,
      });
      return true;
    } catch (error) {
      _errors.add('连接失败: $error');
      return false;
    }
  }

  Future<void> disconnect(String mac) async {
    if (!isBtPlatform) return;
    try {
      await _channel.invokeMethod<void>('disconnect', <String, dynamic>{
        'mac': mac,
      });
    } catch (_) {}
  }

  /// Broadcast this device as a DotChat peer by renaming the local
  /// Bluetooth adapter to `LD:<昵称>:<ID>`. Only DotChat devices use this
  /// prefix, so scanning clients can filter out ordinary Bluetooth gadgets.
  Future<void> setAdvertisedName(String displayName, String deviceId) async {
    if (!isBtPlatform) return;
    final name = displayName.trim().replaceAll(':', ' ');
    final id = deviceId.trim().replaceAll(':', ' ');
    if (name.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('setAdvertisedName', <String, dynamic>{
        'name': 'LD:$name:$id',
      });
    } catch (error) {
      debugPrint('setAdvertisedName failed: $error');
    }
  }

  Future<void> _onEvent(dynamic raw) async {
    final map = raw is Map ? Map<String, dynamic>.from(raw) : null;
    if (map == null) return;
    switch (map['event']) {
      case 'deviceFound':
        _deviceFound.add(BtDevice(
          name: (map['name'] ?? '').toString(),
          mac: (map['mac'] ?? '').toString(),
          displayName: (map['displayName'] ?? '').toString(),
          deviceId: (map['deviceId'] ?? '').toString(),
          paired: map['paired'] == true,
        ));
        break;
      case 'connected':
        final mac = _norm((map['mac'] ?? '').toString());
        if (mac.isEmpty) break;
        _connectedMacs.add(mac);
        _scanning = false;
        _connected.add((map['mac'] ?? '').toString());
        break;
      case 'disconnected':
        final mac = _norm((map['mac'] ?? '').toString());
        _connectedMacs.remove(mac);
        _disconnected.add((map['mac'] ?? '').toString());
        break;
      case 'wire':
        final mac = (map['mac'] ?? '').toString();
        final envelope = (map['envelope'] ?? '').toString();
        if (mac.isEmpty || envelope.isEmpty) break;
        // 中继信封先交给中继桥（本机接收或网关转发），其余走普通消息解析。
        final consumed = await RelayBridge.instance.handleLine(mac, envelope);
        if (consumed) break;
        final conversationId = 'bt:${_norm(mac)}';
        unawaited(gFFI.chatModel.receive(
          ChatModel.clientModeID,
          envelope,
          conversationId: conversationId,
          showChat: false,
        ));
        break;
      case 'adapter':
        if (map['enabled'] != true && _connectedMacs.isNotEmpty) {
          _connectedMacs.clear();
        }
        break;
      case 'error':
        _errors.add((map['message'] ?? '').toString());
        break;
    }
  }
}
