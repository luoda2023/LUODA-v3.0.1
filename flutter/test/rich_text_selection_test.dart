import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/widgets/rich_text_builder.dart';

void main() {
  testWidgets('enableSelection=false renders non-selectable text',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RichChatText(text: 'plain message', foreground: Colors.black),
        ),
      ),
    );

    expect(find.byType(SelectableText), findsNothing);
    expect(find.text('plain message'), findsOneWidget);
  });

  testWidgets('enableSelection=true renders selectable text',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RichChatText(
            text: 'plain message',
            foreground: Colors.black,
            enableSelection: true,
          ),
        ),
      ),
    );

    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('link stays tappable without text selection', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RichChatText(
            text: 'visit https://example.com now',
            foreground: Colors.black,
          ),
        ),
      ),
    );

    expect(find.text('https://example.com'), findsOneWidget);
  });
}
