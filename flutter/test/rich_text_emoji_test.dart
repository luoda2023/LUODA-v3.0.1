import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/string_utils.dart';
import 'package:luoda_flutter/common/widgets/rich_text_builder.dart';

void main() {
  testWidgets('emoji-only messages render at one and a half size',
      (tester) async {
    const defaultSize = 14.0;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RichChatText(
            text: '\u{1F602}\u{1F44D}',
            foreground: Colors.black,
            defaultSize: defaultSize,
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.style?.fontSize, defaultSize * 1.5);
  });

  testWidgets('mixed text and emoji keep the normal size', (tester) async {
    const defaultSize = 14.0;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RichChatText(
            text: 'hello \u{1F602}',
            foreground: Colors.black,
            defaultSize: defaultSize,
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.style?.fontSize, defaultSize);
  });

  testWidgets('rich chat text keeps supplementary emoji spans valid',
      (tester) async {
    const message = 'same 😀😀 different 😂🧑‍💻';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RichChatText(
            text: message,
            foreground: Colors.black,
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.byType(Text));
    final span = text.textSpan! as TextSpan;
    final spans = span.children!.whereType<TextSpan>();

    expect(span.toPlainText(), message);
    expect(spans, hasLength(1));
    for (final span in spans) {
      expect(sanitizeInvalidUtf16(span.text!), span.text);
    }
  });
}
