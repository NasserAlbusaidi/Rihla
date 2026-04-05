---
phase: 30-group-settle-up-activity
plan: "02"
subsystem: groups/settle-up
tags: [ui, flutter, settle-up, tabs, cards, history]
dependency_graph:
  requires:
    - "30-00 (TDD stubs, GroupKeys phase 30 additions)"
    - "30-01 (groupSettlementsProvider, currentUserIdProvider, GroupStatsGrid D-12)"
  provides:
    - "GroupSettleUpScreen with 4-tab layout (D-01, D-02, D-03)"
    - "GroupSettlementTile card-style with collapsible breakdown (D-04)"
    - "Record Payment bottom sheet with warm token polish (D-05)"
    - "All-settled state D-06 preserved"
    - "History tab from groupSettlementsProvider (D-03)"
    - "preSelectedMemberId tab auto-select (D-22)"
  affects:
    - "lib/features/groups/screens/group_settle_up_screen.dart"
    - "lib/features/groups/widgets/group_settlement_tile.dart"
    - "lib/features/groups/widgets/group_settlement_summary.dart"
    - "test/features/groups/group_settle_up_screen_test.dart"
tech_stack:
  added: []
  patterns:
    - "SingleTickerProviderStateMixin for 4-tab TabController"
    - "AnimatedSize + AnimatedRotation for collapsible tile breakdown"
    - "currentUserIdProvider for testable UID injection (no direct Firebase read)"
    - "disableAnimations: true in test MediaQuery to prevent flutter_animate timers"
key_files:
  created: []
  modified:
    - lib/features/groups/screens/group_settle_up_screen.dart
    - lib/features/groups/widgets/group_settlement_tile.dart
    - lib/features/groups/widgets/group_settlement_summary.dart
    - lib/features/groups/keys/group_keys.dart
    - test/features/groups/group_settle_up_screen_test.dart
decisions:
  - "currentUserIdProvider used in screen (not FirebaseConfig directly) so tests can inject UID via override"
  - "disableAnimations in test MediaQuery required to suppress flutter_animate timers — GroupSettlementTile uses AnimatedRotation/AnimatedSize which have own tickers"
  - "Per-event breakdown remains collapsible (AnimatedSize) — not auto-expanded in tests"
  - "GroupSettlementGroupCard removed — each tile is self-contained card"
metrics:
  duration_seconds: 1067
  completed_date: "2026-04-05"
  tasks_completed: 3
  files_modified: 5
---

# Phase 30 Plan 02: Settle-Up Screen Redesign Summary

Tabbed GroupSettleUpScreen with card-style settlement tiles, History tab streaming from groupSettlementsProvider, polished Record Payment bottom sheet, and all 23 tests passing.

## What Was Built

### Task 1: GroupSettlementTile redesign (D-04)
Converted `GroupSettlementTile` from a flat `StatelessWidget` to a card-style `StatefulWidget` with:
- **Card**: `cardSurface` background, `radiusLarge` (16dp) border-radius, `shadowRaised`, border with 50% alpha
- **Avatar pair**: 40dp overlapping avatars (-20dp offset) for payer and payee
- **Sub-label**: "You owe X" / "X owes you" / "X owes Y" depending on tab context
- **Amount colors**: `errorText` (You Owe), `successText` (Owed to You), `textPrimary` (Between Others)
- **Collapsible breakdown**: `AnimatedSize` + `AnimatedRotation` chevron, 200ms `easeOutCubic`
- **Record Payment CTA**: `primaryGradient` container, `buttonHeight` 52dp, white text 17sp/700
- **Removed**: `GroupSettlementGroupCard` class

Also fixed duplicate key declarations in `group_keys.dart` (same keys defined in two sections).

### Task 2: GroupSettleUpScreen 4-tab rewrite (D-01, D-02, D-03, D-05, D-06)
Full rewrite of `GroupSettleUpScreen`:
- **Header**: `ModuleHeader(title: 'Settle Up', subtitle: group.name, useDarkTheme: true)`
- **TabController**: `SingleTickerProviderStateMixin`, `length: 4`
- **AppTabBar**: tabs `['You Owe', 'Owed to You', 'Between Others', 'History']`
- **Tab filtering**: uses `currentUserIdProvider` (injectable) to filter settlements by tab
- **History tab**: streams from `groupSettlementsProvider`, shows payer/recipient avatars + date
- **Per-tab empty states**: contextual copy per UI-SPEC (D-02)
- **All-settled state** (D-06): "All settled up" / "Everyone is square." when all zeros + empty history
- **Record Payment bottom sheet**: warm input tokens (`inputFillWarm`, `borderWarm`, `focusBorderWarm`), gradient CTA, white text
- **Entrance animations**: `fadeIn` + `slideY(0.1)` stagger per tile index
- **preSelectedMemberId**: `_autoSelectTab` called in `build` with injected UID
- **Removed**: `_buildSectionHeader`, `_buildSettlementGroup`, old `_buildHeader`

### Task 3: Test updates (Wave 0 stubs unskipped)
Updated test file with 23 tests (all passing):
- Added `groupSettlementsProvider` + `groupEventsProvider` + `currentUserIdProvider` to `_wrap`
- Added `disableAnimations: true` in `MediaQuery` wrapper to prevent flutter_animate timer failures
- Unskipped and fleshed out 6 Phase 30 stubs: 4-tab render, debtor tab, history, collapsible tiles, per-tab empty state, all-settled
- Unskipped 2 GroupStatsGrid D-12 stubs: `'You owe'` / `'Owed to you'`
- Updated existing tests: `'Record Settlement'` → `'Record Payment'`, all-settled copy updated

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Duplicate key declarations in group_keys.dart**
- **Found during:** Task 1 pre-read
- **Issue:** Phase 30 keys (settleUpTabBar, settleUpYouOweTab, etc.) were declared twice in the file — once around line 63 (from Wave 0) and again at line 122 (from Plan 01 work). Dart doesn't allow duplicate class members.
- **Fix:** Removed the second duplicate block, kept the first clean set.
- **Files modified:** `lib/features/groups/keys/group_keys.dart`
- **Commit:** 8acfa71

**2. [Rule 1 - Bug] Screen read currentUid from FirebaseConfig directly**
- **Found during:** Task 3 (tests failing with Firebase exception)
- **Issue:** `_GroupSettleUpScreenState._currentUid` getter read `FirebaseConfig.currentUser?.uid` directly, ignoring `currentUserIdProvider`. This made tests fail with `[core/no-app] No Firebase App '[DEFAULT]'` when running without Firebase initialized.
- **Fix:** Added `final currentUid = ref.watch(currentUserIdProvider)` in `build()`, removed the `_currentUid` getter, threaded `currentUid` through `_buildTabLayout` and `_autoSelectTab`.
- **Files modified:** `lib/features/groups/screens/group_settle_up_screen.dart`
- **Commit:** cccbb7b

**3. [Rule 2 - Missing] `groupEventsProvider` not overridden in test `_wrap`**
- **Found during:** Task 3 (pending timer failures from live stream subscription)
- **Issue:** The screen watches `groupEventsProvider` to build `eventNameMap`. Without an override, the test subscribes to a real Firestore stream, creating pending timers.
- **Fix:** Added `groupEventsProvider` override to `_wrap` helper with empty events by default.
- **Files modified:** `test/features/groups/group_settle_up_screen_test.dart`
- **Commit:** cccbb7b

## Success Criteria Verification

1. GroupSettleUpScreen uses ModuleHeader instead of custom header (D-01) — ✓
2. Screen shows 4 tabs: You Owe / Owed to You / Between Others / History (D-02, D-03) — ✓
3. Settlement tiles are card-style with collapsible breakdown (D-04) — ✓
4. Record Settlement bottom sheet has token polish with "Record Payment" CTA (D-05) — ✓
5. "All settled" empty state preserved as "All settled up" (D-06) — ✓
6. History tab streams from groupSettlementsProvider — ✓
7. preSelectedMemberId auto-selects correct tab — ✓
8. All widget tests pass (23 tests) — ✓
9. GroupStatsGrid 'You owe'/'Owed to you' subtitle verified in tests (D-12) — ✓

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| lib/features/groups/screens/group_settle_up_screen.dart | FOUND |
| lib/features/groups/widgets/group_settlement_tile.dart | FOUND |
| test/features/groups/group_settle_up_screen_test.dart | FOUND |
| .planning/phases/30-group-settle-up-activity/30-02-SUMMARY.md | FOUND |
| Commit 8acfa71 (Task 1: tile redesign) | FOUND |
| Commit b51c329 (Task 2: screen rewrite) | FOUND |
| Commit cccbb7b (Task 3: tests updated) | FOUND |
| flutter analyze lib/features/groups/ | PASSED (0 issues) |
| flutter test test/features/groups/ | PASSED (97 tests) |
