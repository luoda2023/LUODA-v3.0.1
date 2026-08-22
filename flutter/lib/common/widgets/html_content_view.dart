import 'package:flutter/material.dart';

/// Strip HTML tags from [html] and return plain text.
String stripHtmlText(String html) {
  return html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
}

/// Simple HTML content viewer widget.
class HtmlContentView extends StatelessWidget {
  const HtmlContentView(
    this.html, {
    super.key,
    this.textStyle,
  });

  final String html;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Text(
      stripHtmlText(html),
      style: textStyle,
    );
  }
}
