---
phase: 08-integration-correctness-fixes
plan: 01
subsystem: ledger
tags: [provider-swap, sqlite-comments, fix, tdd]
dependency_graph:
  requires: []
  provides: [EVT-08-fix1, fix3-column-comments]
  affects: [split_scope_selector, add_expense_screen, edit_expense_sheet, expense_provider, balance_cache_repository, cache_service]
tech_stack:
  added: []
  patterns: [eventLogisticsParticipantsProvider-over-SQLite, Event-object-passing]
key_files:
  created:
    - test/unit/provider_swap_test.dart
  modified:
    - lib/features/ledger/widgets/split_scope_selector.dart
    - lib/features/ledger/screens/add_expense_screen.dart
    - lib/features/ledger/screens/edit_expense_sheet.dart
    - lib/features/ledger/providers/expense_provider.dart
    - lib/core/services/balance_cache_repository.dart
    - lib/core/services/cache_service.dart
decisions:
  - "Pass Event object (not eventId String) to SplitScopeSelector so provider swap works without inner Firestore fetch"
  - "eventAsync null-guard in AddExpenseScreen shows CircularProgressIndicator while Event loads"
  - "edit_expense_sheet._buildPayerSelector watches eventDetailProvider directly rather than threading Event through build chain"
metrics:
  duration: "~15 min"
  completed: "2026-03-27"
  tasks: 2
  files: 7
---

# Phase 08 Plan 01: Provider Swap and Column Name Comments Summary

Fix #1 (EVT-08) and Fix #3 (D-05/D-06/D-07) from the v1.0 milestone audit — custom split participant picker now works for Firestore-only events, and all 8 SQLite trip_id column usage sites have clarifying comments.

## What Was Done

### Task 1: Column-Name Comments (Fix #3)

Added clarifying comments at all 8 `trip_id` column usage sites across `BalanceCacheRepository` and `CacheService`. The canonical explanation is in `cacheExpenses()` in `BalanceCacheRepository`; the other 7 sites use a shorter back-reference form. No logic changes.

**Counts verified:**
- `balance_cache_repository.dart`: 1 occurrence of "column is named 'trip_id' for historical reasons" + 3 back-references
- `cache_service.dart`: 4 back-references

### Task 2: Provider Swap (Fix #1, EVT-08)

**Root cause fixed:** `SplitScopeSelector` was calling `tripLogisticsParticipantsProvider(tripId)` which reads from the SQLite `participants` table. For Firestore-only events, that table is never populated. `eventLogisticsParticipantsProvider(event)` derives participants directly from `Event.participantIds`/`Event.participantNames` — zero SQLite overhead.

**Changes:**
- `SplitScopeSelector`: constructor changed from `tripId: String` to `event: Event`. Both `_CustomParticipantSelector` and `_PayerSelector` now use `eventLogisticsParticipantsProvider(event)` synchronously.
- `AddExpenseScreen`: added `eventDetailProvider` watch in `build()`, passes `event:` to `SplitScopeSelector`, removed debug `tripLogisticsParticipantsProvider` call from `_submit()`.
- `EditExpenseSheet._buildPayerSelector`: replaced `tripLogisticsParticipantsProvider` with `eventDetailProvider` + `eventLogisticsParticipantsProvider`.
- `expense_provider.dart`: added deprecation comment on `tripLogisticsParticipantsProvider` usage in the legacy `tripBalancesProvider` shim (not changed — retained as documented shim).

## Deviations from Plan

None — plan executed exactly as written.

## Test Results

- `flutter test test/unit/balance_cache_repository_test.dart`: 14/14 pass
- `flutter test test/unit/provider_swap_test.dart`: 3/3 pass (new tests)
- `flutter test test/unit/`: 441/441 pass
- `flutter analyze --no-fatal-infos`: 0 errors, 0 new warnings introduced by this plan

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 | db5c26a | fix(08-01): add clarifying comments to all 8 trip_id column usage sites |
| Task 2 RED | 7a6b2c7 | test(08-01): add failing test for eventLogisticsParticipantsProvider swap |
| Task 2 GREEN | e03fde2 | feat(08-01): swap tripLogisticsParticipantsProvider to eventLogisticsParticipantsProvider |

## Known Stubs

None.

## Self-Check: PASSED
