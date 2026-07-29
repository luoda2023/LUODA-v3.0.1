import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../common.dart';

/// AI service configuration.
/// Stored as JSON in local options.
class AiConfig {
  final String endpoint;
  final String apiKey;
  final String model;
  final bool enabled;

  const AiConfig({
    this.endpoint = '',
    this.apiKey = '',
    this.model = 'gpt-4o-mini',
    this.enabled = false,
  });

  static const _storageKey = 'luoda_ai_config';

  static AiConfig _cached = const AiConfig();

  static AiConfig get current => _cached;

  static void load() {
    try {
      final raw = bind.mainGetLocalOption(key: _storageKey);
      if (raw.isEmpty) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _cached = AiConfig(
        endpoint: (json['endpoint'] ?? '').toString(),
        apiKey: (json['api_key'] ?? '').toString(),
        model: (json['model'] ?? 'gpt-4o-mini').toString(),
        enabled: json['enabled'] == true,
      );
    } catch (_) {
      // keep defaults
    }
  }

  static Future<void> save(AiConfig config) async {
    _cached = config;
    await bind.mainSetLocalOption(
      key: _storageKey,
      value: jsonEncode({
        'endpoint': config.endpoint,
        'api_key': config.apiKey,
        'model': config.model,
        'enabled': config.enabled,
      }),
    );
  }

  Map<String, dynamic> toJson() => {
        'endpoint': endpoint,
        'api_key': apiKey,
        'model': model,
        'enabled': enabled,
      };
}

/// Shared AI API caller — returns raw response content from any prompt.
String? _callAiSync(String prompt, {double temperature = 0.7}) {
  // This is called synchronously inside a compute isolate stub;
  // for simplicity we use the actual HTTP call inline.
  // In production, consider moving to a background isolate.
  return _callAi(prompt, temperature: temperature);
}

Future<String?> _callAi(String prompt, {double temperature = 0.7}) async {
  final config = AiConfig.current;
  if (!config.enabled || config.endpoint.isEmpty || config.apiKey.isEmpty) {
    return null;
  }
  try {
    final uri = Uri.parse(config.endpoint);
    final response = await http
        .post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (config.apiKey.isNotEmpty)
          'Authorization': 'Bearer ${config.apiKey}',
      },
      body: jsonEncode({
        'model': config.model,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'max_tokens': 2048,
        'temperature': temperature,
      }),
    )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = body['choices'] as List?;
      if (choices != null && choices.isNotEmpty) {
        final content =
            (choices[0] as Map<String, dynamic>)['message']?['content']
                ?.toString()
                .trim();
        if (content != null && content.isNotEmpty) {
          return content;
        }
      }
    } else {
      debugPrint(
          'AI call failed: HTTP ${response.statusCode} ${response.body}');
    }
  } catch (e) {
    debugPrint('AI call error: $e');
  }
  return null;
}

/// AI-powered services: translation + chat.
class AiService {
  /// Translate [text] between Chinese and English.
  static Future<String?> translate(String text) async {
    final hasChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
    final sourceLang = hasChinese ? 'Chinese' : 'English';
    final targetLang = hasChinese ? 'English' : 'Chinese';

    final prompt = 'Translate the following $sourceLang text to $targetLang. '
        'Reply with ONLY the translated text, no explanations, no quotes.\n\n'
        '$text';
    return _callAi(prompt, temperature: 0.1);
  }

  /// Chat: generate a reply for a user message (used for "#" prefixed messages).
  /// Returns the AI-generated reply text.
  static Future<String?> chat(String message) async {
    final prompt = 'You are a helpful assistant. Reply concisely and '
        'naturally in the same language as the user message.\n\n'
        '$message';
    return _callAi(prompt, temperature: 0.7);
  }
}
