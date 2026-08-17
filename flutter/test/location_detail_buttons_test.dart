import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_chat.dart';
import 'package:luoda_flutter/common/widgets/location_detail_page.dart';

// 位置详情页：三按钮渲染验证。
// 导航/复制/分享的实际交互已在真机实测（导航弹地图选择窗、
// 复制写剪贴板、分享调系统分享面板），此处仅验证按钮渲染，
// 避免 widget 测试中 FlutterMap 瓦片网络请求造成挂起。
void main() {
  const loc = DirectChatLocation(
    latitude: 30.2741,
    longitude: 120.1551,
    name: '西湖景区',
    address: '浙江省杭州市西湖区',
  );

  testWidgets('renders the three action buttons', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LocationDetailPage(location: loc)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Navigate'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });
}
