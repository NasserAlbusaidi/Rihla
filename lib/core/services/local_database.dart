import 'dart:async';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Local database service for offline caching
class LocalDatabase {
  static Database? _database;
  static Completer<Database>? _initCompleter;
  static const String _databaseName = 'safar_cache.db';
  static const int _databaseVersion =
      3; // Incremented for participant-based columns

  /// Get database instance (safe for concurrent access)
  static Future<Database> get database async {
    if (_database != null) return _database!;
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<Database>();
    _database = await _initDatabase();
    _initCompleter!.complete(_database!);
    return _database!;
  }

  /// Initialize the database
  static Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Create database tables
  static Future<void> _onCreate(Database db, int version) async {
    // Trips table
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

    // Gear items table
    await db.execute('''
      CREATE TABLE gear_items (
        id TEXT PRIMARY KEY,
        trip_id TEXT NOT NULL,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        is_checked INTEGER DEFAULT 0,
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

    // Sync queue for pending changes
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        action TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0
      )
    ''');

    // Create indexes for faster queries
    await db.execute('CREATE INDEX idx_expenses_trip ON expenses(trip_id)');
    await db.execute('CREATE INDEX idx_gear_trip ON gear_items(trip_id)');
    await db.execute(
      'CREATE INDEX idx_settlements_trip ON settlements(trip_id)',
    );
    await db.execute('CREATE INDEX idx_sync_queue ON sync_queue(table_name)');
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
  }

  /// Close database
  static Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  /// Clear all cached data
  static Future<void> clearAll() async {
    final db = await database;
    await db.delete('expenses');
    await db.delete('settlements');
    await db.delete('gear_items');
    await db.delete('trips');
    await db.delete('sync_queue');
  }
}

/// Enum for sync actions
enum SyncAction {
  create('CREATE'),
  update('UPDATE'),
  delete('DELETE');

  final String value;
  const SyncAction(this.value);
}
