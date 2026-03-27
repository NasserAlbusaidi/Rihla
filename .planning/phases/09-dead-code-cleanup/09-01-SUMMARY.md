---
phase: 09-dead-code-cleanup
plan: 01
subsystem: auth, ledger, logistics
tags: [riverpod, dead-code, providers, flutter, firestore]

# Dependency graph
requires:
  - phase: 08-integration-correctness-fixes
    provides: All screens migrated to EventRef providers; tripBalancesProvider had no active callers
  - phase: 04-firestore-repository-layer
    provides: eventBalancesProvider, eventExpensesProvider, eventSettlementsProvider replacing legacy trip providers
provides:
  - firebase_auth_provider.dart deleted (zero callers; canonical auth in auth_provider.dart)
  - tripBalancesProvider removed from expense_provider.dart (orphan since Phase 04 audit)
  - subGroupsByTypeProvider removed from sub_group_provider.dart (zero callers throughout codebase)
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dead provider removal: verify zero callers with grep before deleting; check imports become unused after removal"

key-files:
  created: []
  modified:
    - lib/features/ledger/providers/expense_provider.dart
    - lib/features/logistics/providers/sub_group_provider.dart
  deleted:
    - lib/features/auth/providers/firebase_auth_provider.dart

key-decisions:
  - "firebase_auth_provider.dart deleted entirely (not just gutted) — the file served no purpose; canonical Firebase auth is in auth_provider.dart"
  - "trip_provider.dart import removed from expense_provider.dart — it was exclusively used by tripBalancesProvider; trip_model.dart import retained for Participant/UserBalance types used by BalanceCalculator"

patterns-established:
  - "Orphan provider removal: delete file entirely when all providers in the file are dead rather than leaving an empty file"

requirements-completed: []

# Metrics
duration: 8min
completed: 2026-03-27
---

# Phase 9 Plan 01: Dead Code Cleanup Summary

**Deleted `firebase_auth_provider.dart` and removed `tripBalancesProvider` + `subGroupsByTypeProvider` — three orphaned Riverpod providers with zero callers eliminated, trip_provider.dart import cleaned, 599 tests green.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-27T15:45:00Z
- **Completed:** 2026-03-27T15:53:00Z
- **Tasks:** 1
- **Files modified:** 2 (+ 1 deleted)

## Accomplishments
- Deleted `lib/features/auth/providers/firebase_auth_provider.dart` — entire file removed since both `firebaseAuthStateProvider` and `firebaseCurrentUserProvider` had zero callers anywhere in the codebase; canonical auth lives in `auth_provider.dart`
- Removed `tripBalancesProvider` block (30 lines) from `expense_provider.dart` — marked as dead in Phase 04 audit (D-02) when its only consumers (the old Trip-based CommandCenter widget) were deleted; cleaned up the now-unused `trip_provider.dart` import
- Removed `subGroupsByTypeProvider` (11 lines) from `sub_group_provider.dart` — zero callers throughout lib/ and test/; type filtering handled at screen level

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove 3 orphaned providers and delete empty file** - `b7607e4` (refactor)

## Files Created/Modified
- `lib/features/auth/providers/firebase_auth_provider.dart` - DELETED (entire file; contained only orphaned providers)
- `lib/features/ledger/providers/expense_provider.dart` - Removed `tripBalancesProvider` block + `trip_provider.dart` import (65 lines net reduction)
- `lib/features/logistics/providers/sub_group_provider.dart` - Removed `subGroupsByTypeProvider` block

## Decisions Made
- `firebase_auth_provider.dart` deleted entirely rather than left empty — an empty Dart file with only imports and no exports serves no purpose and creates confusion
- `trip_model.dart` import kept in `expense_provider.dart` — still needed by `BalanceCalculator` (`Participant`, `ParticipantRole`, `UserBalance`) and `eventBalancesProvider`; only `trip_provider.dart` was exclusively used by the now-deleted `tripBalancesProvider`

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. The worktree was initially at the wrong commit (`c06e4c3` from `origin/main` instead of `b8d2e36` from local `main`). Reset to correct HEAD before executing — not a code issue, just worktree setup.

## Known Stubs

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 09 Plan 01 is the only plan in this phase. The dead-code cleanup is complete:
- Zero references to `tripBalancesProvider`, `firebaseAuthStateProvider`, `firebaseCurrentUserProvider`, or `subGroupsByTypeProvider` remain in `lib/` or `test/`
- `flutter analyze` exits with 0 errors
- `flutter test` passes 599/599 tests

---
*Phase: 09-dead-code-cleanup*
*Completed: 2026-03-27*
