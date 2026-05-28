import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('rihla-wipe-test-');
    await LocalDatabase.setDatabasePathForTesting(
      '${tempDir.path}/safar_cache.db',
    );
  });

  setUp(() async {
    await LocalDatabase.clearAll();
  });

  tearDownAll(() async {
    await LocalDatabase.close();
    await LocalDatabase.setDatabasePathForTesting(null);
    await tempDir.delete(recursive: true);
  });

  group('LocalDatabase.wipeAndReinitialize', () {
    test(
      'deletes the file and re-creates it with the current schema',
      () async {
        final db = await LocalDatabase.database;
        await db.insert('trips', {
          'id': 'trip-1',
          'name': 'Trip Alpha',
          'invite_code': 'ABC123',
          'leader_id': 'uid-1',
          'created_at': DateTime.now().toIso8601String(),
        });
        final beforeRows = await db.query('trips');
        expect(beforeRows, hasLength(1));

        await LocalDatabase.wipeAndReinitialize();

        final fresh = await LocalDatabase.database;
        final afterRows = await fresh.query('trips');
        expect(afterRows, isEmpty, reason: 'wipe should drop existing rows');

        final tableInfo = await fresh.rawQuery('PRAGMA table_info(trips)');
        final columnNames = tableInfo
            .map((row) => row['name'] as String)
            .toList();
        expect(
          columnNames,
          containsAll(['id', 'name', 'invite_code', 'leader_id']),
          reason: 'schema should be re-created on the fresh handle',
        );

        final groupMembersInfo = await fresh.rawQuery(
          'PRAGMA table_info(group_members)',
        );
        final groupMemberColumns = groupMembersInfo
            .map((row) => row['name'] as String)
            .toList();
        expect(groupMemberColumns, contains('is_tombstone'));
      },
    );

    test('subsequent reads succeed against the fresh handle', () async {
      await LocalDatabase.wipeAndReinitialize();
      final db = await LocalDatabase.database;

      await db.insert('groups', {
        'id': 'g1',
        'name': 'Test Group',
        'invite_code': 'XYZ',
        'created_by': 'uid-2',
        'member_ids': '[]',
        'created_at': DateTime.now().toIso8601String(),
      });
      final rows = await db.query('groups');
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Test Group');
    });

    test('fresh schema adds owner_uid to every cache table', () async {
      await LocalDatabase.wipeAndReinitialize();
      final db = await LocalDatabase.database;
      const tables = [
        'trips',
        'expenses',
        'settlements',
        'participants',
        'activity_logs',
        'categories',
        'groups',
        'group_members',
        'group_ledger',
      ];

      for (final table in tables) {
        final info = await db.rawQuery('PRAGMA table_info($table)');
        final columns = info.map((row) => row['name'] as String).toList();
        expect(columns, contains('owner_uid'), reason: '$table owner filter');
      }
    });

    test('cacheFileExists reports the recreated cache file', () async {
      await LocalDatabase.wipeAndReinitialize();

      expect(await LocalDatabase.cacheFileExists(), isTrue);
    });
  });
}
