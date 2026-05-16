import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'rihla-tombstone-migration-',
    );
  });

  tearDown(() async {
    await LocalDatabase.close();
    await LocalDatabase.setDatabasePathForTesting(null);
    await tempDir.delete(recursive: true);
  });

  test('v8 databases gain is_tombstone on group_members at v9', () async {
    final path = '${tempDir.path}/safar_cache.db';
    final oldDb = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 8,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE group_members (
              id TEXT PRIMARY KEY,
              group_id TEXT NOT NULL,
              user_id TEXT,
              display_name TEXT NOT NULL,
              role TEXT NOT NULL DEFAULT 'MEMBER',
              is_shadow INTEGER NOT NULL DEFAULT 0,
              joined_at TEXT NOT NULL,
              synced_at TEXT
            )
          ''');
          await db.insert('group_members', {
            'id': 'member-1',
            'group_id': 'group-1',
            'user_id': 'uid-1',
            'display_name': 'Nasser',
            'role': 'MEMBER',
            'is_shadow': 0,
            'joined_at': DateTime(2026, 1, 1).toIso8601String(),
          });
        },
      ),
    );
    await oldDb.close();

    await LocalDatabase.setDatabasePathForTesting(path);
    final upgraded = await LocalDatabase.database;

    final tableInfo = await upgraded.rawQuery(
      'PRAGMA table_info(group_members)',
    );
    final columnNames = tableInfo.map((row) => row['name'] as String).toList();
    expect(columnNames, contains('is_tombstone'));

    final rows = await upgraded.query('group_members');
    expect(rows.single['is_tombstone'], 0);
  });
}
