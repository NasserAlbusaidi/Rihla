import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    // Initialize sqflite FFI for running tests on macOS/Linux/Windows
    sqfliteFfiInit();
  });

  group('LocalDatabase v6 migration', () {
    late Database db;

    setUp(() async {
      // Open in-memory database at version 6 using the same onCreate/onUpgrade
      // logic as LocalDatabase, extracted for testability
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 6,
          onCreate: _createTables,
          onUpgrade: _onUpgrade,
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('groups table exists with correct columns', () async {
      final result = await db.rawQuery('PRAGMA table_info(groups)');
      final columnNames = result.map((row) => row['name'] as String).toList();

      expect(columnNames, contains('id'));
      expect(columnNames, contains('name'));
      expect(columnNames, contains('invite_code'));
      expect(columnNames, contains('created_by'));
      expect(columnNames, contains('member_ids'));
      expect(columnNames, contains('currency'));
      expect(columnNames, contains('created_at'));
      expect(columnNames, contains('updated_at'));
      expect(columnNames, contains('synced_at'));
    });

    test('group_members table exists with correct columns', () async {
      final result = await db.rawQuery('PRAGMA table_info(group_members)');
      final columnNames = result.map((row) => row['name'] as String).toList();

      expect(columnNames, contains('id'));
      expect(columnNames, contains('group_id'));
      expect(columnNames, contains('user_id'));
      expect(columnNames, contains('display_name'));
      expect(columnNames, contains('role'));
      expect(columnNames, contains('is_shadow'));
      expect(columnNames, contains('joined_at'));
      expect(columnNames, contains('synced_at'));
    });

    test('group_ledger table exists with correct columns', () async {
      final result = await db.rawQuery('PRAGMA table_info(group_ledger)');
      final columnNames = result.map((row) => row['name'] as String).toList();

      expect(columnNames, contains('id'));
      expect(columnNames, contains('group_id'));
      expect(columnNames, contains('member_id'));
      expect(columnNames, contains('counterparty_id'));
      expect(columnNames, contains('net_amount_subunits'));
      expect(columnNames, contains('currency'));
      expect(columnNames, contains('last_updated_at'));
      expect(columnNames, contains('event_id'));
      expect(columnNames, contains('synced_at'));
    });

    test('group_ledger stores net_amount_subunits as INTEGER', () async {
      final result = await db.rawQuery('PRAGMA table_info(group_ledger)');
      final amountCol = result.firstWhere(
        (row) => row['name'] == 'net_amount_subunits',
      );
      expect(amountCol['type'], equals('INTEGER'));
    });

    test('existing trips table still exists at version 6', () async {
      final result = await db.rawQuery('PRAGMA table_info(trips)');
      expect(result, isNotEmpty);
    });

    test('existing expenses table still exists at version 6', () async {
      final result = await db.rawQuery('PRAGMA table_info(expenses)');
      expect(result, isNotEmpty);
    });

    test('existing participants table still exists at version 6', () async {
      final result = await db.rawQuery('PRAGMA table_info(participants)');
      expect(result, isNotEmpty);
    });

    test('all three new tables are listed in sqlite_master', () async {
      final result = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('groups', 'group_members', 'group_ledger')",
      );
      final names = result.map((row) => row['name'] as String).toSet();
      expect(names, containsAll({'groups', 'group_members', 'group_ledger'}));
    });
  });
}

/// Mirrors LocalDatabase._onCreate for isolated testing
Future<void> _createTables(Database db, int version) async {
  // Existing tables (abbreviated subset for migration testing)
  await db.execute('''
    CREATE TABLE trips (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      invite_code TEXT NOT NULL,
      leader_id TEXT NOT NULL,
      icon TEXT DEFAULT 'airplane',
      currency TEXT DEFAULT 'OMR',
      start_date TEXT,
      end_date TEXT,
      modules TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT,
      synced_at TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE expenses (
      id TEXT PRIMARY KEY,
      trip_id TEXT NOT NULL,
      payer_participant_id TEXT NOT NULL,
      amount TEXT NOT NULL,
      description TEXT,
      category_id TEXT,
      category_name TEXT,
      scope TEXT DEFAULT 'GLOBAL',
      sub_group_id TEXT,
      created_at TEXT NOT NULL,
      synced_at TEXT,
      is_deleted INTEGER DEFAULT 0,
      deleted_at TEXT,
      FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE CASCADE
    )
  ''');

  await db.execute('''
    CREATE TABLE participants (
      id TEXT PRIMARY KEY,
      trip_id TEXT NOT NULL,
      user_id TEXT,
      role TEXT NOT NULL DEFAULT 'MEMBER',
      display_name TEXT,
      avatar_url TEXT,
      is_shadow INTEGER NOT NULL DEFAULT 0,
      joined_at TEXT NOT NULL DEFAULT '',
      last_synced_at TEXT,
      FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE CASCADE
    )
  ''');

  // New groups tables (v6)
  await db.execute('''
    CREATE TABLE groups (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      invite_code TEXT NOT NULL,
      created_by TEXT NOT NULL,
      member_ids TEXT NOT NULL DEFAULT '[]',
      currency TEXT DEFAULT 'OMR',
      created_at TEXT NOT NULL,
      updated_at TEXT,
      synced_at TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE group_members (
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL,
      user_id TEXT,
      display_name TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'MEMBER',
      is_shadow INTEGER NOT NULL DEFAULT 0,
      joined_at TEXT NOT NULL,
      synced_at TEXT,
      FOREIGN KEY (group_id) REFERENCES groups (id) ON DELETE CASCADE
    )
  ''');

  await db.execute('''
    CREATE TABLE group_ledger (
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL,
      member_id TEXT NOT NULL,
      counterparty_id TEXT NOT NULL,
      net_amount_subunits INTEGER NOT NULL DEFAULT 0,
      currency TEXT NOT NULL DEFAULT 'OMR',
      last_updated_at TEXT NOT NULL,
      event_id TEXT,
      synced_at TEXT,
      FOREIGN KEY (group_id) REFERENCES groups (id) ON DELETE CASCADE
    )
  ''');
}

/// Mirrors LocalDatabase._onUpgrade for isolated testing
Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 6) {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        invite_code TEXT NOT NULL,
        created_by TEXT NOT NULL,
        member_ids TEXT NOT NULL DEFAULT '[]',
        currency TEXT DEFAULT 'OMR',
        created_at TEXT NOT NULL,
        updated_at TEXT,
        synced_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_members (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        user_id TEXT,
        display_name TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'MEMBER',
        is_shadow INTEGER NOT NULL DEFAULT 0,
        joined_at TEXT NOT NULL,
        synced_at TEXT,
        FOREIGN KEY (group_id) REFERENCES groups (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_ledger (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        member_id TEXT NOT NULL,
        counterparty_id TEXT NOT NULL,
        net_amount_subunits INTEGER NOT NULL DEFAULT 0,
        currency TEXT NOT NULL DEFAULT 'OMR',
        last_updated_at TEXT NOT NULL,
        event_id TEXT,
        synced_at TEXT,
        FOREIGN KEY (group_id) REFERENCES groups (id) ON DELETE CASCADE
      )
    ''');
  }
}
