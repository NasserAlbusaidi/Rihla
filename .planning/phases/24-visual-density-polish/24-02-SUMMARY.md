---
phase: 24-visual-density-polish
plan: 02
subsystem: ui
tags: [flutter, chart, bar-labels, spacing, section-header, tdd, riverpod]

# Dependency graph
requires:
  - phase: 24-visual-density-polish plan 01
    provides: GroupCard accent strip and event context line, groupEventsProvider test overrides

provides:
  - WeeklySpendingCard with 'Weekly Spending (OMR)' title and per-bar amount labels
  - Tightened dashboard section spacing (12dp between sections)
  - "Your Groups (N)" section header above group card list

affects:
  - home/widgets/weekly_spending_card.dart
  - home/screens/home_screen.dart

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Conditional label rendering above bar using `if (entry.amount > Decimal.zero)` guard
    - SizedBox height increase (80 → 96) to accommodate label row above bars
    - Section header with dynamic count interpolation using groups.length

key-files:
  created: []
  modified:
    - lib/features/home/widgets/weekly_spending_card.dart
    - lib/features/home/screens/home_screen.dart
    - test/features/home/widgets_test.dart
    - test/features/home/home_screen_dashboard_test.dart

key-decisions:
  - "Used AppColorTokens.light.textSecondary instead of inline Color(0xFF6B7280) — CLAUDE.md hard constraint blocks hardcoded Color(0xFF...) literals"
  - "Extracted _loadedOverrides() to main() scope so section header test group can reference it"
  - "SizedBox height increased to 96 (not 80) to provide headroom for label row without clipping"

patterns-established:
  - "Bar label guard: if (entry.amount > Decimal.zero) before Text label prevents zero-bar labels"

requirements-completed:
  - CHRT-01
  - CHRT-02
  - LAYT-01
  - LAYT-02

# Metrics
duration: 4min
completed: 2026-04-01
---

# Phase 24 Plan 02: Chart Bar Labels, Title, Dashboard Spacing, and Section Header Summary

**WeeklySpendingCard updated with 'Weekly Spending (OMR)' title and per-bar amount labels (toStringAsFixed(1)); dashboard spacing tightened to 12dp; 'Your Groups (N)' section header added above group list.**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-04-01T09:41:08Z
- **Completed:** 2026-04-01T09:45:03Z
- **Tasks:** 2 (TDD RED + GREEN)
- **Files modified:** 4

## Accomplishments

- Chart title changed from ambiguous 'This Week' to informative 'Weekly Spending (OMR)' (CHRT-02)
- Amount labels rendered above non-zero bars using `toStringAsFixed(1)` (e.g., '7.0', '3.5') with Decimal.zero guard suppressing zero-bar labels (CHRT-01)
- Bar container height increased from 80 to 96dp to accommodate the label row without clipping
- Dashboard section spacing tightened from 16dp to 12dp before BalanceHeroCard and from 24dp to 12dp before activity section (LAYT-01)
- 'Your Groups (N)' section header inserted between QuickActionTray and group cards using groups.length interpolation (LAYT-02)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add failing tests for chart labels, title, and section header** - `bac7f88` (test)
2. **Task 2: Implement chart bar labels, title update, dashboard spacing, and section header** - `31b4003` (feat)

_Note: TDD tasks have two commits — test (RED) then feat (GREEN)_

## Files Created/Modified

- `lib/features/home/widgets/weekly_spending_card.dart` — Title changed to 'Weekly Spending (OMR)', bar height 96, amount labels with Decimal.zero guard
- `lib/features/home/screens/home_screen.dart` — SizedBox 12 before hero card, activity padding 12 top, 'Your Groups (N)' section header sliver
- `test/features/home/widgets_test.dart` — Test 3 updated to assert 'Weekly Spending (OMR)', Test NEW-1 for bar labels, Test NEW-2 for zero suppression
- `test/features/home/home_screen_dashboard_test.dart` — Test NEW-3 for 'Your Groups (2)' section header; _loadedOverrides() extracted to main() scope

## Decisions Made

- **Used AppColorTokens.light.textSecondary instead of inline Color(0xFF6B7280):** The plan's UI-SPEC note said inline was acceptable for 9sp labels below the type scale. However, CLAUDE.md hard-constrains all colors to AppColorTokens — CI blocks hardcoded Color(0xFF...) literals. Overrode the plan note and used the token. The token resolves to the same value (0xFF6B7280 = textSecondary), so visual outcome is identical.
- **Extracted _loadedOverrides() to main() scope:** The function was scoped inside the first test group closure, making it inaccessible to the new section header test group. Extracted to file level so all test groups can reference it. This is a structural improvement that makes the test file more maintainable.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Used AppColorTokens token instead of inline Color literal**
- **Found during:** Task 2 (implementation)
- **Issue:** Plan specified `color: Color(0xFF6B7280)` inline for bar label text. CLAUDE.md hard-constrains all colors to AppColorTokens — CI lint blocks hardcoded Color(0xFF...) literals.
- **Fix:** Used `color: AppColorTokens.light.textSecondary` which resolves to the same `#6B7280` value.
- **Files modified:** `lib/features/home/widgets/weekly_spending_card.dart`
- **Verification:** `flutter analyze` reports "No issues found"
- **Committed in:** `31b4003` (Task 2 feat commit)

**2. [Rule 1 - Bug] Extracted _loadedOverrides() to main() scope for test group accessibility**
- **Found during:** Task 1 (writing Test NEW-3)
- **Issue:** _loadedOverrides() was scoped inside the first test group's closure. The new section header test group (added at file level) could not reference it.
- **Fix:** Moved _loadedOverrides() from inside the group closure to the top-level main() function scope (before all group calls).
- **Files modified:** `test/features/home/home_screen_dashboard_test.dart`
- **Verification:** All 60 tests pass.
- **Committed in:** `bac7f88` (Task 1 test commit)

---

**Total deviations:** 2 auto-fixed (1 Rule 2 - token compliance, 1 Rule 1 - test scope bug)
**Impact on plan:** Both auto-fixes necessary for correctness and CLAUDE.md compliance. No scope creep.

## Issues Encountered

None beyond the deviations documented above.

## Known Stubs

None. All chart labels, title, spacing, and section header are wired to live data (`weeklyGroupSpendingProvider`, `groups.length`). No hardcoded or placeholder values.

## Self-Check: PASSED

- `lib/features/home/widgets/weekly_spending_card.dart` — FOUND
- `lib/features/home/screens/home_screen.dart` — FOUND
- `.planning/phases/24-visual-density-polish/24-02-SUMMARY.md` — FOUND (this file)
- Commit `bac7f88` (RED tests) — FOUND
- Commit `31b4003` (GREEN implementation) — FOUND

## Next Phase Readiness

- Phase 24 visual density polish is complete (both plans done)
- All 60 home tests pass
- Chart is now informative with labeled bars and correct title
- Dashboard layout is visually tighter with consistent 12dp section spacing
- Ready for Phase 23 execution or any next milestone phase

---
*Phase: 24-visual-density-polish*
*Completed: 2026-04-01*
