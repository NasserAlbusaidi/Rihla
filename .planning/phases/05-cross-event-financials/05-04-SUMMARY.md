---
phase: 05-cross-event-financials
plan: "04"
subsystem: ui
tags: [flutter, riverpod, iconsax, decimal, widget, group-dashboard]

# Dependency graph
requires:
  - phase: 05-03
    provides: groupBalancesProvider, GroupBalances typedef, groupActivityProvider

provides:
  - GroupBalanceHero widget: dark gradient hero card with animated totals and Settle Up CTA
  - GroupSpendingStats widget: horizontal scrollable chips with top spenders
  - GroupMemberBalanceCard widget: expandable accordion tile with per-event breakdown and onSettleUpTap (D-22)
  - GroupActivityTile widget: icon-coded activity log entry with relative timestamp
  - Widget tests for GroupMemberBalanceCard: 7 tests covering balance states, expand/collapse, D-22

affects: [05-05-group-detail-screen, any feature assembling group dashboard UI]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "GroupBalanceHero is a StatelessWidget (not ConsumerWidget) — parent reads provider and passes data down"
    - "AnimatedCrossFade for expand/collapse (300ms easeOutCubic); RotationTransition for chevron"
    - "TweenAnimationBuilder<double> (800ms easeOutCubic) for animating currency amounts on GroupBalanceHero"
    - "Accordion pattern: parent manages isExpanded + onExpandChanged; child fires callback on tap"
    - "GroupActivityTile uses Dart 3 switch expression for icon/color mapping"

key-files:
  created:
    - lib/features/groups/widgets/group_balance_hero.dart
    - lib/features/groups/widgets/group_spending_stats.dart
    - lib/features/groups/widgets/group_member_balance_card.dart
    - lib/features/groups/widgets/group_activity_tile.dart
  modified:
    - test/features/group_balance_card_test.dart

key-decisions:
  - "GroupBalanceHero shows 'YOU OWE' pill (rose) or 'YOU ARE OWED' pill (mint) based on sign of userNetBalance"
  - "AnimatedCrossFade keeps both first/second children in widget tree — test assertions adjusted to test Settle button presence rather than text visibility"
  - "GroupSpendingStats limits topSpenders to 3 with .take(3) to prevent horizontal overflow"
  - "GroupActivityTile uses Dart 3 pattern switch expression for clean icon/color dispatch"

patterns-established:
  - "Widget tests check color via Text.style?.color.value comparison against AppColors constant"
  - "Settle button (D-22) rendered only when balance != 0 AND onSettleUpTap != null"
  - "All amount formatting uses AppFormatters.formatCurrency(amount.abs(), currency) with explicit sign prefix"

requirements-completed:
  - FIN-03
  - FIN-06

# Metrics
duration: 10min
completed: 2026-03-26
---

# Phase 05 Plan 04: Group Dashboard UI Widgets Summary

**Four StatelessWidget/StatefulWidget building blocks for the group dashboard: dark gradient hero card (animated totals + settle CTA), scrollable spending stats chips, expandable member balance accordion (D-22 entry point 2), and icon-coded activity feed tile.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-03-26T22:20:30Z
- **Completed:** 2026-03-26T22:26:17Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- GroupBalanceHero: dark gradient card (#0F172A→#1E293B, borderRadius 32) with TweenAnimationBuilder animated total spent, status pill (YOU OWE/YOU ARE OWED), sub-line net position, and primaryGradient Settle Up CTA — disabled with "All settled" text when userNetBalance == 0 (D-21)
- GroupSpendingStats: SingleChildScrollView horizontal row of surfaceLight chips with Iconsax.chart_2 for total and Iconsax.profile_circle for top spenders (max 3)
- GroupMemberBalanceCard: StatefulWidget with AnimatedCrossFade expand/collapse, RotationTransition chevron, per-event breakdown rows, "Settled" badge for zero balance, and "Settle" TextButton (D-22 entry point 2) in expanded state
- GroupActivityTile: icon-coded entries with 36px circle icon container, RichText actor+description, relative timestamp
- 7 widget tests covering positive/negative/zero balance display, accordion tap-to-expand, and D-22 settle-up callback

## Task Commits

1. **Task 1: GroupBalanceHero and GroupSpendingStats** - `f76eb3d` (feat)
2. **Task 2: GroupMemberBalanceCard, GroupActivityTile, and widget tests** - `363a936` (feat)

**Plan metadata:** _(docs commit below)_

## Files Created/Modified

- `lib/features/groups/widgets/group_balance_hero.dart` - Dark gradient hero card widget
- `lib/features/groups/widgets/group_spending_stats.dart` - Horizontal scrollable stats chips
- `lib/features/groups/widgets/group_member_balance_card.dart` - Expandable accordion balance tile with D-22 settle-up tap
- `lib/features/groups/widgets/group_activity_tile.dart` - Single activity log entry widget
- `test/features/group_balance_card_test.dart` - 7 widget tests (replaced stubs)

## Decisions Made

- AnimatedCrossFade keeps both first/second children in the widget tree simultaneously (Flutter semantics). Test assertions were updated to check button presence/absence rather than text visibility of the event name before expansion.
- GroupSpendingStats caps topSpenders at 3 via `.take(3)` to prevent horizontal chip overflow on narrow screens.
- GroupActivityTile uses Dart 3 switch expression for icon/color dispatch — cleaner than a chain of if-else.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed AnimatedCrossFade test assertion**
- **Found during:** Task 2 (widget tests)
- **Issue:** Test expected `find.text('Camping Trip')` to return `findsNothing` before expand, but `AnimatedCrossFade` renders both children simultaneously in the widget tree (first is hidden via Offstage but still findable by `find.text`)
- **Fix:** Changed the "before expand" assertion to check that the Settle button is absent instead — a meaningful behavioral check that is also accurate given AnimatedCrossFade semantics
- **Files modified:** test/features/group_balance_card_test.dart
- **Verification:** All 7 tests pass with `flutter test`
- **Committed in:** `363a936` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - bug in test assertion)
**Impact on plan:** Test assertion adjusted to match AnimatedCrossFade widget tree semantics. Widget behavior unchanged.

## Issues Encountered

- Minor `prefer_const` lint infos on GroupBalanceHero's `Row` containing non-const children — fixed by making the `Row` itself `const` and removing redundant `const` from child widgets.

## Known Stubs

None — all four widgets receive real data via constructor params. Parent (Plan 05-05) will wire provider data.

## Next Phase Readiness

- All four widget files are ready for Plan 05-05 to compose into GroupDetailScreen
- Widget tests passing, no analyzer issues
- Constructor APIs match the GroupBalances typedef from groupBalancesProvider exactly
- onSettleUpTap callback wired — Plan 05-05 must pass a handler that navigates to the settle-up flow (D-22)

---
*Phase: 05-cross-event-financials*
*Completed: 2026-03-26*
