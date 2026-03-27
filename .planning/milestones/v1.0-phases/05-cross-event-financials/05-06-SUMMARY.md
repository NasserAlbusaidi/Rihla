---
phase: 05-cross-event-financials
plan: 06
subsystem: ui
tags: [flutter, riverpod, firestore, settlement, activity-log, pagination]

# Dependency graph
requires:
  - phase: 05-cross-event-financials
    provides: groupBalancesProvider, GroupSettlementService, GroupActivityService (Plans 03-05)

provides:
  - GroupSettleUpScreen: full cross-event settlement flow with recording and preSelectedMemberId support
  - GroupActivityScreen: paginated activity log with cursor-based loading

affects: [human-verification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - ConsumerStatefulWidget with ScrollController for auto-scroll to preSelectedMemberId tile
    - Cursor-based ListView pagination via fetchActivityPageRaw + DocumentSnapshot cursor
    - Modal bottom sheet with editable amount field for partial settlement (D-11)

key-files:
  created: []
  modified:
    - lib/features/groups/screens/group_settle_up_screen.dart
    - lib/features/groups/screens/group_activity_screen.dart
    - test/features/group_settle_up_screen_test.dart

key-decisions:
  - "GroupSettleUpScreen uses ConsumerStatefulWidget (not ConsumerWidget) — needs ScrollController for preSelectedMemberId auto-scroll"
  - "Per-event breakdown in settlement tiles derives attribution from perEventBreakdown map: min(fromNegative, toPositive) per event"
  - "Settlement recording catches FirebaseConfig.currentUser in try-catch per test-safety pattern established in Phase 02"
  - "_SkeletonRow is a private StatelessWidget const class — avoids unnecessary_underscores lint for separatorBuilder lambdas"

patterns-established:
  - "ConsumerStatefulWidget cursor-pagination pattern: _activities list, _lastDocument cursor, _hasMore flag, _loadPage() guard"
  - "Modal bottom sheet for settlement: transparent bg, surface container, 28px top radius, drag handle, editable amount + note fields"

requirements-completed: [FIN-04, FIN-07, GRP-05]

# Metrics
duration: 4min
completed: 2026-03-27
---

# Phase 5 Plan 06: GroupSettleUpScreen and GroupActivityScreen Summary

**Cross-event settlement screen (FIN-04) with optimized tiles, partial-amount editing, and recording flow, plus paginated activity log screen (GRP-05)**

## Performance

- **Duration:** ~4 min (Tasks 1 and 2; Task 3 is human verification checkpoint)
- **Started:** 2026-03-27T07:27:49Z
- **Completed:** 2026-03-27T07:32:00Z
- **Tasks:** 2 of 3 (Task 3 is human checkpoint)
- **Files modified:** 3

## Accomplishments

- GroupSettleUpScreen: replaces placeholder with full ConsumerStatefulWidget — settlement tiles grouped into YOUR ACTIONS / WAITING FOR OTHERS / OTHERS SETTLING, preSelectedMemberId auto-scroll (D-22), per-event breakdown (D-24), modal bottom sheet with editable amount (D-11) and note (D-12), success/error snackbars, all-settled empty state
- GroupActivityScreen: replaces placeholder with cursor-based paginated list — 50 entries/page, Load more button, skeleton loader, EmptyStateView, GroupActivityTile rows with Divider separators
- GroupSettleUpScreen test file: 7 widget tests all green (no skip markers)

## Task Commits

1. **Task 1: Build GroupSettleUpScreen with settlement recording and tests** - `fb4b1ed` (feat)
2. **Task 2: Build GroupActivityScreen with cursor pagination** - `93d5207` (feat)

## Files Created/Modified

- `lib/features/groups/screens/group_settle_up_screen.dart` — Full GroupSettleUpScreen replacing placeholder; 550+ lines; watches groupBalancesProvider, calls BalanceCalculator.calculateOptimalSettlements, shows settlement tiles with recording flow
- `lib/features/groups/screens/group_activity_screen.dart` — Full GroupActivityScreen replacing placeholder; cursor-based pagination with fetchActivityPageRaw
- `test/features/group_settle_up_screen_test.dart` — 7 testWidgets, no skip markers; covers tiles, all-settled state, loading state, bottom sheet

## Decisions Made

- GroupSettleUpScreen uses ConsumerStatefulWidget (not ConsumerWidget) because it needs a ScrollController state field for preSelectedMemberId auto-scroll.
- Per-event breakdown attribution uses `min(|fromNetNegative|, toNetPositive)` per event ID to compute how much of the settlement is attributable to each event.
- FirebaseConfig.currentUser wrapped in try-catch (per Phase 02 pattern) so widget tests without Firebase initialization don't crash.
- _SkeletonRow extracted as a named private StatelessWidget const class to avoid unnecessary_underscores lint warning in separatorBuilder/itemBuilder lambdas.

## Deviations from Plan

None — plan executed exactly as written. Tests adjusted their assertions to handle the fact that `FirebaseConfig.currentUser` returns null in widget tests (all settlements fall into OTHERS SETTLING, not YOUR ACTIONS), which is the expected test-safe behavior.

## Issues Encountered

- First test run: `find.textContaining('Bob')` failed on RichText widgets. Fixed by using `tester.widgetList<RichText>(...).map((rt) => rt.text.toPlainText()).join()` to extract plain text from RichText.
- `prefer_const_constructors` and `unnecessary_underscores` lint warnings in GroupActivityScreen. Fixed inline.

## Known Stubs

None — both screens are fully wired to their providers and services.

## Next Phase Readiness

Tasks 1 and 2 complete. Awaiting Task 3: human verification of the complete Phase 5 feature set.

- GroupSettleUpScreen and GroupActivityScreen are live in the groups feature
- Both screens are navigable from GroupDetailScreen (wired in Plan 05)
- Human must verify: settlement flow end-to-end, pagination, offline behavior

## Self-Check: PASSED

All created files found. All commits verified.

---
*Phase: 05-cross-event-financials*
*Completed: 2026-03-27 (partial — checkpoint at Task 3)*
