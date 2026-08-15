import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

// 回归测试：位置卡片内的 FlutterMap 即使设置 InteractiveFlag.none，
// flutter_map 7.x 内部仍注册 TapGestureRecognizer，会吞掉点击事件，
// 导致外层 GestureDetector 的 onTap（打开位置详情页）永远不触发。
//
// 修复：用 IgnorePointer 包住卡片内地图，让点击穿透到外层 GestureDetector。
void main() {
  Widget harness({required bool useIgnorePointer, required VoidCallback onTap}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              width: 232,
              height: 112,
              color: Colors.white,
              child: useIgnorePointer
                  ? IgnorePointer(
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: const LatLng(30.2741, 120.1551),
                          initialZoom: 16,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none,
                          ),
                        ),
                        children: const <Widget>[],
                      ),
                    )
                  : FlutterMap(
                      options: MapOptions(
                        initialCenter: const LatLng(30.2741, 120.1551),
                        initialZoom: 16,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.none,
                        ),
                      ),
                      children: const <Widget>[],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('bug: FlutterMap with InteractiveFlag.none still swallows tap',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(harness(
      useIgnorePointer: false,
      onTap: () => tapped = true,
    ));
    await tester.tap(find.byType(Container).first);
    // FlutterMap 的 _handleOnTapUp 会创建 250ms timer（吞点击的副作用），
    // 先消化 timer 再断言外层 onTap 未被触发。
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, isFalse,
        reason: 'flutter_map 注册的 TapGestureRecognizer 吞掉了点击');
  });

  testWidgets('fix: IgnorePointer lets the tap reach the outer GestureDetector',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(harness(
      useIgnorePointer: true,
      onTap: () => tapped = true,
    ));
    await tester.tap(find.byType(Container).first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, isTrue, reason: 'IgnorePointer 后点击应穿透到外层 onTap');
  });
}
