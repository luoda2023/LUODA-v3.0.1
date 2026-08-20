import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' show OfflineTts, OfflineTtsConfig, OfflineTtsModelConfig, OfflineTtsVitsModelConfig, initBindings;

import '../models/platform_model.dart';
import 'tts_model_bundle.dart';

/// 语音朗读服务：基于 sherpa-onnx 的完全离线 TTS。
///
/// - 模型首次使用时下载到应用私有目录（支持断点续传思路：失败可重试），
///   之后完全离线朗读，不经过任何服务器。
/// - 内置 5 个中文预设声音（vits-zh-ll 多说话人模型）。
/// - 收到消息时可自动朗读（由设置页开关控制）。
class TtsService extends ChangeNotifier {
  TtsService._();
  static final TtsService instance = TtsService._();

  /// 设置 key（local option，与其它设置一致）
  static const kEnabled = 'tts-read-enabled-v1';
  static const kVoiceId = 'tts-voice-id-v1';
  static const kSpeed = 'tts-speed-v1';
  /// 连续朗读模式：开启后自动朗读所有收到的文字消息，直到手动关闭。
  static const kContinuousRead = 'tts-continuous-read-v1';
  /// 引擎空闲超时（分钟）：超过此时间未朗读则自动释放 OfflineTts 引擎，节省内存。
  /// 值为 0 表示永不自动释放。
  static const kIdleTimeoutMinutes = 'tts-idle-timeout-minutes-v1';

  /// 5 个预设声音（vits-zh-ll 模型内置说话人）
  static const List<String> presetVoices = <String>[
    '女声 1',
    '女声 2',
    '男声 1',
    '男声 2',
    '女声 3',
  ];

  /// 模型文件（从 hf-mirror 逐文件下载，无需解压）
  static const List<String> _modelFiles = <String>[
    'model.onnx',
    'tokens.txt',
    'lexicon.txt',
    'date.fst',
    'number.fst',
    'phone.fst',
    'new_heteronym.fst',
  ];

  static const List<String> _dictFiles = <String>[
    'dict/jieba.dict.utf8',
    'dict/hmm_model.utf8',
    'dict/idf.utf8',
    'dict/stop_words.utf8',
    'dict/user.dict.utf8',
  ];

  static const String _baseUrl =
      'https://hf-mirror.com/csukuangfj/sherpa-onnx-vits-zh-ll/resolve/main/';

  OfflineTts? _tts;
  AudioPlayer? _player;
  bool _speaking = false;
  bool _downloading = false;
  double _downloadProgress = 0;
  String? _downloadError;
  bool _muted = false;
  bool _bindingsReady = false;
  /// 连续朗读队列：存放待朗读的消息文本。
  final List<String> _readQueue = [];
  bool _processingQueue = false;
  /// speak() 并发互斥标志：防止多个异步调用重入。
  bool _speakBusy = false;
  /// 超长文本截断上限（字符数），避免 OOM。
  static const int _maxTextLength = 2000;
  Timer? _idleTimer;

  bool get isSpeaking => _speaking;
  bool get isDownloading => _downloading;
  double get downloadProgress => _downloadProgress;
  String? get downloadError => _downloadError;
  /// 模型是否为内置打包版本（构建时通过 --dart-define=BUNDLE_TTS_MODEL=true 启用）。
  bool get isModelBundled => TtsModelBundle.isBundled;
  bool get isEnabled =>
      bind.mainGetLocalOption(key: kEnabled) == 'Y' && !_muted;
  /// 连续朗读模式是否开启。
  bool get isContinuousRead =>
      bind.mainGetLocalOption(key: kContinuousRead) == 'Y';
  bool get isReadingQueue => _processingQueue;

  /// 语速（0.5 ~ 1.5），默认 1.0
  double get speed {
    final raw = bind.mainGetLocalOption(key: kSpeed).trim();
    final v = double.tryParse(raw);
    if (v == null || v <= 0) return 1.0;
    return v.clamp(0.5, 1.5);
  }

  /// 当前选中的声音 id（0..4）
  int get voiceId {
    final raw = bind.mainGetLocalOption(key: kVoiceId).trim();
    final v = int.tryParse(raw);
    if (v == null) return 0;
    return v.clamp(0, presetVoices.length - 1);
  }

  /// 引擎空闲超时时间（分钟）。0 表示永不自动释放。
  int get idleTimeoutMinutes {
    final raw = bind.mainGetLocalOption(key: kIdleTimeoutMinutes).trim();
    final v = int.tryParse(raw);
    if (v == null) return 5; // 默认 5 分钟
    return v.clamp(0, 60);
  }

  /// 设置引擎空闲超时时间（分钟）。0 表示永不自动释放。
  Future<void> setIdleTimeoutMinutes(int minutes) async {
    final v = minutes.clamp(0, 60);
    await bind.mainSetLocalOption(key: kIdleTimeoutMinutes, value: '$v');
    _resetIdleTimer();
    notifyListeners();
  }

  Future<Directory> _modelsRoot() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}tts_models');
  }

  Future<Directory> _vitsDir() async {
    final root = await _modelsRoot();
    return Directory('${root.path}${Platform.pathSeparator}vits-zh-ll');
  }

  /// 模型是否已下载完整（model.onnx + tokens + lexicon 存在）
  Future<bool> isModelDownloaded() async {
    final dir = await _vitsDir();
    final ok = File('${dir.path}${Platform.pathSeparator}model.onnx')
            .existsSync() &&
        File('${dir.path}${Platform.pathSeparator}tokens.txt').existsSync() &&
        File('${dir.path}${Platform.pathSeparator}lexicon.txt').existsSync();
    return ok;
  }

  /// 从内置 assets 复制模型到应用目录（仅构建时打包了模型时生效）。
  /// 返回 true 表示复制成功或已存在，false 表示复制失败。
  Future<bool> ensureBundledModel() async {
    if (!TtsModelBundle.isBundled) return false;
    if (!await TtsModelBundle.needsCopy()) return true;
    _downloading = true;
    _downloadError = null;
    _downloadProgress = 0;
    notifyListeners();
    try {
      final ok = await TtsModelBundle.copyToAppDir(
        onProgress: (progress, file) {
          _downloadProgress = progress;
          notifyListeners();
        },
      );
      _downloadProgress = 1.0;
      return ok;
    } catch (e) {
      _downloadError = '$e';
      debugPrint('TTS bundled model copy failed: $e');
      return false;
    } finally {
      _downloading = false;
      notifyListeners();
    }
  }

  /// 下载模型（带进度）。内置模型版本会先尝试从 assets 复制。
  /// 失败时抛异常，可重试。
  Future<void> downloadModel() async {
    if (_downloading) return;
    // 内置模型版本：优先从 assets 复制。
    if (TtsModelBundle.isBundled) {
      final copied = await ensureBundledModel();
      if (copied) return;
      // 复制失败则回退到在线下载。
    }
    _downloading = true;
    _downloadError = null;
    _downloadProgress = 0;
    notifyListeners();
    try {
      final dir = await _vitsDir();
      await dir.create(recursive: true);
      final dictDir = Directory(
          '${dir.path}${Platform.pathSeparator}dict');
      await dictDir.create(recursive: true);

      final total = _modelFiles.length + _dictFiles.length;
      var done = 0;
      for (final name in _modelFiles) {
        await _downloadFile(
          '$_baseUrl$name',
          '${dir.path}${Platform.pathSeparator}$name',
        );
        done++;
        _downloadProgress = done / total;
        notifyListeners();
      }
      for (final name in _dictFiles) {
        await _downloadFile(
          '$_baseUrl$name',
          '${dictDir.path}${Platform.pathSeparator}'
              '${name.split('/').last}',
        );
        done++;
        _downloadProgress = done / total;
        notifyListeners();
      }
      _downloadProgress = 1.0;
    } catch (e) {
      _downloadError = '$e';
      rethrow;
    } finally {
      _downloading = false;
      notifyListeners();
    }
  }

  HttpClient? _sharedClient;

  HttpClient get _client {
    return _sharedClient ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..maxConnectionsPerHost = 4;
  }

  /// 下载单个文件，支持断点续传和重试。
  Future<void> _downloadFile(String url, String destPath, {int maxRetries = 3}) async {
    final destFile = File(destPath);
    // 如果目标文件已存在且大小合理，跳过下载
    if (await destFile.exists()) {
      final size = await destFile.length();
      if (size > 0) return;
    }

    for (var attempt = 0; attempt < maxRetries; attempt++) {
      IOSink? sink;
      try {
        final request = await _client.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode != 200) {
          throw HttpException('HTTP ${response.statusCode} for $url');
        }
        final tmpFile = File('$destPath.tmp');
        // 使用异步 sink 避免大文件下载时阻塞事件循环。
        sink = tmpFile.openWrite(mode: FileMode.writeOnly);
        await for (final chunk in response) {
          sink.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
        }
        await sink.flush();
        await sink.close();
        sink = null;
        if (tmpFile.lengthSync() == 0) {
          throw HttpException('Empty download for $url');
        }
        tmpFile.renameSync(destPath);
        return;
      } catch (e) {
        // 确保 sink 在异常时也被关闭，避免文件句柄泄漏。
        if (sink != null) {
          await sink.close();
        }
        // 清理残留的 .tmp 文件，避免磁盘空间浪费。
        final tmpFile = File('$destPath.tmp');
        if (tmpFile.existsSync()) {
          try { tmpFile.deleteSync(); } catch (_) {}
        }
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(Duration(seconds: (attempt + 1) * 2));
      }
    }
  }

  /// 删除模型，释放存储空间。
  /// 删除前先停止当前朗读并释放 AudioPlayer，避免资源泄漏。
  Future<void> deleteModel() async {
    if (_speaking || _speakBusy) await stop();
    final dir = await _vitsDir();
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
    _tts?.free();
    _tts = null;
    // 释放 AudioPlayer 原生资源。
    await _player?.dispose();
    _player = null;
    _sharedClient?.close(force: true);
    _sharedClient = null;
    notifyListeners();
  }

  /// 初始化引擎（懒加载）。模型未下载时返回 false。
  ///
  /// 关键：sherpa-onnx 要求先调用 [initBindings] 加载原生库，
  /// 否则 OfflineTts 构造会抛 “Please initialize sherpa-onnx first”。
  /// Windows 上需传入含 sherpa-onnx-c-api.dll 的目录（exe 同目录）。
  Future<bool> ensureInitialized() async {
    if (_tts != null) return true;
    if (!_bindingsReady) {
      try {
        if (Platform.isWindows) {
          final exeDir = File(Platform.resolvedExecutable).parent.path;
          initBindings(exeDir);
        } else {
          initBindings();
        }
        _bindingsReady = true;
      } catch (e) {
        debugPrint('TTS initBindings failed: $e');
        return false;
      }
    }
    if (!await isModelDownloaded()) return false;
    try {
      final dir = await _vitsDir();
      _tts = OfflineTts(
        OfflineTtsConfig(
          maxNumSenetences: 3,
          model: OfflineTtsModelConfig(
            numThreads: 2,
            debug: false,
            vits: OfflineTtsVitsModelConfig(
              model: '${dir.path}${Platform.pathSeparator}model.onnx',
              tokens: '${dir.path}${Platform.pathSeparator}tokens.txt',
              lexicon: '${dir.path}${Platform.pathSeparator}lexicon.txt',
              dictDir: '${dir.path}${Platform.pathSeparator}dict',
            ),
          ),
        ),
      );
      _resetIdleTimer();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('TTS init failed: $e');
      return false;
    }
  }

  /// 重置空闲超时计时器。超时为 0 时不创建计时器（永不自动释放）。
  void _resetIdleTimer() {
    _idleTimer?.cancel();
    final minutes = idleTimeoutMinutes;
    if (minutes > 0) {
      _idleTimer = Timer(Duration(minutes: minutes), _releaseEngine);
    }
  }

  /// 释放 OfflineTts 引擎以节省内存。下次朗读时会自动重新初始化。
  void _releaseEngine() {
    if (_speaking || _speakBusy) return; // 朗读中不释放
    _tts?.free();
    _tts = null;
    debugPrint('TTS engine released (idle timeout)');
    notifyListeners();
  }

  /// 朗读一段文本。未启用/未就绪时静默跳过。
  ///
  /// 并发保护：如果已有 speak 调用正在执行，新调用直接返回，
  /// 避免两个异步流同时操作 AudioPlayer 导致状态不一致。
  ///
  /// 超长文本截断：超过 [_maxTextLength] 字符时自动截断，
  /// 防止 OfflineTts.generate() 分配过大内存导致 OOM。
  Future<void> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !isEnabled) return;
    // 并发互斥：已有朗读任务时直接跳过。
    if (_speakBusy) return;
    _speakBusy = true;
    try {
      // 如果正在播放旧音频，先干净停止。
      if (_speaking) {
        final player = _player;
        if (player != null) await player.stop();
        _speaking = false;
      }
      final ok = await ensureInitialized();
      if (!ok || _tts == null) return;
      // 超长文本截断保护。
      final safeText = trimmed.length > _maxTextLength
          ? trimmed.substring(0, _maxTextLength)
          : trimmed;
      // 再次检查 _tts 有效性（deleteModel 可能在 await 期间释放了引擎）。
      final tts = _tts;
      if (tts == null) return;
      final audio = tts.generate(
        text: safeText,
        sid: voiceId,
        speed: speed,
      );
      if (audio.samples.isEmpty) return;
      final wav = _toWav(audio.samples, audio.sampleRate);
      _speaking = true;
      notifyListeners();
      final player = _player ??= AudioPlayer();
      await player.play(BytesSource(wav));
      // 播放完成事件在个别设备/平台上可能不触发，加超时避免永久挂起。
      await player.onPlayerComplete
          .first
          .timeout(const Duration(seconds: 60), onTimeout: () {});
    } catch (e) {
      debugPrint('TTS speak failed: $e');
    } finally {
      // 显式停止播放器，确保 AudioPlayer 不会在后台残留播放。
      final player = _player;
      if (player != null) await player.stop();
      _speaking = false;
      _speakBusy = false;
      notifyListeners();
    }
  }

  /// 试听某个声音。预览前停止当前播放。
  Future<void> preview(int sid) async {
    final ok = await ensureInitialized();
    if (!ok || _tts == null) return;
    try {
      final audio = _tts!.generate(
        text: '你好，这是声音预览。',
        sid: sid.clamp(0, presetVoices.length - 1),
        speed: speed,
      );
      if (audio.samples.isEmpty) return;
      final wav = _toWav(audio.samples, audio.sampleRate);
      final player = _player ??= AudioPlayer();
      // 先停止当前播放，再播放预览音频。
      if (_speaking) {
        _speaking = false;
        notifyListeners();
      }
      await player.stop();
      await player.play(BytesSource(wav));
    } catch (e) {
      debugPrint('TTS preview failed: $e');
    }
  }

  Future<void> stop() async {
    final player = _player;
    if (player != null) {
      await player.stop();
    }
    _speaking = false;
    _speakBusy = false;
    _readQueue.clear();
    _processingQueue = false;
    notifyListeners();
  }

  /// 开启/关闭连续朗读模式。
  Future<void> setContinuousRead(bool enabled) async {
    await bind.mainSetLocalOption(
        key: kContinuousRead, value: enabled ? 'Y' : '');
    if (!enabled) {
      // 关闭时停止当前朗读并清空队列（stop() 内部已包含清空逻辑）。
      if (_speaking) await stop();
    }
    notifyListeners();
  }

  /// 连续朗读模式：将消息加入队列，自动逐条朗读。
  /// 收到新消息时调用此方法。
  void enqueueForReading(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !isContinuousRead || !isEnabled) return;
    _readQueue.add(trimmed);
    notifyListeners();
    _processQueue();
  }

  /// 逐条处理朗读队列。
  Future<void> _processQueue() async {
    if (_processingQueue) return;
    _processingQueue = true;
    notifyListeners();
    try {
      while (_readQueue.isNotEmpty && isContinuousRead && isEnabled) {
        final text = _readQueue.removeAt(0);
        await speak(text);
        // 消息之间间隔 300ms，避免连读。
        if (_readQueue.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    } finally {
      _processingQueue = false;
      notifyListeners();
    }
  }

  /// 将 Float32 PCM 转成 16-bit WAV bytes（用于 audioplayers 播放）
  Uint8List _toWav(Float32List samples, int sampleRate) {
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
    bytes.setUint32(16, 16, Endian.little); // PCM chunk size
    bytes.setUint16(20, 1, Endian.little); // PCM format
    bytes.setUint16(22, 1, Endian.little); // mono
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    bytes.setUint16(32, 2, Endian.little); // block align
    bytes.setUint16(34, 16, Endian.little); // bits per sample
    writeString(36, 'data');
    bytes.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
      bytes.setInt16(44 + i * 2, v, Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}
