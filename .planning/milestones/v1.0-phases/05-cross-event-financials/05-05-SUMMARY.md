---
phase: 05-cross-event-financials
plan: 05
subsystem: groups/screens
tags: [groups, dashboard, financial-ui, widget-tests, screens]
dependency_graph:
  requires:
    - 05-03  # groupBalancesProvider + groupActivityProvider
    - 05-04  # GroupBalanceHero, GroupSpendingStats, GroupMemberBalanceCard, GroupActivityTile widgets
  provides:
    - GroupDetailScreen with full D-27 financial layout
    - GroupSettleUpScreen placeholder (Plan 06 completes)
    - GroupActivityScreen placeholder (Plan 06 completes)
  affects:
    - lib/features/groups/screens/group_detail_screen.dart
    - test/features/groups/group_screens_test.dart
tech_stack:
  added: []
  patterns:
    - ConsumerStatefulWidget for accordion expand state management
    - Local non-null variable pattern (hasExpensesData) for Dart flow analysis through boolean gates
    - groupBalancesProvider.valueOrNull gating UI sections (D-19)
key_files:
  created:
    - lib/features/groups/screens/group_settle_up_screen.dart
    - lib/features/groups/screens/group_activity_screen.dart
    - test/features/group_detail_screen_test.dart
  modified:
    - lib/features/groups/screens/group_detail_screen.dart
    - test/features/groups/group_screens_test.dart
decisions:
  - "GroupDetailScreen converted to ConsumerStatefulWidget — needed String? _expandedMemberId for accordion state across GroupMemberBalanceCards (D-13)"
  - "hasExpensesData local variable (non-null when expenses exist) used instead of hasExpenses bool — Dart flow analysis cannot narrow nullable type through a stored bool variable, requires direct null check or conditional assignment"
  - "group_screens_test.dart updated with groupBalancesProvider + groupActivityProvider overrides — new screen watches both providers, tests without overrides would attempt real Firestore streams"
metrics:
  duration_minutes: 8
  completed_date: "2026-03-26"
  tasks_completed: 2
  files_changed: 5
---

# Phase 05 Plan 05: GroupDetailScreen Financial Restructure Summary

Restructured GroupDetailScreen into the D-27 layout order and wired all financial widgets from Plan 04. Created placeholder screens for Plan 06.

## What Was Built

**GroupDetailScreen restructure (D-27 layout):** Converted from ConsumerWidget to ConsumerStatefulWidget (accordion state). New scroll body order: stats chips → GroupBalanceHero+GroupSpendingStats (D-19 gated) → Members & Balances → Events → Invite Code (D-30: moved below events) → Recent Activity (D-34).

**GroupBalanceHero gating (D-19):** `hasExpensesData` is non-null only when `totalSpent > 0`. The `if (hasExpensesData != null)` block renders the hero card and spending stats; otherwise only the skeleton or nothing is shown.

**Members & Balances (D-29):** Replaced old plain Members section (GroupMemberTile list) with GroupMemberBalanceCard for each balance in groupBalancesProvider. Accordion controlled by `_expandedMemberId` in state. onSettleUpTap passes `preSelectedMemberId` for D-22 entry point 2. onEventTap calls `_navigateToEventLedger` for FIN-01 per-event drill-down to LedgerScreen.

**Invite Code (D-30):** Moved from position 3 (before members) to after events section.

**Recent Activity (D-34):** Watches groupActivityProvider, shows up to 5 tiles via GroupActivityTile, with "See all activity" TextButton navigating to GroupActivityScreen.

**Placeholder screens:** GroupSettleUpScreen (with `preSelectedMemberId` param for D-22) and GroupActivityScreen — both show "coming in Plan 06" body.

**Widget tests:** 7 new tests in `group_detail_screen_test.dart` verify: hero shows/hides based on totalSpent, Members & Balances header, spending stats chips, Recent Activity section, "See all activity" button, and invite code appears below events (position check via `getTopLeft`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Dart flow analysis cannot narrow nullable type through stored bool**
- **Found during:** Task 1, flutter analyze
- **Issue:** `final hasExpenses = balancesData != null && ...` followed by `if (hasExpenses)` — analyzer cannot promote `balancesData` from nullable because it can't track flow through a stored bool variable.
- **Fix:** Replaced with `hasExpensesData` — a non-nullable local variable assigned conditionally (`balancesData != null ? balancesData : null`). The `if (hasExpensesData != null)` block then properly narrows the type.
- **Files modified:** lib/features/groups/screens/group_detail_screen.dart
- **Commit:** 1de7ea6

**2. [Rule 1 - Bug] group_screens_test missing groupBalancesProvider + groupActivityProvider overrides**
- **Found during:** Task 2, running existing test suite
- **Issue:** group_screens_test `_wrap` function did not override `groupBalancesProvider` or `groupActivityProvider`. The new GroupDetailScreen watches both. Tests failed because the provider.family body would try to watch other providers (groupEventsProvider, etc.) without full mock chain.
- **Fix:** Added both provider overrides to `_wrap`. Used `_membersWithZeroBalance` (two members, zero balances) so GroupMemberBalanceCard renders both names for the existing members test.
- **Files modified:** test/features/groups/group_screens_test.dart
- **Commit:** 2172447

**3. [Rule 1 - Bug] group_screens_test expected old "Members" header text**
- **Found during:** Task 2, running group_screens_test
- **Issue:** Test asserted `find.text('Members')` — changed to `'Members & Balances'` per D-29.
- **Fix:** Updated assertion to `find.text('Members & Balances')`.
- **Files modified:** test/features/groups/group_screens_test.dart
- **Commit:** 2172447

## Known Stubs

- `lib/features/groups/screens/group_settle_up_screen.dart`: Body text "Settle Up -- coming in Plan 06" — intentional placeholder per plan spec. Plan 05-06 delivers full implementation.
- `lib/features/groups/screens/group_activity_screen.dart`: Body text "Group Activity -- coming in Plan 06" — intentional placeholder per plan spec. Plan 05-06 delivers full implementation.

These stubs do not prevent this plan's goal (GroupDetailScreen dashboard) from being achieved — navigation to these screens works; the screens themselves are incomplete scaffolding.

## Self-Check: PASSED

- lib/features/groups/screens/group_detail_screen.dart — FOUND
- lib/features/groups/screens/group_settle_up_screen.dart — FOUND
- lib/features/groups/screens/group_activity_screen.dart — FOUND
- test/features/group_detail_screen_test.dart — FOUND
- feat commit 1de7ea6 — FOUND
- test commit 2172447 — FOUND
