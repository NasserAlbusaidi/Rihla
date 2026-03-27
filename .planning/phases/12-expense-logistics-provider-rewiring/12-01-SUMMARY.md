---
phase: 12-expense-logistics-provider-rewiring
plan: 01
subsystem: ledger
tags: [riverpod, firebase, expense, provider, cleanup]

requires:
  - phase: 11-gear-write-mutations
    provides: gear mutations pattern used as test reference

provides:
  - payer-override dropdown visible to event creators via event.createdBy == currentUid
  - currency derived from event.currency via eventDetailProvider (not dead SQLite provider)
  - userTripsProvider deleted from codebase
  - widget tests proving payer visibility and currency derivation

affects:
  - ledger screens (add/edit expense flows)
  - any future plan touching split_scope_selector or expense forms

tech-stack:
  added: []
  patterns:
    - "isLeader derived from event.createdBy == currentUid (no Trip/SQLite lookup)"
    - "currency derived from ref.read(eventDetailProvider(...)).valueOrNull?.currency"

key-files:
  created:
    - test/features/ledger/payer_currency_rewiring_test.dart
  modified:
    - lib/features/ledger/widgets/split_scope_selector.dart
    - lib/features/ledger/screens/edit_expense_sheet.dart
    - lib/features/ledger/screens/add_expense_screen.dart
    - lib/features/trip/providers/trip_provider.dart

key-decisions:
  - "trip_model.dart kept in split_scope_selector.dart and edit_expense_sheet.dart because Participant type is used in _ParticipantTile and _buildCustomParticipantSelector — plan assumed it was unused but it is needed"
  - "currentParticipantProvider removed from split_scope_selector.dart — replaced with direct currentUid comparison since participant IDs are Firebase UIDs"

patterns-established:
  - "Event creator check: final currentUid = ref.watch(currentUserProvider)?.uid; final isLeader = currentUid != null && event.createdBy == currentUid;"
  - "Currency from event: ref.read(eventDetailProvider((groupId: ..., eventId: ...))).valueOrNull?.currency ?? 'OMR'"

requirements-completed: [FIN-01]

duration: 6min
completed: 2026-03-27
---

# Phase 12 Plan 01: Fix Payer-Override Visibility and Currency Derivation Summary

**Payer-override dropdown now shows for event creators via event.createdBy == currentUid; currency reads from event.currency via eventDetailProvider; userTripsProvider deleted.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-03-27T21:48:21Z
- **Completed:** 2026-03-27T21:54:22Z
- **Tasks:** 2 (TDD)
- **Files modified:** 5

## Accomplishments
- Fixed payer-override dropdown always-hidden bug by replacing dead `userTripsProvider` SQLite lookup with direct `event.createdBy == currentUid` comparison
- Fixed currency always-OMR bug by reading from `eventDetailProvider` instead of `userTripsProvider`
- Deleted `userTripsProvider` from `trip_provider.dart` — zero references remain in `lib/`
- Wrote 6 widget tests covering: creator sees PAID BY, non-creator doesn't, null user doesn't, BHD currency works, widget renders correctly

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix isLeader and currency derivation in ledger files + delete userTripsProvider** - `a53fc2d` (feat)
2. **Task 2: Write widget tests for payer visibility and currency derivation** - `df62ceb` (test)

## Files Created/Modified
- `lib/features/ledger/widgets/split_scope_selector.dart` - Removed trip_provider.dart import, replaced userTripsProvider trip lookup with event.createdBy == currentUid, replaced currentParticipantProvider with direct currentUid
- `lib/features/ledger/screens/edit_expense_sheet.dart` - Replaced _tripCurrency userTripsProvider lookup with eventDetailProvider, replaced _buildPayerSelector trip lookup with event.createdBy == currentUid
- `lib/features/ledger/screens/add_expense_screen.dart` - Replaced _tripCurrency userTripsProvider lookup with eventDetailProvider, removed diagnostic userTripsProvider block from _submit()
- `lib/features/trip/providers/trip_provider.dart` - Deleted userTripsProvider definition (lines 25-30)
- `test/features/ledger/payer_currency_rewiring_test.dart` - New: 6 widget tests for payer visibility and currency derivation

## Decisions Made
- Kept `trip_model.dart` import in `split_scope_selector.dart` and `edit_expense_sheet.dart` because `Participant` type is referenced in `_ParticipantTile` and `_buildCustomParticipantSelector`. Plan assumed it could be removed but it cannot without refactoring those widgets.
- Removed `currentParticipantProvider` from `split_scope_selector.dart` entirely — replaced all usages with direct `currentUid` comparison since participant IDs are Firebase UIDs.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Kept trip_model.dart import in split_scope_selector.dart and edit_expense_sheet.dart**
- **Found during:** Task 1 (fix isLeader and currency)
- **Issue:** Plan specified removing `trip_model.dart` from both files, but `Participant` type is used in `_ParticipantTile` (split_scope_selector) and `_buildCustomParticipantSelector` (edit_expense_sheet). Removing the import caused compile errors.
- **Fix:** Kept `trip_model.dart` import in both files. All `userTripsProvider` usages were still removed — the essential bug fix is complete.
- **Files modified:** lib/features/ledger/widgets/split_scope_selector.dart, lib/features/ledger/screens/edit_expense_sheet.dart
- **Verification:** `flutter analyze` passes with no errors; `flutter test` passes
- **Committed in:** a53fc2d (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug/correctness)
**Impact on plan:** The deviation keeps `trip_model.dart` import for `Participant` type which is legitimately needed. The core bug fix (removing `userTripsProvider` and replacing with `event.createdBy`) is fully complete. No scope creep.

## Issues Encountered
- `currentParticipantProvider` was used in `_CustomParticipantSelector` and `_PayerSelector` in split_scope_selector.dart. Replaced with direct `currentUid` comparison throughout, enabling full removal of `trip_provider.dart` import from split_scope_selector.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Payer selection now works for event creators — FIN-01 prerequisite resolved
- Plan 12-02 (logistics provider rewiring) can proceed independently
- No blockers

---
*Phase: 12-expense-logistics-provider-rewiring*
*Completed: 2026-03-27*

## Self-Check: PASSED

- FOUND: lib/features/ledger/widgets/split_scope_selector.dart
- FOUND: lib/features/ledger/screens/edit_expense_sheet.dart
- FOUND: lib/features/ledger/screens/add_expense_screen.dart
- FOUND: lib/features/trip/providers/trip_provider.dart
- FOUND: test/features/ledger/payer_currency_rewiring_test.dart
- FOUND: .planning/phases/12-expense-logistics-provider-rewiring/12-01-SUMMARY.md
- FOUND: commit a53fc2d (feat: fix isLeader and currency)
- FOUND: commit df62ceb (test: widget tests)
