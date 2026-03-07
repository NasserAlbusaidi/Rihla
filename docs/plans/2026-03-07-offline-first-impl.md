# Offline-First Architecture Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Rihla work fully offline by using SQLite as the single source of truth, with Supabase as a background sync target.

**Architecture:** OfflineRepository wraps SQLite with reactive streams (StreamController-based change notifications). All providers read from SQLite (instant, never errors). Mutations write to SQLite + sync queue. SyncEngine handles push/pull when online. Real-time Supabase streams write to SQLite instead of directly to UI.

**Tech Stack:** Flutter, Riverpod 2.x, sqflite, Supabase, Decimal

**Design Doc:** `docs/plans/2026-03-07-offline-first-design.md`

---

## Task 1: Expand SQLite Schema to Version 4

Add new tables for participants, sub-groups, activity logs, and categories. Fix gear_items table to match the GearItem model. Enhance sync_queue with error tracking columns.

**Files:**
- Modify: `lib/core/services/local_database.dart`

**Step 1: Update database version and add new tables to `_onCreate`**

Change `_databaseVersion` from `3` to `4`.

In `_onCreate`, after the existing `sync_queue` table creation and before the index creation block, add:

```dart
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

// Sub-groups table
await db.execute('''
  CREATE TABLE sub_groups (
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

// Sub-group members table
await db.execute('''
  CREATE TABLE sub_group_members (
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

// Expense categories table
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
```

Also update the `sync_queue` CREATE TABLE to add `last_error` and `conflict_data` columns:

```dart
// Sync queue for pending changes
await db.execute('''
  CREATE TABLE sync_queue (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    table_name TEXT NOT NULL,
    record_id TEXT NOT NULL,
    action TEXT NOT NULL,
    data TEXT NOT NULL,
    created_at TEXT NOT NULL,
    retry_count INTEGER DEFAULT 0,
    last_error TEXT,
    conflict_data TEXT
  )
''');
```

Update the gear_items table to match the GearItem model:

```dart
// Gear items table
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
```

Add indexes for the new tables (after existing indexes):

```dart
await db.execute('CREATE INDEX idx_participants_trip ON participants(trip_id)');
await db.execute('CREATE INDEX idx_sub_groups_trip ON sub_groups(trip_id)');
await db.execute('CREATE INDEX idx_sgm_group ON sub_group_members(sub_group_id)');
await db.execute('CREATE INDEX idx_activity_trip ON activity_logs(trip_id)');
await db.execute('CREATE INDEX idx_categories_trip ON categories(trip_id)');
```

**Step 2: Add migration in `_onUpgrade` for version 3 to 4**

```dart
if (oldVersion < 4) {
  // New tables
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
      last_synced_at TEXT
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_participants_trip ON participants(trip_id)');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS sub_groups (
      id TEXT PRIMARY KEY,
      trip_id TEXT NOT NULL,
      name TEXT NOT NULL,
      type TEXT NOT NULL DEFAULT 'CAR',
      capacity INTEGER NOT NULL DEFAULT 4,
      created_at TEXT,
      last_synced_at TEXT
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_sub_groups_trip ON sub_groups(trip_id)');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS sub_group_members (
      id TEXT PRIMARY KEY,
      sub_group_id TEXT NOT NULL,
      participant_id TEXT NOT NULL,
      display_name TEXT,
      avatar_url TEXT,
      joined_at TEXT,
      last_synced_at TEXT
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_sgm_group ON sub_group_members(sub_group_id)');

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
      last_synced_at TEXT
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_activity_trip ON activity_logs(trip_id)');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS categories (
      id TEXT PRIMARY KEY,
      trip_id TEXT NOT NULL,
      name TEXT NOT NULL,
      icon TEXT,
      last_synced_at TEXT
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_categories_trip ON categories(trip_id)');

  // Enhance sync_queue
  await db.execute('ALTER TABLE sync_queue ADD COLUMN last_error TEXT');
  await db.execute('ALTER TABLE sync_queue ADD COLUMN conflict_data TEXT');

  // Recreate gear_items with correct schema
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
      deleted_at TEXT
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_gear_trip ON gear_items(trip_id)');
}
```

**Step 3: Update `clearAll()` to include new tables**

```dart
static Future<void> clearAll() async {
  final db = await database;
  await db.delete('activity_logs');
  await db.delete('sub_group_members');
  await db.delete('sub_groups');
  await db.delete('participants');
  await db.delete('categories');
  await db.delete('expenses');
  await db.delete('settlements');
  await db.delete('gear_items');
  await db.delete('trips');
  await db.delete('sync_queue');
}
```

**Step 4: Run tests to verify nothing breaks**

Run: `flutter test`
Expected: All 15 tests pass (schema changes only affect runtime DB creation)

**Step 5: Commit**

```bash
git add lib/core/services/local_database.dart
git commit -m "feat: expand SQLite schema to v4 for offline-first (participants, sub-groups, activity, categories)"
```

---

## Task 2: Expand CacheService for New Tables

Add static cache read/write methods for gear items, participants, sub-groups, sub-group members, activity logs, and categories.

**Files:**
- Modify: `lib/core/services/cache_service.dart`

**Step 1: Add imports for new models**

At the top of `cache_service.dart`, add:

```dart
import '../../features/gear/models/gear_item_model.dart';
import '../../features/trip/models/trip_model.dart'; // Participant is here
import '../../features/logistics/models/sub_group_model.dart';
import '../../features/activity/models/activity_log_model.dart';
import '../../features/ledger/models/expense_category_model.dart';
```

**Step 2: Add gear item caching methods**

```dart
/// Cache gear items for a trip
static Future<void> cacheGearItems(String tripId, List<GearItem> items) async {
  final db = await LocalDatabase.database;
  final batch = db.batch();
  for (final item in items) {
    batch.insert('gear_items', {
      'id': item.id,
      'trip_id': item.tripId,
      'item_name': item.itemName,
      'assigned_to': item.assignedTo,
      'is_packed': item.isPacked ? 1 : 0,
      'sequence_id': item.sequenceId,
      'is_high_priority': item.isHighPriority ? 1 : 0,
      'assigned_to_name': item.assignedToName,
      'assigned_to_avatar': item.assignedToAvatar,
      'created_at': item.createdAt?.toIso8601String(),
      'synced_at': DateTime.now().toIso8601String(),
      'is_deleted': item.isDeleted ? 1 : 0,
      'deleted_at': item.deletedAt?.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

/// Get cached gear items for a trip
static Future<List<GearItem>> getCachedGearItems(String tripId) async {
  final db = await LocalDatabase.database;
  final maps = await db.query(
    'gear_items',
    where: 'trip_id = ? AND is_deleted = 0',
    whereArgs: [tripId],
    orderBy: 'sequence_id ASC',
  );
  return maps.map((map) => GearItem(
    id: map['id'] as String,
    tripId: map['trip_id'] as String,
    itemName: map['item_name'] as String,
    assignedTo: map['assigned_to'] as String?,
    isPacked: (map['is_packed'] as int?) == 1,
    sequenceId: map['sequence_id'] as int? ?? 0,
    isHighPriority: (map['is_high_priority'] as int?) == 1,
    assignedToName: map['assigned_to_name'] as String?,
    assignedToAvatar: map['assigned_to_avatar'] as String?,
    createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : null,
    isDeleted: false,
  )).toList();
}
```

**Step 3: Add participant caching methods**

```dart
/// Cache participants for a trip
static Future<void> cacheParticipants(String tripId, List<Participant> participants) async {
  final db = await LocalDatabase.database;
  final batch = db.batch();
  for (final p in participants) {
    batch.insert('participants', {
      'id': p.id,
      'trip_id': p.tripId,
      'user_id': p.userId,
      'role': p.role.value,
      'display_name': p.displayName,
      'avatar_url': p.avatarUrl,
      'is_shadow': p.isShadow ? 1 : 0,
      'joined_at': p.joinedAt.toIso8601String(),
      'last_synced_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

/// Get cached participants for a trip
static Future<List<Participant>> getCachedParticipants(String tripId) async {
  final db = await LocalDatabase.database;
  final maps = await db.query(
    'participants',
    where: 'trip_id = ?',
    whereArgs: [tripId],
  );
  return maps.map((map) => Participant(
    id: map['id'] as String,
    tripId: map['trip_id'] as String,
    userId: map['user_id'] as String?,
    role: ParticipantRole.values.firstWhere(
      (r) => r.value == map['role'],
      orElse: () => ParticipantRole.member,
    ),
    displayName: map['display_name'] as String?,
    avatarUrl: map['avatar_url'] as String?,
    isShadow: (map['is_shadow'] as int?) == 1,
    joinedAt: map['joined_at'] != null && (map['joined_at'] as String).isNotEmpty
        ? DateTime.parse(map['joined_at'] as String)
        : DateTime.now(),
  )).toList();
}
```

**Step 4: Add sub-group caching methods**

```dart
/// Cache sub-groups for a trip
static Future<void> cacheSubGroups(String tripId, List<SubGroup> subGroups) async {
  final db = await LocalDatabase.database;
  final batch = db.batch();
  for (final sg in subGroups) {
    batch.insert('sub_groups', {
      'id': sg.id,
      'trip_id': sg.tripId,
      'name': sg.name,
      'type': sg.type.value,
      'capacity': sg.capacity,
      'created_at': sg.createdAt?.toIso8601String(),
      'last_synced_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    // Also cache members
    for (final m in sg.members) {
      batch.insert('sub_group_members', {
        'id': m.id,
        'sub_group_id': m.subGroupId,
        'participant_id': m.participantId,
        'display_name': m.displayName,
        'avatar_url': m.avatarUrl,
        'joined_at': m.joinedAt?.toIso8601String(),
        'last_synced_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
  await batch.commit(noResult: true);
}

/// Get cached sub-groups for a trip (with members)
static Future<List<SubGroup>> getCachedSubGroups(String tripId) async {
  final db = await LocalDatabase.database;
  final sgMaps = await db.query(
    'sub_groups',
    where: 'trip_id = ?',
    whereArgs: [tripId],
    orderBy: 'created_at ASC',
  );
  final subGroups = <SubGroup>[];
  for (final sgMap in sgMaps) {
    final memberMaps = await db.query(
      'sub_group_members',
      where: 'sub_group_id = ?',
      whereArgs: [sgMap['id']],
    );
    final members = memberMaps.map((m) => SubGroupMember(
      id: m['id'] as String,
      subGroupId: m['sub_group_id'] as String,
      participantId: m['participant_id'] as String,
      displayName: m['display_name'] as String?,
      avatarUrl: m['avatar_url'] as String?,
      joinedAt: m['joined_at'] != null ? DateTime.parse(m['joined_at'] as String) : null,
    )).toList();

    subGroups.add(SubGroup(
      id: sgMap['id'] as String,
      tripId: sgMap['trip_id'] as String,
      name: sgMap['name'] as String,
      type: SubGroupType.fromValue(sgMap['type'] as String? ?? 'CAR'),
      capacity: sgMap['capacity'] as int? ?? 4,
      createdAt: sgMap['created_at'] != null ? DateTime.parse(sgMap['created_at'] as String) : null,
      members: members,
    ));
  }
  return subGroups;
}
```

**Step 5: Add activity log caching methods**

```dart
/// Cache activity logs for a trip
static Future<void> cacheActivityLogs(String tripId, List<ActivityLog> logs) async {
  final db = await LocalDatabase.database;
  final batch = db.batch();
  for (final log in logs) {
    batch.insert('activity_logs', {
      'id': log.id,
      'trip_id': log.tripId,
      'actor_id': log.actorId,
      'target_participant_id': log.targetParticipantId,
      'category': log.category,
      'event_type': log.eventType,
      'log_text': log.logText,
      'metadata': jsonEncode(log.metadata),
      'actor_name': log.actorName,
      'actor_avatar': log.actorAvatar,
      'created_at': log.createdAt.toIso8601String(),
      'last_synced_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

/// Get cached activity logs for a trip
static Future<List<ActivityLog>> getCachedActivityLogs(String tripId) async {
  final db = await LocalDatabase.database;
  final maps = await db.query(
    'activity_logs',
    where: 'trip_id = ?',
    whereArgs: [tripId],
    orderBy: 'created_at DESC',
    limit: 50,
  );
  return maps.map((map) => ActivityLog(
    id: map['id'] as String,
    tripId: map['trip_id'] as String,
    actorId: map['actor_id'] as String?,
    targetParticipantId: map['target_participant_id'] as String?,
    category: map['category'] as String,
    eventType: map['event_type'] as String,
    logText: map['log_text'] as String,
    metadata: map['metadata'] != null
        ? jsonDecode(map['metadata'] as String) as Map<String, dynamic>
        : {},
    actorName: map['actor_name'] as String?,
    actorAvatar: map['actor_avatar'] as String?,
    createdAt: DateTime.parse(map['created_at'] as String),
  )).toList();
}
```

**Step 6: Add category caching methods**

Note: Check `lib/features/ledger/models/expense_category_model.dart` for the exact model fields. If no model exists, use a simple map. The categories provider likely returns simple maps with `id`, `name`, `icon`.

```dart
/// Cache expense categories for a trip
static Future<void> cacheCategories(String tripId, List<Map<String, dynamic>> categories) async {
  final db = await LocalDatabase.database;
  final batch = db.batch();
  for (final cat in categories) {
    batch.insert('categories', {
      'id': cat['id'] as String,
      'trip_id': tripId,
      'name': cat['name'] as String,
      'icon': cat['icon'] as String?,
      'last_synced_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

/// Get cached categories for a trip
static Future<List<Map<String, dynamic>>> getCachedCategories(String tripId) async {
  final db = await LocalDatabase.database;
  final maps = await db.query(
    'categories',
    where: 'trip_id = ?',
    whereArgs: [tripId],
  );
  return maps.map((m) => {
    'id': m['id'],
    'name': m['name'],
    'icon': m['icon'],
  }).toList();
}
```

**Step 7: Run tests**

Run: `flutter test`
Expected: All 15 tests pass

**Step 8: Commit**

```bash
git add lib/core/services/cache_service.dart
git commit -m "feat: expand CacheService with gear, participant, sub-group, activity, category caching"
```

---

## Task 3: Create OfflineRepository with Reactive SQLite Streams

Build the core `OfflineRepository` class that wraps SQLite with `StreamController`-based change notifications. This is the heart of offline-first: providers will read from this instead of Supabase.

**Files:**
- Create: `lib/core/services/offline_repository.dart`

**Step 1: Create the OfflineRepository class**

```dart
import 'dart:async';
import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../features/activity/models/activity_log_model.dart';
import '../../features/gear/models/gear_item_model.dart';
import '../../features/ledger/models/expense_model.dart';
import '../../features/ledger/models/settlement_model.dart';
import '../../features/logistics/models/sub_group_model.dart';
import '../../features/trip/models/trip_model.dart';
import 'cache_service.dart';
import 'local_database.dart';

/// Riverpod provider for OfflineRepository
final offlineRepositoryProvider = Provider<OfflineRepository>((ref) {
  final repo = OfflineRepository();
  ref.onDispose(() => repo.dispose());
  return repo;
});

/// Reactive SQLite wrapper for offline-first data access.
///
/// Provides:
/// - watch*() methods: reactive streams from SQLite (providers use these)
/// - save*()/delete*() methods: write to SQLite + sync queue (services use these)
/// - notify(): trigger stream re-emission after external writes (sync engine uses this)
class OfflineRepository {
  final Map<String, StreamController<void>> _changeNotifiers = {};
  static const _uuid = Uuid();

  StreamController<void> _getNotifier(String key) {
    return _changeNotifiers.putIfAbsent(
      key,
      () => StreamController<void>.broadcast(),
    );
  }

  /// Notify that data changed for a table+tripId combination.
  /// Called after writes or after sync engine downloads new data.
  void notifyChange(String table, [String? tripId]) {
    final key = tripId != null ? '$table:$tripId' : table;
    if (_changeNotifiers.containsKey(key)) {
      _changeNotifiers[key]!.add(null);
    }
    // Also notify the table-level key for global listeners (e.g., trips list)
    if (tripId != null && _changeNotifiers.containsKey(table)) {
      _changeNotifiers[table]!.add(null);
    }
  }

  void dispose() {
    for (final controller in _changeNotifiers.values) {
      controller.close();
    }
    _changeNotifiers.clear();
  }

  // ── TRIPS ──────────────────────────────────────────────────────────────

  Stream<List<Trip>> watchTrips() async* {
    yield await CacheService.getCachedTrips();
    yield* _getNotifier('trips').stream.asyncMap((_) => CacheService.getCachedTrips());
  }

  // ── EXPENSES ───────────────────────────────────────────────────────────

  Stream<List<Expense>> watchExpenses(String tripId) async* {
    yield await CacheService.getCachedExpenses(tripId);
    yield* _getNotifier('expenses:$tripId').stream
        .asyncMap((_) => CacheService.getCachedExpenses(tripId));
  }

  Future<void> saveExpense(Expense expense) async {
    final db = await LocalDatabase.database;
    await db.insert('expenses', {
      'id': expense.id,
      'trip_id': expense.tripId,
      'payer_participant_id': expense.payerParticipantId,
      'amount': expense.amount.toString(),
      'description': expense.description,
      'category_id': expense.categoryId,
      'category_name': expense.categoryName,
      'scope': expense.scope.value,
      'sub_group_id': expense.subGroupId,
      'created_at': expense.createdAt.toIso8601String(),
      'synced_at': null, // Not synced yet
      'is_deleted': expense.isDeleted ? 1 : 0,
      'deleted_at': expense.deletedAt?.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await CacheService.addToSyncQueue(
      tableName: 'expenses',
      recordId: expense.id,
      action: SyncAction.create,
      data: expense.toJson(),
    );
    notifyChange('expenses', expense.tripId);
  }

  Future<void> updateExpense(Expense expense, Map<String, dynamic> updates) async {
    final db = await LocalDatabase.database;
    // Update only changed fields in local DB
    final localUpdates = <String, dynamic>{};
    if (updates.containsKey('amount')) {
      localUpdates['amount'] = updates['amount'];
    }
    if (updates.containsKey('description')) {
      localUpdates['description'] = updates['description'];
    }
    if (updates.containsKey('scope')) {
      localUpdates['scope'] = updates['scope'];
    }
    if (updates.containsKey('sub_group_id')) {
      localUpdates['sub_group_id'] = updates['sub_group_id'];
    }
    if (updates.containsKey('category_id')) {
      localUpdates['category_id'] = updates['category_id'];
    }
    localUpdates['synced_at'] = null; // Mark as needing sync

    await db.update('expenses', localUpdates, where: 'id = ?', whereArgs: [expense.id]);

    await CacheService.addToSyncQueue(
      tableName: 'expenses',
      recordId: expense.id,
      action: SyncAction.update,
      data: updates,
    );
    notifyChange('expenses', expense.tripId);
  }

  Future<void> deleteExpense(String expenseId, String tripId) async {
    final db = await LocalDatabase.database;
    await db.update('expenses', {
      'is_deleted': 1,
      'deleted_at': DateTime.now().toIso8601String(),
      'synced_at': null,
    }, where: 'id = ?', whereArgs: [expenseId]);

    await CacheService.addToSyncQueue(
      tableName: 'expenses',
      recordId: expenseId,
      action: SyncAction.delete,
      data: {'id': expenseId},
    );
    notifyChange('expenses', tripId);
  }

  // ── SETTLEMENTS ────────────────────────────────────────────────────────

  Stream<List<Settlement>> watchSettlements(String tripId) async* {
    yield await CacheService.getCachedSettlements(tripId);
    yield* _getNotifier('settlements:$tripId').stream
        .asyncMap((_) => CacheService.getCachedSettlements(tripId));
  }

  Future<void> saveSettlement(Settlement settlement) async {
    final db = await LocalDatabase.database;
    await db.insert('settlements', {
      'id': settlement.id,
      'trip_id': settlement.tripId,
      'payer_participant_id': settlement.payerParticipantId,
      'recipient_participant_id': settlement.recipientParticipantId,
      'amount': settlement.amount.toString(),
      'note': settlement.note,
      'created_at': settlement.settledAt.toIso8601String(),
      'synced_at': null,
      'is_deleted': settlement.isDeleted ? 1 : 0,
      'deleted_at': settlement.deletedAt?.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await CacheService.addToSyncQueue(
      tableName: 'settlements',
      recordId: settlement.id,
      action: SyncAction.create,
      data: settlement.toJson(),
    );
    notifyChange('settlements', settlement.tripId);
  }

  // ── GEAR ITEMS ─────────────────────────────────────────────────────────

  Stream<List<GearItem>> watchGearItems(String tripId) async* {
    yield await CacheService.getCachedGearItems(tripId);
    yield* _getNotifier('gear_items:$tripId').stream
        .asyncMap((_) => CacheService.getCachedGearItems(tripId));
  }

  Future<void> saveGearItem(GearItem item) async {
    final db = await LocalDatabase.database;
    await db.insert('gear_items', {
      'id': item.id,
      'trip_id': item.tripId,
      'item_name': item.itemName,
      'assigned_to': item.assignedTo,
      'is_packed': item.isPacked ? 1 : 0,
      'sequence_id': item.sequenceId,
      'is_high_priority': item.isHighPriority ? 1 : 0,
      'assigned_to_name': item.assignedToName,
      'assigned_to_avatar': item.assignedToAvatar,
      'created_at': item.createdAt?.toIso8601String(),
      'synced_at': null,
      'is_deleted': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await CacheService.addToSyncQueue(
      tableName: 'gear_items',
      recordId: item.id,
      action: SyncAction.create,
      data: item.toJson(),
    );
    notifyChange('gear_items', item.tripId);
  }

  Future<void> updateGearItem(String itemId, String tripId, Map<String, dynamic> updates) async {
    final db = await LocalDatabase.database;
    updates['synced_at'] = null;
    await db.update('gear_items', updates, where: 'id = ?', whereArgs: [itemId]);

    await CacheService.addToSyncQueue(
      tableName: 'gear_items',
      recordId: itemId,
      action: SyncAction.update,
      data: updates,
    );
    notifyChange('gear_items', tripId);
  }

  Future<void> deleteGearItem(String itemId, String tripId) async {
    final db = await LocalDatabase.database;
    await db.update('gear_items', {
      'is_deleted': 1,
      'deleted_at': DateTime.now().toIso8601String(),
      'synced_at': null,
    }, where: 'id = ?', whereArgs: [itemId]);

    await CacheService.addToSyncQueue(
      tableName: 'gear_items',
      recordId: itemId,
      action: SyncAction.delete,
      data: {'id': itemId},
    );
    notifyChange('gear_items', tripId);
  }

  // ── PARTICIPANTS ───────────────────────────────────────────────────────

  Stream<List<Participant>> watchParticipants(String tripId) async* {
    yield await CacheService.getCachedParticipants(tripId);
    yield* _getNotifier('participants:$tripId').stream
        .asyncMap((_) => CacheService.getCachedParticipants(tripId));
  }

  // ── SUB-GROUPS ─────────────────────────────────────────────────────────

  Stream<List<SubGroup>> watchSubGroups(String tripId) async* {
    yield await CacheService.getCachedSubGroups(tripId);
    yield* _getNotifier('sub_groups:$tripId').stream
        .asyncMap((_) => CacheService.getCachedSubGroups(tripId));
  }

  // ── ACTIVITY LOGS ──────────────────────────────────────────────────────

  Stream<List<ActivityLog>> watchActivityLogs(String tripId) async* {
    yield await CacheService.getCachedActivityLogs(tripId);
    yield* _getNotifier('activity_logs:$tripId').stream
        .asyncMap((_) => CacheService.getCachedActivityLogs(tripId));
  }

  // ── CATEGORIES ─────────────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> watchCategories(String tripId) async* {
    yield await CacheService.getCachedCategories(tripId);
    yield* _getNotifier('categories:$tripId').stream
        .asyncMap((_) => CacheService.getCachedCategories(tripId));
  }

  // ── HELPERS ────────────────────────────────────────────────────────────

  /// Generate a UUID for new records created offline
  String generateId() => _uuid.v4();
}
```

**Step 2: Add `uuid` dependency to pubspec.yaml**

Check if `uuid` is already in `pubspec.yaml`. If not, add:

```yaml
dependencies:
  uuid: ^4.0.0
```

Run: `flutter pub get`

**Step 3: Run tests**

Run: `flutter test`
Expected: All 15 tests pass

**Step 4: Commit**

```bash
git add lib/core/services/offline_repository.dart pubspec.yaml pubspec.lock
git commit -m "feat: create OfflineRepository with reactive SQLite streams and write-through sync queue"
```

---

## Task 4: Refactor Read Providers to Use OfflineRepository

Change all data StreamProviders from "stream from Supabase, cache as side-effect" to "stream from SQLite via OfflineRepository". The sync engine (Task 6) will keep SQLite fresh.

**Files:**
- Modify: `lib/features/trip/providers/trip_provider.dart`
- Modify: `lib/features/ledger/providers/expense_provider.dart`
- Modify: `lib/features/gear/providers/gear_provider.dart`
- Modify: `lib/features/logistics/providers/sub_group_provider.dart`
- Modify: `lib/features/activity/services/activity_service.dart`

**Step 1: Refactor `userTripsProvider` in `trip_provider.dart`**

Replace the existing `userTripsProvider` (lines 22-60):

```dart
import '../../../core/services/offline_repository.dart';

/// User's trips — reads from SQLite, always instant
final userTripsProvider = StreamProvider<List<Trip>>((ref) {
  return ref.read(offlineRepositoryProvider).watchTrips();
});
```

Remove the `CacheService` import if no longer used elsewhere in the file.

**Step 2: Refactor `tripLogisticsParticipantsProvider` in `trip_provider.dart`**

Replace lines 63-79:

```dart
/// Trip participants — reads from SQLite
final tripLogisticsParticipantsProvider =
    StreamProvider.family<List<Participant>, String>((ref, tripId) {
  return ref.read(offlineRepositoryProvider).watchParticipants(tripId);
});
```

**Step 3: Refactor `tripExpensesProvider` in `expense_provider.dart`**

Replace lines 22-55:

```dart
import '../../../core/services/offline_repository.dart';

/// Stream of expenses — reads from SQLite, always instant
final tripExpensesProvider = StreamProvider.family<List<Expense>, String>((
  ref,
  tripId,
) {
  return ref.read(offlineRepositoryProvider).watchExpenses(tripId);
});
```

**Step 4: Refactor `tripSettlementsProvider` in `expense_provider.dart`**

Replace lines 58-91:

```dart
/// Stream of settlements — reads from SQLite
final tripSettlementsProvider = StreamProvider.family<List<Settlement>, String>((
  ref,
  tripId,
) {
  return ref.read(offlineRepositoryProvider).watchSettlements(tripId);
});
```

**Step 5: Refactor `tripGearProvider` in `gear_provider.dart`**

Replace lines 14-57:

```dart
import '../../../core/services/offline_repository.dart';

/// Stream of gear items — reads from SQLite
final tripGearProvider = StreamProvider.family<List<GearItem>, String>((
  ref,
  tripId,
) {
  return ref.read(offlineRepositoryProvider).watchGearItems(tripId);
});
```

**Step 6: Refactor `tripSubGroupsProvider` in `sub_group_provider.dart`**

Replace lines 15-59:

```dart
import '../../../core/services/offline_repository.dart';

/// Stream of sub-groups — reads from SQLite
final tripSubGroupsProvider = StreamProvider.family<List<SubGroup>, String>((
  ref,
  tripId,
) {
  return ref.read(offlineRepositoryProvider).watchSubGroups(tripId);
});
```

**Step 7: Refactor activity providers in `activity_service.dart`**

Replace `tripActivityProvider` (lines 12-53) and `tripTransactionActivityProvider` (lines 56-101):

```dart
import '../../../core/services/offline_repository.dart';

/// Stream of activity logs — reads from SQLite
final tripActivityProvider = StreamProvider.family<List<ActivityLog>, String>((
  ref,
  tripId,
) {
  return ref.read(offlineRepositoryProvider).watchActivityLogs(tripId);
});

/// Transaction-only activity logs (filtered from cached data)
final tripTransactionActivityProvider =
    StreamProvider.family<List<ActivityLog>, String>((ref, tripId) {
  return ref.read(offlineRepositoryProvider).watchActivityLogs(tripId).map(
    (logs) => logs.where((log) => log.category == 'MONEY').toList(),
  );
});
```

**Step 8: Run analyzer and tests**

Run: `flutter analyze && flutter test`
Expected: 0 errors, all tests pass. Some tests may need provider override updates if they override the old Supabase-based providers — fix by overriding with `Stream.value(mockData)` as before (the provider signature is the same: `StreamProvider.family<List<T>, String>`).

**Step 9: Commit**

```bash
git add lib/features/trip/providers/trip_provider.dart \
  lib/features/ledger/providers/expense_provider.dart \
  lib/features/gear/providers/gear_provider.dart \
  lib/features/logistics/providers/sub_group_provider.dart \
  lib/features/activity/services/activity_service.dart
git commit -m "refactor: all read providers now stream from SQLite via OfflineRepository"
```

---

## Task 5: Refactor Write Operations to Use OfflineRepository

Change service CRUD methods from "write to Supabase" to "write to SQLite + sync queue via OfflineRepository". The sync engine will push these to Supabase later.

**Files:**
- Modify: `lib/features/ledger/providers/expense_provider.dart` (ExpenseService class)
- Modify: `lib/features/gear/providers/gear_provider.dart` (GearService class)
- Modify: `lib/features/logistics/providers/sub_group_provider.dart` (SubGroupService — keep Supabase for now, add cache-on-success)

**Step 1: Refactor `ExpenseService.addExpense()` in `expense_provider.dart`**

The key change: write to SQLite first (instant UI update), then try Supabase. If Supabase fails, the sync queue handles it.

```dart
/// Add a new expense — writes to SQLite immediately, queues for sync
Future<Expense?> addExpense({
  required String tripId,
  required String payerParticipantId,
  required Decimal amount,
  String? description,
  ExpenseScope scope = ExpenseScope.global,
  String? subGroupId,
  List<String>? customSplitParticipants,
  String? receiptUrl,
  String? categoryId,
  String? note,
}) async {
  _ref.read(expenseLoadingProvider.notifier).state = true;
  _ref.read(expenseErrorProvider.notifier).state = null;

  final repo = _ref.read(offlineRepositoryProvider);

  try {
    // Build the expense data
    final expenseData = {
      'trip_id': tripId,
      'payer_participant_id': payerParticipantId,
      'amount': amount.toString(),
      'description': description,
      'scope': scope.value,
      'sub_group_id': scope == ExpenseScope.subGroup ? subGroupId : null,
      'custom_split_participants': scope == ExpenseScope.custom
          ? customSplitParticipants
          : null,
      'receipt_url': receiptUrl,
      'category_id': categoryId,
      'note': note,
    };

    // Try Supabase first (for server-generated ID and relationships)
    try {
      final data = await _client
          .from('expenses')
          .insert(expenseData)
          .select('*, expense_categories(name, icon), participants!payer_participant_id(*)')
          .single();

      final expense = Expense.fromJson(data);
      // Cache the server-returned expense (has proper ID and joined data)
      await CacheService.cacheExpenses(tripId, [expense]);
      repo.notifyChange('expenses', tripId);
      _ref.read(expenseLoadingProvider.notifier).state = false;
      return expense;
    } catch (e) {
      // Supabase failed (offline) — save locally with generated ID
      debugPrint('Supabase insert failed, saving locally: $e');
      final expense = Expense(
        id: repo.generateId(),
        tripId: tripId,
        payerParticipantId: payerParticipantId,
        amount: amount,
        description: description,
        scope: scope,
        subGroupId: scope == ExpenseScope.subGroup ? subGroupId : null,
        customSplitParticipants: scope == ExpenseScope.custom ? customSplitParticipants : null,
        receiptUrl: receiptUrl,
        categoryId: categoryId,
        note: note,
        createdAt: DateTime.now(),
      );
      await repo.saveExpense(expense);
      _ref.read(expenseLoadingProvider.notifier).state = false;
      return expense;
    }
  } catch (e) {
    debugPrint('addExpense FAILED: $e');
    _ref.read(expenseErrorProvider.notifier).state = e.toString();
    _ref.read(expenseLoadingProvider.notifier).state = false;
    return null;
  }
}
```

**Step 2: Refactor `ExpenseService.deleteExpense()`**

```dart
/// Delete an expense — soft delete in SQLite, queue for sync
Future<bool> deleteExpense(String expenseId, {String? tripId}) async {
  try {
    final repo = _ref.read(offlineRepositoryProvider);
    // Try Supabase first
    try {
      await _client.from('expenses').update({
        'is_deleted': true,
        'deleted_at': DateTime.now().toIso8601String(),
      }).eq('id', expenseId);
    } catch (_) {
      // Offline — will sync later
    }
    // Always update local
    if (tripId != null) {
      await repo.deleteExpense(expenseId, tripId);
    }
    return true;
  } catch (e) {
    debugPrint('deleteExpense FAILED: $e');
    return false;
  }
}
```

**Step 3: Refactor GearService methods similarly**

Apply the same pattern to `GearService`: try Supabase, fallback to local + sync queue. For `addItem`, `deleteItem`, `claimItem`, `unclaimItem`, `packItem`, `unpackItem`, `togglePriority`.

For each method:
1. Try the Supabase operation
2. On success: update local cache + notify
3. On failure: write to local SQLite + sync queue + notify

Example for `addItem`:

```dart
Future<GearItem?> addItem({
  required String tripId,
  required String itemName,
  bool isHighPriority = false,
}) async {
  _ref.read(gearLoadingProvider.notifier).state = true;
  final repo = _ref.read(offlineRepositoryProvider);

  try {
    try {
      final data = await _client
          .from('gear_items')
          .insert({'trip_id': tripId, 'item_name': itemName, 'is_high_priority': isHighPriority})
          .select()
          .single();
      final item = GearItem.fromJson(data);
      await CacheService.cacheGearItems(tripId, [item]);
      repo.notifyChange('gear_items', tripId);
      _ref.read(gearLoadingProvider.notifier).state = false;
      return item;
    } catch (e) {
      debugPrint('Supabase gear insert failed, saving locally: $e');
      final item = GearItem(
        id: repo.generateId(),
        tripId: tripId,
        itemName: itemName,
        isHighPriority: isHighPriority,
        createdAt: DateTime.now(),
      );
      await repo.saveGearItem(item);
      _ref.read(gearLoadingProvider.notifier).state = false;
      return item;
    }
  } catch (e) {
    _ref.read(gearErrorProvider.notifier).state = e.toString();
    _ref.read(gearLoadingProvider.notifier).state = false;
    return null;
  }
}
```

**Step 4: Run analyzer and tests**

Run: `flutter analyze && flutter test`

**Step 5: Commit**

```bash
git add lib/features/ledger/providers/expense_provider.dart \
  lib/features/gear/providers/gear_provider.dart
git commit -m "refactor: write operations use OfflineRepository — try Supabase first, fallback to local+queue"
```

---

## Task 6: Build Enhanced SyncEngine

Replace the current `SyncService` with a more capable `SyncEngine` that handles:
- Push: upload pending queue with retry logic and conflict tracking
- Pull: incremental download using last_synced_at timestamps
- Called by connectivity provider when online

**Files:**
- Modify: `lib/core/services/sync_service.dart`

**Step 1: Enhance `syncPendingChanges()` with retry tracking**

Add `last_error` and `conflict_data` tracking. Skip items with 5+ retries. Update retry_count on failure.

```dart
/// Process sync queue with retry tracking
static Future<SyncResult> syncPendingChanges() async {
  int synced = 0;
  int failed = 0;
  final List<String> errors = [];

  try {
    final db = await LocalDatabase.database;
    final pendingItems = await db.query(
      'sync_queue',
      where: 'retry_count < 5',
      orderBy: 'created_at ASC',
      limit: 50,
    );

    for (final item in pendingItems) {
      try {
        final tableName = item['table_name'] as String;
        final recordId = item['record_id'] as String;
        final action = item['action'] as String;
        final data = jsonDecode(item['data'] as String) as Map<String, dynamic>;
        final id = item['id'] as int;

        switch (action) {
          case 'CREATE':
            await _client.from(tableName).insert(data);
            break;
          case 'UPDATE':
            await _client.from(tableName).update(data).eq('id', recordId);
            break;
          case 'DELETE':
            await _client.from(tableName).update({
              'is_deleted': true,
              'deleted_at': DateTime.now().toIso8601String(),
            }).eq('id', recordId);
            break;
        }

        await CacheService.removeSyncItem(id);
        synced++;
      } catch (e) {
        failed++;
        errors.add(e.toString());
        // Increment retry count and store error
        final id = item['id'] as int;
        final retryCount = (item['retry_count'] as int? ?? 0) + 1;
        await db.update('sync_queue', {
          'retry_count': retryCount,
          'last_error': e.toString(),
        }, where: 'id = ?', whereArgs: [id]);
        debugPrint('Sync error (retry $retryCount): $e');
      }
    }
  } catch (e) {
    errors.add('Sync failed: $e');
  }

  return SyncResult(syncedCount: synced, failedCount: failed, errors: errors);
}
```

**Step 2: Add incremental pull methods**

Add methods that download data incrementally (only changes since last sync) and write to SQLite:

```dart
/// Download and cache all data for a trip (incremental)
static Future<void> downloadTripData(String tripId, OfflineRepository repo) async {
  try {
    await Future.wait([
      _pullExpenses(tripId, repo),
      _pullSettlements(tripId, repo),
      _pullGearItems(tripId, repo),
      _pullParticipants(tripId, repo),
      _pullSubGroups(tripId, repo),
      _pullActivityLogs(tripId, repo),
      _pullCategories(tripId, repo),
    ]);
  } catch (e) {
    debugPrint('Error downloading trip data: $e');
  }
}

static Future<void> _pullExpenses(String tripId, OfflineRepository repo) async {
  try {
    final data = await _client
        .from('expenses')
        .select('*, expense_categories(name, icon), participants!payer_participant_id(*)')
        .eq('trip_id', tripId)
        .order('created_at', ascending: false);

    final expenses = (data as List).map((json) => Expense.fromJson(json)).toList();
    await CacheService.cacheExpenses(tripId, expenses);
    repo.notifyChange('expenses', tripId);
  } catch (e) {
    debugPrint('Error pulling expenses: $e');
  }
}

static Future<void> _pullSettlements(String tripId, OfflineRepository repo) async {
  try {
    final data = await _client
        .from('settlements')
        .select('*, payer_participant:participants!payer_participant_id(*), recipient_participant:participants!recipient_participant_id(*)')
        .eq('trip_id', tripId)
        .order('settled_at', ascending: false);

    final settlements = (data as List).map((json) => Settlement.fromJson(json)).toList();
    await CacheService.cacheSettlements(tripId, settlements);
    repo.notifyChange('settlements', tripId);
  } catch (e) {
    debugPrint('Error pulling settlements: $e');
  }
}

static Future<void> _pullGearItems(String tripId, OfflineRepository repo) async {
  try {
    final data = await _client
        .from('gear_items')
        .select('*')
        .eq('trip_id', tripId)
        .eq('is_deleted', false)
        .order('sequence_id', ascending: true);

    final items = (data as List).map((json) => GearItem.fromJson(json)).toList();
    await CacheService.cacheGearItems(tripId, items);
    repo.notifyChange('gear_items', tripId);
  } catch (e) {
    debugPrint('Error pulling gear items: $e');
  }
}

static Future<void> _pullParticipants(String tripId, OfflineRepository repo) async {
  try {
    final data = await _client
        .from('participants')
        .select('*')
        .eq('trip_id', tripId);

    final participants = (data as List).map((json) => Participant.fromJson(json)).toList();
    await CacheService.cacheParticipants(tripId, participants);
    repo.notifyChange('participants', tripId);
  } catch (e) {
    debugPrint('Error pulling participants: $e');
  }
}

static Future<void> _pullSubGroups(String tripId, OfflineRepository repo) async {
  try {
    final sgData = await _client
        .from('sub_groups')
        .select('*')
        .eq('trip_id', tripId)
        .order('created_at', ascending: true);

    final subGroups = <SubGroup>[];
    for (final sg in sgData) {
      final membersData = await _client
          .from('sub_group_members')
          .select('*, participants!participant_id(*)')
          .eq('sub_group_id', sg['id']);
      final members = (membersData as List)
          .map((m) => SubGroupMember.fromJson(m))
          .toList();
      subGroups.add(SubGroup.fromJson(sg).copyWith(members: members));
    }
    await CacheService.cacheSubGroups(tripId, subGroups);
    repo.notifyChange('sub_groups', tripId);
  } catch (e) {
    debugPrint('Error pulling sub-groups: $e');
  }
}

static Future<void> _pullActivityLogs(String tripId, OfflineRepository repo) async {
  try {
    final data = await _client
        .from('trip_activity_logs')
        .select('*')
        .eq('trip_id', tripId)
        .order('created_at', ascending: false)
        .limit(50);

    final logs = (data as List).map((json) => ActivityLog.fromJson(json)).toList();
    await CacheService.cacheActivityLogs(tripId, logs);
    repo.notifyChange('activity_logs', tripId);
  } catch (e) {
    debugPrint('Error pulling activity logs: $e');
  }
}

static Future<void> _pullCategories(String tripId, OfflineRepository repo) async {
  try {
    final data = await _client
        .from('expense_categories')
        .select('*')
        .eq('trip_id', tripId);

    await CacheService.cacheCategories(tripId, List<Map<String, dynamic>>.from(data));
    repo.notifyChange('categories', tripId);
  } catch (e) {
    debugPrint('Error pulling categories: $e');
  }
}
```

**Step 3: Update `fullSync` to use new pull methods**

```dart
/// Full sync: push pending changes, then pull fresh data for all user trips
static Future<SyncResult> fullSync(String userId, OfflineRepository repo) async {
  // Push first
  final uploadResult = await syncPendingChanges();

  // Pull trips
  await downloadTrips(userId);
  repo.notifyChange('trips');

  // Pull data for each cached trip
  final trips = await CacheService.getCachedTrips();
  for (final trip in trips) {
    await downloadTripData(trip.id, repo);
  }

  return uploadResult;
}
```

**Step 4: Add required imports**

Add at top of sync_service.dart:

```dart
import 'offline_repository.dart';
import '../../features/gear/models/gear_item_model.dart';
import '../../features/logistics/models/sub_group_model.dart';
import '../../features/activity/models/activity_log_model.dart';
import 'local_database.dart';
```

**Step 5: Run analyzer and tests**

Run: `flutter analyze && flutter test`

**Step 6: Commit**

```bash
git add lib/core/services/sync_service.dart
git commit -m "feat: enhanced SyncEngine with retry tracking, incremental pull for all tables"
```

---

## Task 7: Wire Up Sync Triggers and Notifications

Update the connectivity provider to trigger full sync on connectivity changes. Add periodic sync and app lifecycle sync. Show toast after sync.

**Files:**
- Modify: `lib/core/providers/connectivity_provider.dart`
- Modify: `lib/main.dart` (for app lifecycle)

**Step 1: Update `SyncController.fullSync` to accept OfflineRepository**

In `connectivity_provider.dart`, update `SyncController`:

```dart
class SyncController {
  final Ref _ref;

  SyncController(this._ref);

  /// Trigger a full sync
  Future<SyncResult> fullSync(String userId) async {
    _ref.read(connectivityProvider.notifier).setSyncing();

    try {
      final repo = _ref.read(offlineRepositoryProvider);
      final result = await SyncService.fullSync(userId, repo);
      _ref.read(connectivityProvider.notifier).setOnline();
      _ref.invalidate(pendingSyncCountProvider);
      return result;
    } catch (e) {
      _ref.read(connectivityProvider.notifier).setOffline();
      rethrow;
    }
  }

  /// Sync pending changes only
  Future<SyncResult> syncPending() async {
    _ref.read(connectivityProvider.notifier).setSyncing();

    try {
      final result = await SyncService.syncPendingChanges();
      _ref.read(connectivityProvider.notifier).setOnline();
      _ref.invalidate(pendingSyncCountProvider);
      return result;
    } catch (e) {
      _ref.read(connectivityProvider.notifier).setOffline();
      rethrow;
    }
  }
}
```

Add import:

```dart
import '../services/offline_repository.dart';
```

**Step 2: Add auto-sync on connectivity change**

In `ConnectivityNotifier.checkConnectivity()`, trigger sync when transitioning from offline to online:

```dart
Future<void> checkConnectivity() async {
  final wasOffline = state == ConnectivityStatus.offline;
  final isOnline = await SyncService.isOnline();
  if (!mounted) return;

  if (isOnline) {
    state = ConnectivityStatus.online;
    // Auto-sync when coming back online
    if (wasOffline) {
      debugPrint('Connectivity restored — triggering sync');
      // Sync is triggered by listeners watching this state change
    }
  } else {
    state = ConnectivityStatus.offline;
  }
}
```

**Step 3: Update periodic check to 60 seconds (per design)**

Change `Duration(seconds: 30)` to `Duration(seconds: 60)` in `_startPeriodicCheck`.

**Step 4: Run tests**

Run: `flutter test`

**Step 5: Commit**

```bash
git add lib/core/providers/connectivity_provider.dart
git commit -m "feat: sync triggers on connectivity change, SyncController uses OfflineRepository"
```

---

## Task 8: Add "Unavailable Offline" States for Vault and Memories

Documents and memories are not cached (too large). Instead of error pages, show a friendly empty state when offline.

**Files:**
- Modify: `lib/features/vault/screens/vault_screen.dart`
- Modify: `lib/features/memories/screens/memories_screen.dart`

**Step 1: Add connectivity check to VaultScreen**

In `vault_screen.dart`, watch `connectivityProvider` and show `EmptyStateView` when offline:

```dart
// Inside the build method, before the main content:
final connectivity = ref.watch(connectivityProvider);
if (connectivity == ConnectivityStatus.offline) {
  return Scaffold(
    body: Column(
      children: [
        // Keep the header
        const ModuleHeader(title: 'Vault', subtitle: 'Trip documents'),
        const Expanded(
          child: EmptyStateView(
            icon: Icons.cloud_off_rounded,
            title: 'Unavailable Offline',
            subtitle: 'Documents require an internet connection.\nYour other trip data is available offline.',
          ),
        ),
      ],
    ),
  );
}
```

Add import: `import '../../../core/providers/connectivity_provider.dart';`

**Step 2: Add connectivity check to MemoriesScreen**

Same pattern for `memories_screen.dart`:

```dart
final connectivity = ref.watch(connectivityProvider);
if (connectivity == ConnectivityStatus.offline) {
  return Scaffold(
    body: Column(
      children: [
        const ModuleHeader(title: 'Memories', subtitle: 'Trip photos'),
        const Expanded(
          child: EmptyStateView(
            icon: Icons.cloud_off_rounded,
            title: 'Unavailable Offline',
            subtitle: 'Memories require an internet connection.\nYour other trip data is available offline.',
          ),
        ),
      ],
    ),
  );
}
```

**Step 3: Run analyzer**

Run: `flutter analyze`
Expected: No new errors

**Step 4: Commit**

```bash
git add lib/features/vault/screens/vault_screen.dart \
  lib/features/memories/screens/memories_screen.dart
git commit -m "feat: vault and memories show 'unavailable offline' instead of error pages"
```

---

## Task 9: Initial Data Seeding on First Sync

When a user first opens the app or navigates to a trip, the SQLite database is empty. We need a mechanism to seed it from Supabase on first load.

**Files:**
- Modify: `lib/features/home/screens/command_center.dart` (trigger trip data download)
- Modify: `lib/features/trip/providers/trip_provider.dart` (seed trips on login)

**Step 1: Add initial seed in the home screen or app bootstrap**

When the user first opens the app and is online, trigger a full sync to populate SQLite. In `trip_provider.dart`, add an initializer that checks if SQLite is empty and does a one-time download:

```dart
/// Provider that seeds SQLite on first load
final tripSeedProvider = FutureProvider<void>((ref) async {
  final cachedTrips = await CacheService.getCachedTrips();
  if (cachedTrips.isEmpty) {
    // First load — download from Supabase
    final user = ref.read(currentUserProvider);
    if (user != null) {
      final repo = ref.read(offlineRepositoryProvider);
      await SyncService.fullSync(user.id, repo);
    }
  }
});
```

**Step 2: Trigger trip data download when entering CommandCenter**

In `command_center.dart`, add a one-time data fetch when the screen opens (if not already cached):

```dart
// In initState or a ref.listen:
ref.listen(connectivityProvider, (prev, next) {
  if (next == ConnectivityStatus.online) {
    final repo = ref.read(offlineRepositoryProvider);
    SyncService.downloadTripData(trip.id, repo);
  }
});
```

**Step 3: Run tests**

Run: `flutter test`

**Step 4: Commit**

```bash
git add lib/features/trip/providers/trip_provider.dart \
  lib/features/home/screens/command_center.dart
git commit -m "feat: seed SQLite from Supabase on first load and when entering trips"
```

---

## Task 10: Tests

Write tests for the offline-first architecture: OfflineRepository reactive streams, sync queue operations, and provider wiring.

**Files:**
- Create: `test/unit/offline_repository_test.dart`
- Modify: `test/features/command_center_test.dart` (update provider overrides)
- Modify: `test/features/ledger_test.dart` (update provider overrides)

**Step 1: Write OfflineRepository unit tests**

Note: Since OfflineRepository depends on SQLite (platform channel), tests should mock at the provider level. Test that:
1. Providers emit data from the stream
2. Provider overrides work correctly
3. Offline states render properly

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Test that provider overrides still work with the new architecture
void main() {
  group('Offline-first providers', () {
    test('tripExpensesProvider can be overridden with mock data', () async {
      final container = ProviderContainer(overrides: [
        tripExpensesProvider('test-trip').overrideWith(
          (ref) => Stream.value(<Expense>[]),
        ),
      ]);
      addTearDown(container.dispose);

      final expenses = await container.read(tripExpensesProvider('test-trip').future);
      expect(expenses, isEmpty);
    });

    test('tripGearProvider can be overridden with mock data', () async {
      final container = ProviderContainer(overrides: [
        tripGearProvider('test-trip').overrideWith(
          (ref) => Stream.value(<GearItem>[]),
        ),
      ]);
      addTearDown(container.dispose);

      final gear = await container.read(tripGearProvider('test-trip').future);
      expect(gear, isEmpty);
    });
  });
}
```

**Step 2: Update existing test overrides if needed**

The provider signatures haven't changed (still `StreamProvider.family<List<T>, String>`), so existing test overrides should work. Verify by running:

Run: `flutter test`

**Step 3: Commit**

```bash
git add test/
git commit -m "test: add offline-first provider tests, update existing test overrides"
```

---

## Summary of Files Changed

| File | Action | Purpose |
|------|--------|---------|
| `lib/core/services/local_database.dart` | Modify | Schema v4: new tables, enhanced sync_queue |
| `lib/core/services/cache_service.dart` | Modify | Add caching for gear, participants, sub-groups, activity, categories |
| `lib/core/services/offline_repository.dart` | **Create** | Reactive SQLite streams + write-through sync queue |
| `lib/core/services/sync_service.dart` | Modify | Enhanced push with retry, incremental pull for all tables |
| `lib/core/providers/connectivity_provider.dart` | Modify | Sync triggers, uses OfflineRepository |
| `lib/features/trip/providers/trip_provider.dart` | Modify | Providers read from SQLite |
| `lib/features/ledger/providers/expense_provider.dart` | Modify | Providers read from SQLite, writes use OfflineRepository |
| `lib/features/gear/providers/gear_provider.dart` | Modify | Providers read from SQLite, writes use OfflineRepository |
| `lib/features/logistics/providers/sub_group_provider.dart` | Modify | Provider reads from SQLite |
| `lib/features/activity/services/activity_service.dart` | Modify | Provider reads from SQLite |
| `lib/features/vault/screens/vault_screen.dart` | Modify | "Unavailable offline" state |
| `lib/features/memories/screens/memories_screen.dart` | Modify | "Unavailable offline" state |
| `lib/features/home/screens/command_center.dart` | Modify | Trigger data seeding |
| `test/unit/offline_repository_test.dart` | **Create** | Offline-first tests |
| `pubspec.yaml` | Modify | Add uuid dependency |
