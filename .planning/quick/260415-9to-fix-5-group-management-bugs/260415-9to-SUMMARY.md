---
phase: quick-260415-9to
plan: 01
type: quick-task
completed: "2026-04-15T03:12:52Z"
duration_minutes: 15
tasks_completed: 2
files_modified: 5
commits:
  - hash: c07b2d4
    message: "fix(260415-9to): group management bugs — duplicate join guard, balance-gated leave/delete, awaited operations, tab auto-select"
key_decisions:
  - "Balance guard uses ref.read(groupBalancesProvider).valueOrNull — synchronous read of cached provider state, no async needed"
  - "joinGroup reads groupDoc before any write; existing groupDoc local variable is NOT reused for Step 3 (that read needs the post-write state)"
  - "_hasAutoSelected is a bool state field on _GroupSettleUpScreenState, not initState logic — correctly survives hot reload"
tags: [groups, events, firestore, safety, async]
---

# Quick Task 260415-9to: Fix 5 Group Management Bugs

One-liner: Balance-gated leave/delete, awaited Firestore operations with error snackbars, duplicate-join guard, one-shot tab auto-select.

## Bugs Fixed

| Bug | File | Fix |
|-----|------|-----|
| Bug 8 — duplicate join | group_provider.dart | Read groupDoc before Step 1 memberIds update; throw 'Already a member' if uid in memberIds |
| Bug 9 — unguarded leave | group_danger_section.dart | Check current user netBalance != Decimal.zero before leaveGroup; show settle-up snackbar |
| Bug 9 — unguarded delete | group_danger_section.dart | Check ALL members netBalance != Decimal.zero before deleteGroup; show snackbar |
| Bug 10 — fire-and-forget | event_danger_section.dart, group_danger_section.dart, group_members_section.dart | All 4 locations now async/await with try/catch; navigate only on success |
| Bug 13 — tab hijack | group_settle_up_screen.dart | _hasAutoSelected bool guard; _autoSelectTab exits early on rebuilds after first invocation |
| Bug 21 — atomicity docs | group_provider.dart | createGroup and joinGroup doc comments explain the two-step write tradeoff and why batching is not possible |

## Files Modified

- `lib/features/groups/providers/group_provider.dart` — duplicate-join guard + atomicity documentation
- `lib/features/groups/widgets/group_danger_section.dart` — decimal import, balance-gated leave/delete, async with error handling
- `lib/features/events/widgets/event_danger_section.dart` — async _executeDelete with try/catch
- `lib/features/groups/widgets/group_members_section.dart` — async _handleRemove with try/catch
- `lib/features/groups/screens/group_settle_up_screen.dart` — _hasAutoSelected one-shot guard

## Verification

- `flutter analyze` on all 5 files: no issues
- `flutter test test/`: 892 tests passed, 0 failures
- Pre-existing warning in group_balance_provider.dart (unused_local_variable line 142) — out of scope, not introduced by this task

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- 8f82316 confirmed in git log
- 8d656f5 confirmed in git log
- All 5 modified files verified via flutter analyze
