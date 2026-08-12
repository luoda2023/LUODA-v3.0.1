import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:luoda_flutter/common.dart';
import 'package:luoda_flutter/common/direct_chat.dart';
import 'package:luoda_flutter/common/direct_chat_storage.dart';
import 'package:luoda_flutter/common/direct_pairing.dart';
import 'package:luoda_flutter/models/platform_model.dart';

/// DotChat local backup / restore.
///
/// Contacts and chat history live in the app-private directory (Rust
/// LocalConfig + ldesk_direct_chat_v1.json), which Android wipes on
/// uninstall. To survive a reinstall, every write is mirrored to a public
/// folder (/sdcard/DotChat on Android) and, on first launch after a fresh
/// install, an existing backup is restored automatically.
class DotChatBackup {
  DotChatBackup._();

  static const _fileName = 'dotchat-backup.json';
  static const _backupRoot = 'DotChat';
  static Timer? _debounce;

  static const List<String> _policyKeys = <String>[
    'direct-chat-contact-policies',
    'direct-chat-accepted-peers-v1',
    'direct-chat-trusted-only',
    'direct-chat-always-on',
    'direct-chat-auto-reconnect',
    'pinned_conversations',
    'marked_unread',
  ];

  static Future<Directory?> _backupDir() async {
    if (isAndroid) {
      // Public storage survives uninstall. Requires MANAGE_EXTERNAL_STORAGE,
      // which is part of the one-time permission wizard.
      final dir = Directory('/storage/emulated/0/$_backupRoot');
      try {
        await dir.create(recursive: true);
        final probe = File('${dir.path}/.probe');
        await probe.writeAsString('ok');
        await probe.delete();
        return dir;
      } catch (_) {
        return null;
      }
    }
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/$_backupRoot');
      await dir.create(recursive: true);
      return dir;
    } catch (_) {
      return null;
    }
  }

  static Future<File?> _backupFile() async {
    final dir = await _backupDir();
    if (dir == null) return null;
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  /// Debounced auto-backup: call after contacts / messages / policies change.
  static void schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      unawaited(exportNow());
    });
  }

  static String _localOption(String key) {
    try {
      return bind.mainGetLocalOption(key: key);
    } catch (_) {
      return '';
    }
  }

  static Future<void> _setLocalOption(String key, String value) async {
    try {
      await bind.mainSetLocalOption(key: key, value: value);
    } catch (_) {}
  }

  static Future<void> exportNow() async {
    try {
      final file = await _backupFile();
      if (file == null) return;
      final storage = DirectChatStorage();
      final rawChat = await storage.read();
      final bundle = <String, dynamic>{
        'schema': 1,
        'app': 'DotChat',
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'contacts': DirectPairingStore.exportContacts(),
        'chat': rawChat == null || rawChat.isEmpty
            ? null
            : jsonDecode(rawChat),
        'bound_phone': DirectPairingStore.boundPhone(),
        'options': <String, String>{
          for (final key in _policyKeys)
            if (_localOption(key).isNotEmpty) key: _localOption(key),
        },
      };
      await file.writeAsString(jsonEncode(bundle), flush: true);
    } catch (_) {}
  }

  /// Restore a backup after a reinstall. Only fills empty local stores so a
  /// live device never gets overwritten by stale data.
  static Future<bool> tryRestore() async {
    try {
      final file = await _backupFile();
      if (file == null || !await file.exists()) return false;
      final parsed = jsonDecode(await file.readAsString());
      if (parsed is! Map<String, dynamic>) return false;
      var restored = false;

      final contacts = parsed['contacts'];
      if (contacts is List &&
          contacts.isNotEmpty &&
          DirectPairingStore.load().isEmpty) {
        await DirectPairingStore.mergeContacts(contacts);
        restored = true;
      }

      final chat = parsed['chat'];
      if (chat is Map<String, dynamic>) {
        final storage = DirectChatStorage();
        final current = await storage.read();
        if (current == null || current.trim().isEmpty) {
          await storage.write(jsonEncode(chat));
          restored = true;
        }
      }

      final options = parsed['options'];
      if (options is Map<String, dynamic>) {
        for (final entry in options.entries) {
          final value = entry.value.toString();
          if (value.isNotEmpty && _localOption(entry.key).isEmpty) {
            await _setLocalOption(entry.key, value);
            restored = true;
          }
        }
      }
      return restored;
    } catch (_) {
      return false;
    }
  }
}
