---
phase: 18-home-dashboard-redesign
plan: "02"
subsystem: home-dashboard-widgets
tags: [widgets, riverpod, tdd, home-dashboard, bottom-nav, skeleton]
dependency_graph:
  requires:
    - crossGroupBalanceProvider (18-01)
    - crossGroupActivityProvider (18-01)
    - weeklyGroupSpendingProvider (18-01)
    - HomeKeys (18-01)
    - AppColors.errorText / successText / bottomNav* (18-01)
    - TapBounce (Phase 17)
    - SkeletonLoader.dashboardHero / generic (Phase 17)
  provides:
    - BalanceHeroCard (ConsumerWidget)
    - QuickActionTray (StatelessWidget)
    - ActivityRow (StatelessWidget)
    - WeeklySpendingCard (ConsumerWidget)
    - BottomNavShell (StatefulWidget)
  affects:
    - lib/features/home/widgets/ (5 new files)
    - test/features/home/balance_hero_card_test.dart
    - test/features/home/widgets_test.dart
tech_stack:
  added:
    - balance_hero_card.dart (BalanceHeroCard ConsumerWidget)
    - quick_action_tray.dart (QuickActionTray StatelessWidget)
    - activity_row.dart (ActivityRow StatelessWidget with timeago)
    - weekly_spending_card.dart (WeeklySpendingCard ConsumerWidget with bar chart)
    - bottom_nav_shell.dart (BottomNavShell StatefulWidget with IndexedStack)
  patterns:
    - ConsumerWidget for Riverpod data (BalanceHeroCard, WeeklySpendingCard)
    - StatelessWidget for pure display (ActivityRow, QuickActionTray)
    - StatefulWidget for tab state (BottomNavShell)
    - IndexedStack for tab body preservation (RESEARCH Pitfall 3)
    - BottomNavigationBarType.fixed for 4-tab display (RESEARCH Pitfall 3)
    - Division-by-zero guard in WeeklySpendingCard (RESEARCH Pitfall 5)
    - Deterministic avatar color via hashCode % Colors.primaries.length
    - TDD: RED tests first, GREEN implementation, all tests pass
key_files:
  created:
    - lib/features/home/widgets/balance_hero_card.dart
    - lib/features/home/widgets/quick_action_tray.dart
    - lib/features/home/widgets/activity_row.dart
    - lib/features/home/widgets/weekly_spending_card.dart
    - lib/features/home/widgets/bottom_nav_shell.dart
    - test/features/home/balance_hero_card_test.dart
    - test/features/home/widgets_test.dart
  modified:
    - lib/features/home/widgets/balance_hero_card.dart (minor tearoff cleanup)
decisions:
  - "BalanceHeroCard uses Dart 3 switch expression on net.compareTo(Decimal.zero) for clean three-state rendering"
  - "QuickActionTray puts keys on _QuickActionButton instances (not the inner Icon) so find.byKey() works reliably in tests"
  - "WeeklySpendingCard renders a 2dp stub bar for zero-amount days rather than hiding them — avoids chart collapse"
  - "BottomNavShell does NOT use GoRouter for tab switching (RESEARCH Pitfall 3) — Phase 19 wires real routes"
  - "ActivityRow timestamps use textMuted (#9CA3AF) — decorative only per WCAG rules (timestamps are non-functional)"
metrics:
  duration_minutes: 10
  completed_date: "2026-03-30"
  tasks_completed: 2
  tasks_total: 2
  files_created: 7
  files_modified: 1
  tests_added: 17
  tests_total: 731
---

# Phase 18 Plan 02: Widget Components Summary

**One-liner:** Five home dashboard widgets (BalanceHeroCard, QuickActionTray, ActivityRow, WeeklySpendingCard, BottomNavShell) with TDD, consuming Plan 01 providers and tokens — 17 new tests, 731 total, flutter analyze clean.

## Tasks Completed

### Task 1: BalanceHeroCard and QuickActionTray widgets

Created `lib/features/home/widgets/balance_hero_card.dart`:
- `ConsumerWidget` watching `crossGroupBalanceProvider`
- Three visual states via Dart 3 switch on `net.compareTo(Decimal.zero)`:
  - Negative: `AppColors.errorText` (#B91C1C) + "You owe OMR X.XXX across N groups"
  - Positive: `AppColors.successText` (#047857) + "You are owed OMR X.XXX across N groups"
  - Zero: `AppColors.textSecondary` + "All settled up" + "OMR 0.000"
- `SkeletonLoader.dashboardHero()` on loading state
- Error fallback card ("Balance unavailable") with gray styling
- `HomeKeys.balanceHeroCard` key on outer container

Created `lib/features/home/widgets/quick_action_tray.dart`:
- `StatelessWidget` with 4 required callbacks
- `TapBounce`-wrapped `_QuickActionButton` private widgets
- 4 buttons: Add Expense, Settle Up, Invite Friend, Activity
- All HomeKeys wired (`quickActionTray`, `addExpenseAction`, `settleUpAction`, `inviteAction`, `activityAction`)
- 48x48 icon containers (WCAG minimum touch target)

**Commit:** `ed2d23e`

### Task 2: ActivityRow, WeeklySpendingCard, and BottomNavShell widgets

Created `lib/features/home/widgets/activity_row.dart`:
- `StatelessWidget` with `GroupActivityLog`, `groupName`, `groupId`, `onTap` params
- `CircleAvatar` with deterministic color: `Colors.primaries[hashCode.abs() % length]`
- Layout: avatar | name+description row | group tag chip + timeago timestamp
- `InkWell(onTap: onTap)` for optional tap navigation
- textMuted for timestamp (decorative-only per WCAG rules)

Created `lib/features/home/widgets/weekly_spending_card.dart`:
- `ConsumerWidget` watching `weeklyGroupSpendingProvider`
- Container-based bar chart: 7 `Expanded` columns, max 60dp bar height
- Division-by-zero guard: `maxAmount > Decimal.zero ? fraction : 0.0`
- "No spending this week" empty state when all amounts zero
- `SkeletonLoader.generic(count: 3)` on loading, error text on failure
- `HomeKeys.weeklySpendingCard` key on card container

Created `lib/features/home/widgets/bottom_nav_shell.dart`:
- `StatefulWidget` with `int _currentIndex = 0` state
- `IndexedStack` with 4 children: [child, Placeholder, Placeholder, Placeholder]
- `BottomNavigationBarType.fixed` (RESEARCH Pitfall 3 — required for 4-tab label display)
- Colors: `bottomNavBackground`/`bottomNavActiveIcon`/`bottomNavInactiveIcon` from AppColors
- Tabs: Groups (Iconsax.people), Activity (Iconsax.activity), Chats (Iconsax.message), Profile (Iconsax.profile_circle)
- `_PlaceholderTab` widget with "Coming soon" text
- All HomeKeys wired on nav icons

**Commit:** `0c814c4`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed unnecessary_lambdas lint warnings in BalanceHeroCard and WeeklySpendingCard**
- **Found during:** Task 2 flutter analyze
- **Issue:** `when(loading: () => SkeletonLoader.dashboardHero(), data: (x) => _buildCard(x))` triggers `unnecessary_lambdas` and `unnecessary_underscores` lint rules
- **Fix:** Converted to tearoffs where valid: `loading: SkeletonLoader.dashboardHero, data: _buildCard` in both files; kept named params `error: (error, stack) => ...` since `_buildErrorCard` has no params
- **Files modified:** `lib/features/home/widgets/balance_hero_card.dart`, `lib/features/home/widgets/weekly_spending_card.dart`
- **Commit:** `0c814c4`

## Known Stubs

None. All widgets consume real providers from Plan 01. `BottomNavShell` placeholder tabs ("Coming soon") are intentional per plan specification — Phase 19 (Navigation Restructuring) will wire real GoRouter routes for Activity/Chats/Profile tabs.

## Self-Check: PASSED

Files verified:
- `lib/features/home/widgets/balance_hero_card.dart` — `class BalanceHeroCard extends ConsumerWidget` ✓
- `lib/features/home/widgets/quick_action_tray.dart` — `class QuickActionTray` ✓
- `lib/features/home/widgets/activity_row.dart` — `class ActivityRow` + `timeago.format` + `CircleAvatar` ✓
- `lib/features/home/widgets/weekly_spending_card.dart` — `class WeeklySpendingCard` + `HomeKeys.weeklySpendingCard` + `This Week` + `No spending this week` ✓
- `lib/features/home/widgets/bottom_nav_shell.dart` — `class BottomNavShell` + `BottomNavigationBarType.fixed` + `IndexedStack` + `Coming soon` ✓
- `test/features/home/balance_hero_card_test.dart` — 9 tests pass ✓
- `test/features/home/widgets_test.dart` — 8 tests pass ✓
- Full suite: 731 tests pass (17 new, 0 regressions) ✓
- `flutter analyze lib/features/home/widgets/` — no issues ✓

Commits verified:
- `ed2d23e` feat(18-02): add BalanceHeroCard and QuickActionTray widgets with TDD tests ✓
- `0c814c4` feat(18-02): add ActivityRow, WeeklySpendingCard, and BottomNavShell widgets with TDD tests ✓
