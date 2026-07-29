import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../common.dart';

/// A single AI provider profile (endpoint + key + model + name + enabled).
class AiProfile {
  final String name;
  final String endpoint;
  final String apiKey;
  final String model;
  final bool enabled;

  /// Built-in profiles (e.g. hermesAPI) don't expose credentials in the UI
  /// and are auto-added on every load — they are not persisted.
  final bool builtIn;

  const AiProfile({
    this.name = '',
    this.endpoint = '',
    this.apiKey = '',
    this.model = 'gpt-4o-mini',
    this.enabled = true,
    this.builtIn = false,
  });

  /// Only non-built-in profiles are serialised to local storage.
  Map<String, dynamic> toJson() => builtIn
      ? {}
      : {
          'name': name,
          'endpoint': endpoint,
          'api_key': apiKey,
          'model': model,
          'enabled': enabled,
        };

  factory AiProfile.fromJson(Map<String, dynamic> json) => AiProfile(
        name: (json['name'] ?? '').toString(),
        endpoint: (json['endpoint'] ?? '').toString(),
        apiKey: (json['api_key'] ?? '').toString(),
        model: (json['model'] ?? 'gpt-4o-mini').toString(),
        enabled: json['enabled'] != false,
      );

  /// Display label shown in the input box selector.
  String get displayLabel =>
      name.isNotEmpty ? name : (model.isNotEmpty ? model : 'AI');
}

/// AI service configuration — multiple profiles.
/// Stored as JSON in local options.
class AiConfig {
  final List<AiProfile> profiles;
  final int activeProfileIndex;
  final String email;

  const AiConfig({
    this.profiles = const [],
    this.activeProfileIndex = 0,
    this.email = '',
  });

  /// Built-in hermesAPI proxy — free for 100 calls.
  /// Endpoint/key are hidden from the UI; only the name is shown.
  static const builtInProfiles = [
    AiProfile(
      builtIn: true,
      name: 'hermesAPI',
      endpoint: 'http://47.114.75.115:40000/v1',
      apiKey:
          'sk-proxy-local-51f5bd4b9797f2620bc55460946802711cf7312b38c24794',
      model: 'hermesAPI',
      enabled: true,
    ),
  ];

  /// The currently active profile, or a default fallback.
  AiProfile get currentProfile =>
      activeProfileIndex >= 0 && activeProfileIndex < profiles.length
          ? profiles[activeProfileIndex]
          : const AiProfile(enabled: false);

  /// Shorthand for consumers that just need 'enabled'.
  bool get enabled => currentProfile.enabled;

  static const _storageKey = 'luoda_ai_config';

  static AiConfig _cached = const AiConfig();

  static AiConfig get current => _cached;

  static AiProfile get currentProfile => _cached.currentProfile;

  /// Migrate old single-profile storage, parse user profiles,
  /// then merge with built-in profiles.
  static void load() {
    try {
      final raw = bind.mainGetLocalOption(key: _storageKey);
      final userProfiles = <AiProfile>[];
      if (raw.isNotEmpty) {
        try {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          final rawProfiles = json['profiles'];
          if (rawProfiles is List) {
            for (final p in rawProfiles) {
              if (p is Map<String, dynamic>) {
                userProfiles.add(AiProfile.fromJson(p));
              }
            }
          }
          // Migration: old single-profile format
          if (userProfiles.isEmpty) {
            final oldEndpoint = (json['endpoint'] ?? '').toString();
            if (oldEndpoint.isNotEmpty) {
              userProfiles.add(AiProfile(
                name: 'Default',
                endpoint: oldEndpoint,
                apiKey: (json['api_key'] ?? '').toString(),
                model: (json['model'] ?? 'gpt-4o-mini').toString(),
                enabled: json['enabled'] == true,
              ));
            }
          }
        } catch (_) {}
      }

      // Built-in profiles come first, then user profiles
      final allProfiles = <AiProfile>[...builtInProfiles, ...userProfiles];
      final savedIdx = (() {
        try {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          return (json['active_profile_index'] as int?) ?? 0;
        } catch (_) {
          return 0;
        }
      })();

      _cached = AiConfig(
        profiles: allProfiles,
        activeProfileIndex:
            savedIdx.clamp(0, allProfiles.length - 1),
        email: (() {
          try {
            final json = jsonDecode(raw) as Map<String, dynamic>;
            return (json['email'] ?? '').toString();
          } catch (_) {
            return '';
          }
        })(),
      );
    } catch (_) {
      // Fallback: built-in only
      _cached = AiConfig(
        profiles: [...builtInProfiles],
        activeProfileIndex: 0,
      );
    }
  }

  /// Persist only user-defined profiles (built-in are auto-added on load).
  static Future<void> save(AiConfig config) async {
    final userProfiles =
        config.profiles.where((p) => !p.builtIn).toList();
    _cached = AiConfig(
      profiles: [...builtInProfiles, ...userProfiles],
      activeProfileIndex: config.activeProfileIndex,
      email: config.email,
    );
    await bind.mainSetLocalOption(
      key: _storageKey,
      value: jsonEncode({
        'profiles': userProfiles.map((p) => p.toJson()).toList(),
        'active_profile_index': _cached.activeProfileIndex,
        'email': config.email,
      }),
    );
  }

  /// Switch to a different profile by index (in the combined list).
  static Future<void> setActiveProfile(int index) async {
    final cfg = _cached;
    if (index < 0 || index >= cfg.profiles.length) return;
    // Persist the index into the saved config — build-in profiles always
    // occupy the first slots so the index is stable across sessions.
    await save(AiConfig(
      profiles: cfg.profiles.where((p) => !p.builtIn).toList(),
      activeProfileIndex: index,
      email: cfg.email,
    ));
  }
}

/// Shared AI API caller — returns raw response content from any prompt.
Future<String?> _callAi(AiProfile profile, String prompt,
    {double temperature = 0.7}) async {
  if (!profile.enabled ||
      profile.endpoint.isEmpty ||
      profile.apiKey.isEmpty) {
    return null;
  }
  try {
    final uri = Uri.parse(profile.endpoint);
    final response = await http
        .post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (profile.apiKey.isNotEmpty)
          'Authorization': 'Bearer ${profile.apiKey}',
      },
      body: jsonEncode({
        'model': profile.model,
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
  /// Translate [text] between Chinese and English using the active profile.
  static Future<String?> translate(String text) async {
    final profile = AiConfig.currentProfile;
    if (!profile.enabled) return null;
    final hasChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
    final sourceLang = hasChinese ? 'Chinese' : 'English';
    final targetLang = hasChinese ? 'English' : 'Chinese';
    final prompt = 'Translate the following $sourceLang text to $targetLang. '
        'Reply with ONLY the translated text, no explanations, no quotes.\n\n'
        '$text';
    return _callAi(profile, prompt, temperature: 0.1);
  }

  /// Chat: generate a reply for a user message (used for "#" prefixed messages).
  static Future<String?> chat(String message) async {
    final profile = AiConfig.currentProfile;
    if (!profile.enabled) return null;
    final prompt = 'You are a helpful assistant. Reply concisely and '
        'naturally in the same language as the user message.\n\n'
        '$message';
    return _callAi(profile, prompt, temperature: 0.7);
  }
}
