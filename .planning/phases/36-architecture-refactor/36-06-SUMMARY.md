---
phase: 36-architecture-refactor
plan: "06"
subsystem: cache-layer
tags: [refactor, sqlite, riverpod, decomposition, arch-04]
dependency_graph:
  requires: [36-00 (test scaffolding, not executed — test created inline), 36-01..05 (Wave 1)]
  provides: [9 domain cache repos, expenseCacheRepositoryProvider, settlementCacheRepositoryProvider, participantCacheRepositoryProvider, ARCH-04]
  affects: [expense_provider.dart, trip_provider.dart, test/architecture/]
tech_stack:
  added: []
  patterns: [domain-repository, riverpod-provider, delete-then-insert ghost-row-free, cascading-transaction]
key_files:
  created:
    - lib/core/services/cache/expense_cache_repository.dart
    - lib/core/services/cache/settlement_cache_repository.dart
    - lib/core/services/cache/trip_cache_repository.dart
    - lib/core/services/cache/gear_cache_repository.dart
    - lib/core/services/cache/participant_cache_repository.dart
    - lib/core/services/cache/sub_group_cache_repository.dart
    - lib/core/services/cache/activity_log_cache_repository.dart
    - lib/core/services/cache/category_cache_repository.dart
    - lib/core/services/cache/group_cache_repository.dart
    - test/unit/expense_cache_repository_test.dart
    - test/unit/settlement_cache_repository_test.dart
    - test/architecture/no_cache_service_test.dart
  modified:
    - lib/features/trip/providers/trip_provider.dart
    - lib/features/ledger/providers/expense_provider.dart
    - lib/core/README.md
  deleted:
    - lib/core/services/cache_service.dart
    - lib/core/services/balance_cache_repository.dart
    - test/unit/balance_cache_repository_test.dart
decisions:
  - "delete-then-insert (not ConflictAlgorithm.replace) is mandatory for expense and settlement tables — prevents ghost rows from server-side Firestore deletes persisting in SQLite"
  - "watchExpenses/watchSettlements deprecated streams NOT ported — already confirmed zero consumers after Plan 04-05"
  - "tripExpensesProvider and tripSettlementsProvider deleted (zero consumers verified before deletion)"
  - "SQLite schema version kept at 6 — no column or table changes"
  - "trip_id column name preserved in all 9 repos — stores eventId by historical convention, rename requires migration"
metrics:
  duration: "~25 minutes"
  completed: "2026-04-16"
  tasks: 4 (+ task-0 RED test)
  files_created: 12
  files_deleted: 3
  files_modified: 3
  loc_created: 844 (repos) + 374 (tests) = 1218
  loc_deleted: ~1183 (cache_service 660 + balance_cache_repository 219 + old test 304)
requirements: [ARCH-04]
---

# Phase 36 Plan 06: CacheService Decomposition Summary

**One-liner:** Decomposed the 660-line all-static `CacheService` god class and misnamed `BalanceCacheRepository` into 9 instance-based domain cache repositories under `lib/core/services/cache/`, each with a Riverpod provider and documented conflict strategy.

## What Was Built

### 9 Domain Cache Repositories

| File | Class | Conflict Strategy | Tables |
|------|-------|-------------------|--------|
| `expense_cache_repository.dart` | `ExpenseCacheRepository` | delete-all-for-event + batch-insert | `expenses` |
| `settlement_cache_repository.dart` | `SettlementCacheRepository` | delete-all-for-event + batch-insert | `settlements` |
| `trip_cache_repository.dart` | `TripCacheRepository` | upsert + cascading transaction delete | `trips` + 8 related |
| `gear_cache_repository.dart` | `GearCacheRepository` | delete-all + batch-insert (snapshot); single upsert (addItem) | `gear_items` |
| `participant_cache_repository.dart` | `ParticipantCacheRepository` | delete-all + batch-insert | `participants` |
| `sub_group_cache_repository.dart` | `SubGroupCacheRepository` | FK-ordered delete (members first) + batch-insert | `sub_groups`, `sub_group_members` |
| `activity_log_cache_repository.dart` | `ActivityLogCacheRepository` | delete-all + batch-insert, 50-row read cap | `activity_logs` |
| `category_cache_repository.dart` | `CategoryCacheRepository` | delete-all + batch-insert | `categories` |
| `group_cache_repository.dart` | `GroupCacheRepository` | upsert + explicit cascade delete | `groups`, `group_members` |

### Callers Migrated

| File | Before | After |
|------|--------|-------|
| `trip_provider.dart:21` | `CacheService.getCachedParticipants(tripId)` | `ref.read(participantCacheRepositoryProvider).getCachedParticipants(tripId)` |
| `expense_provider.dart:60` | `ref.read(balanceCacheRepositoryProvider).cacheExpenses(...)` | `ref.read(expenseCacheRepositoryProvider).cacheExpenses(...)` |
| `expense_provider.dart:85` | `ref.read(balanceCacheRepositoryProvider).cacheSettlements(...)` | `ref.read(settlementCacheRepositoryProvider).cacheSettlements(...)` |

### Deprecated Providers Removed

- `tripExpensesProvider` — deleted (zero consumers confirmed by grep)
- `tripSettlementsProvider` — deleted (zero consumers confirmed by grep)

### Test Files

- `test/unit/expense_cache_repository_test.dart` — 7 tests including ghost-row prevention test
- `test/unit/settlement_cache_repository_test.dart` — 6 tests including ghost-row prevention test
- `test/architecture/no_cache_service_test.dart` — 3 ARCH-04 enforcement tests (GREEN)

## Verification Results

| Check | Result |
|-------|--------|
| `flutter test test/architecture/no_cache_service_test.dart` | GREEN (3/3) |
| `flutter test test/unit/` | GREEN (560 tests) |
| `flutter analyze lib/` | No errors (38 pre-existing info warnings) |
| `grep -rn 'CacheService\.' lib/` | 0 matches |
| `grep -rn 'balanceCacheRepositoryProvider' lib/` | 0 matches |
| `lib/core/services/cache_service.dart` exists | false |
| `lib/core/services/balance_cache_repository.dart` exists | false |
| `ls lib/core/services/cache/*.dart \| wc -l` | 9 |
| `grep '_databaseVersion' lib/core/services/local_database.dart` | `= 6` (unchanged) |

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

**Task 0 (pre-plan):** Wave 0 plan 36-00 was never executed, so `test/architecture/no_cache_service_test.dart` did not exist. Created it as a RED test first (committed separately), then made it GREEN through the plan's tasks. This matches the directive in the execution objective.

**Import path correction (Rule 1):** Initial import paths used `../../features/` (wrong — 2 levels from `cache/`). Corrected to `../../../features/` (3 levels: cache → services → core → lib). Caught by `flutter analyze` immediately on first run.

**Dangling doc comment (Rule 1):** File-top `///` comments triggered `dangling_library_doc_comments` analyzer info. Fixed by converting to `//` with perl one-liner before committing.

## Known Stubs

None — all 9 repositories are fully wired. No placeholder data flows to UI.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes introduced. SQLite schema version unchanged at 6.

## Self-Check: PASSED

- All 12 created files exist: VERIFIED
- All 3 deleted files absent: VERIFIED
- Commits 41cfbd1, 1bbdb17, aefb9f0, 27893d7, 366e886 exist: VERIFIED
- Architecture test GREEN: VERIFIED
- Unit suite 560 tests: VERIFIED
