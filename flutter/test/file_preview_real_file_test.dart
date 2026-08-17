// 用真实存在的截图文件渲染 FilePreviewPage，验证 PC 端图片预览。
// 直接覆盖用户当前环境中的真实文件。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/desktop/pages/file_preview_page.dart';

void main() {
  const realFile =
      r'C:\Users\Administrator\AppData\Roaming\DotChat\DotChat\screenshots\screenshot_1786766536083.png';

  testWidgets('FilePreviewPage 渲染真实截图文件', (tester) async {
    if (!File(realFile).existsSync()) {
      // 测试环境无此文件时跳过（CI 上不存在）。
      return;
    }
    await tester.pumpWidget(
      MaterialApp(
        home: FilePreviewPage(
          windowId: 1,
          filePath: realFile,
          fileName: 'screenshot_1786766536083.png',
        ),
      ),
    );
    // 等图片解码完成（Image.file 异步加载）。
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    // Image 存在且未显示失败占位。
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
  });
}
