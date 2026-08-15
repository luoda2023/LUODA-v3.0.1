import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/widgets/message_context_region.dart';

// 回归测试：图片 / 文件消息卡片都是 InkWell + onTap 打开预览，
// 外层包着 MessageContextRegion（右键/长按弹出操作菜单）。
// 必须确认：
//   1. 点击图片/文件卡片 → onTap（打开预览）正常触发，不被外层手势吞掉
//   2. 长按卡片 → onLongPress（操作菜单）仍然触发，两个手势互不干扰
void main() {
  Widget harness({
    required VoidCallback onTap,
    required ValueChanged<Offset> onLongPress,
    Widget? child,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: MessageContextRegion(
            onSecondaryTap: (_) {},
            onLongPress: onLongPress,
            child: InkWell(
              onTap: onTap,
              child: Container(
                width: 220,
                height: 100,
                color: Colors.white,
                child: child ??
                    const Icon(Icons.insert_drive_file_rounded, size: 40),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('图片/文件卡片：点击触发 InkWell onTap，不被 MessageContextRegion 吞',
      (tester) async {
    var tapped = 0;
    var longPressed = 0;
    await tester.pumpWidget(harness(
      onTap: () => tapped++,
      onLongPress: (_) => longPressed++,
    ));
    await tester.tap(find.byType(InkWell));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tapped, 1, reason: '点击卡片应触发 onTap（打开预览）');
    expect(longPressed, 0);
  });

  testWidgets('图片卡片：Image.file 场景下点击仍触发 onTap', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(harness(
      onTap: () => tapped++,
      onLongPress: (_) {},
      child: Container(
        width: 200,
        height: 140,
        color: const Color(0xFFF0F0F0),
        child: const Icon(Icons.broken_image_outlined, size: 40),
      ),
    ));
    await tester.tap(find.byType(InkWell));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tapped, 1, reason: '图片附件卡片点击应触发预览 onTap');
  });

  testWidgets('长按仍触发 MessageContextRegion 的 onLongPress（操作菜单）',
      (tester) async {
    var tapped = 0;
    var longPressed = 0;
    await tester.pumpWidget(harness(
      onTap: () => tapped++,
      onLongPress: (_) => longPressed++,
    ));
    final center = tester.getCenter(find.byType(InkWell));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    expect(longPressed, 1, reason: '长按应触发操作菜单');
    expect(tapped, 0, reason: '长按不应误触 onTap');
  });
}
