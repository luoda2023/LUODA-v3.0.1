/// SQLite-backed storage for direct chat messages.
///
/// Replaces the previous single-JSON-file approach (`DirectChatStorage`)
/// with a proper SQLite database, mirroring how WeChat's WCDB works:
/// a native SQLite C library accessed via FFI (`sqflite_common_ffi`).
///
/// Benefits over the JSON store:
/// - WAL mode gives safe cross-process concurrency (no FileLock retries)
/// - Indexed queries replace full-file scans (pagination, cursor, latest)
/// - No mtime-polling / signature comparison for external-change detection
/// - Atomic per-record writes instead of rewriting the entire JSON blob
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'direct_chat.dart';
import 'direct_chat_storage.dart' show DirectChatStorage;
import 'direct_pairing.dart';
import 'string_utils.dart';
import '../models/platform_model.dart';

/// Schema version — bumped when the table structure changes.
/// v1: initial messages table
/// v2: +meetings, meeting_members, pairings, contact_policies tables
///     +location_lat/location_lng/location_name columns on messages
const int _kDbVersion = 2;

const String _kDbFileName = 'ldesk_chat.db';

/// SQL to create the [messages] table.
const String _kCreateMessagesTable = '''
CREATE TABLE IF NOT EXISTS messages (
  id               TEXT PRIMARY KEY,
  conversation_id  TEXT NOT NULL,
  origin_device_id TEXT NOT NULL,
  origin_sequence  INTEGER NOT NULL,
  direction        TEXT NOT NULL,
  kind             TEXT NOT NULL,
  text             TEXT NOT NULL,
  sender_id        TEXT NOT NULL,
  sender_name      TEXT NOT NULL DEFAULT '',
  sender_avatar    TEXT NOT NULL DEFAULT '',
  sent_at          TEXT NOT NULL,
  delivery         TEXT NOT NULL,
  disposition      TEXT NOT NULL DEFAULT 'active',
  file_name        TEXT NOT NULL DEFAULT '',
  file_size        INTEGER NOT NULL DEFAULT 0,
  file_sha256      TEXT NOT NULL DEFAULT '',
  local_path       TEXT NOT NULL DEFAULT '',
  voice_duration_ms INTEGER NOT NULL DEFAULT 0,
  expires_at       TEXT,
  reply_to_id      TEXT NOT NULL DEFAULT '',
  reply_to_sender  TEXT NOT NULL DEFAULT '',
  reply_to_text    TEXT NOT NULL DEFAULT '',
  reactions        TEXT NOT NULL DEFAULT '{}',
  is_edited        INTEGER NOT NULL DEFAULT 0,
  edited_at        TEXT,
  forward_title    TEXT NOT NULL DEFAULT '',
  forward_items    TEXT NOT NULL DEFAULT '[]',
  conn_mode        TEXT NOT NULL DEFAULT '',
  conn_endpoint    TEXT NOT NULL DEFAULT '',
  conn_port        INTEGER NOT NULL DEFAULT 0,
  src_platform TEXT NOT NULL DEFAULT '',
  location_lat REAL,
  location_lng REAL,
  location_name TEXT NOT NULL DEFAULT '',
  image_width INTEGER NOT NULL DEFAULT 0,
  image_height INTEGER NOT NULL DEFAULT 0
)''';

const String _kCreateConvIndex =
    'CREATE INDEX IF NOT EXISTS idx_msg_conv ON messages(conversation_id, sent_at DESC)';

const String _kCreateDeliveryIndex =
    'CREATE INDEX IF NOT EXISTS idx_msg_delivery ON messages(conversation_id, delivery)';

const String _kCreateMetaTable =
    'CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)';

const String _kCreateDeviceIndex =
 'CREATE INDEX IF NOT EXISTS idx_msg_device ON messages(origin_device_id, origin_sequence)';

// ── Meeting tables (v2) ───────────────────────────────────

const String _kCreateMeetingsTable = '''
CREATE TABLE IF NOT EXISTS meetings (
 meeting_id TEXT PRIMARY KEY,
 title TEXT NOT NULL DEFAULT '',
 host_peer_id TEXT NOT NULL,
 host_display_name TEXT NOT NULL DEFAULT '',
 created_at TEXT NOT NULL,
 active_session_endpoint TEXT NOT NULL DEFAULT '',
 invite_short_code TEXT NOT NULL DEFAULT '',
 presenter_peer_id TEXT NOT NULL DEFAULT '',
 presenter_display_name TEXT NOT NULL DEFAULT '',
 viewer_token TEXT NOT NULL DEFAULT '',
 start_time TEXT,
 duration_minutes INTEGER NOT NULL DEFAULT 60
)''';

const String _kCreateMeetingMembersTable = '''
CREATE TABLE IF NOT EXISTS meeting_members (
 meeting_id TEXT NOT NULL,
 peer_id TEXT NOT NULL,
 display_name TEXT NOT NULL DEFAULT '',
 joined_at TEXT NOT NULL,
 PRIMARY KEY (meeting_id, peer_id),
 FOREIGN KEY (meeting_id) REFERENCES meetings(meeting_id) ON DELETE CASCADE
)''';

const String _kCreateMeetingIndex =
 'CREATE INDEX IF NOT EXISTS idx_meetings_host ON meetings(host_peer_id)';
const String _kCreateMeetingMemberIndex =
 'CREATE INDEX IF NOT EXISTS idx_mm_peer ON meeting_members(peer_id)';

// ── Pairings table (v2) ───────────────────────────────────

const String _kCreatePairingsTable = '''
CREATE TABLE IF NOT EXISTS pairings (
 peer_id TEXT PRIMARY KEY,
 display_name TEXT NOT NULL DEFAULT '',
 lan_endpoint TEXT NOT NULL DEFAULT '',
 public_endpoint TEXT NOT NULL DEFAULT '',
 fingerprint TEXT NOT NULL DEFAULT '',
 updated_at TEXT NOT NULL,
 account_id TEXT NOT NULL DEFAULT '',
 avatar TEXT NOT NULL DEFAULT '',
 conversation_id TEXT NOT NULL DEFAULT '',
 conn_mode TEXT NOT NULL DEFAULT '',
 conn_port INTEGER NOT NULL DEFAULT 0,
 is_bound_phone INTEGER NOT NULL DEFAULT 0
)''';

// ── Contact policies table (v2) ──────────────────────────

const String _kCreateContactPoliciesTable = '''
CREATE TABLE IF NOT EXISTS contact_policies (
 peer_id TEXT PRIMARY KEY,
 policy TEXT NOT NULL DEFAULT 'stranger',
 alias TEXT NOT NULL DEFAULT '',
 category TEXT NOT NULL DEFAULT '',
 accepted INTEGER NOT NULL DEFAULT 0
)''';

// ── v2 ALTER TABLE for messages (location columns) ────────

const String _kAlterMessagesAddLocationLat =
 'ALTER TABLE messages ADD COLUMN location_lat REAL';
const String _kAlterMessagesAddLocationLng =
 'ALTER TABLE messages ADD COLUMN location_lng REAL';
const String _kAlterMessagesAddLocationName =
 'ALTER TABLE messages ADD COLUMN location_name TEXT NOT NULL DEFAULT \'\'';
const String _kAlterMessagesAddImageWidth =
 'ALTER TABLE messages ADD COLUMN image_width INTEGER NOT NULL DEFAULT 0';
const String _kAlterMessagesAddImageHeight =
 'ALTER TABLE messages ADD COLUMN image_height INTEGER NOT NULL DEFAULT 0';

/// Drop-in replacement for [DirectChatStorage] backed by SQLite.
///
/// Exposes the same high-level operations that [DirectChatRepository] calls,
/// but uses SQL instead of JSON encode/decode + FileLock.
class DirectChatSqlite {
  DirectChatSqlite._();
  static final DirectChatSqlite instance = DirectChatSqlite._();

 Database? _db;
 String? _dbPath;

 /// Test hook: overrides the database directory so tests use an isolated
 /// temp path instead of the shared ProgramData location.
 @visibleForTesting
 static String? debugDbDirOverride;

 /// Test hook: closes the database and resets cached state so the next
 /// [_database()] call re-opens with a fresh path.
 @visibleForTesting
 Future<void> resetForTest() async {
 await _db?.close();
 _db = null;
 _dbPath = null;
 _lastSeenRowCount = -1;
 _lastSeenMaxSentAt = '';
 }

 /// Cached fingerprint of the last-seen database state, used by
  /// [hasExternalChanges] to detect cross-process writes without reading
  /// every row. This replaces the old JSON-store mtime+signature poll.
 int _lastSeenRowCount = -1;
 String _lastSeenMaxSentAt = '';

 /// Execute an ALTER TABLE ADD COLUMN, ignoring "duplicate column" errors
 /// so the migration is idempotent when run from both onCreate (fresh
 /// install) and onUpgrade (existing DB).
 static Future<void> _safeAlter(Database db, String sql) async {
 try {
 await db.execute(sql);
 } on DatabaseException catch (e) {
 if (!e.isDuplicateColumnError()) rethrow;
 }
 }


  /// The shared database directory. On Windows this is under
  /// `%PROGRAMDATA%\LUODA\chat` so both the LocalSystem service and the
  /// interactive user session read/write the same file (same rationale as
  /// the old JSON store).
Future<Directory> _dbDirectory() async {
if (debugDbDirOverride != null) {
final d = Directory(debugDbDirOverride!);
await d.create(recursive: true);
return d;
}
if (!Platform.isWindows) {
return getApplicationSupportDirectory();
}
    final programData = Platform.environment['PROGRAMDATA'];
    final base = (programData == null || programData.trim().isEmpty)
        ? r'C:\ProgramData'
        : programData.trim();
    final shared =
        Directory('$base${Platform.pathSeparator}LUODA${Platform.pathSeparator}chat');
    await shared.create(recursive: true);
    return shared;
  }

  Future<String> _resolveDbPath() async {
    if (_dbPath != null) return _dbPath!;
    final dir = await _dbDirectory();
    _dbPath = p.join(dir.path, _kDbFileName);
    return _dbPath!;
  }

  /// Lazily opens the database, running migrations and JSON import on the
  /// first call. Safe to call from any process — SQLite WAL handles
  /// concurrent access.
  Future<Database> _database() async {
    if (_db != null) return _db!;
    final path = await _resolveDbPath();
    _db = await openDatabase(
      path,
      version: _kDbVersion,
      onConfigure: (db) async {
        // WAL = concurrent readers + one writer, no separate lock file.
        await db.execute('PRAGMA journal_mode = WAL;');
        await db.execute('PRAGMA foreign_keys = ON;');
        // Normal sync is fine for a chat store; WAL avoids the fsync storm.
        await db.execute('PRAGMA synchronous = NORMAL;');
      },
 onCreate: (db, _) async {
 await db.execute(_kCreateMessagesTable);
 await db.execute(_kCreateConvIndex);
 await db.execute(_kCreateDeliveryIndex);
 await db.execute(_kCreateDeviceIndex);
 await db.execute(_kCreateMetaTable);
 // v2 tables created fresh on new installs.
 await db.execute(_kCreateMeetingsTable);
 await db.execute(_kCreateMeetingMembersTable);
 await db.execute(_kCreateMeetingIndex);
 await db.execute(_kCreateMeetingMemberIndex);
 await db.execute(_kCreatePairingsTable);
 await db.execute(_kCreateContactPoliciesTable);
 // v2 columns on messages (included in the fresh CREATE TABLE for
 // new installs — see _kCreateMessagesTable which is already v2-aware).
 await _safeAlter(db, _kAlterMessagesAddLocationLat);
 await _safeAlter(db, _kAlterMessagesAddLocationLng);
 await _safeAlter(db, _kAlterMessagesAddLocationName);
 await _safeAlter(db, _kAlterMessagesAddImageWidth);
 await _safeAlter(db, _kAlterMessagesAddImageHeight);
 },
 onUpgrade: (db, oldVersion, newVersion) async {
 if (oldVersion < 2) {
 // v2: add meeting/pairing/policy tables + location columns.
 await db.execute(_kCreateMeetingsTable);
 await db.execute(_kCreateMeetingMembersTable);
 await db.execute(_kCreateMeetingIndex);
 await db.execute(_kCreateMeetingMemberIndex);
 await db.execute(_kCreatePairingsTable);
 await db.execute(_kCreateContactPoliciesTable);
 await _safeAlter(db, _kAlterMessagesAddLocationLat);
 await _safeAlter(db, _kAlterMessagesAddLocationLng);
 await _safeAlter(db, _kAlterMessagesAddLocationName);
 await _safeAlter(db, _kAlterMessagesAddImageWidth);
 await _safeAlter(db, _kAlterMessagesAddImageHeight);
 }
 },
    );
 // One-time migration from the old JSON store (idempotent via INSERT OR IGNORE).
 await _migrateFromJsonStore();
 // Migrate KV stores (meetings, pairings) to SQLite tables.
 await _migrateMeetingsFromKV();
 await _migratePairingsFromKV();
 return _db!;
 }

  // ── Meta helpers ──────────────────────────────────────────

Future<String> _getMeta(String key, {String fallback = ''}) async {
  final db = await _database();
  final rows = await db.query('meta',
      where: 'key = ?', whereArgs: [key], limit: 1);
  if (rows.isEmpty) return fallback;
  return (rows.first['value'] ?? '').toString();
}

/// Detects writes by another process (e.g. the connection-manager window)
/// using a lightweight 2-column aggregate query — COUNT(*) + MAX(sent_at).
///
/// This replaces the old JSON-store mtime+signature poll. On the first call
/// it records the current state and returns false; on subsequent calls it
/// returns true if either value changed (a row was inserted/updated by
/// another process).
Future<bool> hasExternalChanges() async {
  final db = await _database();
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS cnt, MAX(sent_at) AS latest FROM messages');
  final count = (rows.isEmpty ? 0 : (rows.first['cnt'] as int? ?? 0));
  final latest = (rows.isEmpty ? '' : (rows.first['latest'] ?? '')).toString();
  if (_lastSeenRowCount < 0) {
    _lastSeenRowCount = count;
    _lastSeenMaxSentAt = latest;
    return false;
  }
  final changed = count != _lastSeenRowCount || latest != _lastSeenMaxSentAt;
  _lastSeenRowCount = count;
  _lastSeenMaxSentAt = latest;
  return changed;
}


  Future<void> _setMeta(String key, String value) async {
    final db = await _database();
    await db.insert(
      'meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String> get deviceId async {
    var id = await _getMeta('device_id');
    if (id.isEmpty) {
      id = const Uuid().v4();
      await _setMeta('device_id', id);
    }
    return id;
  }

  Future<int> get nextSequence async {
    final raw = await _getMeta('next_sequence', fallback: '1');
    return int.tryParse(raw) ?? 1;
  }

  Future<int> _bumpSequence() async {
    final current = await nextSequence;
    await _setMeta('next_sequence', (current + 1).toString());
    return current;
  }

  // ── CRUD ──────────────────────────────────────────────────

  /// Insert an outgoing record. Returns the persisted record.
  Future<DirectChatRecord> createOutgoing({
    String? id,
    required String conversationId,
    required DirectChatKind kind,
    required String text,
    required String senderId,
    required String senderName,
    required String senderAvatar,
    String fileName = '',
    int fileSize = 0,
    String fileSha256 = '',
    String localPath = '',
    String inlineBytes = '',
    int voiceDurationMs = 0,
    String replyToId = '',
    String replyToSender = '',
    String replyToText = '',
    String forwardTitle = '',
    List<DirectChatForwardItem> forwardItems = const <DirectChatForwardItem>[],
    String connectionTarget = '',
    bool recordSource = true,
  }) async {
    final db = await _database();
    final recordId = id ?? const Uuid().v4();
    final sourceTarget = connectionTarget.trim().isNotEmpty
        ? connectionTarget.trim()
        : conversationId;
    final sourceMode =
        recordSource ? DirectPairingStore.classifyConnMode(sourceTarget) : '';
    final seq = await _bumpSequence();
    final now = DateTime.now().toUtc();
    final record = DirectChatRecord(
      id: recordId,
      conversationId: sanitizeInvalidUtf16(conversationId),
      originDeviceId: await deviceId,
      originSequence: seq,
      direction: DirectChatDirection.outgoing,
      kind: kind,
      text: sanitizeInvalidUtf16(text),
      senderId: sanitizeInvalidUtf16(senderId),
      senderName: sanitizeInvalidUtf16(senderName),
      senderAvatar: sanitizeInvalidUtf16(senderAvatar),
      sentAt: now,
      delivery: DirectChatDelivery.queued,
      fileName: sanitizeInvalidUtf16(fileName),
      fileSize: fileSize,
      fileSha256: sanitizeInvalidUtf16(fileSha256),
      localPath: sanitizeInvalidUtf16(localPath),
      inlineBytes: inlineBytes,
      voiceDurationMs: voiceDurationMs,
      replyToId: sanitizeInvalidUtf16(replyToId),
      replyToSender: sanitizeInvalidUtf16(replyToSender),
      replyToText: sanitizeInvalidUtf16(replyToText),
      forwardTitle: sanitizeInvalidUtf16(forwardTitle),
      forwardItems: forwardItems,
      connMode: sourceMode,
      connEndpoint:
          recordSource ? DirectPairingStore.connEndpointOf(sourceTarget) : '',
      connPort: recordSource ? DirectPairingStore.connPortOf(sourceTarget) : 0,
      srcPlatform: recordSource ? directChatPlatformLabel : '',
    );
    await db.insert('messages', _recordToRow(record),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return record;
  }

  /// Insert or update a record (incoming replica, upsert semantics).
  Future<bool> upsert(DirectChatRecord record) async {
    if (record.id.isEmpty || record.conversationId.isEmpty) return false;
    final db = await _database();
    final existing = await db.query('messages',
        where: 'id = ?', whereArgs: [record.id], limit: 1);
    if (existing.isEmpty) {
      await db.insert('messages', _recordToRow(record),
          conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    }
    final prev = _rowToRecord(existing.first);
    final newerMutation = record.originDeviceId == prev.originDeviceId &&
        record.originSequence > prev.originSequence;
    if (newerMutation) {
      await db.update('messages', _recordToRow(record),
          where: 'id = ?', whereArgs: [record.id]);
      return true;
    }
    if (_deliveryRank(record.delivery) > _deliveryRank(prev.delivery)) {
      await db.update(
          'messages',
          {'delivery': record.delivery.name},
          where: 'id = ?',
          whereArgs: [record.id]);
      return true;
    }
    return false;
  }

  Future<DirectChatRecord?> createIncomingLegacy({
    required String conversationId,
    required String text,
    required String senderId,
    required String senderName,
    required String senderAvatar,
  }) async {
    final db = await _database();
    final normalizedConv = sanitizeInvalidUtf16(conversationId);
    final normalizedText = sanitizeInvalidUtf16(text);
    final normalizedSender = sanitizeInvalidUtf16(senderId);
    final now = DateTime.now().toUtc();
    // De-dup: the session delivers the same legacy message twice.
    final dupes = await db.query('messages',
        where:
            'conversation_id = ? AND direction = ? AND text = ? AND sender_id = ? AND sent_at > ?',
        whereArgs: [
          normalizedConv,
          'incoming',
          normalizedText,
          normalizedSender,
          now.subtract(const Duration(seconds: 10)).toIso8601String(),
        ],
        limit: 1);
    if (dupes.isNotEmpty) return _rowToRecord(dupes.first);
    final seq = await _bumpSequence();
    final record = DirectChatRecord(
      id: const Uuid().v4(),
      conversationId: normalizedConv,
      originDeviceId: 'legacy:$normalizedConv',
      originSequence: seq,
      direction: DirectChatDirection.incoming,
      kind: DirectChatKind.text,
      text: normalizedText,
      senderId: normalizedSender,
      senderName: sanitizeInvalidUtf16(senderName),
      senderAvatar: sanitizeInvalidUtf16(senderAvatar),
      sentAt: now,
      delivery: DirectChatDelivery.delivered,
      connMode: DirectPairingStore.classifyConnMode(conversationId),
      connEndpoint: DirectPairingStore.connEndpointOf(conversationId),
      connPort: DirectPairingStore.connPortOf(conversationId),
    );
    await db.insert('messages', _recordToRow(record),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return record;
  }

  Future<void> markDelivery(String id, DirectChatDelivery delivery) async {
    final db = await _database();
    await db.update('messages', {'delivery': delivery.name},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markUndeliveredFailed(String conversationId) async {
    final db = await _database();
    await db.update(
      'messages',
      {'delivery': DirectChatDelivery.failed.name},
      where:
          'conversation_id = ? AND direction = ? AND delivery != ?',
      whereArgs: [
        conversationId,
        'outgoing',
        DirectChatDelivery.delivered.name,
      ],
    );
  }

  Future<void> markUndeliveredQueued(String conversationId) async {
    final db = await _database();
    await db.update(
      'messages',
      {'delivery': DirectChatDelivery.queued.name},
      where:
          'conversation_id = ? AND direction = ? AND delivery != ?',
      whereArgs: [
        conversationId,
        'outgoing',
        DirectChatDelivery.delivered.name,
      ],
    );
  }

  Future<DirectChatRecord?> mutateOutgoing(
    String conversationId,
    String id,
    DirectChatDisposition disposition,
  ) async {
    final db = await _database();
    final rows = await db.query('messages',
        where: 'id = ? AND conversation_id = ? AND direction = ?',
        whereArgs: [id, conversationId, 'outgoing'],
        limit: 1);
    if (rows.isEmpty) return null;
    final record = _rowToRecord(rows.first);
    if (record.disposition == DirectChatDisposition.destroyed ||
        (record.disposition == DirectChatDisposition.recalled &&
            disposition == DirectChatDisposition.recalled)) {
      return null;
    }
    final seq = await _bumpSequence();
    final updated = record.copyWith(
      originSequence: seq,
      delivery: DirectChatDelivery.queued,
      disposition: disposition,
    );
    await db.update('messages', _recordToRow(updated),
        where: 'id = ?', whereArgs: [id]);
    return updated;
  }

  Future<DirectChatRecord?> setSelfDestruct(
    String conversationId,
    String id,
    Duration duration,
  ) async {
    final db = await _database();
    final rows = await db.query('messages',
        where:
            'id = ? AND conversation_id = ? AND direction = ? AND disposition = ?',
        whereArgs: [id, conversationId, 'outgoing', 'active'],
        limit: 1);
    if (rows.isEmpty) return null;
    final record = _rowToRecord(rows.first);
    if (duration <= Duration.zero) return null;
    final seq = await _bumpSequence();
    final updated = record.copyWith(
      originSequence: seq,
      delivery: DirectChatDelivery.queued,
      expiresAt: DateTime.now().toUtc().add(duration),
    );
    await db.update('messages', _recordToRow(updated),
        where: 'id = ?', whereArgs: [id]);
    return updated;
  }

  Future<DirectChatRecord?> toggleReaction(
    String id,
    String emoji,
    String deviceId,
  ) async {
    final db = await _database();
    final rows = await db.query('messages',
        where: 'id = ? AND disposition = ?', whereArgs: [id, 'active'],
        limit: 1);
    if (rows.isEmpty) return null;
    final record = _rowToRecord(rows.first);
    final reactions = Map<String, List<String>>.from(record.reactions);
    final users = List<String>.from(reactions[emoji] ?? []);
    if (users.contains(deviceId)) {
      users.remove(deviceId);
      if (users.isEmpty) {
        reactions.remove(emoji);
      } else {
        reactions[emoji] = users;
      }
    } else {
      users.add(deviceId);
      reactions[emoji] = users;
    }
    final updated = record.copyWith(reactions: reactions);
    await db.update('messages', {'reactions': jsonEncode(reactions)},
        where: 'id = ?', whereArgs: [id]);
    return updated;
  }

  Future<DirectChatRecord?> editText(String id, String newText) async {
    final db = await _database();
    final rows = await db.query('messages',
        where: 'id = ? AND direction = ? AND disposition = ?',
        whereArgs: [id, 'outgoing', 'active'],
        limit: 1);
    if (rows.isEmpty) return null;
    final record = _rowToRecord(rows.first);
    final seq = await _bumpSequence();
    final updated = record.copyWith(
      text: sanitizeInvalidUtf16(newText),
      isEdited: true,
      editedAt: DateTime.now().toUtc(),
      originSequence: seq,
    );
    await db.update('messages', _recordToRow(updated),
        where: 'id = ?', whereArgs: [id]);
    return updated;
  }

  Future<void> remapConversation(String from, String to) async {
    if (from.isEmpty || to.isEmpty || from == to) return;
    final db = await _database();
    await db.update('messages', {'conversation_id': to},
        where: 'conversation_id = ?', whereArgs: [from]);
  }

  Future<void> deleteRecord(String id, String conversationId) async {
    final db = await _database();
    await db.delete('messages',
        where: 'id = ? AND conversation_id = ?',
        whereArgs: [id, conversationId]);
  }

  Future<void> deleteConversations(Iterable<String> conversationIds) async {
    if (conversationIds.isEmpty) return;
    final db = await _database();
    final placeholders = List.filled(conversationIds.length, '?').join(',');
    await db.delete('messages',
        where: 'conversation_id IN ($placeholders)',
        whereArgs: conversationIds.toList());
  }

  // ── Queries ───────────────────────────────────────────────

  Future<DirectChatRecord?> find(String id) async {
    final db = await _database();
    final rows = await db.query('messages',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _rowToRecord(rows.first);
  }

  Future<List<DirectChatRecord>> forConversation(
    String conversationId, {
    int? limit,
  }) async {
    final db = await _database();
    final rows = await db.query('messages',
        where: 'conversation_id = ? AND disposition != ?',
        whereArgs: [conversationId, 'destroyed'],
        orderBy: 'sent_at DESC',
        limit: limit);
    // Filter expired in Dart (cheap, avoids dynamic SQL).
    return rows.map(_rowToRecord).where((r) => !r.isExpired).toList();
  }

  Future<List<DirectChatRecord>> mediaForConversation(
    String conversationId,
  ) async {
    final db = await _database();
    final rows = await db.query('messages',
        where:
            'conversation_id = ? AND kind = ? AND disposition = ?',
        whereArgs: [conversationId, 'file', 'active'],
        orderBy: 'sent_at DESC');
    return rows.map(_rowToRecord).where((r) => !r.isExpired).toList();
  }

  Future<List<String>> conversationIds() async {
    final db = await _database();
    // Only conversations that have at least one non-destroyed,
    // non-expired message.
    final rows = await db.rawQuery('''
      SELECT conversation_id, MAX(sent_at) AS latest
      FROM messages
      WHERE disposition != 'destroyed'
      GROUP BY conversation_id
      ORDER BY latest DESC
    ''');
    // Filter out conversations whose only messages are expired.
    final result = <String>[];
    for (final row in rows) {
      final convId = (row['conversation_id'] ?? '').toString();
      if (convId.isEmpty) continue;
      // Check if any non-expired message exists.
      final alive = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM messages WHERE conversation_id = ? AND disposition != ? AND (expires_at IS NULL OR expires_at > ?)',
        [convId, 'destroyed', DateTime.now().toUtc().toIso8601String()],
      );
      final count = alive.isEmpty ? 0 : (alive.first['cnt'] as int? ?? 0);
      if (count > 0) result.add(convId);
    }
    return result;
  }

  Future<Map<String, DirectChatRecord>> latestConversations() async {
    final db = await _database();
    final rows = await db.rawQuery('''
      SELECT m.*
      FROM messages m
      INNER JOIN (
        SELECT conversation_id, MAX(sent_at) AS max_sent
        FROM messages
        WHERE disposition != 'destroyed'
          AND (expires_at IS NULL OR expires_at > ?)
          AND conversation_id != ''
        GROUP BY conversation_id
      ) latest ON m.conversation_id = latest.conversation_id
                AND m.sent_at = latest.max_sent
      WHERE m.disposition != 'destroyed'
    ''', [DateTime.now().toUtc().toIso8601String()]);
    final result = <String, DirectChatRecord>{};
    for (final row in rows) {
      final record = _rowToRecord(row);
      if (record.isExpired) continue;
      result[record.conversationId] = record;
    }
    return result;
  }

  Future<Map<String, int>> cursor({String? conversationId}) async {
    final db = await _database();
    final rows = await db.rawQuery('''
      SELECT origin_device_id, MAX(origin_sequence) AS max_seq
      FROM messages
      ${conversationId != null ? 'WHERE conversation_id = ?' : ''}
      GROUP BY origin_device_id
    ''', conversationId != null ? [conversationId] : null);
    final result = <String, int>{};
    for (final row in rows) {
      final devId = (row['origin_device_id'] ?? '').toString();
      final seq = (row['max_seq'] as int?) ?? 0;
      if (devId.isNotEmpty) result[devId] = seq;
    }
    return result;
  }

  Future<List<DirectChatRecord>> afterCursor(
    Map<String, int> cursor, {
    String? conversationId,
    bool outgoingOnly = false,
  }) async {
    final db = await _database();
    // SQLite can't bind a variable-length IN list easily, so fetch all
    // candidates by conversation and filter by cursor in Dart. With an
    // index on (origin_device_id, origin_sequence) this is fast.
    final whereParts = <String>[];
    final args = <Object?>[];
    if (conversationId != null) {
      whereParts.add('conversation_id = ?');
      args.add(conversationId);
    }
    if (outgoingOnly) {
      whereParts.add('direction = ?');
      args.add('outgoing');
    }
    final where = whereParts.isEmpty ? '' : 'WHERE ${whereParts.join(' AND ')}';
    final rows = await db.rawQuery(
      'SELECT * FROM messages $where ORDER BY sent_at ASC, origin_sequence ASC',
      args,
    );
    return rows
        .map(_rowToRecord)
        .where((r) =>
            r.originSequence > (cursor[r.originDeviceId] ?? 0))
        .toList();
  }

  Future<List<DirectChatRecord>> pendingFor(String conversationId) async {
    final db = await _database();
    final rows = await db.query('messages',
        where:
            'conversation_id = ? AND direction = ? AND delivery != ?',
        whereArgs: [
          conversationId,
          'outgoing',
          DirectChatDelivery.delivered.name,
        ],
        orderBy: 'sent_at ASC');
    return rows
        .map(_rowToRecord)
        .where((r) => !r.isExpired)
        .toList();
  }

  Future<bool> linkReceivedTransferFile({
    required String conversationId,
    required String fileName,
    required int fileSize,
    required String localPath,
  }) async {
    if (conversationId.isEmpty || fileName.isEmpty || localPath.isEmpty) {
      return false;
    }
    final db = await _database();
    final rows = await db.query('messages',
        where:
            'conversation_id = ? AND file_name = ? AND (local_path = ? OR local_path = ?)',
        whereArgs: [conversationId, fileName, '', ''],
    );
    var updated = false;
    for (final row in rows) {
      final record = _rowToRecord(row);
      if (fileSize > 0 && record.fileSize != fileSize) continue;
      await db.update('messages', {'local_path': localPath},
          where: 'id = ?', whereArgs: [record.id]);
      updated = true;
    }
    return updated;
  }

  Future<int> purgeExpired() async {
    final db = await _database();
    final now = DateTime.now().toUtc().toIso8601String();
    const destroyedRetention = Duration(days: 7);
    final cutoff =
        DateTime.now().toUtc().subtract(destroyedRetention).toIso8601String();
    // Delete expired messages.
    final expiredCount = await db.delete('messages',
        where: 'expires_at IS NOT NULL AND expires_at <= ?',
        whereArgs: [now]);
    // Delete destroyed messages older than 7 days.
    final destroyedCount = await db.delete('messages',
        where: 'disposition = ? AND sent_at < ?',
        whereArgs: ['destroyed', cutoff]);
    return expiredCount + destroyedCount;
  }

  // ── JSON migration ────────────────────────────────────────

  /// One-time import from the legacy JSON store. Idempotent via
  /// `INSERT OR IGNORE`. After a successful import the JSON file is
  /// renamed to `.bak` so it's not re-read on subsequent launches.
  Future<void> _migrateFromJsonStore() async {
    // Guard: only migrate once per process (the `.bak` rename is the
    // durable guard across processes).
    final migrated = await _getMeta('json_migrated');
    if (migrated == '1') return;

    try {
      final legacyStorage = DirectChatStorage();
      final raw = await legacyStorage.read();
      if (raw == null || raw.isEmpty) {
        await _setMeta('json_migrated', '1');
        return;
      }
      final parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) {
        await _setMeta('json_migrated', '1');
        return;
      }
      final recordsList =
          (parsed['records'] as List<dynamic>?) ?? const <dynamic>[];
      final deviceId =
          (parsed['device_id'] ?? '').toString();
      final nextSeq =
          int.tryParse('${parsed['next_sequence'] ?? 1}') ?? 1;

      if (deviceId.isNotEmpty) {
        await _setMeta('device_id', deviceId);
      }
      await _setMeta('next_sequence', nextSeq.toString());

      final db = await _database();
      await db.transaction((txn) async {
        for (final entry in recordsList) {
          if (entry is! Map<String, dynamic>) continue;
          try {
            final record = DirectChatRecord.fromJson(
              Map<String, dynamic>.from(entry),
            );
            if (record.id.isEmpty ||
                record.conversationId.isEmpty ||
                record.text
                    .trim()
                    .startsWith(DirectChatEnvelope.prefix)) {
              continue;
            }
            await txn.insert('messages', _recordToRow(record),
                conflictAlgorithm: ConflictAlgorithm.ignore);
          } catch (_) {}
        }
      });

      // Rename the JSON file so it's not re-imported.
      await legacyStorage.renameToBackup();
      await _setMeta('json_migrated', '1');
      debugPrint('CHAT-SQLITE: migrated ${recordsList.length} records from '
          'legacy JSON store');
    } catch (e, st) {
      debugPrint('CHAT-SQLITE: JSON migration failed: $e\n$st');
      // Don't set json_migrated=1 — retry on next launch.
    }
  }

  // ── Row ↔ Record conversion ───────────────────────────────

  Map<String, Object?> _recordToRow(DirectChatRecord r) {
    return <String, Object?>{
      'id': r.id,
      'conversation_id': r.conversationId,
      'origin_device_id': r.originDeviceId,
      'origin_sequence': r.originSequence,
      'direction': r.direction.name,
      'kind': r.kind.name,
      'text': r.text,
      'sender_id': r.senderId,
      'sender_name': r.senderName,
      'sender_avatar': r.senderAvatar,
      'sent_at': r.sentAt.toUtc().toIso8601String(),
      'delivery': r.delivery.name,
      'disposition': r.disposition.name,
      'file_name': r.fileName,
      'file_size': r.fileSize,
      'file_sha256': r.fileSha256,
      'local_path': r.localPath,
      'voice_duration_ms': r.voiceDurationMs,
      'expires_at': r.expiresAt?.toUtc().toIso8601String(),
      'reply_to_id': r.replyToId,
      'reply_to_sender': r.replyToSender,
      'reply_to_text': r.replyToText,
      'reactions': jsonEncode(r.reactions),
      'is_edited': r.isEdited ? 1 : 0,
      'edited_at': r.editedAt?.toUtc().toIso8601String(),
      'forward_title': r.forwardTitle,
      'forward_items':
          jsonEncode(r.forwardItems.map((i) => i.toJson()).toList()),
      'conn_mode': r.connMode,
      'conn_endpoint': r.connEndpoint,
      'conn_port': r.connPort,
      'src_platform': r.srcPlatform,
    };
  }

  DirectChatRecord _rowToRecord(Map<String, Object?> row) {
    return DirectChatRecord(
      id: (row['id'] ?? '').toString(),
      conversationId: (row['conversation_id'] ?? '').toString(),
      originDeviceId: (row['origin_device_id'] ?? '').toString(),
      originSequence: (row['origin_sequence'] as int?) ?? 0,
      direction: _enumFromName(
          DirectChatDirection.values, (row['direction'] ?? '').toString(),
          DirectChatDirection.incoming),
      kind: _enumFromName(
          DirectChatKind.values, (row['kind'] ?? '').toString(),
          DirectChatKind.text),
      text: (row['text'] ?? '').toString(),
      senderId: (row['sender_id'] ?? '').toString(),
      senderName: (row['sender_name'] ?? '').toString(),
      senderAvatar: (row['sender_avatar'] ?? '').toString(),
      sentAt: DateTime.tryParse((row['sent_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      delivery: _enumFromName(
          DirectChatDelivery.values, (row['delivery'] ?? '').toString(),
          DirectChatDelivery.queued),
      disposition: _enumFromName(
          DirectChatDisposition.values,
          (row['disposition'] ?? '').toString(),
          DirectChatDisposition.active),
      fileName: (row['file_name'] ?? '').toString(),
      fileSize: (row['file_size'] as int?) ?? 0,
      fileSha256: (row['file_sha256'] ?? '').toString(),
      localPath: (row['local_path'] ?? '').toString(),
      inlineBytes: '', // Never persisted — wire-only field
      voiceDurationMs: (row['voice_duration_ms'] as int?) ?? 0,
      expiresAt: DateTime.tryParse((row['expires_at'] ?? '').toString()),
      replyToId: (row['reply_to_id'] ?? '').toString(),
      replyToSender: (row['reply_to_sender'] ?? '').toString(),
      replyToText: (row['reply_to_text'] ?? '').toString(),
      reactions: _parseReactions(row['reactions']),
      isEdited: (row['is_edited'] as int?) == 1,
      editedAt: DateTime.tryParse((row['edited_at'] ?? '').toString()),
      forwardTitle: (row['forward_title'] ?? '').toString(),
      forwardItems: _parseForwardItems(row['forward_items']),
      connMode: (row['conn_mode'] ?? '').toString(),
      connEndpoint: (row['conn_endpoint'] ?? '').toString(),
      connPort: (row['conn_port'] as int?) ?? 0,
      srcPlatform: (row['src_platform'] ?? '').toString(),
    );
  }

  static T _enumFromName<T extends Enum>(
      List<T> values, String name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  static Map<String, List<String>> _parseReactions(dynamic raw) {
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final result = <String, List<String>>{};
      for (final entry in decoded.entries) {
        final emoji = sanitizeInvalidUtf16(entry.key.toString());
        final list = entry.value;
        if (list is List) {
          result[emoji] =
              list.map((e) => sanitizeInvalidUtf16(e.toString())).toList();
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  static List<DirectChatForwardItem> _parseForwardItems(dynamic raw) {
    if (raw is! String || raw.isEmpty) return const <DirectChatForwardItem>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <DirectChatForwardItem>[];
      return decoded
          .whereType<Map>()
          .map((item) => DirectChatForwardItem.fromJson(
              Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } catch (_) {
      return const <DirectChatForwardItem>[];
    }
  }

static int _deliveryRank(DirectChatDelivery delivery) {
 switch (delivery) {
 case DirectChatDelivery.queued:
 return 0;
 case DirectChatDelivery.failed:
 return 1;
 case DirectChatDelivery.sent:
 return 2;
 case DirectChatDelivery.delivered:
 return 3;
 }
 }

 // ── Meeting CRUD (v2) ────────────────────────────────────

 /// Insert or replace a meeting group row.
 Future<void> upsertMeeting(Map<String, dynamic> row) async {
 final db = await _database();
 await db.insert('meetings', row,
 conflictAlgorithm: ConflictAlgorithm.replace);
 }

 /// Delete a meeting and its members (CASCADE).
 Future<void> deleteMeeting(String meetingId) async {
 final db = await _database();
 await db.transaction((txn) async {
 await txn.delete('meeting_members',
 where: 'meeting_id = ?', whereArgs: [meetingId]);
 await txn
 .delete('meetings', where: 'meeting_id = ?', whereArgs: [meetingId]);
 });
 }

 /// Load all meetings with their members in a single transaction.
 Future<List<Map<String, dynamic>>> loadAllMeetings() async {
 final db = await _database();
 final meetingRows = await db.query('meetings', orderBy: 'created_at DESC');
 final result = <Map<String, dynamic>>[];
 for (final m in meetingRows) {
 final members = await db.query('meeting_members',
 where: 'meeting_id = ?',
 whereArgs: [m['meeting_id']],
 orderBy: 'joined_at ASC');
 result.add(<String, dynamic>{
 ...m,
 'members': members,
 });
 }
 return result;
 }

 /// Replace all meeting members for [meetingId] within a transaction.
 Future<void> replaceMeetingMembers(
 String meetingId, List<Map<String, dynamic>> members) async {
 final db = await _database();
 await db.transaction((txn) async {
 await txn.delete('meeting_members',
 where: 'meeting_id = ?', whereArgs: [meetingId]);
 for (final m in members) {
 await txn.insert('meeting_members', <String, dynamic>{
 ...m,
 'meeting_id': meetingId,
 },
 conflictAlgorithm: ConflictAlgorithm.replace);
 }
 });
 }

 // ── Pairing CRUD (v2) ─────────────────────────────────────

 Future<void> upsertPairing(Map<String, dynamic> row) async {
 final db = await _database();
 await db.insert('pairings', row,
 conflictAlgorithm: ConflictAlgorithm.replace);
 }

 Future<void> deletePairing(String peerId) async {
 final db = await _database();
 await db.delete('pairings', where: 'peer_id = ?', whereArgs: [peerId]);
 }

 Future<List<Map<String, dynamic>>> loadAllPairings() async {
 final db = await _database();
 return db.query('pairings', orderBy: 'display_name ASC');
 }

 // ── Contact policy CRUD (v2) ──────────────────────────────

 Future<void> upsertContactPolicy(Map<String, dynamic> row) async {
 final db = await _database();
 await db.insert('contact_policies', row,
 conflictAlgorithm: ConflictAlgorithm.replace);
 }

 Future<void> deleteContactPolicy(String peerId) async {
 final db = await _database();
 await db.delete('contact_policies',
 where: 'peer_id = ?', whereArgs: [peerId]);
 }

 Future<List<Map<String, dynamic>>> loadAllContactPolicies() async {
 final db = await _database();
 return db.query('contact_policies');
 }

 // ── KV → SQLite migration helpers ─────────────────────────

 /// One-time migration of meeting groups from KV store to SQLite.
 /// Idempotent: uses INSERT OR REPLACE, so re-running is safe.
 Future<void> _migrateMeetingsFromKV() async {
 String raw;
 try {
 raw = bind.mainGetLocalOption(key: 'meeting_groups_v1');
 } catch (_) {
 return; // FFI not available (e.g. in unit tests without native lib)
 }
 if (raw.isEmpty) return;
 try {
 final decoded = jsonDecode(raw);
 if (decoded is! List) return;
 final db = await _database();
 await db.transaction((txn) async {
 for (final item in decoded) {
 if (item is! Map<String, dynamic>) continue;
 final meetingId = (item['meeting_id'] ?? '').toString();
 if (meetingId.isEmpty) continue;
 await txn.insert('meetings', {
 'meeting_id': meetingId,
 'title': (item['title'] ?? '').toString(),
 'host_peer_id': (item['host_peer_id'] ?? '').toString(),
 'host_display_name':
 (item['host_display_name'] ?? '').toString(),
 'created_at': (item['created_at'] ?? '').toString(),
 'active_session_endpoint':
 (item['active_session_endpoint'] ?? '').toString(),
 'invite_short_code':
 (item['invite_short_code'] ?? '').toString(),
 'presenter_peer_id':
 (item['presenter_peer_id'] ?? '').toString(),
 'presenter_display_name':
 (item['presenter_display_name'] ?? '').toString(),
 'viewer_token': (item['viewer_token'] ?? '').toString(),
 'start_time': (item['start_time'] ?? '').toString(),
 'duration_minutes':
 int.tryParse('${item['duration_minutes']}') ?? 60,
 }, conflictAlgorithm: ConflictAlgorithm.replace);
 final members = (item['members'] as List?) ?? [];
 for (final m in members) {
 if (m is! Map<String, dynamic>) continue;
 final pid = (m['peer_id'] ?? '').toString();
 if (pid.isEmpty) continue;
 await txn.insert('meeting_members', {
 'meeting_id': meetingId,
 'peer_id': pid,
 'display_name': (m['display_name'] ?? '').toString(),
 'joined_at': (m['joined_at'] ?? '').toString(),
 }, conflictAlgorithm: ConflictAlgorithm.replace);
 }
 }
 });
 // Mark migration done so we never re-read the stale KV blob.
 await _setMeta('meetings_migrated_v2', '1');
 } catch (e) {
 debugPrint('Meeting KV→SQLite migration failed: $e');
 }
 }

 /// One-time migration of pairings from KV store to SQLite.
 Future<void> _migratePairingsFromKV() async {
 String raw;
 try {
 raw = bind.mainGetLocalOption(key: 'direct-pairings-v1');
 } catch (_) {
 return; // FFI not available (e.g. in unit tests without native lib)
 }
 if (raw.isEmpty) return;
 try {
 final decoded = jsonDecode(raw);
 if (decoded is! List) return;
 final db = await _database();
 await db.transaction((txn) async {
 for (final item in decoded) {
 if (item is! Map<String, dynamic>) continue;
 final pid = (item['peer_id'] ?? '').toString();
 if (pid.isEmpty) continue;
 await txn.insert('pairings', {
 'peer_id': pid,
 'display_name': (item['display_name'] ?? '').toString(),
 'lan_endpoint': (item['lan_endpoint'] ?? '').toString(),
 'public_endpoint':
 (item['public_endpoint'] ?? '').toString(),
 'fingerprint': (item['fingerprint'] ?? '').toString(),
 'updated_at': (item['updated_at'] ?? '').toString(),
 'account_id': (item['account_id'] ?? '').toString(),
 'avatar': (item['avatar'] ?? '').toString(),
 'conversation_id': pid,
 'conn_mode': (item['conn_mode'] ?? '').toString(),
 'conn_port': int.tryParse('${item['conn_port']}') ?? 0,
 'is_bound_phone': 0,
 }, conflictAlgorithm: ConflictAlgorithm.replace);
 }
 });
 await _setMeta('pairings_migrated_v2', '1');
 } catch (e) {
 debugPrint('Pairings KV→SQLite migration failed: $e');
 }
 }
}
