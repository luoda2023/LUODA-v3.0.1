import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../common.dart';
import '../models/chat_model.dart';

/// 手机端消息横幅通知（微信式）：收到新消息时在系统顶部弹出横幅，
/// 点击跳转到对应会话。PC 端不启用（桌面端有自己的窗口闪烁/托盘提醒）。
class ChatNotifier {
  ChatNotifier._();

  static final ChatNotifier instance = ChatNotifier._();

  static const String _channelId = 'chat_messages';
  static const String _channelName = 'Chat messages';
  static const String _channelDescription = 'New incoming chat messages';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// 初始化通知插件并申请 Android 13+ 通知权限。
  Future<void> init() async {
    if (!isMobile) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );
      _ready = true;
      if (isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
    } catch (e) {
      debugPrint('ChatNotifier init failed: $e');
    }
  }

  void _onNotificationTap(NotificationResponse response) {
    final peerId = response.payload?.trim() ?? '';
    if (peerId.isEmpty) return;
    try {
      gFFI.chatModel.changeCurrentKey(MessageKey(peerId, -1));
    } catch (e) {
      debugPrint('ChatNotifier tap failed: $e');
    }
  }

  /// 弹出一条新消息通知。[peerId] 用于点击跳转；[senderName] 是标题；
  /// [body] 是消息摘要。
  Future<void> showIncomingMessage({
    required String peerId,
    required String senderName,
    required String body,
  }) async {
    if (!_ready || !isMobile) return;
    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          styleInformation: BigTextStyleInformation(
            body,
            htmlFormatBigText: false,
            contentTitle: senderName,
            htmlFormatContent: false,
            summaryText: '',
          ),
        ),
      );
      await _plugin.show(
        peerId.hashCode,
        senderName,
        body,
        details,
        payload: peerId,
      );
    } catch (e) {
      debugPrint('ChatNotifier show failed: $e');
    }
  }
}
