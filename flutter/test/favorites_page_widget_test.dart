import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/favorites_model.dart';
import 'package:luoda_flutter/common/widgets/favorites_page.dart';

ChatUser _user(String id, String name) => ChatUser(id: id, firstName: name);

void main() {
  testWidgets('FavoritesPage renders category tabs and empty state',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: FavoritesPage()),
    );
    await tester.pumpAndSettle();

    // AppBar title 与分类 tabs 应渲染（测试环境 translate 返回原 key）。
    expect(find.text('Favorites'), findsWidgets);

    // 测试环境 translate 返回英文 key（较长），只断言视口内可见的分类 tab；
    // 末尾 tab（语音/联系人）在真机中文环境下必然显示。
    for (final cat in <String>[
      'favorites_cat_all',
      'favorites_cat_image',
      'favorites_cat_file',
      'favorites_cat_location',
      'favorites_cat_text',
    ]) {
      expect(find.text(cat), findsOneWidget, reason: 'missing tab $cat');
    }

    // 空态提示。
    expect(find.text('favorites_empty'), findsOneWidget);
  });

  testWidgets('FavoritesPage switches category and filters items',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final model = FavoritesModel.instance;
    await model.removeAll(model.items.map((e) => e.id));

    // 预置两条不同分类的收藏：文字 + 位置。
    await model.toggleMessage(ChatMessage(
      text: 'hello world',
      createdAt: DateTime.now(),
      user: _user('peer-1', 'Peer One'),
      customProperties: <String, dynamic>{
        'ldesk_kind': 'text',
        'ldesk_id': 'seed-text',
      },
    ));
    await model.toggleMessage(ChatMessage(
      text: '[location]31.230416,121.473701|上海迪士尼乐园|上海市浦东新区',
      createdAt: DateTime.now(),
      user: _user('peer-1', 'Peer One'),
      customProperties: <String, dynamic>{
        'ldesk_kind': 'text',
        'ldesk_id': 'seed-loc',
      },
    ));

    await tester.pumpWidget(
      const MaterialApp(home: FavoritesPage()),
    );
    await tester.pumpAndSettle();

    // 全部分类应显示两条。
    expect(find.textContaining('hello world'), findsOneWidget);
    expect(find.textContaining('上海迪士尼乐园'), findsOneWidget);

    // 切到"位置"分类 → 只显示位置收藏。
    await tester.tap(find.text('favorites_cat_location'));
    await tester.pumpAndSettle();
    expect(find.textContaining('上海迪士尼乐园'), findsOneWidget);
    expect(find.textContaining('hello world'), findsNothing);

    await model.removeAll(model.items.map((e) => e.id));
  });
}
