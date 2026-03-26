# Phase 4: Firestore Repository Layer - Research

**Researched:** 2026-03-26
**Domain:** Firestore service layer, offline-first writes, Supabase bridge teardown, SQLite balance cache
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Migration Strategy
- **D-01:** Module-by-module migration. Each module is a self-contained migration step.
- **D-02:** Financial-first order: Expenses → Settlements → Gear → SubGroups → Vault → Memories → Activity. Hardest modules first.
- **D-03:** Hard cutover per module. When a module migrates, the old Supabase service code is deleted immediately. No dual-write period.
- **D-04:** SyncService and sync_queue deleted only after ALL modules are migrated, as a final cleanup step.

#### Repository Abstraction
- **D-05:** Per-feature Firestore services with a shared `FirestoreRepository` base class. Each module gets its own service (e.g., `ExpenseService`) that extends/uses `FirestoreRepository`. The base class owns the `FirebaseFirestore` instance.
- **D-06:** Existing `GroupService` and `EventService` refactored to use the same base class.
- **D-07:** Services keep existing names (ExpenseService, GearService, etc.) — rewired internally to Firestore. Providers and screens don't change their imports.
- **D-08:** Old Supabase service files deleted immediately when a module migrates.
- **D-09:** Firestore services live inside feature folders (e.g., `lib/features/ledger/services/expense_service.dart`). Base class in `lib/core/services/firestore_repository.dart`.

#### Firestore Data Model
- **D-10:** Module data stored as subcollections under events: `groups/{groupId}/events/{eventId}/expenses/{expenseId}`.
- **D-11:** Security rules: any event participant can read and write module data.
- **D-12:** Money serialization: integer fils in Firestore, Decimal conversion at the boundary. Each document carries `{amountFils: int, currency: String}`.

#### Provider Migration
- **D-13:** Providers switch from SQLite-backed streams (`OfflineRepository.watch*`) to Firestore snapshot listeners.

#### SQLite Role
- **D-14:** SQLite retained narrowly for BalanceCalculator queries only.
- **D-15:** Firestore snapshot listeners for expenses and settlements write to SQLite as a side effect.
- **D-16:** `OfflineRepository` slimmed down to balance-related SQLite queries only. Renamed to reflect narrow purpose (e.g., `BalanceCacheRepository`).

#### Bridge Teardown
- **D-17:** Supabase bridge removed in this phase.
- **D-18:** Existing events with Supabase data lazily migrated on access: if module data doesn't exist in Firestore, pull from Supabase via `bridgeTripId` and write to Firestore.

### Claude's Discretion
- FirestoreRepository base class design (abstract class, mixin, or utility)
- Firestore snapshot listener implementation details (stream transformers, error handling)
- SQLite write strategy from Firestore listeners (batch vs individual inserts)
- Lazy migration implementation (migration service, error handling, progress tracking)
- Security rule implementation details for module subcollections
- BalanceCalculator interface changes (if any) to work with new SQLite schema
- ConnectivityNotifier changes (currently pings Supabase to check online status)
- CacheService cleanup scope (which methods to keep/remove)
- Exact order within the financial cluster (expenses before settlements, or together)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MIG-01 | All per-event writes (expenses, settlements, gear, etc.) go through Firestore instead of Supabase | D-09: per-feature services in feature folders; D-10: subcollection path `groups/{groupId}/events/{eventId}/{module}/{docId}`; FirestoreRepository base class provides the `_db` instance |
| MIG-02 | Firestore realtime listeners replace Supabase Realtime subscriptions | Pattern: `collection.snapshots().map(...)` returns a `Stream<List<T>>` — identical contract to OfflineRepository.watch*(); providers swap the stream source |
| MIG-03 | Firestore offline persistence replaces manual sync queue (SyncService deleted, not ported) | Firestore offline persistence already enabled in Phase 1 (`persistenceEnabled: true`); Firestore queues writes automatically when offline; SyncService + sync_queue table deleted after all modules migrate |
| MIG-04 | SQLite retained for fast local reads and balance computation queries | BalanceCalculator lives in expense_provider.dart and operates on in-memory List<Expense>/List<Settlement> passed by providers; providers must continue providing that data — sourced from Firestore snapshots writing to SQLite as side-effect |
| MIG-05 | `FirestoreRepository` is the single Firestore contact point | D-05/D-09: `lib/core/services/firestore_repository.dart` base class; all module services extend it; GroupService and EventService refactored to use same base class |
</phase_requirements>

---

## Summary

Phase 4 replaces the Supabase-backed module services (expenses, settlements, gear, sub-groups, vault, memories, activity) with Firestore-backed services. The Supabase bridge introduced in Phase 3 is torn down. The manual sync queue (`SyncService` + `sync_queue` SQLite table) is deleted — Firestore's built-in offline write queue handles offline writes automatically. SQLite is retained narrowly: Firestore snapshot listeners write expense and settlement data into SQLite as a side effect, and the `BalanceCalculator` reads from those SQLite tables.

The key technical insight is that Firestore snapshot listeners return a `Stream<QuerySnapshot>` which maps cleanly to the same `Stream<List<T>>` contract that the existing Riverpod `StreamProvider.family` providers already consume. The migration is mechanical: swap the stream source from `OfflineRepository.watch*()` to `collection.snapshots().map(...)`. The module-by-module approach (D-01 through D-03) means each migration is a self-contained unit with its own test coverage before moving to the next.

The `BalanceCalculator` is a pure in-memory function in `expense_provider.dart` — it receives `List<Expense>`, `List<Settlement>`, `List<Participant>`, `List<SubGroup>` and computes balances without touching SQLite directly. The SQLite role (D-14) means expense/settlement Firestore listeners write to SQLite, and the providers that feed `BalanceCalculator` read from those SQLite tables (or directly from Firestore — see Architecture Patterns for the recommended approach).

**Primary recommendation:** Implement `FirestoreRepository` base class first (Wave 0), then migrate modules in the order prescribed by D-02, deleting Supabase service code immediately after each module's tests pass.

---

## Project Constraints (from CLAUDE.md)

| Directive | Impact on This Phase |
|-----------|---------------------|
| Immutability is non-negotiable — always create new objects, never mutate | All Firestore models must use `copyWith()` / immutable constructors; no in-place map mutation |
| File size: 200-400 lines typical, 800 max | Each module service should be one focused file; FirestoreRepository base class should be thin |
| Functions < 50 lines | Each service method (addExpense, updateExpense, deleteExpense) stays under 50 lines |
| TDD mandatory — 80%+ coverage, write tests first | Every new Firestore service gets tests against `FakeFirebaseFirestore` before implementation |
| `--dart-define-from-file=config.json` required for all runs | No change to run commands; Firebase is already initialized |
| GSD workflow enforcement — no direct edits outside GSD workflow | All changes go through `/gsd:execute-phase` |

---

## Standard Stack

### Core (no version changes required)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `cloud_firestore` | `^6.2.0` (current) | All module reads/writes | Already in project; offline persistence enabled; Phase 1 validated |
| `firebase_auth` | `^6.3.0` (current) | Auth UID for security rules | Already in project; `FirebaseConfig.currentUser?.uid` established pattern |
| `firebase_core` | `^4.6.0` (current) | SDK foundation | Already in project; no change |
| `flutter_riverpod` | `^2.4.9` (current) | State management | Stay on 2.x per pre-phase-1 decision; 3.x is future milestone |
| `sqflite` | `^2.4.2` (current) | Balance cache reads | Retained narrowly for BalanceCalculator; no schema changes needed |
| `decimal` | `^3.2.4` (current) | Money precision | All OMR amounts stay as Decimal client-side; convert via MoneySerializer |
| `fake_cloud_firestore` | `^4.1.0+1` (current) | Test Firestore | Already in project; used in event_service_test.dart as the established test pattern |
| `mocktail` | `^1.0.4` (current) | Mock non-Firestore | Already in project |
| `firebase_auth_mocks` | `^0.15.1` (current) | Mock Firebase auth | Already in project |

### No New Dependencies Required

Phase 4 is a migration inside the existing stack. No new packages are needed. The established pattern from Phase 3 (`EventService.withFirestore` + `FakeFirebaseFirestore`) is the template for all new services.

---

## Architecture Patterns

### Recommended Project Structure (additions only)

```
lib/
├── core/
│   └── services/
│       ├── firestore_repository.dart    # NEW: base class (D-05, D-09)
│       ├── balance_cache_repository.dart # RENAMED from offline_repository.dart (D-16)
│       ├── sync_service.dart            # DELETED after all modules migrate (D-04)
│       ├── offline_repository.dart      # DELETED after all modules migrate (D-16)
│       └── cache_service.dart           # TRIMMED: remove sync_queue + trip methods
├── features/
│   ├── ledger/
│   │   └── services/
│   │       ├── expense_service.dart     # NEW: Firestore CRUD (moved from providers/expense_provider.dart)
│   │       └── settlement_service.dart  # REPLACED: Firestore CRUD
│   ├── gear/
│   │   └── services/
│   │       └── gear_service.dart        # NEW: extracted from providers/gear_provider.dart
│   ├── logistics/
│   │   └── services/
│   │       └── sub_group_service.dart   # NEW: extracted from providers/sub_group_provider.dart
│   ├── vault/
│   │   └── services/
│   │       └── document_service.dart    # REPLACED: Firebase Storage
│   ├── memories/
│   │   └── services/
│   │       └── memory_service.dart      # REPLACED: Firebase Storage
│   └── activity/
│       └── services/
│           └── activity_service.dart    # REPLACED: Firestore CRUD
```

### Pattern 1: FirestoreRepository Base Class

**What:** A thin base class (or utility class) that owns the `FirebaseFirestore` instance and provides the test injection hook. All module services extend or use it.

**When to use:** Every new module service in this phase.

**Design recommendation:** Use a base class with a named constructor for test injection, matching the `EventService.withFirestore(db, ...)` pattern already established in the codebase.

```dart
// lib/core/services/firestore_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../features/groups/models/group_model.dart';
import '../config/firebase_config.dart';

abstract class FirestoreRepository {
  final FirebaseFirestore _db;

  /// Production constructor — uses FirebaseConfig singleton.
  FirestoreRepository() : _db = FirebaseConfig.firestore;

  /// Test constructor — injects FakeFirebaseFirestore.
  @visibleForTesting
  FirestoreRepository.withFirestore(FirebaseFirestore db) : _db = db;

  FirebaseFirestore get db => _db;

  /// Convenience: events subcollection reference.
  CollectionReference<Map<String, dynamic>> eventSubcollection(
    String groupId,
    String eventId,
    String module,
  ) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .collection(module);
  }
}
```

**Why abstract class over mixin:** The test constructor pattern (`withFirestore`) is already proven in `EventService`. Abstract class allows Dart's constructor inheritance. Mixin would require a different injection approach.

### Pattern 2: Module Service with Firestore Snapshot Stream

**What:** A module service that returns `Stream<List<T>>` from Firestore's `.snapshots()` — same return type as the existing `OfflineRepository.watch*()` methods, allowing providers to swap sources without changing consumers.

**When to use:** Every module that has a list-based provider (expenses, settlements, gear, sub-groups, activity, documents, memories).

```dart
// lib/features/ledger/services/expense_service.dart
class ExpenseService extends FirestoreRepository {
  ExpenseService() : super();

  @visibleForTesting
  ExpenseService.withFirestore(FirebaseFirestore db) : super.withFirestore(db);

  Stream<List<Expense>> watchExpenses(String groupId, String eventId) {
    return eventSubcollection(groupId, eventId, 'expenses')
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Expense.fromFirestoreDoc).toList());
  }

  Future<Expense> addExpense({
    required String groupId,
    required String eventId,
    required String payerParticipantId,
    required Decimal amount,
    String currency = 'OMR',
    // ... other fields
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    final data = {
      'id': id,
      'eventId': eventId,
      'payerParticipantId': payerParticipantId,
      'amountFils': MoneySerializer.toSubunits(amount, currency),
      'currency': currency,
      // ...
      'isDeleted': false,
      'createdAt': now.toIso8601String(), // client timestamp per Pitfall 3
    };
    await eventSubcollection(groupId, eventId, 'expenses').doc(id).set(data);
    return Expense.fromMap(data);
  }
}
```

**Key note on `createdAt`:** Use client-generated ISO 8601 string (not `FieldValue.serverTimestamp()`) for `createdAt` so the value is immediately readable in the returned object. This matches the established pattern in `EventService.createEvent()` and was documented as the correct approach in the Phase 3 pitfalls. Use `FieldValue.serverTimestamp()` only for `updatedAt` and `deletedAt` on mutations where immediate readback is not needed.

### Pattern 3: Provider Migration — Stream Source Swap

**What:** Changing the stream source in a `StreamProvider.family` from `OfflineRepository.watch*()` to a Firestore snapshot stream.

**When to use:** Every module provider that previously used SQLite streams.

```dart
// BEFORE (Supabase + SQLite pattern):
final tripExpensesProvider = StreamProvider.family<List<Expense>, String>(
  (ref, tripId) => ref.read(offlineRepositoryProvider).watchExpenses(tripId),
);

// AFTER (Firestore pattern) — note: tripId is now eventId, needs groupId too
// The provider signature changes to use a record/tuple if groupId is needed:
typedef EventRef = ({String groupId, String eventId});

final eventExpensesProvider = StreamProvider.family<List<Expense>, EventRef>(
  (ref, eventRef) => ref.read(expenseServiceProvider)
      .watchExpenses(eventRef.groupId, eventRef.eventId),
);
```

**Important consideration:** The current providers use `tripId` as the family parameter. Firestore subcollections require both `groupId` and `eventId`. The screens currently access `event.bridgeTripId` as the trip ID. After migration, screens need `event.groupId` and `event.id`. The `EventCommandCenter` already has the `Event` model which contains both fields — this is the integration point where screens must be updated to pass the correct arguments.

**Recommendation for provider family parameter:** Use a Dart record `(groupId: String, eventId: String)` as the family key. Records support equality by value in Dart 3.x, which is required for `StreamProvider.family` deduplication.

### Pattern 4: SQLite Side-Write from Firestore Listener

**What:** Firestore snapshot listeners for expenses and settlements write to SQLite as a side effect, keeping `BalanceCalculator` data fresh (D-15).

**When to use:** Expense and Settlement providers only. Other modules (gear, vault, memories, activity, sub-groups) do NOT write to SQLite — their data comes from Firestore snapshots directly.

**Implementation approach:** In the `StreamProvider` itself (or in a dedicated provider transformation), listen to Firestore changes and write to SQLite after each emission.

```dart
final eventExpensesProvider = StreamProvider.family<List<Expense>, EventRef>(
  (ref, eventRef) {
    final service = ref.read(expenseServiceProvider);
    return service.watchExpenses(eventRef.groupId, eventRef.eventId)
        .asyncMap((expenses) async {
          // Side effect: write to SQLite for BalanceCalculator
          await BalanceCacheRepository.cacheExpenses(eventRef.eventId, expenses);
          return expenses; // pass through unchanged
        });
  },
);
```

**Why asyncMap over listen:** `asyncMap` keeps the stream pipeline intact and ensures SQLite writes complete before downstream subscribers (including `BalanceCalculator` providers) receive the data. A separate `listen()` listener would create a dangling subscription outside Riverpod's lifecycle management.

**SQLite write strategy:** Batch inserts (use `db.batch()`) for the full replacement on snapshot updates — matches the existing `CacheService.cacheExpenses()` pattern. Individual row inserts are only needed for new single-document events (created locally before the listener fires).

### Pattern 5: Lazy Migration from Supabase

**What:** When a user opens an event for the first time after migration, check if Firestore subcollection data exists. If not (it's a pre-migration event with data in Supabase only), fetch from Supabase using `event.bridgeTripId` and write to Firestore.

**When to use:** On first Firestore snapshot emission for each module subcollection — if the snapshot is empty AND the event has a `bridgeTripId`.

**Implementation approach:** A dedicated `LazyMigrationService` that is called from the module service when a snapshot returns empty on an event known to have Supabase data.

```dart
// lib/core/services/lazy_migration_service.dart
class LazyMigrationService {
  static Future<void> migrateExpensesIfNeeded({
    required String groupId,
    required String eventId,
    required String bridgeTripId,
    required FirebaseFirestore db,
  }) async {
    // Check Firestore — if empty, pull from Supabase and write
    final snapshot = await db
        .collection('groups/$groupId/events/$eventId/expenses')
        .limit(1)
        .get();
    if (snapshot.docs.isNotEmpty) return; // already migrated

    // Fetch from Supabase via bridgeTripId
    // Write to Firestore
    // Mark as migrated (set a flag on the event doc or just let the data speak)
  }
}
```

**Error handling:** Migration failures are non-fatal. If Supabase is unreachable during lazy migration, log the error and let the module show empty state. Retry on next access.

**Migration detection:** The empty Firestore snapshot is the signal. No separate "migrated" flag is needed — once data is in Firestore, future snapshots will be non-empty.

### Pattern 6: ConnectivityNotifier Update

**What:** Replace the Supabase-based connectivity check (`SyncService.isOnline()` which calls `_client.auth.refreshSession()`) with a Firestore-based check.

**Recommended approach:** Use `FirebaseAuth.instance.authStateChanges()` status plus Firestore's network state. The simplest replacement is:

```dart
Future<bool> checkConnectivity() async {
  try {
    // Lightweight: check if Firebase Auth has a current user
    // (auth state is maintained locally — if null, we're having issues)
    final user = FirebaseConfig.auth.currentUser;
    if (user == null) return false;
    // Try a lightweight Firestore read (a non-existent doc — no charge, fast)
    await FirebaseConfig.firestore
        .collection('_health')
        .doc('ping')
        .get(const GetOptions(source: Source.server));
    return true;
  } catch (e) {
    return false;
  }
}
```

**Alternative (simpler):** Remove the periodic poll entirely. Firestore's SDK already emits errors/reconnection events. The `OfflineBanner` could watch `FirebaseFirestore.instance.snapshotInSyncWithServer()` or simply use a package like `connectivity_plus`. However, since `ConnectivityNotifier` is referenced in many screens and the existing pattern works, the simplest migration is swapping the Supabase ping for a Firestore ping.

### Pattern 7: FirestoreRepository Base Class Used by GroupService and EventService

**What:** GroupService and EventService are refactored to extend `FirestoreRepository` (D-06), removing their direct `FirebaseConfig.firestore` references in favor of `db` from the base class.

**Why this matters for MIG-05:** All Firestore access must flow through `FirestoreRepository`. `GroupService` currently has `FirebaseFirestore get _db => FirebaseConfig.firestore;` inline — this must become `db` from the base class.

### Anti-Patterns to Avoid

- **Direct `FirebaseFirestore.instance` calls outside FirestoreRepository:** Violates MIG-05. Every Firestore interaction must go through the base class `db` getter.
- **`FieldValue.serverTimestamp()` for `createdAt` on new documents:** Makes the returned object's timestamp null until the next snapshot — breaks the pattern of returning the created object immediately. Use client-generated `DateTime.now().toUtc().toIso8601String()` for `createdAt`.
- **Writing to sync_queue for Firestore writes:** SyncService is the old pattern. Firestore queues writes offline automatically. No `CacheService.addToSyncQueue()` calls in new services.
- **`ref.read(offlineRepositoryProvider)` in migrated providers:** After migration, providers use Firestore streams. `offlineRepositoryProvider` is only used by `BalanceCacheRepository` after the rename.
- **Mutating Firestore documents in-place:** Pass new immutable maps to Firestore. Per CLAUDE.md, never mutate existing objects.
- **Double-key provider families with string concatenation:** Use Dart records `(groupId: String, eventId: String)` not `"$groupId:$eventId"` strings. Records provide compile-time structure and proper equality semantics.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Offline write queuing | Custom retry queue, local pending writes table | Firestore SDK offline persistence | Already enabled in Phase 1; Firestore queues writes in its own internal LevelDB; handles retry, ordering, conflict resolution automatically |
| Real-time data streaming | Polling loops, WebSocket management | `collection.snapshots()` | Firestore snapshot listeners handle connection management, reconnection, and delivery guarantees |
| Conflict resolution for concurrent writes | Merge logic, version vectors | Firestore last-write-wins | Explicitly scoped as acceptable per REQUIREMENTS.md Out of Scope: "last-write-wins is fine for expenses" |
| Firestore test doubles | Mock CollectionReference, DocumentSnapshot, QuerySnapshot | `FakeFirebaseFirestore` (already in project) | Firestore's internal API surface is too large to mock reliably; established in Phase 1 |
| Storage signed URL management | Custom expiry tracking, URL rotation | Firebase Storage `getDownloadURL()` | Storage handles URL lifecycle; replaces Supabase signed URL pattern |
| Money subunit conversion | Inline arithmetic in service methods | `MoneySerializer.toSubunits()` / `fromSubunits()` | Already built in Phase 1; use the boundary utility consistently |

**Key insight:** Firestore's offline persistence is not a "sync when online" system — it is a durable write-ahead log that the SDK manages autonomously. The developer does not need to monitor connectivity or trigger uploads. This is the fundamental architectural difference from the old SyncService.

---

## Runtime State Inventory

> This phase is a migration — existing runtime state must be catalogued.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data — Supabase PostgreSQL | expenses, settlements, gear_items, participants, sub_groups, sub_group_members, trip_activity_logs, trip_memories, documents tables — data exists for all events created in Phase 3 | Lazy migration per D-18: on first Firestore snapshot read for each module, if empty, pull from Supabase via bridgeTripId and write to Firestore |
| Stored data — SQLite (device) | `sync_queue` table has any pending Supabase writes from before migration | Delete sync_queue table entries as part of final cleanup (D-04); users should be online at migration time or accept data loss for unsynced pre-migration writes |
| Stored data — SQLite (device) | `expenses`, `settlements`, `gear_items`, `participants`, `sub_groups`, `sub_group_members`, `activity_logs`, `categories` tables populated with Supabase-synced data | These tables remain valid for BalanceCalculator reads; expense/settlement tables repopulated by Firestore listeners going forward; other tables cleared on module migration |
| Live service config | Supabase project active, RLS policies in place | No action in Phase 4 — Supabase stays alive until Phase 7 (MIG-07); it is the source for lazy migration |
| OS-registered state | None — no OS-registered tasks or services | None |
| Secrets/env vars | `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SENTRY_DSN` in config.json | No change — Supabase keys stay until Phase 7; `SENTRY_DSN` unchanged |
| Build artifacts | `build/` directory, app-release.aab in project root | No action — these are stale release builds, not affected by migration |

**Nothing found in category:** OS-registered state — verified by reviewing project structure; no launchd plists, pm2 config, or Task Scheduler entries.

---

## Common Pitfalls

### Pitfall 1: FieldValue.serverTimestamp() in createdAt Breaks Immediate Readback

**What goes wrong:** A service creates a document with `'createdAt': FieldValue.serverTimestamp()`, then returns an in-memory object. The returned object's `createdAt` is null until the server resolves the timestamp and the snapshot listener fires.

**Why it happens:** `FieldValue.serverTimestamp()` is a sentinel that Firestore resolves server-side. The local write is pending — the snapshot comes back later with the resolved value.

**How to avoid:** Use `DateTime.now().toUtc().toIso8601String()` for `createdAt` on document creation (client timestamp). Use `FieldValue.serverTimestamp()` only for `updatedAt` and `deletedAt` where immediate readback is not needed.

**Warning signs:** A service method returns `null` for `createdAt` or the object shows in the list before the timestamp appears. This was already documented in Phase 3 context as the established pattern.

### Pitfall 2: Provider Family Key Must Support Equality

**What goes wrong:** Using `StreamProvider.family<T, String>` with a concatenated key like `"$groupId:$eventId"` — Riverpod caches by equality of the key. If two different providers call with the same string, they share the cache (good), but parsing the string back to groupId/eventId is error-prone.

**Why it happens:** Firestore subcollections require two IDs; old Supabase providers only needed `tripId`.

**How to avoid:** Use Dart 3 records: `StreamProvider.family<List<Expense>, ({String groupId, String eventId})>`. Records support structural equality (`==`) by default in Dart 3.x. Riverpod 2.x family parameters must be `==`-comparable — records satisfy this.

**Warning signs:** Two widget subtrees watching the same event show different data, or Riverpod creates duplicate subscriptions for the same event.

### Pitfall 3: Security Rules — Module Subcollections Require event get()

**What goes wrong:** Writing a security rule for `groups/{groupId}/events/{eventId}/expenses/{expenseId}` that does `get(events/{eventId})` to check `participantIds` — this costs one `get()` call per write, and Firestore security rules have a 10 `get()` call limit per request.

**Why it happens:** Subcollection rules inherit nothing from parent documents; membership must be re-checked.

**How to avoid:** The existing security rules already use `get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds` for the events subcollection. For module subcollections, the rule can check `request.auth.uid in get(/databases/.../events/$(eventId)).data.participantIds` — but this is a second `get()` call stacked on top of the group membership check. With 10-get limit, this is safe for single writes but not for batched writes.

**Recommended rule:** Allow any authenticated event participant (checked via the event document's `participantIds`) to read/write module data. This requires one `get()` to the event document per request.

```
match /groups/{groupId}/events/{eventId}/{module}/{docId} {
  function isEventParticipant() {
    return request.auth != null &&
      request.auth.uid in
        get(/databases/$(database)/documents/groups/$(groupId)/events/$(eventId)).data.participantIds;
  }
  allow read, write: if isEventParticipant();
}
```

**Warning signs:** Permission-denied errors in the emulator when writing expenses while having a valid Firebase user.

### Pitfall 4: WriteBatch + Security Rules Ordering (Known Gotcha from Phase 2)

**What goes wrong:** Using `WriteBatch` to atomically write multiple module documents in a single batch. If any security rule in the batch calls `get()` on a document being written in the same batch, it evaluates against the pre-batch state.

**Why it happens:** Firestore evaluates each batch document's rules against the current database state, not the proposed batch state.

**How to avoid:** Don't batch module document creation across different subcollections. Batch same-subcollection writes (multiple expenses at once) are fine. The lazy migration service should write documents one-by-one or in same-type batches, not across modules.

**Warning signs:** Permission-denied errors only on batch operations, even with correct security rules.

### Pitfall 5: Composite Index Required for Ordered Subcollection Queries

**What goes wrong:** Querying `expenses.where('isDeleted', isEqualTo: false).orderBy('createdAt', descending: true)` fails with "requires an index" error in production.

**Why it happens:** Firestore requires explicit composite indexes for queries combining a `where` filter with an `orderBy` on a different field.

**How to avoid:** Create index entries in `firestore.indexes.json` before deployment. The Firebase console will provide a direct link to create the required index when the error occurs. For the emulator (used in tests), indexes are not required — this pitfall only surfaces on real Firestore.

**Warning signs:** `FirebaseException` with code `failed-precondition` and a URL to create the index.

### Pitfall 6: Firestore Offline Write Queue vs. SQLite sync_queue Ordering

**What goes wrong:** Assuming that migrating a module means existing SQLite sync_queue entries for that module will be picked up. They won't — the sync_queue is Supabase-specific. If there are pending unsynced Supabase writes in sync_queue for an already-migrated module, they'll never be uploaded.

**Why it happens:** The migration is a hard cutover (D-03) — old Supabase sync queue entries are abandoned.

**How to avoid:** Before cutting over each module, ensure any pending sync_queue entries for that module's table (e.g., `table_name = 'expenses'`) are either flushed to Supabase first or acknowledged as acceptable data loss. Since this migration is happening in a development context before wide production use, data loss risk is low, but it should be noted in the plan.

**Warning signs:** Sync queue entries with `retry_count < 5` for the migrated table remain after module cutover.

### Pitfall 7: BalanceCalculator Data Freshness After Provider Migration

**What goes wrong:** The `tripBalanceProvider` in `expense_provider.dart` reads from `tripExpensesProvider` and `tripSettlementsProvider`. After migration, these switch to Firestore streams. If the SQLite side-write happens AFTER the BalanceCalculator runs (race condition), balances will be stale.

**Why it happens:** The `asyncMap` side-write in the expense stream and the provider that calls `BalanceCalculator.calculateBalances()` are in the same Riverpod dependency graph. If the balance provider fires before `asyncMap` completes the SQLite write, it reads stale data.

**How to avoid:** `BalanceCalculator.calculateBalances()` takes `List<Expense>` and `List<Settlement>` directly (not SQLite queries). The current `tripBalanceProvider` is a `FutureProvider.family` that `await`s the expense and settlement providers' futures. Since these providers now emit from Firestore directly, `BalanceCalculator` should use the in-memory Firestore data directly — NOT read from SQLite.

**Key finding:** `BalanceCalculator` in `expense_provider.dart` is a pure function operating on in-memory lists. It does NOT query SQLite directly. The providers feed it data. After migration, the providers can feed it data from Firestore snapshots directly. SQLite writes (D-15) are for Phase 5 cross-event balance computation (which needs a persistent store to aggregate across events), not for Phase 4 per-event balance computation.

**Resolution for this phase:** `tripBalanceProvider` can be updated to watch the new Firestore-backed `eventExpensesProvider` and `eventSettlementsProvider` directly. The SQLite side-write for expenses/settlements (D-15) can be implemented as a background write without blocking the in-memory BalanceCalculator path.

---

## Code Examples

Verified patterns from existing codebase sources:

### Firestore Snapshot Stream (from GroupService pattern)

```dart
// Source: lib/features/groups/providers/group_provider.dart
final userGroupsProvider = StreamProvider<List<Group>>((ref) {
  final uid = ref.watch(firebaseUserProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value([]);

  return FirebaseConfig.firestore
      .collection('groups')
      .where('memberIds', arrayContains: uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(Group.fromDoc).toList());
});
```

Apply the same `.snapshots().map(...)` pattern for module subcollections.

### Client Timestamp for Document Creation (from EventService pattern)

```dart
// Source: lib/features/events/services/event_service.dart
final now = DateTime.now().toUtc();
// ...
// Use ISO 8601 string for immediate readability in returned object
'createdAt': now.toIso8601String(),
```

### MoneySerializer Boundary (from Phase 1)

```dart
// Source: test/unit/money_serializer_test.dart (verified working)
// Serialize to Firestore:
final fils = MoneySerializer.toSubunits(amount, currency);  // Decimal -> int
// Deserialize from Firestore:
final amount = MoneySerializer.fromSubunits(fils, currency); // int -> Decimal
// .toDecimal(scaleOnInfinitePrecision: 10) required for division results
```

### FakeFirebaseFirestore Test Pattern (from event_service_test.dart)

```dart
// Source: test/unit/event_service_test.dart
final fakeDb = FakeFirebaseFirestore();
final mockGearService = MockGearService();
final service = EventService.withFirestore(fakeDb, mockGearService);

// For new module services:
final fakeDb = FakeFirebaseFirestore();
final service = ExpenseService.withFirestore(fakeDb);

// Write a document to fakeDb to set up test state:
await fakeDb
    .collection('groups/$groupId/events/$eventId/expenses')
    .doc(expenseId)
    .set(expenseMap);
```

### BalanceCalculator Call Pattern (from expense_provider.dart)

```dart
// Source: lib/features/ledger/providers/expense_provider.dart (line 269)
// BalanceCalculator.calculateBalances takes in-memory lists — NOT SQLite queries
return BalanceCalculator.calculateBalances(
  expenses: expenses,           // List<Expense> from provider
  settlements: settlements,     // List<Settlement> from provider
  participants: participants,   // List<Participant> from provider
  subGroups: subGroups,         // List<SubGroup> from provider (optional)
);
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `OfflineRepository.watch*()` → SQLite stream | `collection.snapshots().map(...)` → Firestore stream | Phase 4 | Providers swap stream source; consumers unchanged |
| `SyncService.syncPendingChanges()` — manual queue upload | Firestore SDK offline write queue | Phase 4 | No polling loop; writes queue automatically on disconnect |
| `CacheService.addToSyncQueue()` in write path | No queue entry — Firestore handles offline writes | Phase 4 | Simpler write path; remove sync_queue writes from services |
| `sync_queue` SQLite table | Deleted | Phase 4 (final cleanup) | Schema simplified |
| `OfflineRepository` (full reactive wrapper) | `BalanceCacheRepository` (narrow: expenses + settlements only) | Phase 4 | Most watch/save methods deleted |
| Supabase bridge trip creation in EventService | Bridge removed from EventService | Phase 4 | EventService writes to Firestore only |
| `ConnectivityNotifier` pings Supabase | `ConnectivityNotifier` pings Firestore | Phase 4 | Same API, different backend |

**Deprecated/outdated after this phase:**
- `SyncService`: deleted entirely after all modules migrate
- `OfflineRepository.watchExpenses/watchGearItems/watchSettlements/etc.`: deleted — only balance-related SQLite queries remain
- `CacheService.addToSyncQueue()`, `removeSyncItem()`, `getPendingSyncItems()`, `hasPendingSync()`, `getSyncQueueCount()`: deleted
- `sync_queue` SQLite table: dropped in `_onUpgrade` (or left as tombstone — depends on migration approach)
- `EventService._createBridgeTrip()`, `EventService._generateBridgeCode()`: deleted
- `EventModel.bridgeTripId`: removed after bridge teardown

---

## Open Questions

1. **BalanceCalculator data source for Phase 5 cross-event aggregation**
   - What we know: BalanceCalculator in Phase 4 works fine reading from Firestore-backed in-memory providers. For Phase 5 (cross-event group balances), data needs to persist across events.
   - What's unclear: Whether Phase 4's SQLite side-write (D-15) should populate a structure useful for Phase 5, or if Phase 5 will redefine this from scratch.
   - Recommendation: Implement D-15 as a simple `REPLACE INTO expenses/settlements` with `event_id` as the key column — Phase 5 can query by `group_id` after the events table is linked.

2. **Vault/Memories: Firebase Storage or Firestore metadata?**
   - What we know: Documents (vault) and memories use Supabase Storage today. Firebase Storage (`firebase_storage`) is in the CLAUDE.md stack recommendations but NOT in the current pubspec.yaml.
   - What's unclear: Whether Firebase Storage should be added in Phase 4 or whether vault/memories use Firestore metadata only (storing URLs/paths) and defer the binary storage migration.
   - Recommendation: Add `firebase_storage: ^13.2.0` as a dependency in Phase 4. The vault module stores file metadata in Firestore subcollections and binary files in Firebase Storage (`trip-documents` bucket → Firebase Storage). Memory photos similarly. This is a clean migration that avoids a hybrid state.

3. **Participants data source after migration**
   - What we know: `Participant` data is currently in the Supabase `participants` table and SQLite cache. `BalanceCalculator` needs `List<Participant>`. The event document in Firestore has `participantNames: Map<uid, name>` but not the full `Participant` model (which includes `id`, `tripId`, `role`, `isShadow`).
   - What's unclear: Whether to create a `participants` subcollection in Firestore or derive `Participant` objects from the event document's `participantIds`/`participantNames` maps.
   - Recommendation: Derive `Participant` objects from the Firestore event document fields. The `Participant` model can be constructed from `event.participantIds` and `event.participantNames`. The `id` field for BalanceCalculator purposes becomes the Firebase UID (not a separate Supabase participant ID). This is a model simplification that aligns with the Firestore data model.

4. **CampingGear seeding after bridge removal**
   - What we know: `EventService._seedCampingGear()` calls `GearService.addItem()` which currently writes to Supabase. After migration, GearService writes to Firestore. The seeding logic in EventService needs to call the new Firestore-backed GearService.
   - What's unclear: Whether the `EventService.withFirestore` test constructor needs to be updated to inject both a `FakeFirebaseFirestore` and a `MockGearService` still (it already does), or whether the real GearService can be used in tests after migration.
   - Recommendation: After GearService migrates to Firestore, the `EventService.withFirestore` test constructor can pass a real `GearService.withFirestore(fakeDb)` instead of a `MockGearService` — tests become more integration-like and more reliable.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | Build/run/test | Yes | 3.41.5 (stable) | — |
| Dart SDK | Build/test | Yes | 3.11.3 | — |
| Firebase CLI | Security rules deployment | Checked separately | — | Use emulator-based tests only |
| `cloud_firestore` | All Firestore reads/writes | Yes (in pubspec) | ^6.2.0 | — |
| `firebase_auth` | Auth UID in rules | Yes (in pubspec) | ^6.3.0 | — |
| `firebase_storage` | Vault + Memories binary storage | NOT IN pubspec | — | Add ^13.2.0 or defer vault/memories |
| `fake_cloud_firestore` | All Firestore tests | Yes (dev dep) | ^4.1.0+1 | — |
| `firebase_auth_mocks` | Auth tests | Yes (dev dep) | ^0.15.1 | — |
| `sqflite_common_ffi` | SQLite tests on macOS | Yes (dev dep) | ^2.3.4 | — |
| Supabase project | Lazy migration source | Yes (active) | — | Data loss for pre-migration events if unreachable |

**Missing dependencies with no fallback:**
- `firebase_storage` is not in pubspec.yaml but is needed for Vault and Memories migration. Must be added if vault/memories are migrated in this phase.

**Missing dependencies with fallback:**
- If vault/memories migration is deferred within Phase 4, those two modules can remain on Supabase temporarily (treating them as last in the migration order). This is acceptable given D-02's order (vault and memories come after gear/logistics).

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Flutter Test (built-in) + fake_cloud_firestore 4.1.0+1 |
| Config file | None — standard `flutter test` discovery |
| Quick run command | `flutter test test/unit/ --no-pub` |
| Full suite command | `flutter test --no-pub` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MIG-01 | Expense written to Firestore subcollection `groups/{gId}/events/{eId}/expenses/{id}` | unit | `flutter test test/unit/expense_service_test.dart --no-pub` | ❌ Wave 0 |
| MIG-01 | Settlement written to Firestore subcollection | unit | `flutter test test/unit/settlement_service_test.dart --no-pub` | ❌ Wave 0 |
| MIG-01 | GearItem written to Firestore subcollection | unit | `flutter test test/unit/gear_service_test.dart --no-pub` | ❌ Wave 0 |
| MIG-01 | SubGroup written to Firestore subcollection | unit | `flutter test test/unit/sub_group_service_test.dart --no-pub` | ❌ Wave 0 |
| MIG-01 | Activity log written to Firestore subcollection | unit | `flutter test test/unit/activity_service_test.dart --no-pub` | ❌ Wave 0 |
| MIG-02 | Firestore snapshot change propagates to UI via StreamProvider | unit | `flutter test test/unit/expense_service_test.dart --no-pub` | ❌ Wave 0 |
| MIG-03 | SyncService class does not exist in codebase | unit | `flutter test test/unit/sync_service_test.dart --no-pub` (verify it fails to import) | Exists (must be deleted) |
| MIG-04 | BalanceCalculator returns correct result from in-memory lists | unit | `flutter test test/unit/balance_calculations_test.dart --no-pub` | ✅ Exists |
| MIG-05 | No direct `FirebaseFirestore.instance` calls outside FirestoreRepository | unit | Verified via grep in CI + `flutter analyze` | Partially (EventService + GroupService use FirebaseConfig.firestore) |
| MIG-05 | FirestoreRepository base class exists and is used | unit | `flutter test test/unit/firestore_repository_test.dart --no-pub` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `flutter test test/unit/ --no-pub`
- **Per wave merge:** `flutter test --no-pub`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/unit/expense_service_test.dart` — covers MIG-01, MIG-02 for expenses
- [ ] `test/unit/settlement_service_test.dart` — covers MIG-01, MIG-02 for settlements
- [ ] `test/unit/gear_service_test.dart` — covers MIG-01 for gear
- [ ] `test/unit/sub_group_service_test.dart` — covers MIG-01 for sub-groups
- [ ] `test/unit/activity_service_test.dart` — covers MIG-01 for activity
- [ ] `test/unit/firestore_repository_test.dart` — covers MIG-05 base class contract
- [ ] `test/unit/balance_cache_repository_test.dart` — covers MIG-04 narrow SQLite interface
- [ ] `test/unit/lazy_migration_service_test.dart` — covers D-18 lazy migration
- [ ] `test/unit/connectivity_provider_test.dart` — covers ConnectivityNotifier Firestore ping

---

## Sources

### Primary (HIGH confidence)

- Codebase: `lib/features/events/services/event_service.dart` — established `withFirestore` test constructor pattern; client timestamp pattern; fire-and-forget bridge
- Codebase: `lib/features/groups/providers/group_provider.dart` — `.snapshots().map()` Firestore stream provider pattern
- Codebase: `lib/core/services/sync_service.dart` — full inventory of what must be deleted
- Codebase: `lib/core/services/offline_repository.dart` — full inventory of what must be trimmed
- Codebase: `lib/core/services/local_database.dart` — SQLite schema v6; `sync_queue` table definition; expense/settlement column shapes
- Codebase: `lib/core/config/firebase_config.dart` — `FirebaseConfig.firestore` singleton; offline persistence already enabled
- Codebase: `lib/features/ledger/providers/expense_provider.dart` — `BalanceCalculator` location and interface; confirms it takes in-memory lists not SQLite queries
- Codebase: `security/firestore.rules` — existing rules structure; events subcollection pattern to extend for module subcollections
- Codebase: `pubspec.yaml` — current dependency versions; `firebase_storage` is absent
- `.planning/phases/04-firestore-repository-layer/04-CONTEXT.md` — all locked decisions D-01 through D-18
- `.planning/phases/01-data-foundation/1-CONTEXT.md` — money serialization decisions; Phase 1 validated Firestore baseline
- `.planning/phases/03-events/03-CONTEXT.md` — bridge pattern (D-22); event Firestore data model
- Project memory: `project_firebase_gotchas.md` — 6 runtime gotchas from Phase 2 UAT

### Secondary (MEDIUM confidence)

- CLAUDE.md Technology Stack section — recommended Firebase package versions (cloud_firestore ^6.2.0, firebase_storage ^13.2.0)
- Project STATE.md accumulated decisions — Firestore offline persistence confirmed active from Phase 1

### Tertiary (LOW confidence)

- None — all critical findings are verified against the live codebase

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages confirmed in pubspec.yaml (except firebase_storage noted as gap)
- Architecture: HIGH — patterns verified against existing EventService and GroupService in codebase
- Pitfalls: HIGH — pitfalls 1-4 are verified against existing gotchas file and codebase patterns; pitfalls 5-7 are confirmed by code inspection
- BalanceCalculator interface: HIGH — confirmed pure in-memory function, no direct SQLite dependency

**Research date:** 2026-03-26
**Valid until:** 2026-04-26 (30 days — stable Firebase/Flutter SDKs)
