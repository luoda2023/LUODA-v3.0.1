import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../common.dart';
import '../consts.dart';
import '../models/chat_model.dart';
import '../models/platform_model.dart';

/// 手机端消息横幅通知（微信式）：收到新消息时在系统顶部弹出横幅，
/// 点击跳转到对应会话。附带提示音 + 震动（可在设置中开关）。
/// PC 端不启用（桌面端有自己的窗口闪烁/托盘提醒）。
class ChatNotifier {
  ChatNotifier._();

  static final ChatNotifier instance = ChatNotifier._();

  static const String _channelId = 'chat_messages';
  static const String _channelName = 'Chat messages';
  static const String _channelDescription = 'New incoming chat messages';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _tonePlayer = AudioPlayer();
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

  /// 消息提示音是否开启（默认开启）。
  bool get soundEnabled {
    try {
      return option2bool(kOptionMessageSound,
          bind.mainGetOptionSync(key: kOptionMessageSound));
    } catch (e) {
      return true;
    }
  }

  /// 消息震动是否开启（默认开启）。
  bool get vibrationEnabled {
    try {
      return option2bool(kOptionMessageVibration,
          bind.mainGetOptionSync(key: kOptionMessageVibration));
    } catch (e) {
      return true;
    }
  }

  /// 播放提示音：内置多选音（builtin:x）→ 用户自定义文件 → 默认"叮咚"音。
  Future<void> _playTone() async {
    try {
      final custom =
          bind.mainGetOptionSync(key: kOptionMessageSoundPath).trim();
      await _tonePlayer.stop();
      if (custom.startsWith(kBuiltinTonePrefix)) {
        final name = custom.substring(kBuiltinTonePrefix.length);
        await _tonePlayer.play(AssetSource('assets/tones/$name.wav'));
      } else if (custom.isNotEmpty && File(custom).existsSync()) {
        await _tonePlayer.play(DeviceFileSource(custom));
      } else {
        await _tonePlayer.play(AssetSource('assets/msg_tone.wav'));
      }
    } catch (e) {
      debugPrint('ChatNotifier play tone failed: $e');
    }
  }

  /// 弹出一条新消息通知。[peerId] 用于点击跳转；[senderName] 是标题；
  /// [body] 是消息摘要。
  Future<void> showIncomingMessage({
    required String peerId,
    required String senderName,
    required String body,
  }) async {
    // 提示音两端都播；通知横幅仅手机端。
    if (soundEnabled) {
      unawaited(_playTone());
    }
    if (!_ready || !isMobile) return;
    try {
      final vibrate = vibrationEnabled;
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: vibrate,
          // 提示音由 audioplayers 自己播放，避免系统通知音与自定义音叠加
          playSound: false,
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
