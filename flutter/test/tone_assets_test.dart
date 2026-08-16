import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/consts.dart';

void main() {
  group('内置消息提示音资源与路径', () {
    test('默认提示音 msg_tone.wav 存在', () {
      expect(File('assets/msg_tone.wav').existsSync(), isTrue,
          reason: 'assets/msg_tone.wav 缺失，默认提示音将无法播放');
    });

    test('每个内置提示音文件存在且命名带 tone_ 前缀', () {
      expect(kBuiltinTones, isNotEmpty);
      for (final tone in kBuiltinTones) {
        final key = tone['key']!;
        // 播放/试听路径解析统一走 resolveToneAsset。
        final resolved = resolveToneAsset('$kBuiltinTonePrefix$key');
        expect(resolved, 'assets/tones/tone_$key.wav',
            reason: '内置音 $key 的解析路径必须带 tone_ 前缀');
        expect(File(resolved).existsSync(), isTrue,
            reason: '$resolved 缺失，内置音 $key 将无法播放');
      }
    });

    test('resolveToneAsset 处理默认音与自定义文件路径', () {
      expect(resolveToneAsset(''), '');
      expect(
        resolveToneAsset('builtin:crisp'),
        'assets/tones/tone_crisp.wav',
      );
      expect(
        resolveToneAsset('C:/my/custom.mp3'),
        'C:/my/custom.mp3',
      );
    });

    test('内置音 key 全局唯一', () {
      final keys = kBuiltinTones.map((t) => t['key']).toList();
      expect(keys.toSet().length, keys.length,
          reason: '内置音 key 重复会导致选择器冲突');
    });
  });
}
