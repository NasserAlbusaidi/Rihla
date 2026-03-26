---
phase: "04"
plan: "04"
subsystem: "core/services"
tags: ["firestore", "migration", "sync", "repository-pattern", "sqlite"]
dependency_graph:
  requires: ["04-01", "04-02", "04-03"]
  provides: ["BalanceCacheRepository", "ConnectivityNotifier-Firestore", "FirestoreRepository-base-class"]
  affects: ["ledger", "gear", "activity", "logistics", "trip", "groups", "events"]
tech_stack:
  added: ["sqflite_common_ffi (test-only)"]
  patterns:
    - "FirestoreRepository base class — all Firestore access flows through protected db getter (MIG-05)"
    - "asyncMap side-write pipeline — Firestore snapshot → asyncMap → SQLite BalanceCacheRepository"
    - "Firestore Source.server ping for connectivity detection (replaces Supabase auth.refreshSession)"
key_files:
  created:
    - lib/core/services/balance_cache_repository.dart
    - test/unit/balance_cache_repository_test.dart
    - test/unit/connectivity_provider_test.dart
  modified:
    - lib/core/providers/connectivity_provider.dart
    - lib/core/services/cache_service.dart
    - lib/core/services/firestore_repository.dart
    - lib/features/events/services/event_service.dart
    - lib/features/groups/providers/group_provider.dart
    - lib/features/ledger/providers/expense_provider.dart
    - lib/features/activity/services/activity_service.dart
    - lib/features/gear/providers/gear_provider.dart
    - lib/features/gear/screens/gear_screen.dart
    - lib/features/home/screens/command_center.dart
    - lib/features/logistics/providers/sub_group_provider.dart
    - lib/features/trip/providers/trip_provider.dart
    - test/unit/event_service_test.dart
  deleted:
    - lib/core/services/sync_service.dart
    - lib/core/services/offline_repository.dart
    - test/unit/sync_service_test.dart
    - test/unit/sync_retry_test.dart
    - test/unit/offline_repository_test.dart
decisions:
  - "BalanceCacheRepository replaces OfflineRepository for balance query path — narrow SQLite wrapper with no stream subscriptions to manage"
  - "Firestore Source.server ping replaces Supabase auth.refreshSession for connectivity detection"
  - "Gear seeding for Camping events is now unconditional — no longer gated on Supabase bridge success"
  - "FirestoreRepository.withFirestore annotated @protected (not @visibleForTesting) so subclasses call super.withFirestore without lint"
  - "Deprecated watchExpenses/watchSettlements streams retained in BalanceCacheRepository for backward-compat until 04-05"
metrics:
  duration: "~90 minutes (continued from previous session)"
  completed: "2026-03-26"
  tasks_completed: 2
  tasks_total: 2
  files_changed: 18
requirements: ["MIG-03", "MIG-04", "MIG-05"]
---

# Phase 04 Plan 04: Infrastructure Cleanup and FirestoreRepository Base Class Summary

Delete SyncService + OfflineRepository, create BalanceCacheRepository as their narrow replacement, migrate ConnectivityNotifier to Firestore ping, and establish FirestoreRepository base class inheritance for GroupService and EventService.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Delete SyncService + OfflineRepository, create BalanceCacheRepository, migrate ConnectivityNotifier | 2eafb84 | 17 files changed (592 insertions, 1769 deletions) |
| 2 | GroupService + EventService extend FirestoreRepository, update gear seeding API | e40e804 | 4 files changed (97 insertions, 77 deletions) |

## What Was Built

### Task 1: SyncService Deletion + BalanceCacheRepository + ConnectivityNotifier

**Deleted (MIG-03):**
- `lib/core/services/sync_service.dart` — Supabase polling sync queue entirely removed
- `lib/core/services/offline_repository.dart` — reactive SQLite wrapper removed; balance query path extracted to BalanceCacheRepository

**Created:**
- `lib/core/services/balance_cache_repository.dart` — narrow SQLite wrapper serving BalanceCalculator queries only
  - `cacheExpenses(eventId, expenses)` / `cacheSettlements(eventId, settlements)`: side-write targets for asyncMap pipelines (D-15)
  - `getExpenses(eventId)` / `getSettlements(eventId)`: synchronous reads for BalanceCalculator
  - `watchExpenses` / `watchSettlements`: deprecated backward-compat streams (will be removed in 04-05)
  - `balanceCacheRepositoryProvider`: Riverpod provider for DI

**ConnectivityNotifier rewrite:**
- Replaced `auth.refreshSession()` (Supabase) with a `FirebaseConfig.firestore.collection('_health').doc('ping').get(GetOptions(source: Source.server))` ping
- Removed `SyncController` class entirely — Firestore manages its own offline persistence
- Removed `pendingSyncCountProvider` — no longer meaningful

**CacheService trimmed:**
- Removed 5 sync_queue methods: `addToSyncQueue`, `getPendingSyncItems`, `removeSyncItem`, `hasPendingSync`, `getSyncQueueCount`

**Consumer file updates (no `offlineRepositoryProvider` in lib/):**
- `expense_provider.dart`: asyncMap side-writes to `BalanceCacheRepository`; deprecated providers use `balanceCacheRepositoryProvider`
- `gear_provider.dart`: `tripGearProvider` now returns `Stream.value([])`
- `activity_service.dart`: `tripActivityProvider` / `tripTransactionActivityProvider` stub to `Stream.value([])`
- `sub_group_provider.dart`: `tripSubGroupsProvider` stubs to `Stream.value([])`
- `trip_provider.dart`: `userTripsProvider` uses `CacheService.getCachedTrips()` directly; `tripSeedProvider` is a no-op
- `command_center.dart`: `_tripDataSeedProvider` is a no-op
- `gear_screen.dart`: all mutations stubbed as `debugPrint('[GearScreen] ... deferred to 04-05 migration')`

**Tests:**
- `test/unit/balance_cache_repository_test.dart`: 10 tests using sqflite_common_ffi (in-memory SQLite)
  - cacheExpenses/getExpenses: write, read by eventId, upsert on conflict, exclude deleted
  - cacheSettlements/getSettlements: write, read, exclude deleted
  - watchExpenses: stream emits initial list, empty when no cache
- `test/unit/connectivity_provider_test.dart`: 7 state-machine tests
  - Initial state online, setOffline/setOnline/setSyncing transitions, dispose without error

### Task 2: GroupService + EventService Extend FirestoreRepository

**FirestoreRepository base class change:**
- Changed `@visibleForTesting` → `@protected` on `withFirestore` constructor
- This allows subclasses to call `super.withFirestore(db)` from their own `@visibleForTesting` constructors without triggering `invalid_use_of_visible_for_testing_member` lint

**GroupService refactor:**
- Now `class GroupService extends FirestoreRepository`
- Added `GroupService.withFirestore(this._ref, FirebaseFirestore firestoreDb)` test constructor
- All `_db` field references replaced with `db` from base class
- `FirebaseConfig.firestore` no longer called directly in GroupService

**EventService refactor:**
- Now `class EventService extends FirestoreRepository`
- Added `EventService.withFirestore(FirebaseFirestore firestoreDb, GearService gearService)` test constructor
- Removed `firebase_config.dart` import (no longer needed directly)
- `_seedCampingGear` now calls `addGearItem(groupId:, eventId:, itemName:, isHighPriority:)` per Plan 04-02 API (was `addItem(tripId:, itemName:, isHighPriority:)`)
- Gear seeding for Camping events is now unconditional — no longer gated on Supabase bridge success (`bridgeSucceeded` variable removed)

**Tests updated:**
- `test/unit/event_service_test.dart`: All mock stubs updated from `addItem` to `addGearItem` with the new `(groupId:, eventId:, itemName:, isHighPriority:)` signature

## Acceptance Criteria Verification

```
sync_service.dart deleted:         PASS (D lib/core/services/sync_service.dart)
offline_repository.dart deleted:   PASS (D lib/core/services/offline_repository.dart)
balance_cache_repository.dart:     PASS (A lib/core/services/balance_cache_repository.dart)
BalanceCacheRepository class:      PASS
connectivity uses Source.server:   PASS (2 occurrences)
GroupService extends FR:           PASS (class GroupService extends FirestoreRepository)
EventService extends FR:           PASS (class EventService extends FirestoreRepository)
eventExpensesProvider asyncMap:    PASS (5 occurrences in expense_provider.dart)
no offlineRepositoryProvider:      PASS (0 matches in lib/)
no SyncService in lib/:            PASS (0 matches in lib/)
FirebaseFirestore.instance only in firebase_config.dart: PASS
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Missing `scope` parameter in balance_cache_repository_test.dart helper**
- **Found during:** Test run after Task 1 completion
- **Issue:** `buildExpense()` helper and inline `Expense` constructions were missing the required `scope` named parameter, causing 2 compile errors in test suite
- **Fix:** Added `scope: ExpenseScope.global` to `buildExpense()` helper and inline construction
- **Files modified:** `test/unit/balance_cache_repository_test.dart`
- **Not a separate commit:** Included in Task 1 test file

**2. [Rule 1 - Bug] Dead code warning from `if (false)` block in gear_screen.dart**
- **Found during:** Static analysis after tasks complete
- **Issue:** `_togglePacked` contained an `if (false)` placeholder block left from previous session work
- **Fix:** Removed the dead `if (false)` block entirely
- **Files modified:** `lib/features/gear/screens/gear_screen.dart`

**3. [Rule 1 - Bug] tearDown/setUp DB lifecycle in balance_cache_repository_test.dart**
- **Found during:** Test run (7 of 10 balance_cache_repository tests failing with `DatabaseException(error database_closed)`)
- **Issue:** `tearDown(() => LocalDatabase.close())` closed the in-memory database after each test; the next test's `setUp(() => LocalDatabase.clearAll())` then failed because clearAll fetches the closed DB reference before re-opening
- **Fix:** Changed `tearDown` → `tearDownAll` so the database closes once after ALL tests, not after each. `setUp` now only calls `clearAll()` to reset state between tests
- **Files modified:** `test/unit/balance_cache_repository_test.dart`

### Pre-existing Issues (Out of Scope, Deferred)

The following errors exist in the codebase from Plan 04-03 and are not introduced by this plan:
- `lib/features/ledger/screens/add_expense_screen.dart` — 3 errors: missing `eventId`/`groupId`, unknown `tripId`
- `lib/features/ledger/screens/edit_expense_sheet.dart` — 6 errors: missing `eventId`/`groupId`, unknown `oldExpense`/`newAmount`/etc.

These will be fixed in Plan 04-05 when the ledger screens are migrated to the Firestore LedgerService API.

## Self-Check: PASSED

| Item | Status |
|------|--------|
| `balance_cache_repository.dart` created | FOUND |
| `04-04-SUMMARY.md` created | FOUND |
| `sync_service.dart` deleted | CONFIRMED |
| `offline_repository.dart` deleted | CONFIRMED |
| Commit `2eafb84` (Task 1) | FOUND |
| Commit `e40e804` (Task 2) | FOUND |
