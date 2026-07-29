import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../common.dart';

/// AI service configuration for chat translation.
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

/// AI-powered translation service.
class AiTranslateService {
  /// Translate [text] between Chinese and English using the configured AI API.
  /// Returns the translated text, or null on failure.
  static Future<String?> translate(String text) async {
    final config = AiConfig.current;
    if (!config.enabled || config.endpoint.isEmpty || config.apiKey.isEmpty) {
      return null;
    }

    // Detect direction: if text contains Chinese chars, translate to English
    final hasChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
    final sourceLang = hasChinese ? 'Chinese' : 'English';
    final targetLang = hasChinese ? 'English' : 'Chinese';

    final prompt = 'Translate the following $sourceLang text to $targetLang. '
        'Reply with ONLY the translated text, no explanations, no quotes.\n\n'
        '$text';

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
          'temperature': 0.1,
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
            'AI translate failed: HTTP ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('AI translate error: $e');
    }
    return null;
  }
}
