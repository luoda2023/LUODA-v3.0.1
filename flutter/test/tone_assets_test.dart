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
        // AssetSource 会由 audioplayers 自动拼接 assets/ 前缀，
        // 所以这里解析出的必须是**相对路径**（tones/tone_x.wav），
        // 否则会去找 assets/assets/... 导致播放无声。
        final resolved = resolveToneAsset('$kBuiltinTonePrefix$key');
        expect(resolved, 'tones/tone_$key.wav',
            reason: '内置音 $key 的解析路径必须带 tone_ 前缀（相对 assets/）');
        expect(File('assets/$resolved').existsSync(), isTrue,
            reason: 'assets/$resolved 缺失，内置音 $key 将无法播放');
      }
    });

    test('resolveToneAsset 处理默认音与自定义文件路径', () {
      expect(resolveToneAsset(''), '');
      expect(
        resolveToneAsset('builtin:crisp'),
        'tones/tone_crisp.wav',
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
