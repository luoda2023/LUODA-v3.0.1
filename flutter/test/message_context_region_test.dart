import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/widgets/message_context_region.dart';

void main() {
  testWidgets(
    'secondary pointer reaches the message menu through selectable text',
    (tester) async {
      Offset? secondaryPosition;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MessageContextRegion(
                onSecondaryTap: (position) => secondaryPosition = position,
                child: const SelectableText('selectable chat message'),
              ),
            ),
          ),
        ),
      );

      final position = tester.getCenter(find.text('selectable chat message'));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.down(position);
      await gesture.up();
      await tester.pump();

      expect(secondaryPosition, position);
    },
  );

  testWidgets('long press on touch reaches the message menu', (tester) async {
    Offset? longPressPosition;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MessageContextRegion(
              onSecondaryTap: (_) {},
              onLongPress: (position) => longPressPosition = position,
              child: const Text('touch chat message'),
            ),
          ),
        ),
      ),
    );

    final position = tester.getCenter(find.text('touch chat message'));
    final gesture = await tester.startGesture(position);
    // Long-press threshold is ~500ms; hold longer to guarantee firing.
    await tester.pump(const Duration(milliseconds: 800));
    await gesture.up();
    await tester.pump();

    expect(longPressPosition, isNotNull);
    expect(longPressPosition!.dx, closeTo(position.dx, 1));
    expect(longPressPosition!.dy, closeTo(position.dy, 1));
  });

  testWidgets('selectable text keeps its own long press selection',
      (tester) async {
    // SelectableText 内部的长按选择手势会优先于外层长按（文字选择是系统
    // 默认行为）。消息场景通过 RichChatText.enableSelection=false 避免冲突。
    Offset? longPressPosition;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MessageContextRegion(
              onSecondaryTap: (_) {},
              onLongPress: (position) => longPressPosition = position,
              child: const SelectableText('selectable long press message'),
            ),
          ),
        ),
      ),
    );

    final position =
        tester.getCenter(find.text('selectable long press message'));
    final gesture = await tester.startGesture(position);
    await tester.pump(const Duration(milliseconds: 800));
    await gesture.up();
    await tester.pump();

    // 文字选择优先：外层长按不触发（消息场景已用不可选文本避免冲突）。
    expect(longPressPosition, isNull);
  });
}
