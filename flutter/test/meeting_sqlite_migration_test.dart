import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/direct_chat_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dbFileName = 'ldesk31_chat.db';

Future<void> _createLegacyDatabase(String directory) async {
  final path = '$directory${Platform.pathSeparator}$_dbFileName';
  final db = await openDatabase(
    path,
    version: 5,
    onCreate: (db, _) async {
      // This is intentionally the pre-invite_short_code shape. The database
      // version is already 5, so the normal onUpgrade branches do not touch
      // meetings; _ensureMeetingsColumns must perform the real ALTER TABLE.
      await db.execute('''
        CREATE TABLE messages (
          id TEXT PRIMARY KEY,
          text TEXT NOT NULL DEFAULT '',
          sent_at TEXT NOT NULL,
          expires_at TEXT,
          edited_at TEXT
        )
      ''');
      await db.execute(
          'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      await db.execute('''
        CREATE TABLE meetings (
          meeting_id TEXT PRIMARY KEY,
          title TEXT NOT NULL DEFAULT '',
          host_peer_id TEXT NOT NULL,
          host_display_name TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          active_session_endpoint TEXT NOT NULL DEFAULT ''
        )
      ''');
      await db.execute('''
        CREATE TABLE meeting_members (
          meeting_id TEXT NOT NULL,
          peer_id TEXT NOT NULL,
          display_name TEXT NOT NULL DEFAULT '',
          joined_at TEXT NOT NULL,
          PRIMARY KEY (meeting_id, peer_id)
        )
      ''');
      await db.execute('''
        CREATE TABLE pairings (
          peer_id TEXT PRIMARY KEY,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE assist_records (
          id TEXT PRIMARY KEY,
          started_at TEXT NOT NULL,
          ended_at TEXT
        )
      ''');
    },
  );
  await db.close();
}

void main() {
  late Directory tempDir;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('ldesk_meeting_migration');
    DirectChatSqlite.debugDbDirOverride = tempDir.path;
    await DirectChatSqlite.instance.resetForTest();
    await _createLegacyDatabase(tempDir.path);
  });

  tearDown(() async {
    await DirectChatSqlite.instance.resetForTest();
    DirectChatSqlite.debugDbDirOverride = null;
    await tempDir.delete(recursive: true);
  });

  test('adds invite_short_code to a legacy meetings table and persists it',
      () async {
    await DirectChatSqlite.instance.upsertMeeting({
      'meeting_id': 'legacy-meeting-1',
      'title': 'Legacy meeting',
      'host_peer_id': 'host-1',
      'host_display_name': 'Host',
      'created_at': '2026-09-09T12:00:00.000Z',
      'active_session_endpoint': '',
      'invite_short_code': 'ABCD2345',
      'presenter_peer_id': 'host-1',
      'presenter_display_name': 'Host',
      'viewer_token': 'viewer-token',
      'start_time': '',
      'duration_minutes': 60,
    });

    final loaded = await DirectChatSqlite.instance.loadAllMeetings();
    expect(loaded, hasLength(1));
    expect(loaded.single['meeting_id'], 'legacy-meeting-1');
    expect(loaded.single['invite_short_code'], 'ABCD2345');

    // Verify the physical SQLite column and value, not only the Dart map.
    final path = '${tempDir.path}${Platform.pathSeparator}$_dbFileName';
    final db = await openDatabase(path, version: 6);
    try {
      final columns = await db.rawQuery('PRAGMA table_info(meetings)');
      expect(
        columns.any((column) => column['name'] == 'invite_short_code'),
        isTrue,
      );
      final rows = await db.query(
        'meetings',
        columns: ['invite_short_code'],
        where: 'meeting_id = ?',
        whereArgs: ['legacy-meeting-1'],
      );
      expect(rows.single['invite_short_code'], 'ABCD2345');
    } finally {
      await db.close();
    }

    // Simulate the next application launch: the value must still be readable.
    await DirectChatSqlite.instance.resetForTest();
    final afterRestart = await DirectChatSqlite.instance.loadAllMeetings();
    expect(afterRestart.single['invite_short_code'], 'ABCD2345');
  });
}
