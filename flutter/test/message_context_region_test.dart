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
}
