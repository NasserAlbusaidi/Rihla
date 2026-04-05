---
phase: 33-ledger
plan: "01"
subsystem: ledger-screens
tags: [flutter, riverpod, ledger, settle-up, edit-expense, module-header, skeleton-loader, wcag]

# Dependency graph
requires:
  - phase: 33-ledger
    plan: "00"
    provides: Compilable ledger test suite with eventDetailProvider override pattern

provides:
  - SettleUpScreen with dark ModuleHeader and SkeletonLoader loading state
  - EditExpenseScreen with dark ModuleHeader in all states and SkeletonLoader on loading
  - WCAG-compliant section headers using textSecondary in SettleUpScreen
affects: [33-02]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - SettleUpScreen loading pattern: dark ModuleHeader with title only, then SkeletonLoader.expenseList()
    - SettleUpScreen loaded pattern: ModuleHeader with event.name.toUpperCase() as subtitle + OfflineBanner
    - EditExpenseScreen loading pattern: dark ModuleHeader + Expanded(SkeletonLoader.expenseList())
    - Section header WCAG rule: use textSecondary (#6B7280) for functional labels, not textMuted (#9CA3AF)

key-files:
  created: []
  modified:
    - lib/features/ledger/screens/settle_up_screen.dart
    - lib/features/ledger/screens/edit_expense_screen.dart
    - test/features/ledger_test.dart

key-decisions:
  - "Test file fix included in Task 1 commit as blocking deviation — ledger_test.dart in this worktree still used old LedgerScreen(event:, group:) constructor"
  - "EditExpenseScreen ModuleHeader was already present in loaded/error/not-found states — only loading state needed updating"
  - "SettleUpScreen loading state for eventAsync also updated to show ModuleHeader (plan only called out expensesAsync loading)"

requirements-completed: [LEDGER-VISUAL-SETTLEUP, LEDGER-VISUAL-EDIT]

# Metrics
duration: 12min
completed: 2026-04-05
---

# Phase 33 Plan 01: SettleUpScreen and EditExpenseScreen Visual Refresh Summary

**SettleUpScreen gets dark ModuleHeader with event subtitle and SkeletonLoader; EditExpenseScreen loading state gets ModuleHeader + SkeletonLoader; WCAG section headers fixed**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-04-05T11:10:00Z
- **Completed:** 2026-04-05T11:22:00Z
- **Tasks:** 2 (+ 1 pre-fix deviation)
- **Files modified:** 3

## Accomplishments

- Removed `_buildHeader` method from SettleUpScreen — replaced with `ModuleHeader(title: 'Settle Up', subtitle: event.name.toUpperCase(), useDarkTheme: true)`
- Removed `SafeArea` wrapper from SettleUpScreen body — ModuleHeader handles SafeArea internally
- Added `OfflineBanner` after ModuleHeader in SettleUpScreen (consistent with all other module screens)
- Replaced both `CircularProgressIndicator` loading states in SettleUpScreen with `SkeletonLoader.expenseList()`
- Fixed WCAG: `_buildSectionHeader` now uses `textSecondary` (#6B7280, 5.74:1) instead of `textMuted` (#9CA3AF, 2.86:1) for 'YOUR ACTIONS', 'WAITING FOR OTHERS', 'OTHERS SETTLING' labels
- Removed unused `shadow_tokens.dart` import from SettleUpScreen
- Added `SkeletonLoader.expenseList()` loading state to EditExpenseScreen with dark ModuleHeader
- Removed `const` from EditExpenseScreen loading Scaffold (needed dynamic children)

## Task Commits

1. **Task 1: Replace SettleUpScreen header, SafeArea, and loading spinners** - `cf503c6` (feat)
2. **Task 2: Replace EditExpenseScreen loading-state CircularProgressIndicator** - `6a27908` (feat)

## Files Created/Modified

- `lib/features/ledger/screens/settle_up_screen.dart` — ModuleHeader + OfflineBanner + SkeletonLoader + WCAG section headers + removed _buildHeader + removed SafeArea + removed shadow_tokens import
- `lib/features/ledger/screens/edit_expense_screen.dart` — Loading state now shows ModuleHeader + SkeletonLoader; added skeleton_loader.dart import
- `test/features/ledger_test.dart` — Fixed LedgerScreen constructor calls from (event:, group:) to (groupId:, eventId:); added eventDetailProvider and eventUnifiedLedgerProvider overrides; removed Group import and mockGroup local variable

## Decisions Made

- Test file fix included in Task 1 commit as a blocking deviation — the worktree had old LedgerScreen(event:, group:) constructor calls not updated from Phase 33 Plan 00 work (which ran in a different worktree)
- EditExpenseScreen loaded/error/not-found states already had ModuleHeader — only the loading state was missing it
- SettleUpScreen eventAsync loading state also updated (not just the expensesAsync loading state) for visual consistency

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fix ledger_test.dart: old LedgerScreen constructor syntax**
- **Found during:** Task 1 (pre-verification step)
- **Issue:** `test/features/ledger_test.dart` in this worktree still used `LedgerScreen(event: event, group: mockGroup)` constructor calls. Phase 33-00 work was done in a different worktree and its test changes were not in this branch. All 6 tests failed to compile.
- **Fix:** Updated all 4 inline `LedgerScreen(event:, group:)` calls to `LedgerScreen(groupId:, eventId:)`. Added `eventDetailProvider` and `eventUnifiedLedgerProvider` overrides to `_wrapLedger` helper and all 3 inline `ProviderScope` blocks. Removed unused `Group` import and `_mockGroup`/`mockGroup` variable.
- **Files modified:** `test/features/ledger_test.dart`
- **Commit:** `cf503c6` (included with Task 1)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary prerequisite. No scope creep.

## Known Stubs

None — both screens render real provider data with no hardcoded placeholders.

## Issues Encountered

None beyond the test file sync issue above.

## Next Phase Readiness

- 33-02 (AddExpenseScreen header + skeleton) can proceed
- All 6 ledger tests pass with current state
- SettleUpScreen and EditExpenseScreen both comply with the dark gradient header pattern established in phases 28-32

---
*Phase: 33-ledger*
*Completed: 2026-04-05*
