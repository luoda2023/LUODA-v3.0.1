import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// TTS 模型内置打包支持。
///
/// 构建时通过 `--dart-define=BUNDLE_TTS_MODEL=true` 启用模型打包。
/// 启用后，应用首次启动时会将 assets 中的模型文件复制到应用私有目录，
/// 之后 TtsService 直接从私有目录读取，无需联网下载。
class TtsModelBundle {
  TtsModelBundle._();

  /// 构建标志：是否内置了 TTS 模型。
  static const bool isBundled = bool.fromEnvironment(
    'BUNDLE_TTS_MODEL',
    defaultValue: false,
  );

  /// assets 中的模型根路径。
  static const String _assetRoot = 'assets/tts_models/vits-zh-ll';

  /// 目标目录名（与 TtsService._vitsDir() 一致）。
  static const String _targetDirName = 'vits-zh-ll';

  /// 需要复制的模型文件列表。
  static const List<String> _modelAssetFiles = <String>[
    'model.onnx',
    'tokens.txt',
    'lexicon.txt',
    'date.fst',
    'number.fst',
    'phone.fst',
    'new_heteronym.fst',
  ];

  /// 需要复制的字典文件列表（在 dict/ 子目录下）。
  static const List<String> _dictAssetFiles = <String>[
    'dict/jieba.dict.utf8',
    'dict/hmm_model.utf8',
    'dict/idf.utf8',
    'dict/stop_words.utf8',
    'dict/user.dict.utf8',
  ];

  /// 标记文件：表示已完成复制。
  static const String _markerFileName = '.bundled_v1';

  /// 检查是否需要从 assets 复制模型。
  /// 返回 true 表示需要复制（首次启动或版本更新）。
  static Future<bool> needsCopy() async {
    if (!isBundled) return false;
    final base = await getApplicationSupportDirectory();
    final targetDir = Directory(
      '${base.path}${Platform.pathSeparator}tts_models'
      '${Platform.pathSeparator}$_targetDirName',
    );
    if (!targetDir.existsSync()) return true;
    final marker = File(
      '${targetDir.path}${Platform.pathSeparator}$_markerFileName',
    );
    return !marker.existsSync();
  }

  /// 从 assets 复制模型到应用私有目录。
  /// 首次启动时调用，复制完成后创建标记文件。
  /// 如果已复制过则静默跳过。
  static Future<bool> copyToAppDir({
    void Function(double progress, String currentFile)? onProgress,
  }) async {
    if (!isBundled) return false;

    try {
      final base = await getApplicationSupportDirectory();
      final targetDir = Directory(
        '${base.path}${Platform.pathSeparator}tts_models'
        '${Platform.pathSeparator}$_targetDirName',
      );
      await targetDir.create(recursive: true);

      final dictDir = Directory(
        '${targetDir.path}${Platform.pathSeparator}dict',
      );
      await dictDir.create(recursive: true);

      final allFiles = [
        for (final f in _modelAssetFiles) (f, false),
        for (final f in _dictAssetFiles) (f, true),
      ];

      for (var i = 0; i < allFiles.length; i++) {
        final (assetName, isDict) = allFiles[i];
        final assetPath = '$_assetRoot/$assetName';
        final fileName = assetName.split('/').last;
        final targetPath = isDict
            ? '${dictDir.path}${Platform.pathSeparator}$fileName'
            : '${targetDir.path}${Platform.pathSeparator}$fileName';

        final targetFile = File(targetPath);
        // 如果目标文件已存在且大小合理，跳过（支持断点续复制）
        if (await targetFile.exists()) {
          final size = await targetFile.length();
          if (size > 0) {
            onProgress?.call((i + 1) / allFiles.length, assetName);
            continue;
          }
        }

        // 从 assets 加载并写入磁盘。
        final ByteData data = await rootBundle.load(assetPath);
        final bytes = data.buffer.asUint8List();
        await targetFile.writeAsBytes(bytes, flush: true);
        onProgress?.call((i + 1) / allFiles.length, assetName);
      }

      // 写入标记文件，表示复制完成。
      final marker = File(
        '${targetDir.path}${Platform.pathSeparator}$_markerFileName',
      );
      await marker.writeAsString('bundled_v1');

      debugPrint('TTS model copied from assets to ${targetDir.path}');
      return true;
    } catch (e) {
      debugPrint('TTS model bundle copy failed: $e');
      return false;
    }
  }
}
