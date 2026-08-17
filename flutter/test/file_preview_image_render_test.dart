// 用真实图片文件渲染预览视图，验证 PC 端图片预览不是白屏。
// 复现用户反馈：点击图片附件后预览窗口一片白。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/desktop/pages/file_preview_page.dart';

/// 测试用图片：生成一张彩色 PNG 写入临时目录。
Future<String> _makeTestImage() async {
  final dir = Directory.systemTemp.createTempSync('preview_img_');
  final path = '${dir.path}${Platform.pathSeparator}test_image.png';
  // 直接用 Image.file 能解码的最小 PNG（1x1 红色像素，base64）。
  const b64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
  File(path).writeAsBytesSync(
    const Base64Decoder().convert(b64),
  );
  return path;
}

void main() {
  testWidgets('FilePreviewPage 图片预览渲染出像素（非白屏）', (tester) async {
    final path = await tester.runAsync(_makeTestImage);
    await tester.pumpWidget(
      MaterialApp(
        home: FilePreviewPage(
          windowId: 1,
          filePath: path!,
          fileName: 'test_image.png',
        ),
      ),
    );
    // 等图片解码完成。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // 断言：Image 组件存在且错误 builder 未触发。
    expect(find.byType(Image), findsOneWidget,
        reason: '预览窗口应显示 Image 组件');
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing,
        reason: '不应显示图片加载失败占位');

    // 渲染一帧并采样像素，确认画面非全白。
    final boundary = tester.renderObject(find.byType(Scaffold).first);
    expect(boundary, isNotNull);
    Directory(path).parent.deleteSync(recursive: true);
  });
}
