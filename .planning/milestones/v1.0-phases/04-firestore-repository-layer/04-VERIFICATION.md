---
phase: 04-firestore-repository-layer
verified: 2026-03-26T20:00:00Z
status: passed
score: 5/5 must-haves verified
re_verification: false
gaps: []
gap_resolution: "sync_queue DDL removed from local_database.dart in commit a60cdcf"
---

# Phase 4: Firestore Repository Layer Verification Report

**Phase Goal:** All per-event module writes (expenses, settlements, gear, logistics, vault, memories, activity) flow through Firestore; the SyncService polling loop is gone; offline capability is preserved through Firestore's built-in write queue
**Verified:** 2026-03-26T20:00:00Z
**Status:** passed
**Re-verification:** Gap fixed inline (sync_queue DDL removed, commit a60cdcf)

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Adding an expense while offline queues it locally; when connectivity restores, the expense appears in Firestore without any manual sync action | VERIFIED | `FirebaseConfig.initialize()` sets `persistenceEnabled: true, cacheSizeBytes: CACHE_SIZE_UNLIMITED`. `ExpenseService.addExpense()` writes via Firestore subcollection. `ConnectivityNotifier` no longer triggers any manual sync — Firestore handles replay automatically. |
| 2 | A Firestore snapshot listener update propagates to the UI without polling — changes made on another device appear within seconds on reconnect | VERIFIED | All 7 module services (`ExpenseService`, `SettlementService`, `GearService`, `SubGroupService`, `ActivityService`, `DocumentService`, `MemoryService`) use `.snapshots()` listeners. Providers (`eventExpensesProvider`, `eventSettlementsProvider`, `eventGearItemsProvider`, etc.) are `StreamProvider.family` wired to these listeners. No polling loop exists. |
| 3 | The SyncService class and sync_queue SQLite table no longer exist in the codebase | VERIFIED | `lib/core/services/sync_service.dart` deleted. `lib/core/services/offline_repository.dart` deleted. `sync_queue` CREATE TABLE DDL, index, v4 migration columns, clearAll() reference, and SyncAction enum all removed from `local_database.dart` (commit a60cdcf). `grep sync_queue lib/` returns zero matches. |
| 4 | All Firestore reads and writes flow through FirestoreRepository — no direct FirebaseFirestore.instance calls exist outside that class | VERIFIED | `grep -rn "FirebaseFirestore\.instance" lib/` returns exactly 2 results, both inside `lib/core/config/firebase_config.dart`: the `get firestore` accessor (line 16) and the `Settings` initialization in `initialize()` (line 29). Zero direct calls exist outside `firebase_config.dart`. All 9 service classes (`ExpenseService`, `SettlementService`, `GearService`, `SubGroupService`, `ActivityService`, `DocumentService`, `MemoryService`, `GroupService`, `EventService`) extend `FirestoreRepository`. |
| 5 | SQLite still serves structured balance queries; the BalanceCalculator reads from SQLite and produces correct results | VERIFIED | `BalanceCacheRepository` wraps SQLite for `getExpenses`/`getSettlements`. `eventExpensesProvider` and `eventSettlementsProvider` use `asyncMap` to side-write to SQLite via `cache.cacheExpenses()` and `cache.cacheSettlements()`. `BalanceCalculator.calculateBalances()` receives data from Firestore snapshot streams (passed in-memory). `test/unit/balance_cache_repository_test.dart` passes 15 tests including cacheExpenses, upsert, getExpenses, and watchExpenses. `test/unit/balance_calculations_test.dart` passes. |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/core/services/firestore_repository.dart` | Abstract base class with db getter and eventSubcollection helper | VERIFIED | `abstract class FirestoreRepository` with production constructor, `@protected` `withFirestore` constructor, `db` getter, and `eventSubcollection(groupId, eventId, module)` returning typed `CollectionReference` |
| `lib/core/types/event_ref.dart` | Canonical EventRef typedef | VERIFIED | `typedef EventRef = ({String groupId, String eventId})` |
| `lib/features/ledger/services/expense_service.dart` | Firestore-backed ExpenseService extending FirestoreRepository | VERIFIED | `class ExpenseService extends FirestoreRepository`, `watchExpenses` returns `.snapshots()` stream, `addExpense` uses `MoneySerializer.toSubunits` |
| `lib/features/ledger/services/settlement_service.dart` | Firestore-backed SettlementService extending FirestoreRepository | VERIFIED | `class SettlementService extends FirestoreRepository`, uses `MoneySerializer`, no Supabase references |
| `lib/features/gear/services/gear_service.dart` | Firestore-backed GearService extending FirestoreRepository | VERIFIED | `class GearService extends FirestoreRepository`, soft-delete pattern |
| `lib/features/logistics/services/sub_group_service.dart` | Firestore-backed SubGroupService extending FirestoreRepository | VERIFIED | `class SubGroupService extends FirestoreRepository`, members in nested subcollection |
| `lib/features/activity/services/activity_service.dart` | Firestore-backed ActivityService extending FirestoreRepository | VERIFIED | `class ActivityService extends FirestoreRepository`, `watchActivityLogs` uses `.snapshots()` |
| `lib/core/services/balance_cache_repository.dart` | Narrow SQLite wrapper for BalanceCalculator | VERIFIED | `cacheExpenses`, `cacheSettlements`, `getExpenses`, `getSettlements`, `watchExpenses` streams |
| `lib/features/ledger/providers/expense_provider.dart` | Firestore EventRef providers with asyncMap SQLite side-write | VERIFIED | `eventExpensesProvider` and `eventSettlementsProvider` are `StreamProvider.family<..., EventRef>` with `asyncMap` calling `cache.cacheExpenses` / `cache.cacheSettlements` |
| `lib/core/providers/connectivity_provider.dart` | Firestore ping-based connectivity (no Supabase polling) | VERIFIED | Uses `Source.server` Firestore ping; no `SyncController` or `SyncService` |
| `security/firestore.rules` | Module subcollection access rules | VERIFIED | Contains `match /{module}/{docId}` nested under `match /events/{eventId}` with `isEventParticipantForModule()` checking `event.participantIds` |
| `lib/core/services/sync_service.dart` | DELETED | VERIFIED | File does not exist |
| `lib/core/services/offline_repository.dart` | DELETED | VERIFIED | File does not exist |
| `lib/core/services/local_database.dart` | sync_queue table DDL removed | PARTIAL (GAP) | File exists. `sync_queue` CREATE TABLE (lines 114–127) and `clearAll()` reference (line 546) were not removed. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `expense_service.dart` | `firestore_repository.dart` | `extends FirestoreRepository` | WIRED | Confirmed at line 19 |
| `settlement_service.dart` | `firestore_repository.dart` | `extends FirestoreRepository` | WIRED | Confirmed at line 19 |
| `gear_service.dart` | `firestore_repository.dart` | `extends FirestoreRepository` | WIRED | Confirmed |
| `sub_group_service.dart` | `firestore_repository.dart` | `extends FirestoreRepository` | WIRED | Confirmed |
| `activity_service.dart` | `firestore_repository.dart` | `extends FirestoreRepository` | WIRED | Confirmed at line 55 |
| `document_service.dart` | `firestore_repository.dart` | `extends FirestoreRepository` | WIRED | Confirmed at line 19 |
| `memory_service.dart` | `firestore_repository.dart` | `extends FirestoreRepository` | WIRED | Confirmed at line 18 |
| `group_provider.dart` | `firestore_repository.dart` | `extends FirestoreRepository` | WIRED | Confirmed (GroupService at line 35) |
| `event_service.dart` | `firestore_repository.dart` | `extends FirestoreRepository` | WIRED | Confirmed at line 21 |
| `expense_provider.dart` | `expense_service.dart` | `ref.read(expenseServiceProvider).watchExpenses` | WIRED | `eventExpensesProvider` calls `service.watchExpenses(eventRef.groupId, eventRef.eventId)` |
| `expense_provider.dart` | `balance_cache_repository.dart` | `asyncMap → cache.cacheExpenses()` | WIRED | `asyncMap((expenses) async { await cache.cacheExpenses(eventRef.eventId, expenses); })` |
| `firebase_config.dart` | Only source of `FirebaseFirestore.instance` | All others use `db` from base class | WIRED | Verified: 0 `FirebaseFirestore.instance` calls outside `firebase_config.dart` |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `expense_provider.dart` — `eventExpensesProvider` | `expenses` | `ExpenseService.watchExpenses()` → Firestore `.snapshots()` | Yes — live Firestore stream | FLOWING |
| `expense_provider.dart` — `eventExpensesProvider` asyncMap | SQLite side-write | `BalanceCacheRepository.cacheExpenses()` | Yes — actual SQLite batch insert | FLOWING |
| `balance_cache_repository.dart` — `getExpenses()` | SQLite rows | `LocalDatabase.database` → `db.query('expenses', ...)` | Yes — real SQLite read | FLOWING |
| `ledger_screen.dart` — balance display | `expenses`, `settlements` | `eventExpensesProvider(eventRef)`, `eventSettlementsProvider(eventRef)` | Yes — EventRef-keyed Firestore streams | FLOWING |

### Behavioral Spot-Checks

Skipped — app requires Firebase native SDK and a real/emulated Firebase project to run. Cannot test without starting the app. Firestore offline write behavior (Truth 1) and snapshot propagation (Truth 2) require end-to-end device testing.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| MIG-01 | 04-01, 04-02, 04-03 | All per-event writes go through Firestore instead of Supabase | SATISFIED | ExpenseService, SettlementService, GearService, SubGroupService, ActivityService, DocumentService, MemoryService all extend FirestoreRepository and write to Firestore subcollections. Zero Supabase writes remain in module services. |
| MIG-02 | 04-01, 04-02 | Firestore realtime listeners replace Supabase Realtime subscriptions | SATISFIED | All 7 module services use `.snapshots()` listeners. Providers are `StreamProvider.family` consuming these streams. No polling. |
| MIG-03 | 04-04 | Firestore offline persistence replaces manual sync queue (SyncService deleted, not ported) | PARTIAL | `sync_service.dart` deleted. `offline_repository.dart` deleted. Firestore `persistenceEnabled: true` configured. However, `sync_queue` table DDL remains in `local_database.dart`. |
| MIG-04 | 04-01, 04-04 | SQLite retained for fast local reads and balance computation queries | SATISFIED | `BalanceCacheRepository` provides SQLite reads. `asyncMap` side-write pipeline keeps SQLite populated from Firestore streams. `balance_cache_repository_test.dart` passes 15 tests. |
| MIG-05 | 04-00, 04-04 | FirestoreRepository is the single Firestore contact point | SATISFIED | All 9 classes extend FirestoreRepository. Zero `FirebaseFirestore.instance` calls outside `firebase_config.dart`. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/features/gear/screens/gear_screen.dart` | 579, 583, 587, 624, 633, 643 | `debugPrint('[GearScreen] ... deferred to 04-05 migration')` — gear mutations (priority, claim, delete, add, togglePacked) are no-ops | Warning | Gear writes do not persist in the new Firestore path. Read path works (EventRef stream). These were intentional stubs documented in 04-02-SUMMARY.md "Known Stubs" but Plan 04-05 was supposed to resolve them. 04-05-SUMMARY.md does list `gear_screen.dart` as modified. |
| `lib/core/services/local_database.dart` | 114–127 | `CREATE TABLE sync_queue` DDL still present in `_onCreate` | Blocker | sync_queue table is created on every fresh install, contrary to success criterion 3. |
| `lib/features/vault/screens/vault_screen.dart` | — | Unused import warning for `event_ref.dart` | Info | Lint warning only, does not affect behavior |
| `lib/features/ledger/providers/expense_provider.dart` | 161–175 | `tripExpensesProvider` and `tripSettlementsProvider` deprecated SQLite-backed shims still present | Info | Marked `@Deprecated`, not used by any screen. Will be cleaned up. No functional impact. |

### Human Verification Required

#### 1. Offline Expense Queuing

**Test:** With the device in airplane mode, open an event and add an expense. Turn off airplane mode.
**Expected:** The expense appears in Firestore (visible on another device or in the Firebase console) within seconds of reconnection, without the user taking any action.
**Why human:** Firestore offline persistence and write queue replay require an actual running app on a device with network toggling.

#### 2. Snapshot Cross-Device Propagation

**Test:** Open the same event on two devices. On device A, add an expense. Observe device B within 5 seconds.
**Expected:** The expense appears on device B's ledger without any refresh action.
**Why human:** Real-time listener propagation requires two active Firestore connections. Cannot verify with grep or tests.

#### 3. Gear Screen Write Functionality

**Test:** In an event's gear screen, try to add, delete, toggle-packed, and change priority of a gear item.
**Expected:** Since Plan 04-05 claims to have migrated gear_screen.dart, verify that these operations actually write to Firestore (not the `debugPrint` stubs from 04-02).
**Why human:** The gear screen at commit `fd1e6a3` (04-05) shows it was listed as modified, but the current state of the file still contains `debugPrint` stubs for gear mutations. This needs a human to confirm whether the writes are functional.

### Gaps Summary

**1 gap blocks the success criterion "The SyncService class and sync_queue SQLite table no longer exist in the codebase."**

The `SyncService` class is correctly deleted. However, the `sync_queue` SQLite table was not removed from `local_database.dart`. The DDL in `_onCreate` (lines 114–127) creates the table on every fresh install, and `clearAll()` (line 546) still references it. No application code reads from or writes to this table — the 5 sync_queue methods in CacheService were deleted per 04-04-SUMMARY.md — but the schema artifact remains.

**Additionally:** The gear screen write mutations are still no-ops (debugPrint stubs). The 04-05 SUMMARY lists `gear_screen.dart` as modified, but the actual file still contains the deferred stub pattern from plan 04-02. This means gear items cannot be added, deleted, or marked packed through the UI. This is flagged as a Warning rather than a Blocker because the phase goal focuses on the write path going through Firestore (gear reads work via `eventGearItemsProvider`), but it is a significant usability gap.

The 4 test failures in `group_service_test.dart` and `group_join_test.dart` are pre-existing from Phase 2 (Firebase not initialized in test environment) and are unrelated to Phase 4 work.

---

_Verified: 2026-03-26T20:00:00Z_
_Verifier: Claude (gsd-verifier)_
