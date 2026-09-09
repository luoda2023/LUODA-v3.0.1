import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_chat.dart';
import 'package:luoda_flutter/common/direct_chat_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbFileName = 'ldesk31_chat.db';

Future<void> _createIncompleteDatabase(String directory) async {
  final path = '$directory${Platform.pathSeparator}$_dbFileName';
  final db = await openDatabase(
    path,
    version: 5,
    onCreate: (db, _) async {
      // Deliberately omit all columns added after the first table shapes.
      await db.execute('''
        CREATE TABLE messages (
          id TEXT PRIMARY KEY
        )
      ''');
      await db.execute(
          'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      await db.execute('''
        CREATE TABLE meetings (
          meeting_id TEXT PRIMARY KEY
        )
      ''');
      await db.execute('''
        CREATE TABLE pairings (
          peer_id TEXT PRIMARY KEY
        )
      ''');
      await db.execute('''
        CREATE TABLE meeting_members (
          meeting_id TEXT NOT NULL,
          peer_id TEXT NOT NULL,
          PRIMARY KEY (meeting_id, peer_id)
        )
      ''');
      await db.execute('''
        CREATE TABLE assist_records (
          id TEXT PRIMARY KEY,
          started_at TEXT NOT NULL
        )
      ''');
    },
  );
  await db.close();
}

Future<Set<String>> _columns(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name'].toString()).toSet();
}

void main() {
  late Directory tempDir;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('ldesk_schema_migration');
    DirectChatSqlite.debugDbDirOverride = tempDir.path;
    await DirectChatSqlite.instance.resetForTest();
    await _createIncompleteDatabase(tempDir.path);
  });

  tearDown(() async {
    await DirectChatSqlite.instance.resetForTest();
    DirectChatSqlite.debugDbDirOverride = null;
    await tempDir.delete(recursive: true);
  });

  test('reconciles all current messages, meetings and pairings columns',
      () async {
    final store = DirectChatSqlite.instance;

    await store.createOutgoing(
      conversationId: 'peer-1',
      kind: DirectChatKind.text,
      text: 'schema migration',
      senderId: 'me',
      senderName: 'Me',
      senderAvatar: '',
      connectionTarget: 'peer-1',
    );
    await store.upsertMeeting({
      'meeting_id': 'meeting-1',
      'title': 'Meeting',
      'host_peer_id': 'host',
      'host_display_name': 'Host',
      'created_at': '2026-09-09T12:00:00.000Z',
      'active_session_endpoint': '',
      'invite_short_code': 'ABCD2345',
      'presenter_peer_id': 'host',
      'presenter_display_name': 'Host',
      'viewer_token': 'viewer',
      'start_time': '',
      'duration_minutes': 60,
    });
    await store.upsertPairing({
      'peer_id': 'peer-1',
      'display_name': 'Peer',
      'lan_endpoint': '192.168.1.10:21116',
      'public_endpoint': '',
      'fingerprint': 'fp',
      'updated_at': '2026-09-09T12:00:00.000Z',
      'account_id': 'account',
      'avatar': '',
      'conversation_id': 'peer-1',
      'conn_mode': 'lan',
      'conn_port': 21116,
      'is_bound_phone': 1,
      'companion': 1,
      'sync_secret': 'secret',
      'hardware_id': 'hw',
    });

    final path = '${tempDir.path}${Platform.pathSeparator}$_dbFileName';
    // Use a separate handle: sqflite's default single-instance cache would
    // otherwise return the store's live handle and closing it would invalidate
    // DirectChatSqlite.instance mid-test.
    final db = await openDatabase(path, version: 6, singleInstance: false);
    try {
      final messages = await _columns(db, 'messages');
      final meetings = await _columns(db, 'meetings');
      final pairings = await _columns(db, 'pairings');

      expect(
          messages,
          containsAll(<String>[
            'conversation_id',
            'origin_device_id',
            'origin_sequence',
            'direction',
            'kind',
            'text',
            'sender_id',
            'sender_name',
            'sender_avatar',
            'sent_at',
            'delivery',
            'disposition',
            'file_name',
            'file_size',
            'file_sha256',
            'local_path',
            'voice_duration_ms',
            'expires_at',
            'reply_to_id',
            'reply_to_sender',
            'reply_to_text',
            'reactions',
            'is_edited',
            'edited_at',
            'forward_title',
            'forward_items',
            'conn_mode',
            'conn_endpoint',
            'conn_port',
            'src_platform',
            'location_lat',
            'location_lng',
            'location_name',
            'image_width',
            'image_height',
          ]));
      expect(
          meetings,
          containsAll(<String>[
            'title',
            'host_peer_id',
            'host_display_name',
            'created_at',
            'active_session_endpoint',
            'invite_short_code',
            'presenter_peer_id',
            'presenter_display_name',
            'viewer_token',
            'start_time',
            'duration_minutes',
          ]));
      expect(
          pairings,
          containsAll(<String>[
            'display_name',
            'lan_endpoint',
            'public_endpoint',
            'fingerprint',
            'updated_at',
            'account_id',
            'avatar',
            'conversation_id',
            'conn_mode',
            'conn_port',
            'is_bound_phone',
            'companion',
            'sync_secret',
            'hardware_id',
          ]));
    } finally {
      await db.close();
    }

    final meetingRows = await store.loadAllMeetings();
    expect(meetingRows.single['invite_short_code'], 'ABCD2345');
    final pairingRows = await store.loadAllPairings();
    expect(pairingRows.single['fingerprint'], 'fp');

    // Reopen to prove the reconciliation is idempotent and values survive.
    await store.resetForTest();
    final reopened = await store.loadAllMeetings();
    expect(reopened.single['invite_short_code'], 'ABCD2345');
  });
}
