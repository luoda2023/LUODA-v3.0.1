import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// ============================================================================
// TtsService 单元测试
//
// 覆盖场景：
// 1. 超长文本截断逻辑
// 2. WAV 转换正确性
// 3. 空闲超时配置范围验证
// 4. 语速/声音 ID 边界值
// 5. 文本预处理（trim / 空字符串）
// 6. 队列逻辑（enqueue / dequeue 顺序）
// 7. 并发互斥标志状态机
// ============================================================================

/// 模拟 TtsService 的核心逻辑，不依赖 sherpa-onnx / audioplayers 原生库。
/// 用于测试纯 Dart 逻辑的正确性。
class TtsServiceLogic {
  static const int maxTextLength = 2000;
  static const List<String> presetVoices = [
    '女声 1',
    '女声 2',
    '男声 1',
    '男声 2',
    '女声 3',
  ];

  bool speaking = false;
  bool speakBusy = false;
  bool processingQueue = false;
  final List<String> readQueue = [];

  /// 模拟文本截断逻辑（来自 tts_service.dart speak()）
  String truncateText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.length > maxTextLength) {
      return trimmed.substring(0, maxTextLength);
    }
    return trimmed;
  }

  /// 模拟空闲超时配置范围验证
  int clampIdleTimeout(int minutes) {
    return minutes.clamp(0, 60);
  }

  /// 模拟语速范围验证
  double clampSpeed(double speed) {
    if (speed <= 0) return 1.0;
    return speed.clamp(0.5, 1.5);
  }

  /// 模拟声音 ID 范围验证
  int clampVoiceId(int id) {
    return id.clamp(0, presetVoices.length - 1);
  }

  /// 模拟 stop() 清理所有状态
  void stop() {
    speaking = false;
    speakBusy = false;
    readQueue.clear();
    processingQueue = false;
  }

  /// 模拟 enqueueForReading 逻辑
  bool enqueueForReading(String text, {required bool isContinuousRead, required bool isEnabled}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !isContinuousRead || !isEnabled) return false;
    readQueue.add(trimmed);
    return true;
  }

  /// 模拟 speak() 的并发互斥检查
  bool canSpeak() {
    return !speakBusy;
  }

  /// 模拟 speak() 获取 safe text（含截断）
  String getSafeText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length > maxTextLength) {
      return trimmed.substring(0, maxTextLength);
    }
    return trimmed;
  }
}

/// WAV 头部构造逻辑（从 tts_service.dart _toWav 提取）
Uint8List toWav(Float32List samples, int sampleRate) {
  final bytes = ByteData(44 + samples.length * 2);
  void writeString(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeString(0, 'RIFF');
  bytes.setUint32(4, 36 + samples.length * 2, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  writeString(36, 'data');
  bytes.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    bytes.setInt16(44 + i * 2, v, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void main() {
  final logic = TtsServiceLogic();

  // ========================================================================
  // 1. 超长文本截断测试
  // ========================================================================
  group('超长文本截断保护', () {
    test('短文本不截断', () {
      expect(logic.truncateText('你好'), '你好');
    });

    test('恰好 2000 字不截断', () {
      final text = 'a' * 2000;
      expect(logic.truncateText(text).length, 2000);
    });

    test('2001 字截断为 2000', () {
      final text = 'a' * 2001;
      final result = logic.truncateText(text);
      expect(result.length, 2000);
      expect(result, 'a' * 2000);
    });

    test('超长文本截断后保持前 2000 字', () {
      final text = '测试' * 1500; // 3000 字
      final result = logic.truncateText(text);
      expect(result.length, 2000);
      expect(result, text.substring(0, 2000));
    });

    test('空字符串返回空', () {
      expect(logic.truncateText(''), '');
    });

    test('纯空格返回空', () {
      expect(logic.truncateText('   '), '');
    });

    test('前后空格被 trim 后再截断', () {
      final text = '  ${'a' * 2001}  ';
      final result = logic.truncateText(text);
      expect(result.length, 2000);
    });

    test('getSafeText 与 truncateText 行为一致', () {
      final text = 'x' * 3000;
      expect(logic.getSafeText(text).length, 2000);
      expect(logic.getSafeText(text), logic.truncateText(text));
    });

    test('getSafeText 空输入返回空', () {
      expect(logic.getSafeText(''), '');
      expect(logic.getSafeText('   '), '');
    });
  });

  // ========================================================================
  // 2. 空闲超时配置测试
  // ========================================================================
  group('空闲超时配置范围', () {
    test('默认值 5 分钟在范围内', () {
      expect(logic.clampIdleTimeout(5), 5);
    });

    test('0 分钟（永不释放）', () {
      expect(logic.clampIdleTimeout(0), 0);
    });

    test('负值被 clamp 到 0', () {
      expect(logic.clampIdleTimeout(-1), 0);
      expect(logic.clampIdleTimeout(-100), 0);
    });

    test('超过 60 被 clamp 到 60', () {
      expect(logic.clampIdleTimeout(61), 60);
      expect(logic.clampIdleTimeout(999), 60);
    });

    test('边界值 1 和 60', () {
      expect(logic.clampIdleTimeout(1), 1);
      expect(logic.clampIdleTimeout(60), 60);
    });

    test('常见值保持不变', () {
      for (final v in [1, 2, 3, 5, 10, 15, 30, 60]) {
        expect(logic.clampIdleTimeout(v), v);
      }
    });
  });

  // ========================================================================
  // 3. 语速范围测试
  // ========================================================================
  group('语速范围验证', () {
    test('默认语速 1.0', () {
      expect(logic.clampSpeed(1.0), 1.0);
    });

    test('最小语速 0.5', () {
      expect(logic.clampSpeed(0.5), 0.5);
    });

    test('最大语速 1.5', () {
      expect(logic.clampSpeed(1.5), 1.5);
    });

    test('低于 0.5 被 clamp 到 0.5', () {
      expect(logic.clampSpeed(0.3), 0.5);
      expect(logic.clampSpeed(0.0), 1.0); // 0 或负值返回默认 1.0
      expect(logic.clampSpeed(-1.0), 1.0);
    });

    test('高于 1.5 被 clamp 到 1.5', () {
      expect(logic.clampSpeed(2.0), 1.5);
      expect(logic.clampSpeed(10.0), 1.5);
    });
  });

  // ========================================================================
  // 4. 声音 ID 范围测试
  // ========================================================================
  group('声音 ID 范围验证', () {
    test('有效 ID 0..4', () {
      for (var i = 0; i < TtsServiceLogic.presetVoices.length; i++) {
        expect(logic.clampVoiceId(i), i);
      }
    });

    test('负 ID 被 clamp 到 0', () {
      expect(logic.clampVoiceId(-1), 0);
      expect(logic.clampVoiceId(-100), 0);
    });

    test('超过范围被 clamp 到最大值', () {
      expect(logic.clampVoiceId(5), 4);
      expect(logic.clampVoiceId(100), 4);
    });
  });

  // ========================================================================
  // 5. 文本预处理测试
  // ========================================================================
  group('文本预处理', () {
    test('trim 去除前后空格', () {
      expect(logic.truncateText('  hello  '), 'hello');
    });

    test('trim 去除换行和制表符', () {
      expect(logic.truncateText('\n\t你好\n\t'), '你好');
    });

    test('中文文本正常处理', () {
      final text = '这是一段中文文本，用于测试朗读功能是否正常工作。';
      expect(logic.truncateText(text), text);
    });

    test('混合语言文本', () {
      final text = 'Hello 你好 World 世界';
      expect(logic.truncateText(text), text);
    });
  });

  // ========================================================================
  // 6. 队列逻辑测试
  // ========================================================================
  group('朗读队列逻辑', () {
    setUp(() {
      logic.stop();
    });

    test('空文本不入队', () {
      final added = logic.enqueueForReading('', isContinuousRead: true, isEnabled: true);
      expect(added, isFalse);
      expect(logic.readQueue.isEmpty, isTrue);
    });

    test('纯空格不入队', () {
      final added = logic.enqueueForReading('   ', isContinuousRead: true, isEnabled: true);
      expect(added, isFalse);
    });

    test('连续朗读关闭时不入队', () {
      final added = logic.enqueueForReading('hello', isContinuousRead: false, isEnabled: true);
      expect(added, isFalse);
      expect(logic.readQueue.isEmpty, isTrue);
    });

    test('TTS 关闭时不入队', () {
      final added = logic.enqueueForReading('hello', isContinuousRead: true, isEnabled: false);
      expect(added, isFalse);
      expect(logic.readQueue.isEmpty, isTrue);
    });

    test('正常文本入队', () {
      final added = logic.enqueueForReading('hello', isContinuousRead: true, isEnabled: true);
      expect(added, isTrue);
      expect(logic.readQueue.length, 1);
      expect(logic.readQueue.first, 'hello');
    });

    test('多条消息按顺序入队', () {
      logic.enqueueForReading('msg1', isContinuousRead: true, isEnabled: true);
      logic.enqueueForReading('msg2', isContinuousRead: true, isEnabled: true);
      logic.enqueueForReading('msg3', isContinuousRead: true, isEnabled: true);
      expect(logic.readQueue, ['msg1', 'msg2', 'msg3']);
    });

    test('stop() 清空队列', () {
      logic.enqueueForReading('msg1', isContinuousRead: true, isEnabled: true);
      logic.enqueueForReading('msg2', isContinuousRead: true, isEnabled: true);
      logic.stop();
      expect(logic.readQueue.isEmpty, isTrue);
    });

    test('stop() 重置所有状态', () {
      logic.speaking = true;
      logic.speakBusy = true;
      logic.processingQueue = true;
      logic.readQueue.add('test');
      logic.stop();
      expect(logic.speaking, isFalse);
      expect(logic.speakBusy, isFalse);
      expect(logic.processingQueue, isFalse);
      expect(logic.readQueue.isEmpty, isTrue);
    });
  });

  // ========================================================================
  // 7. 并发互斥标志状态机测试
  // ========================================================================
  group('并发互斥保护', () {
    setUp(() {
      logic.stop();
    });

    test('初始状态可以 speak', () {
      expect(logic.canSpeak(), isTrue);
    });

    test('speakBusy 时不能再次 speak', () {
      logic.speakBusy = true;
      expect(logic.canSpeak(), isFalse);
    });

    test('stop() 后可以再次 speak', () {
      logic.speakBusy = true;
      logic.stop();
      expect(logic.canSpeak(), isTrue);
    });

    test('speaking 和 speakBusy 可以独立为 true', () {
      logic.speaking = true;
      logic.speakBusy = true;
      expect(logic.speaking, isTrue);
      expect(logic.speakBusy, isTrue);
    });

    test('stop() 同时重置 speaking 和 speakBusy', () {
      logic.speaking = true;
      logic.speakBusy = true;
      logic.stop();
      expect(logic.speaking, isFalse);
      expect(logic.speakBusy, isFalse);
    });

    test('processingQueue 独立于 speakBusy', () {
      logic.processingQueue = true;
      expect(logic.canSpeak(), isTrue); // processingQueue 不影响 canSpeak
      logic.stop();
      expect(logic.processingQueue, isFalse);
    });
  });

  // ========================================================================
  // 8. WAV 转换测试
  // ========================================================================
  group('WAV 转换正确性', () {
    test('空样本生成正确大小的 WAV', () {
      final samples = Float32List(0);
      final wav = toWav(samples, 16000);
      // 44 字节头 + 0 字节数据 = 44
      expect(wav.length, 44);
    });

    test('WAV 头部 RIFF 签名正确', () {
      final samples = Float32List(10);
      final wav = toWav(samples, 16000);
      // RIFF
      expect(wav[0], 0x52); // 'R'
      expect(wav[1], 0x49); // 'I'
      expect(wav[2], 0x46); // 'F'
      expect(wav[3], 0x46); // 'F'
    });

    test('WAV 头部 WAVE 格式正确', () {
      final samples = Float32List(10);
      final wav = toWav(samples, 16000);
      // WAVE at offset 8
      expect(wav[8], 0x57);  // 'W'
      expect(wav[9], 0x41);  // 'A'
      expect(wav[10], 0x56); // 'V'
      expect(wav[11], 0x45); // 'E'
    });

    test('单样本 WAV 大小正确', () {
      final samples = Float32List(1);
      final wav = toWav(samples, 16000);
      // 44 + 1 * 2 = 46 字节
      expect(wav.length, 46);
    });

    test('多样本 WAV 大小正确', () {
      final samples = Float32List(1000);
      final wav = toWav(samples, 16000);
      // 44 + 1000 * 2 = 2044 字节
      expect(wav.length, 2044);
    });

    test('采样率正确写入', () {
      final samples = Float32List(10);
      final wav = toWav(samples, 22050);
      // 采样率在 offset 24, 4 字节小端
      final sampleRate = wav[24] | (wav[25] << 8) | (wav[26] << 16) | (wav[27] << 24);
      expect(sampleRate, 22050);
    });

    test('PCM 格式标记正确', () {
      final samples = Float32List(10);
      final wav = toWav(samples, 16000);
      // PCM format = 1 at offset 20
      final format = wav[20] | (wav[21] << 8);
      expect(format, 1);
    });

    test('单声道标记正确', () {
      final samples = Float32List(10);
      final wav = toWav(samples, 16000);
      // mono = 1 at offset 22
      final channels = wav[22] | (wav[23] << 8);
      expect(channels, 1);
    });

    test('16-bit 位深度正确', () {
      final samples = Float32List(10);
      final wav = toWav(samples, 16000);
      // bits per sample = 16 at offset 34
      final bits = wav[34] | (wav[35] << 8);
      expect(bits, 16);
    });

    test('静音样本（全 0）正确编码', () {
      final samples = Float32List(5); // 全 0
      final wav = toWav(samples, 16000);
      // 数据从 offset 44 开始，每样本 2 字节
      for (var i = 44; i < wav.length; i++) {
        expect(wav[i], 0);
      }
    });

    test('正最大值 (1.0) 编码为 32767', () {
      final samples = Float32List.fromList([1.0]);
      final wav = toWav(samples, 16000);
      // offset 44: 32767 小端 = 0xFF 0x7F
      expect(wav[44], 0xFF);
      expect(wav[45], 0x7F);
    });

    test('负最大值 (-1.0) 编码为 -32767', () {
      final samples = Float32List.fromList([-1.0]);
      final wav = toWav(samples, 16000);
      // -1.0 * 32767 = -32767, 小端 = 0x01 0x80
      expect(wav[44], 0x01);
      expect(wav[45], 0x80);
    });

    test('超出范围的值被 clamp', () {
      final samples = Float32List.fromList([2.0, -2.0]);
      final wav = toWav(samples, 16000);
      // 2.0 clamp to 1.0 -> 32767 -> 0xFF 0x7F
      expect(wav[44], 0xFF);
      expect(wav[45], 0x7F);
      // -2.0 clamp to -1.0 -> -32767 -> 0x01 0x80
      expect(wav[46], 0x01);
      expect(wav[47], 0x80);
    });

    test('data chunk 大小正确', () {
      final samples = Float32List(500);
      final wav = toWav(samples, 16000);
      // data size at offset 40, 4 bytes little-endian
      final dataSize = wav[40] | (wav[41] << 8) | (wav[42] << 16) | (wav[43] << 24);
      expect(dataSize, 500 * 2);
    });

    test('data 签名正确', () {
      final samples = Float32List(10);
      final wav = toWav(samples, 16000);
      expect(wav[36], 0x64); // 'd'
      expect(wav[37], 0x61); // 'a'
      expect(wav[38], 0x74); // 't'
      expect(wav[39], 0x61); // 'a'
    });

    test('典型 TTS 输出（16kHz，几秒音频）', () {
      // 模拟 16kHz 采样率，1 秒音频 = 16000 样本
      final samples = Float32List(16000);
      for (var i = 0; i < 16000; i++) {
        samples[i] = (i / 16000.0 * 2 - 1) * 0.5; // 线性 ramp -0.5 ~ 0.5
      }
      final wav = toWav(samples, 16000);
      // 44 + 16000 * 2 = 32044
      expect(wav.length, 32044);
    });
  });

  // ========================================================================
  // 9. 预设声音列表测试
  // ========================================================================
  group('预设声音列表', () {
    test('包含 5 个声音', () {
      expect(TtsServiceLogic.presetVoices.length, 5);
    });

    test('所有声音名称非空', () {
      for (final voice in TtsServiceLogic.presetVoices) {
        expect(voice.isNotEmpty, isTrue);
      }
    });

    test('声音名称无重复', () {
      final names = TtsServiceLogic.presetVoices;
      expect(names.toSet().length, names.length);
    });
  });

  // ========================================================================
  // 10. 常量一致性测试
  // ========================================================================
  group('常量一致性', () {
    test('maxTextLength 为 2000', () {
      expect(TtsServiceLogic.maxTextLength, 2000);
    });

    test('语速范围 0.5~1.5', () {
      expect(logic.clampSpeed(0.49), 0.5);
      expect(logic.clampSpeed(0.5), 0.5);
      expect(logic.clampSpeed(1.5), 1.5);
      expect(logic.clampSpeed(1.51), 1.5);
    });

    test('空闲超时范围 0~60', () {
      expect(logic.clampIdleTimeout(-1), 0);
      expect(logic.clampIdleTimeout(0), 0);
      expect(logic.clampIdleTimeout(60), 60);
      expect(logic.clampIdleTimeout(61), 60);
    });
  });

  // ========================================================================
  // 11. 边界条件与回归测试
  // ========================================================================
  group('边界条件与回归', () {
    test('空文本 speak 不应标记 speakBusy', () {
      logic.speakBusy = false;
      // 空文本在 speak() 入口返回，不应设置 speakBusy
      final text = logic.truncateText('');
      expect(text, '');
      expect(logic.speakBusy, isFalse);
    });

    test('连续朗读关闭时 stop 应清理所有状态', () {
      logic.speaking = true;
      logic.speakBusy = true;
      logic.processingQueue = true;
      logic.readQueue.addAll(['a', 'b', 'c']);
      logic.stop();
      expect(logic.speaking, isFalse);
      expect(logic.speakBusy, isFalse);
      expect(logic.processingQueue, isFalse);
      expect(logic.readQueue, isEmpty);
    });

    test('deleteModel 场景：stop 后 speakBusy 应为 false', () {
      logic.speakBusy = true;
      logic.speaking = true;
      logic.stop(); // 模拟 deleteModel 中的 stop()
      expect(logic.speakBusy, isFalse);
      // 之后即使 speak() 重新进入也不应冲突
      expect(logic.canSpeak(), isTrue);
    });

    test('超长文本 10000 字截断后精确为 2000 字', () {
      final text = '测' * 10000;
      final result = logic.truncateText(text);
      expect(result.length, 2000);
      expect(result, '测' * 2000);
    });

    test('恰好 1999 字不截断', () {
      final text = 'a' * 1999;
      expect(logic.truncateText(text).length, 1999);
    });

    test('恰好 2001 字截断', () {
      final text = 'a' * 2001;
      expect(logic.truncateText(text).length, 2000);
    });
  });

  // ========================================================================
  // 12. 并发场景模拟测试
  // ========================================================================
  group('并发场景模拟', () {
    setUp(() {
      logic.stop();
    });

    test('模拟：连续朗读中用户手动 speak 应被拒绝', () {
      // 场景 A：连续朗读进行中
      logic.speakBusy = true;
      logic.speaking = true;
      expect(logic.canSpeak(), isFalse);
      // 用户手动点击朗读 → 被拒绝
    });

    test('模拟：stop 后可以重新 speak', () {
      logic.speakBusy = true;
      logic.stop();
      expect(logic.canSpeak(), isTrue);
    });

    test('模拟：deleteModel 并发场景', () {
      // 朗读中
      logic.speaking = true;
      logic.speakBusy = true;
      // deleteModel 调用 stop()
      logic.stop();
      // 之后 speak() 应该可以安全调用
      expect(logic.canSpeak(), isTrue);
      expect(logic.speaking, isFalse);
    });

    test('模拟：快速连续 stop 不会出错', () {
      logic.stop();
      logic.stop();
      logic.stop();
      expect(logic.speaking, isFalse);
      expect(logic.speakBusy, isFalse);
    });
  });
}
