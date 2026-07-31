import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../common.dart';
import 'platform_model.dart';

/// AI profile type.
enum AiProfileType { text, image }

/// A single AI provider profile (endpoint + key + model + name + enabled + type).
class AiProfile {
  final String name;
  final String endpoint;
  final String apiKey;
  final String model;
  final bool enabled;

  /// Built-in profiles (e.g. hermesAPI) don't expose credentials in the UI
  /// and are auto-added on every load — they are not persisted.
  final bool builtIn;

  /// Profile type: text (chat/translation) or image (generation).
  final AiProfileType profileType;

  /// Free-tier quota for built-in profiles (e.g. hermesAPI = 100 calls).
  /// 0 means unlimited (used for user-configured profiles).
  final int freeQuota;

  const AiProfile({
    this.name = '',
    this.endpoint = '',
    this.apiKey = '',
    this.model = 'gpt-4o-mini',
    this.enabled = true,
    this.builtIn = false,
    this.profileType = AiProfileType.text,
    this.freeQuota = 0,
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
          'profile_type': profileType.name,
        };

  factory AiProfile.fromJson(Map<String, dynamic> json) => AiProfile(
        name: (json['name'] ?? '').toString(),
        endpoint: (json['endpoint'] ?? '').toString(),
        apiKey: (json['api_key'] ?? '').toString(),
        model: (json['model'] ?? 'gpt-4o-mini').toString(),
        enabled: json['enabled'] != false,
        profileType: (json['profile_type'] as String?) == 'image'
            ? AiProfileType.image
            : AiProfileType.text,
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
  final Map<String, int> usageByProfile;

  const AiConfig({
    this.profiles = const [],
    this.activeProfileIndex = 0,
    this.email = '',
    this.usageByProfile = const {},
  });

  /// Get remaining free calls for a profile. Returns -1 for unlimited (user-configured).
  int remainingFor(AiProfile profile) {
    if (profile.freeQuota <= 0) return -1;
    final used = usageByProfile[profile.name] ?? 0;
    final remaining = profile.freeQuota - used;
    return remaining < 0 ? 0 : remaining;
  }

  /// Increment usage count for a profile name; persists to storage.
  Future<void> incrementUsage(String profileName) async {
    final newMap = Map<String, int>.from(usageByProfile);
    newMap[profileName] = (newMap[profileName] ?? 0) + 1;
    final updated = AiConfig(
      profiles: profiles,
      activeProfileIndex: activeProfileIndex,
      email: email,
      usageByProfile: newMap,
    );
    await save(updated);
  }

  /// Built-in hermesAPI proxy — free for 100 calls (text).
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
      profileType: AiProfileType.text,
      freeQuota: 100,
    ),
    AiProfile(
      builtIn: true,
      name: 'ImageAI',
      endpoint: 'https://apihub.agnes-ai.com/v1',
      apiKey: 'sk-WqlzOkaKLh0QFcfvPfJTnYdPqaj3X6ZJ7wUaVlX3KAiqNcPV',
      model: 'agnes-image-2.1-flash',
      enabled: true,
      profileType: AiProfileType.image,
    ),
  ];

  /// The currently active profile, or a default fallback.
  /// NOTE: This is instance-level but has the SAME name as the static
  /// getter below. dart2js/web rejects duplicate names in the same scope.
  /// Consumers should use AiConfig.currentProfile (static) instead.
  // (Instance getter removed to avoid 'already declared' compile error.)

  /// Shorthand — delegates to the static currentProfile.
  bool get enabled => _cached.profiles.isNotEmpty &&
      _cached.activeProfileIndex < _cached.profiles.length
      ? _cached.profiles[_cached.activeProfileIndex].enabled
      : false;

  /// Find the first enabled profile of the given type.
  AiProfile getProfileByType(AiProfileType type) {
    final match = profiles.cast<AiProfile?>().firstWhere(
          (p) => p!.enabled && p.profileType == type,
          orElse: () => null,
        );
    return match ?? _currentActiveProfile();
  }

  AiProfile _currentActiveProfile() {
    if (activeProfileIndex >= 0 && activeProfileIndex < profiles.length) {
      return profiles[activeProfileIndex];
    }
    return const AiProfile(enabled: false);
  }

  static const _storageKey = 'luoda_ai_config';

  static AiConfig _cached = const AiConfig();

  static AiConfig get current => _cached;

  // ---- Change notification (for UI widgets that need to react) ----
  static void Function()? _onChanged;
  static void set onChange(void Function() callback) => _onChanged = callback;
  static void clearOnChange() => _onChanged = null;
  static void _notifyChanged() => _onChanged?.call();

  static AiProfile get currentProfile {
    final cfg = _cached;
    if (cfg.activeProfileIndex >= 0 && cfg.activeProfileIndex < cfg.profiles.length) {
      return cfg.profiles[cfg.activeProfileIndex];
    }
    return const AiProfile(enabled: false);
  }

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

      final usage = <String, int>{};
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final rawUsage = json['usage'];
        if (rawUsage is Map) {
          rawUsage.forEach((k, v) {
            if (v is int) usage[k.toString()] = v;
          });
        }
      } catch (_) {}

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
        usageByProfile: usage,
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
      usageByProfile: config.usageByProfile,
    );
    await bind.mainSetLocalOption(
      key: _storageKey,
      value: jsonEncode({
        'profiles': userProfiles.map((p) => p.toJson()).toList(),
        'active_profile_index': _cached.activeProfileIndex,
        'email': config.email,
        'usage': config.usageByProfile,
      }),
    );
    _notifyChanged();
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
    _notifyChanged();
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
          // Track usage count for built-in profiles with quotas.
          if (profile.builtIn && profile.freeQuota > 0) {
            unawaited(AiConfig.current.incrementUsage(profile.name));
          }
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
    final prompt = 'You are a helpful assistant integrated into a chat app. '
        'Reply concisely and naturally in the same language as the user message.\n'
        'You MAY use the following formatting syntax in your reply when appropriate:\n'
        '- **bold** for emphasis\n'
        '- *italic* for subtle emphasis\n'
        '- `code` for code snippets or commands\n'
        '- ~~strikethrough~~ \n'
        '- # Heading at start of line for titles\n'
        '- ## Subheading for sections\n'
        '- [color=red]text[/color] for colored text (red, green, blue, orange, purple, gray)\n'
        '- [size=20]text[/size] to change font size\n'
        '- | col1 | col2 |\\n| --- | --- |\\n| val1 | val2 | for tables\n'
        '- > quote for blockquotes\n'
        '- --- for horizontal rules\n\n'
        'Format naturally — only use formatting when it improves readability.\n\n'
        '$message';
    return _callAi(profile, prompt, temperature: 0.7);
  }
}

/// AI image generation service.
/// Calls the image AI profile via OpenAI-compatible /v1/images/generations.
/// Downloads the generated image and saves it to a temp path.
class AiImageService {
  static Future<String?> generate(
    String prompt, {
    String size = '1024x1024',
  }) async {
    final profile = AiConfig.current.getProfileByType(AiProfileType.image);
    if (!profile.enabled ||
        profile.endpoint.isEmpty ||
        profile.apiKey.isEmpty) {
      debugPrint('Image AI not configured');
      return null;
    }

    try {
      // Construct the image generation URL (append /images/generations)
      var base = profile.endpoint;
      if (!base.endsWith('/')) base += '/';
      final uri = Uri.parse('${base}images/generations');

      final response = await http
          .post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${profile.apiKey}',
        },
        body: jsonEncode({
          'model': profile.model,
          'prompt': prompt,
          'n': 1,
          'size': size,
          'response_format': 'b64_json',
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final dataList = body['data'] as List?;
        if (dataList != null && dataList.isNotEmpty) {
          final data = dataList[0] as Map<String, dynamic>;
          final b64 = data['b64_json'] as String?;
          final url = data['url'] as String?;

          Uint8List? bytes;
          if (b64 != null && b64.isNotEmpty) {
            bytes = base64Decode(b64);
          } else if (url != null && url.isNotEmpty) {
            // Download from URL with 15s timeout
            try {
              final imgResp = await http.get(Uri.parse(url))
                  .timeout(const Duration(seconds: 15));
              if (imgResp.statusCode == 200) {
                bytes = imgResp.bodyBytes;
              }
            } catch (_) {
              debugPrint('Image download failed: $url');
            }
          }

          if (bytes != null) {
            // Save to a flat temp file (no extra directory).
            final ts = DateTime.now().millisecondsSinceEpoch;
            final dir = Directory.systemTemp;
            final file = File('${dir.path}/luoda_ai_img_$ts.png');
            await file.writeAsBytes(bytes);
            return file.path;
          }
        }
      } else {
        debugPrint(
            'Image gen failed: HTTP ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('Image gen error: $e');
    }
    return null;
  }
}
