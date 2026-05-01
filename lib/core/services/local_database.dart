import 'dart:async';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Local database service for offline caching
class LocalDatabase {
  static Database? _database;
  static Completer<Database>? _initCompleter;
  static const String _databaseName = 'safar_cache.db';
  static const int _databaseVersion =
      7; // Phase 39 strip — drop gear_items + cut tables + trips.currency
  static String? _databasePathOverride;

  /// Get database instance (safe for concurrent access).
  ///
  /// If init fails, completes the completer with the error (unblocking
  /// waiters) and resets it so the next access retries initialization.
  static Future<Database> get database async {
    if (_database != null) return _database!;
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<Database>();
    try {
      _database = await _initDatabase();
      _initCompleter!.complete(_database!);
    } catch (e, st) {
      _initCompleter!.completeError(e, st);
      _initCompleter = null;
      rethrow;
    }
    return _database!;
  }

  /// Initialize the database
  static Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = _databasePathOverride ?? join(databasesPath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Create database tables
  static Future<void> _onCreate(Database db, int version) async {
    // Trips table (Phase 39: trips.currency column dropped — OMR only)
    await db.execute('''
      CREATE TABLE trips (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        invite_code TEXT NOT NULL,
        leader_id TEXT NOT NULL,
        icon TEXT DEFAULT 'airplane',
        start_date TEXT,
        end_date TEXT,
        modules TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        synced_at TEXT
      )
    ''');

    // Expenses table
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

    // Settlements table
    await db.execute('''
      CREATE TABLE settlements (
        id TEXT PRIMARY KEY,
        trip_id TEXT NOT NULL,
        payer_participant_id TEXT NOT NULL,
        recipient_participant_id TEXT NOT NULL,
        amount TEXT NOT NULL,
        currency TEXT DEFAULT 'OMR',
        note TEXT,
        created_at TEXT NOT NULL,
        synced_at TEXT,
        is_deleted INTEGER DEFAULT 0,
        deleted_at TEXT,
        FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE CASCADE
      )
    ''');

    // Participants table
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

    // Activity logs table
    await db.execute('''
      CREATE TABLE activity_logs (
        id TEXT PRIMARY KEY,
        trip_id TEXT NOT NULL,
        actor_id TEXT,
        target_participant_id TEXT,
        category TEXT NOT NULL,
        event_type TEXT NOT NULL,
        log_text TEXT NOT NULL,
        metadata TEXT,
        actor_name TEXT,
        actor_avatar TEXT,
        created_at TEXT NOT NULL,
        last_synced_at TEXT,
        FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE CASCADE
      )
    ''');

    // Categories table
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        trip_id TEXT NOT NULL,
        name TEXT NOT NULL,
        icon TEXT,
        last_synced_at TEXT,
        FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE CASCADE
      )
    ''');

    // Groups table
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

    // Group members table
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

    // Group ledger table
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

    // Create indexes for faster queries
    await db.execute('CREATE INDEX idx_expenses_trip ON expenses(trip_id)');
    await db.execute(
      'CREATE INDEX idx_settlements_trip ON settlements(trip_id)',
    );

    await db.execute(
      'CREATE INDEX idx_participants_trip ON participants(trip_id)',
    );
    await db.execute(
      'CREATE INDEX idx_activity_trip ON activity_logs(trip_id)',
    );
    await db.execute('CREATE INDEX idx_categories_trip ON categories(trip_id)');
    await db.execute('CREATE INDEX idx_groups_invite ON groups(invite_code)');
    await db.execute(
      'CREATE INDEX idx_group_members_group ON group_members(group_id)',
    );
    await db.execute(
      'CREATE INDEX idx_group_ledger_group ON group_ledger(group_id)',
    );
    await db.execute(
      'CREATE INDEX idx_group_ledger_pair ON group_ledger(group_id, member_id, counterparty_id)',
    );
  }

  /// Handle database upgrades
  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      // Add soft delete columns
      await db.execute(
        'ALTER TABLE expenses ADD COLUMN is_deleted INTEGER DEFAULT 0',
      );
      await db.execute('ALTER TABLE expenses ADD COLUMN deleted_at TEXT');

      await db.execute(
        'ALTER TABLE gear_items ADD COLUMN is_deleted INTEGER DEFAULT 0',
      );
      await db.execute('ALTER TABLE gear_items ADD COLUMN deleted_at TEXT');

      await db.execute(
        'ALTER TABLE settlements ADD COLUMN is_deleted INTEGER DEFAULT 0',
      );
      await db.execute('ALTER TABLE settlements ADD COLUMN deleted_at TEXT');
    }

    if (oldVersion < 3) {
      // Rename payer_id to payer_participant_id in expenses
      await db.execute(
        'ALTER TABLE expenses RENAME COLUMN payer_id TO payer_participant_id',
      );
      // Rename columns in settlements
      await db.execute(
        'ALTER TABLE settlements RENAME COLUMN payer_id TO payer_participant_id',
      );
      await db.execute(
        'ALTER TABLE settlements RENAME COLUMN recipient_id TO recipient_participant_id',
      );
    }

    if (oldVersion < 4) {
      // Drop and recreate gear_items with correct schema
      await db.execute('DROP TABLE IF EXISTS gear_items');
      await db.execute('''
        CREATE TABLE gear_items (
          id TEXT PRIMARY KEY,
          trip_id TEXT NOT NULL,
          item_name TEXT NOT NULL,
          assigned_to TEXT,
          is_packed INTEGER DEFAULT 0,
          sequence_id INTEGER DEFAULT 0,
          is_high_priority INTEGER DEFAULT 0,
          assigned_to_name TEXT,
          assigned_to_avatar TEXT,
          created_at TEXT,
          synced_at TEXT,
          is_deleted INTEGER DEFAULT 0,
          deleted_at TEXT,
          FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE CASCADE
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_gear_trip ON gear_items(trip_id)',
      );

      // Create participants table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS participants (
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

      // Create sub_groups table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sub_groups (
          id TEXT PRIMARY KEY,
          trip_id TEXT NOT NULL,
          name TEXT NOT NULL,
          type TEXT NOT NULL DEFAULT 'CAR',
          capacity INTEGER NOT NULL DEFAULT 4,
          created_at TEXT,
          last_synced_at TEXT,
          FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE CASCADE
        )
      ''');

      // Create sub_group_members table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sub_group_members (
          id TEXT PRIMARY KEY,
          sub_group_id TEXT NOT NULL,
          participant_id TEXT NOT NULL,
          display_name TEXT,
          avatar_url TEXT,
          joined_at TEXT,
          last_synced_at TEXT,
          FOREIGN KEY (sub_group_id) REFERENCES sub_groups (id) ON DELETE CASCADE
        )
      ''');

      // Create activity_logs table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS activity_logs (
          id TEXT PRIMARY KEY,
          trip_id TEXT NOT NULL,
          actor_id TEXT,
          target_participant_id TEXT,
          category TEXT NOT NULL,
          event_type TEXT NOT NULL,
          log_text TEXT NOT NULL,
          metadata TEXT,
          actor_name TEXT,
          actor_avatar TEXT,
          created_at TEXT NOT NULL,
          last_synced_at TEXT,
          FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE CASCADE
        )
      ''');

      // Create categories table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS categories (
          id TEXT PRIMARY KEY,
          trip_id TEXT NOT NULL,
          name TEXT NOT NULL,
          icon TEXT,
          last_synced_at TEXT,
          FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE CASCADE
        )
      ''');

      // Create indexes for new tables
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_participants_trip ON participants(trip_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sub_groups_trip ON sub_groups(trip_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sgm_group ON sub_group_members(sub_group_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_activity_trip ON activity_logs(trip_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_categories_trip ON categories(trip_id)',
      );
    }

    if (oldVersion < 5) {
      try {
        await db.execute(
          "ALTER TABLE trips ADD COLUMN currency TEXT DEFAULT 'OMR'",
        );
      } catch (_) {
        // Column already exists from a previous migration — safe to ignore.
      }
    }

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
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_groups_invite ON groups(invite_code)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_group_members_group ON group_members(group_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_group_ledger_group ON group_ledger(group_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_group_ledger_pair ON group_ledger(group_id, member_id, counterparty_id)',
      );
    }

    if (oldVersion < 7) {
      // Phase 39 strip — drop tables for cut features.
      // gear_items definitely exists in v6 schema; the others are defensive
      // (no-op if they don't exist — IF EXISTS makes the DROP idempotent).
      await db.execute('DROP TABLE IF EXISTS gear_items');
      await db.execute('DROP TABLE IF EXISTS sub_group_members');
      await db.execute('DROP TABLE IF EXISTS sub_groups');
      await db.execute('DROP TABLE IF EXISTS documents');
      await db.execute('DROP TABLE IF EXISTS memories');
      await db.execute('DROP TABLE IF EXISTS trip_memories');
      await db.execute('DROP TABLE IF EXISTS logistics');

      // ROADMAP SC2 — drop trips.currency column.
      // SQLite ALTER TABLE DROP COLUMN is available since 3.35 (2021).
      // Wrap in try/catch in case the underlying SQLite is older — falls
      // back to leaving the column in place (it's no longer written by
      // application code after Phase 39, so a stale column is harmless).
      try {
        await db.execute('ALTER TABLE trips DROP COLUMN currency');
      } catch (_) {
        // Older SQLite — column stays. Not load-bearing post-strip.
      }
    }
  }

  /// Close database and reset completer so next access re-initializes.
  static Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
      _initCompleter = null;
    }
  }

  /// Override the database path in tests so parallel suites do not share locks.
  static Future<void> setDatabasePathForTesting(String? path) async {
    await close();
    _databasePathOverride = path;
  }

  /// Clear all cached data
  static Future<void> clearAll() async {
    final db = await database;
    // Delete child tables first to respect foreign key constraints
    await db.delete('group_ledger');
    await db.delete('group_members');
    await db.delete('groups');
    await db.delete('activity_logs');
    await db.delete('participants');
    await db.delete('categories');
    await db.delete('expenses');
    await db.delete('settlements');
    await db.delete('trips');
  }
}
