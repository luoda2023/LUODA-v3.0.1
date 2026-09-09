import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/models/chat_model.dart';

/// 禁中继原则契约测试（LUODA）：
/// VPS 只做信令、配置低——音视频/远程协助/会议视频/会议语音的流量
/// 必须走点对点直连（局域网直连 / UDP·TCP 打洞），绝不走中继服务器。
void main() {
  group('Dart 直连闸门（语音/会议语音发起前检查）', () {
    test('无连接信息（老版本/异常）放行，避免误伤', () {
      expect(ChatModel.mediaDirectGateAllows(null), isTrue);
      expect(ChatModel.mediaDirectGateAllows(''), isTrue);
    });

    test('direct=true（P2P 直连：局域网直连/打洞成功）放行', () {
      expect(
        ChatModel.mediaDirectGateAllows(
          '{"direct":true,"peer_addr":"192.168.1.5:25488"}',
        ),
        isTrue,
      );
    });

    test('direct=false（中继）拒绝——音视频/会议语音不走中继', () {
      expect(
        ChatModel.mediaDirectGateAllows(
          '{"direct":false,"peer_addr":"relay.example.com:23117"}',
        ),
        isFalse,
      );
    });

    test('非法 JSON（查询异常）放行兜底', () {
      expect(ChatModel.mediaDirectGateAllows('not-json'), isTrue);
    });
  });

  group('源码契约：媒体发起前必须经过直连闸门', () {
    test('一对一语音/视频发起前检查直连（home_page）', () {
      final src = File('lib/mobile/pages/home_page.dart').readAsStringSync();
      expect(src, contains('ChatModel.mediaDirectGateAllows(info)'));
      expect(src, contains('_ensureDirectForMediaCall'));
    });

    test('会议语音加入前检查直连（chat_model）', () {
      final src = File('lib/models/chat_model.dart').readAsStringSync();
      expect(src, contains('_ensureMeetingVoiceDirect'));
      expect(src, contains('mediaDirectGateAllows(info)'));
    });
  });

  group('Rust 契约：媒体连接打洞失败不退化中继', () {
    test('client.rs 存在禁中继策略并区分媒体/非媒体连接', () {
      final src = File('../src/client.rs').readAsStringSync();
      expect(src, contains('fn media_conn_relay_forbidden'));
      expect(src, contains('fn apply_no_relay_media_policy'));
      // 媒体连接直连失败且未显式 force_relay 时拒绝。
      expect(src, contains('media_conn_relay_forbidden(conn_type) && !direct_ok'));
    });
  });
}