import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class DirectChatStorage {
  static const _fileName = 'ldesk31_direct_chat_v1.json';
  static const _maxLockAttempts = 12;

  Future<File> _file() async {
    final directory = await _supportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }

  /// On Windows the app commonly runs split across accounts: the server and
  /// connection-manager processes run as the LocalSystem service, while the
  /// main window runs in the interactive user session. `getApplicationSupportDirectory()`
  /// resolves to different profile folders per account, so incoming chat
  /// written by the CM landed in the SYSTEM profile store while the main
  /// window kept reading the user profile store (messages appeared to be
  /// "never received"). Use one shared store under %PROGRAMDATA% for every
  /// account and migrate the per-profile legacy stores into it.
  Future<Directory> _supportDirectory() async {
    if (!Platform.isWindows) {
      return getApplicationSupportDirectory();
    }
    final programData = Platform.environment['PROGRAMDATA'];
    final base = (programData == null || programData.trim().isEmpty)
        ? r'C:\ProgramData'
        : programData.trim();
final shared = Directory('$base${Platform.pathSeparator}LUODA31'
 '${Platform.pathSeparator}chat');
    await shared.create(recursive: true);
    final sharedFile =
        File('${shared.path}${Platform.pathSeparator}$_fileName');
    await _migrateLegacyStores(sharedFile);
    return shared;
  }

  /// Merge chat history written by older builds into the shared store so no
  /// account loses its records. Safe to run from every process: it only adds
  /// records whose id is not already present, under an exclusive lock.
  Future<void> _migrateLegacyStores(File sharedFile) async {
    final candidates = <String>{};
    try {
      candidates.add(
          '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}$_fileName');
    } catch (_) {}
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    candidates.add('$systemRoot\\System32\\config\\systemprofile'
        '\\AppData\\Roaming\\LUODA31\\LUODA31\\$_fileName');

    final lockFile = File('${sharedFile.path}.lock');
    Object? lastError;
    for (var attempt = 0; attempt < _maxLockAttempts; attempt++) {
      RandomAccessFile? lock;
      try {
        lock = await lockFile.open(mode: FileMode.append);
        await lock.lock(FileLock.exclusive);
        final shared = <String, dynamic>{
          'schema': 1,
          'next_sequence': 0,
          'records': <Map<String, dynamic>>[],
        };
        if (await sharedFile.exists()) {
          try {
            final parsed = jsonDecode(await sharedFile.readAsString());
            if (parsed is Map<String, dynamic>) {
              shared..clear()..addAll(parsed);
            }
          } catch (_) {}
        }
        final records = <String, Map<String, dynamic>>{
          for (final record
              in ((shared['records'] as List<dynamic>?) ?? const <dynamic>[]))
            if (record is Map<String, dynamic> &&
                record['id'] != null &&
                record['id'].toString().isNotEmpty)
              record['id'].toString(): record,
        };
        var changed = false;
        for (final path in candidates) {
          try {
            final legacy = File(path);
            if (!await legacy.exists()) continue;
            final parsed = jsonDecode(await legacy.readAsString());
            if (parsed is! Map<String, dynamic>) continue;
            for (final record
                in ((parsed['records'] as List<dynamic>?) ?? const <dynamic>[])) {
              if (record is! Map<String, dynamic> ||
                  record['id'] == null ||
                  record['id'].toString().isEmpty) {
                continue;
              }
              final id = record['id'].toString();
              if (!records.containsKey(id)) {
                records[id] = record;
                changed = true;
              }
            }
          } catch (_) {}
        }
        if (changed) {
          shared['records'] = records.values.toList();
          await sharedFile.writeAsString(jsonEncode(shared), flush: true);
        }
        await lock.unlock();
        await lock.close();
        return;
      } catch (error) {
        lastError = error;
        try {
          await lock?.unlock();
        } catch (_) {}
        try {
          await lock?.close();
        } catch (_) {}
        if (attempt == _maxLockAttempts - 1) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 30 * (attempt + 1)));
      }
    }
    throw lastError ?? StateError('Unable to migrate direct chat storage');
  }

  /// Last modification time of the persisted chat history file, or null when
  /// the file does not exist yet. Used by the UI to detect records written by
  /// another process (e.g. the connection-manager window) without re-reading
  /// the whole JSON payload.
  Future<DateTime?> modifiedTime() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return (await file.stat()).modified;
  }

  Future<String?> read() async {
    final file = await _file();
    final lockFile = File('${file.path}.lock');
    Object? lastError;
    for (var attempt = 0; attempt < _maxLockAttempts; attempt++) {
      RandomAccessFile? lock;
      try {
        lock = await lockFile.open(mode: FileMode.append);
        await lock.lock(FileLock.shared);
        final value = await file.exists() ? await file.readAsString() : null;
        await lock.unlock();
        await lock.close();
        return value;
      } catch (error) {
        lastError = error;
        try {
          await lock?.unlock();
        } catch (_) {}
        try {
          await lock?.close();
        } catch (_) {}
        if (attempt == _maxLockAttempts - 1) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 30 * (attempt + 1)));
      }
    }
    throw lastError ?? StateError('Unable to read direct chat storage');
  }

Future<void> write(String value) async {
final file = await _file();
await file.writeAsString(value, flush: true);
}

/// Rename the JSON store to `.bak` so the SQLite migration layer
/// doesn't re-import it on every launch. Safe to call when the file
/// doesn't exist.
Future<void> renameToBackup() async {
final file = await _file();
if (await file.exists()) {
final backup = File('${file.path}.bak');
try {
await backup.delete(); // remove a previous backup if present
} catch (_) {}
await file.rename(backup.path);
}
}

Future<String> update(
    Future<String> Function(String? current) transform,
  ) async {
    final file = await _file();
    final lockFile = File('${file.path}.lock');
    Object? lastError;
    for (var attempt = 0; attempt < _maxLockAttempts; attempt++) {
      RandomAccessFile? lock;
      try {
        lock = await lockFile.open(mode: FileMode.append);
        await lock.lock(FileLock.exclusive);
        final current = await file.exists() ? await file.readAsString() : null;
        final next = await transform(current);
        // Skip the disk write when the transformed payload is byte-identical.
        // This keeps periodic "merge/refresh" passes from churning the store
        // file mtime, which otherwise makes the UI change-detector fire on
        // every poll and rebuild the whole chat page in a loop.
        if (next != current) {
          await file.writeAsString(next, flush: true);
        }
        await lock.unlock();
        await lock.close();
        return next;
      } catch (error) {
        lastError = error;
        try {
          await lock?.unlock();
        } catch (_) {}
        try {
          await lock?.close();
        } catch (_) {}
        if (attempt == _maxLockAttempts - 1) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 30 * (attempt + 1)));
      }
    }
    throw lastError ?? StateError('Unable to update direct chat storage');
  }
}
