import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/widgets/message_source_label.dart';

void main() {
  // 7 种连接方式：PC/手机 × (ID / 公网IP / 局域网IP) + 蓝牙。
  // 用户期望：同一个人、同一个头像下的每条消息，都用灰色小字标出
  // 来自哪个端口、什么连接方式，且 PC 与手机端显示一致。

  test('PC 端 ID 连接', () {
    final label = messageSourceLabel(
      srcPlatform: 'desktop',
      connMode: 'id',
      connEndpoint: '423156@dotchat.dicad.cn',
      connPort: 21116,
      fallbackTarget: '423156@dotchat.dicad.cn',
    );
    expect(label, contains('PC'));
    expect(label, contains('ID'));
    expect(label, contains('423156@dotchat.dicad.cn'));
  });

  test('PC 端公网 IP 连接', () {
    final label = messageSourceLabel(
      srcPlatform: 'windows',
      connMode: 'public',
      connEndpoint: '8.8.8.8:21116',
      connPort: 21116,
      fallbackTarget: '8.8.8.8:21116',
    );
    expect(label, contains('PC'));
    expect(label, contains('Public IP'));
  });

  test('PC 端局域网 IP 连接', () {
    final label = messageSourceLabel(
      srcPlatform: 'pc',
      connMode: 'lan',
      connEndpoint: '192.168.1.5:37175',
      connPort: 37175,
      fallbackTarget: '192.168.1.5:37175',
    );
    expect(label, contains('PC'));
    expect(label, contains('LAN IP'));
  });

  test('手机端 ID 连接', () {
    final label = messageSourceLabel(
      srcPlatform: 'android',
      connMode: 'id',
      connEndpoint: '423727@dotchat.dicad.cn',
      connPort: 21116,
      fallbackTarget: '423727@dotchat.dicad.cn',
    );
    expect(label, contains('Mobile'));
    expect(label, contains('ID'));
  });

  test('手机端公网 IP 连接', () {
    final label = messageSourceLabel(
      srcPlatform: 'ios',
      connMode: 'public',
      connEndpoint: '114.114.114.114:21116',
      connPort: 21116,
      fallbackTarget: '114.114.114.114:21116',
    );
    expect(label, contains('Mobile'));
    expect(label, contains('Public IP'));
  });

  test('手机端局域网 IP 连接', () {
    final label = messageSourceLabel(
      srcPlatform: 'mobile',
      connMode: 'lan',
      connEndpoint: '10.0.0.8:24266',
      connPort: 24266,
      fallbackTarget: '10.0.0.8:24266',
    );
    expect(label, contains('Mobile'));
    expect(label, contains('LAN IP'));
  });

  test('蓝牙连接（手机-手机）', () {
    final label = messageSourceLabel(
      srcPlatform: 'android',
      connMode: 'ble',
      connEndpoint: 'AA:BB:CC:DD:EE:FF',
      connPort: 0,
      fallbackTarget: 'bt:aa:bb:cc:dd:ee:ff',
    );
    expect(label, contains('Mobile'));
    expect(label, contains('Bluetooth'));
  });

  test('来源缺失时从会话推断连接方式（旧消息兜底）', () {
    final label = messageSourceLabel(
      srcPlatform: null,
      connMode: '',
      connEndpoint: '',
      connPort: 0,
      fallbackTarget: '192.168.1.5:37175',
    );
    expect(label, contains('LAN IP'));
  });

  test('来源缺失且会话为 ID 时兜底显示 ID 连接', () {
    final label = messageSourceLabel(
      srcPlatform: null,
      connMode: '',
      connEndpoint: '',
      connPort: 0,
      fallbackTarget: '423156@dotchat.dicad.cn',
    );
    expect(label, contains('ID'));
  });

  test('文件助手等无会话上下文时返回空来源标记', () {
    final label = messageSourceLabel(
      srcPlatform: null,
      connMode: '',
      connEndpoint: '',
      connPort: 0,
      fallbackTarget: '',
    );
    expect(label, 'Source not recorded');
  });
}
