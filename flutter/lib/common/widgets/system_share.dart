import 'dart:io';

import 'package:share_plus/share_plus.dart';

/// 分享到微信等应用（Android/iOS 系统分享面板，微信作为接收方出现）。
///
/// - [text]: 分享文本（纯文本消息、位置描述等）。
/// - [files]: 要分享的文件（图片/文档/音视频）。路径必须是真实存在的本地文件。
/// - [subject]: 可选主题（部分系统面板显示）。
Future<bool> shareToSystemApp({
  String text = '',
  List<String> files = const <String>[],
  String? subject,
}) async {
  final existingFiles = <XFile>[
    for (final path in files)
      if (path.trim().isNotEmpty && File(path).existsSync()) XFile(path.trim()),
  ];
  final shareText = text.trim();
  if (shareText.isEmpty && existingFiles.isEmpty) return false;
  try {
    final ShareResult result;
    if (existingFiles.isNotEmpty) {
      result = await Share.shareXFiles(
        existingFiles,
        subject: subject,
        text: shareText.isEmpty ? null : shareText,
      );
    } else {
      result = await Share.share(
        shareText,
        subject: subject,
      );
    }
    // 用户取消了分享面板时不提示错误。
    return result.status != ShareResultStatus.dismissed ||
        result.status == ShareResultStatus.success;
  } catch (e) {
    // 分享失败（罕见，如 FileProvider 未配置）静默处理，调用方决定提示。
    return false;
  }
}

/// 分享单个文件（图片/文档/音视频），带 MIME 无关的系统分享。
Future<bool> shareFileToSystemApp(
  String path, {
  String? text,
}) {
  return shareToSystemApp(
    text: text ?? '',
    files: <String>[path],
  );
}

/// 分享消息文本（普通文本消息、位置卡片文本等）。
Future<bool> shareTextToSystemApp(
  String text, {
  String? subject,
}) {
  return shareToSystemApp(text: text, subject: subject);
}
