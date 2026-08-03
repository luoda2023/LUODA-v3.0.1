import 'package:url_launcher/url_launcher.dart';

import 'string_utils.dart';

typedef EmailDraftLauncher = Future<bool> Function(Uri uri);

class EmailDraftMessage {
  const EmailDraftMessage({
    required this.sender,
    required this.sentAt,
    required this.text,
    this.fileName = '',
  });

  final String sender;
  final DateTime sentAt;
  final String text;
  final String fileName;
}

class EmailDraftService {
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static bool isValidAddress(String value) =>
      _emailPattern.hasMatch(value.trim());

  static String formatMessages(
    Iterable<EmailDraftMessage> messages, {
    required String fileLabel,
  }) {
    final output = StringBuffer();
    for (final message in messages) {
      final local = message.sentAt.toLocal();
      final timestamp = '${local.year.toString().padLeft(4, '0')}-'
          '${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')} '
          '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}:'
          '${local.second.toString().padLeft(2, '0')}';
      final sender = sanitizeInvalidUtf16(message.sender);
      final text = sanitizeInvalidUtf16(message.text);
      final fileName = sanitizeInvalidUtf16(message.fileName);
      final content = fileName.isEmpty
          ? text
          : '[${sanitizeInvalidUtf16(fileLabel)}] $fileName'
              '${text.isEmpty ? '' : '\n$text'}';
      output
        ..writeln('[$timestamp] $sender:')
        ..writeln(content)
        ..writeln();
    }
    return output.toString().trimRight();
  }

  static Uri buildUri({
    required String recipient,
    required String subject,
    required String body,
  }) {
    return Uri(
      scheme: 'mailto',
      path: sanitizeInvalidUtf16(recipient).trim(),
      queryParameters: <String, String>{
        'subject': sanitizeInvalidUtf16(subject),
        'body': sanitizeInvalidUtf16(body),
      },
    );
  }

  static Future<bool> openDraft({
    required String recipient,
    required String subject,
    required String body,
    EmailDraftLauncher? launcher,
  }) async {
    if (!isValidAddress(recipient)) return false;
    final uri = buildUri(
      recipient: recipient,
      subject: subject,
      body: body,
    );
    try {
      return await (launcher ?? _launch)(uri);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _launch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
