---
phase: 18-home-dashboard-redesign
verified: 2026-03-30T00:00:00Z
status: human_needed
score: 12/14 must-haves verified
human_verification:
  - test: "Confirm dashboard scrolls smoothly at 60fps on a mid-range Android device"
    expected: "No frame exceeds 16ms. CustomScrollView + Slivers layout produces no jank as the user scrolls through balance hero, group cards, activity strip, and weekly spending card."
    why_human: "Frame timing requires DevTools Performance view on a real or emulator device. Cannot be verified statically or by unit tests."
  - test: "Confirm quick-action tray (Add Expense, Settle Up, Invite Friend, Activity) is visible without scrolling on a typical phone screen"
    expected: "The tray sits directly below the balance hero card and above the group list; on a 390dp-wide, ~800dp-tall screen the tray is visible in the initial viewport without any scroll."
    why_human: "Requires visual inspection on a device or emulator. Static analysis cannot measure rendered viewport height."
---

# Phase 18: Home Dashboard Redesign — Verification Report

**Phase Goal:** The home screen surfaces enough information that a user can answer "what do I owe across all groups?" and reach any group's event without a second tap

**Verified:** 2026-03-30
**Status:** human_needed — all automated checks pass; 2 items require device inspection
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | crossGroupBalanceProvider returns the current user's net balance as a Decimal across all groups | VERIFIED | `lib/features/groups/providers/group_balance_provider.dart` line 300 — `Provider<AsyncValue<CrossGroupBalance>>` loops over `userGroupsProvider` and sums `UserBalance.netBalance` per group via `groupBalancesProvider` |
| 2 | crossGroupActivityProvider returns the 5 most recent activity entries merged chronologically from all groups | VERIFIED | `lib/features/home/providers/dashboard_providers.dart` lines 37-70 — loops `userGroupsProvider`, watches `groupActivityProvider(group.id)`, sorts descending by timestamp, takes sublist(0, 5) |
| 3 | weeklyGroupSpendingProvider returns daily spending totals for the current week | VERIFIED | `lib/features/home/providers/dashboard_providers.dart` lines 92-154 — computes Monday startOfWeek, iterates all groups/events/expenses, buckets by day, returns 7 `DailySpending` entries |
| 4 | AppColors.errorText, AppColors.successText, and 4 new bottom-nav/offline tokens exist as static constants | VERIFIED | `lib/core/theme/app_theme.dart` lines 45-54 — 6 static const Color fields confirmed |
| 5 | HomeKeys has 12+ new semantic keys for all new dashboard widgets | VERIFIED | `lib/features/home/keys/home_keys.dart` lines 16-31 — 12 new keys: balanceHeroCard, quickActionTray, activitySection, weeklySpendingCard, 4 action keys, 4 bottom nav keys |
| 6 | BalanceHeroCard renders three distinct visual states: red text for "You owe", green text for "You are owed", gray text for "All settled up" | VERIFIED | `lib/features/home/widgets/balance_hero_card.dart` — Dart 3 switch on `net.compareTo(Decimal.zero)` using `AppColors.errorText`, `AppColors.successText`, `AppColors.textSecondary`; 5 passing unit tests confirm behavior |
| 7 | QuickActionTray shows 4 labeled icon buttons in a horizontal row | VERIFIED | `lib/features/home/widgets/quick_action_tray.dart` — 4 `_QuickActionButton` children: "Add Expense", "Settle Up", "Invite Friend", "Activity"; all wrapped in `TapBounce` with HomeKeys |
| 8 | ActivityRow displays avatar circle, actor name, description, group name tag, and relative timestamp | VERIFIED | `lib/features/home/widgets/activity_row.dart` — `CircleAvatar` with deterministic hashCode color, `timeago.format`, group tag chip; 2 passing widget tests |
| 9 | WeeklySpendingCard renders 7 proportional-height teal bars for Mon-Sun with day labels | VERIFIED | `lib/features/home/widgets/weekly_spending_card.dart` — 7 `Expanded` columns, `AppColors.primary` bars, division-by-zero guard, "No spending this week" empty state; 3 passing widget tests |
| 10 | BottomNavShell has 4 tabs (Groups, Activity, Chats, Profile) with placeholder screens for non-Groups tabs | VERIFIED | `lib/features/home/widgets/bottom_nav_shell.dart` — `BottomNavigationBarType.fixed`, `IndexedStack`, `_PlaceholderTab` with "Coming soon"; 3 passing widget tests |
| 11 | Home screen is a single-scroll dashboard with balance hero, quick-action tray, group cards, activity strip, and weekly spending card | VERIFIED | `lib/features/home/screens/home_screen.dart` (451 lines) — `CustomScrollView` with 6 sliver sections; 12 passing dashboard integration tests |
| 12 | GroupCard shows user's personal net balance instead of totalSpent | VERIFIED | `lib/features/groups/widgets/group_card.dart` — `ref.watch(currentUserIdProvider)`, Dart 3 switch on `net.compareTo`, "You owe OMR X.XXX" / "You are owed OMR X.XXX" / "Settled" with correct AppColors tokens |
| 13 | Dashboard scrolls smoothly at 60fps on mid-range Android device | UNCERTAIN | CustomScrollView + SliverToBoxAdapter structure is correct; `cacheExtent: 2000` pre-builds slivers; actual frame timing requires device verification |
| 14 | Quick-action tray is visible on home screen without scrolling | UNCERTAIN | Tray is positioned immediately after BalanceHeroCard in layout; actual above-fold visibility depends on rendered device dimensions |

**Score:** 12/14 truths verified (2 require human device inspection)

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|---------|--------|---------|
| `lib/core/theme/tokens/color_tokens.dart` | 4 new token fields | VERIFIED | `offlineBannerBackground`, `bottomNavBackground`, `bottomNavActiveIcon`, `bottomNavInactiveIcon` — required constructor params, final fields, light instance values, copyWith and lerp updated |
| `lib/core/theme/app_theme.dart` | 6 new AppColors static constants | VERIFIED | `errorText`, `successText`, `offlineBannerBackground`, `bottomNavBackground`, `bottomNavActiveIcon`, `bottomNavInactiveIcon` |
| `lib/features/home/keys/home_keys.dart` | 12+ new semantic keys | VERIFIED | 12 new Key constants in 3 groups (sections, actions, bottom nav) |
| `lib/features/groups/providers/group_balance_provider.dart` | crossGroupBalanceProvider + CrossGroupBalance typedef + currentUserIdProvider | VERIFIED | All 3 present; provider watches groupBalancesProvider in loop |
| `lib/features/home/providers/dashboard_providers.dart` | crossGroupActivityProvider + weeklyGroupSpendingProvider + typedefs | VERIFIED | New file, 166 lines, all 4 declarations present and substantive |
| `lib/features/home/widgets/balance_hero_card.dart` | BalanceHeroCard ConsumerWidget | VERIFIED | Class exists, watches crossGroupBalanceProvider, 3-state rendering, SkeletonLoader.dashboardHero on loading |
| `lib/features/home/widgets/quick_action_tray.dart` | QuickActionTray StatelessWidget | VERIFIED | Class exists, 4 callbacks, TapBounce, HomeKeys wired |
| `lib/features/home/widgets/activity_row.dart` | ActivityRow StatelessWidget | VERIFIED | Class exists, CircleAvatar, timeago.format, group tag chip |
| `lib/features/home/widgets/weekly_spending_card.dart` | WeeklySpendingCard ConsumerWidget | VERIFIED | Class exists, 7-bar chart, division-by-zero guard, HomeKeys.weeklySpendingCard |
| `lib/features/home/widgets/bottom_nav_shell.dart` | BottomNavShell StatefulWidget | VERIFIED | Class exists, IndexedStack, BottomNavigationBarType.fixed, "Coming soon" placeholders |
| `lib/features/home/screens/home_screen.dart` | Rewritten dashboard (min 150 lines) | VERIFIED | 451 lines, CustomScrollView, all 5 widget sections, 4 screen states |
| `lib/features/groups/widgets/group_card.dart` | GroupCard with personal balance display | VERIFIED | AppColors.errorText present, currentUserIdProvider used, "You owe"/"You are owed"/"Settled" switch expression |
| `test/features/home/home_screen_dashboard_test.dart` | Dashboard integration tests with BalanceHeroCard | VERIFIED | 459 lines, 12 tests all passing, full provider overrides |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `group_balance_provider.dart` | `groupBalancesProvider` | `ref.watch` in loop | WIRED | Line 326: `ref.watch(groupBalancesProvider(group.id))` iterates over all groups |
| `dashboard_providers.dart` | `groupActivityProvider` | `ref.watch` in loop | WIRED | Line 53: `ref.watch(groupActivityProvider(group.id))` inside group loop |
| `balance_hero_card.dart` | `crossGroupBalanceProvider` | `ref.watch` | WIRED | Line 25: `final balanceAsync = ref.watch(crossGroupBalanceProvider)` |
| `weekly_spending_card.dart` | `weeklyGroupSpendingProvider` | `ref.watch` | WIRED | Line 24: `final spendingAsync = ref.watch(weeklyGroupSpendingProvider)` |
| `home_screen.dart` | `crossGroupBalanceProvider` | BalanceHeroCard widget | WIRED | Line 136: `const SliverToBoxAdapter(child: BalanceHeroCard())` |
| `home_screen.dart` | `crossGroupActivityProvider` | ActivityRow widgets | WIRED | Line 119: `ref.watch(crossGroupActivityProvider)` feeds ActivityRow list |
| `home_screen.dart` | `weeklyGroupSpendingProvider` | WeeklySpendingCard widget | WIRED | Line 181: `const SliverToBoxAdapter(child: WeeklySpendingCard())` |
| `group_card.dart` | `groupBalancesProvider` | `ref.watch` for personal balance | WIRED | Line 29: `ref.watch(currentUserIdProvider)` + groupBalancesProvider watch for balance lookup |
| `home_screen.dart` | `/group/:id` | `context.push` from GroupCard onTap | WIRED | Lines 163/166: `context.push('/group/${group.id}')` — route defined in `app_router.dart` line 127 |

---

## Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| `balance_hero_card.dart` | `balanceAsync` (CrossGroupBalance) | `crossGroupBalanceProvider` → `groupBalancesProvider` → Firestore `GroupService` | Yes — reads real UserBalance from Firestore-backed groupBalancesProvider | FLOWING |
| `weekly_spending_card.dart` | `spendingAsync` (List<DailySpending>) | `weeklyGroupSpendingProvider` → `eventExpensesProvider` → Firestore | Yes — traces to Firestore expense queries; Decimal.zero returned for days with no expenses (correct behavior) | FLOWING |
| `home_screen.dart` ActivitySection | `activityAsync` (List<CrossGroupActivityEntry>) | `crossGroupActivityProvider` → `groupActivityProvider` → Firestore | Yes — reads GroupActivityLog from Firestore stream | FLOWING |
| `group_card.dart` | `uid` / `balancesAsync` | `currentUserIdProvider` → `FirebaseConfig.currentUser?.uid` | Yes — Firebase Auth real UID at runtime; injectable for tests | FLOWING |

---

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Unit tests pass (tokens, providers) | `flutter test test/unit/color_tokens_test.dart test/unit/cross_group_balance_test.dart test/unit/dashboard_providers_test.dart` | 20/20 tests passed | PASS |
| Widget tests pass (all home widgets) | `flutter test test/features/home/` | 35/35 tests passed | PASS |
| Full test suite (no regressions) | `flutter test` | 743/743 tests passed | PASS |
| Flutter analyze (no errors/warnings) | `flutter analyze lib/features/home/ lib/features/groups/widgets/group_card.dart lib/core/theme/` | No issues found | PASS |
| All 6 Phase 18 commits exist in git | `git log --oneline | grep "feat(18"` | 199c47c, 1aebc84, ed2d23e, 0c814c4, a4b4bd2, 974548a all present | PASS |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| NAV-01 | 18-01, 18-02, 18-03 | Home screen shows single-scroll dashboard with balance hero, inline group cards, quick-action tray, and recent activity | SATISFIED | `home_screen.dart` uses CustomScrollView with BalanceHeroCard, QuickActionTray, FadeInList(GroupCards), ActivitySection, WeeklySpendingCard — all in one scroll |
| NAV-02 | 18-01, 18-03 | User can see net cross-group balance (color-coded green/red/gray) on home screen without tapping | SATISFIED | BalanceHeroCard renders immediately with crossGroupBalanceProvider data; errorText/successText/textSecondary color coding verified by 5 unit tests |
| NAV-04 | 18-03 | User can reach any module screen within 2 taps from home dashboard | SATISFIED (first tap delivered, second tap pre-exists) | Tap 1: GroupCard → `context.push('/group/:id')` → GroupDetailScreen (wired in app_router.dart line 127). Tap 2: group detail → CommandCenter (pre-existing from Phase 2). Plan 03 explicitly documents this scope boundary. |
| NAV-06 | 18-03 | All empty screens show contextual illustrations with single clear CTA | SATISFIED | Empty state: EmptyStateView("Create your first group", CTA: "Create Group") at line 255-259. Error state: OfflineBanner + EmptyStateView("Something went wrong") + "Retry" + "View Offline Data" at lines 270-294. Tests 5-8 verify these states. |

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/features/home/screens/home_screen.dart` | 288 | `onPressed: () {}` on "View Offline Data" TextButton | Info | Empty handler is intentional and documented in plan ("Phase 19 will wire offline data view"). Not a blocker — the button is visible and Phase 19 will complete it. |
| `lib/features/home/widgets/bottom_nav_shell.dart` | 97 | `_PlaceholderTab` with "Coming soon" for Activity, Chats, Profile tabs | Info | Intentional per plan spec — Phase 19 wires real GoRouter routes for non-Groups tabs. Does not prevent NAV-06 satisfaction. |

Both anti-patterns are intentional, documented stubs explicitly deferred to Phase 19. Neither prevents the Phase 18 goal.

---

## Human Verification Required

### 1. 60fps Dashboard Scroll Performance

**Test:** Run `flutter run --dart-define-from-file=config.json` on a mid-range Android device or emulator. Open DevTools Performance view (or `flutter run --profile`). Scroll the home dashboard slowly from top to bottom through all 5 sections (balance hero → quick-action tray → group cards → activity strip → weekly spending chart).

**Expected:** No frame exceeds 16ms. Timeline shows no green/yellow/red bars in the "UI Thread" row during scrolling. CustomScrollView + SliverToBoxAdapter layout renders without layout thrashing.

**Why human:** Frame timing requires real rendering on hardware or emulator with DevTools. Static analysis cannot verify 60fps performance.

---

### 2. Quick-Action Tray Above the Fold

**Test:** Run the app on a typical phone screen (~390dp wide, ~800dp tall). With groups present (loaded state), note whether the QuickActionTray (4 buttons: Add Expense, Settle Up, Invite Friend, Activity) is visible without any scrolling.

**Expected:** The tray appears in the initial viewport immediately below the BalanceHeroCard, before the group cards section begins. The user does not need to scroll to see the tray.

**Why human:** Above-fold placement depends on rendered pixel heights of the header + BalanceHeroCard card on an actual device screen. Cannot be calculated from static code alone.

---

## Gaps Summary

No gaps blocking phase goal achievement. All 12 automated truths verified, all key links wired, all data flows to real Firestore-backed providers, all 743 tests pass with zero regressions.

Two items require human verification on device:
- 60fps scroll performance (Success Criterion 4 from ROADMAP.md)
- Quick-action tray above-fold visibility (Success Criterion 5 from ROADMAP.md)

These cannot be verified statically. The underlying code structure is correct for both (CustomScrollView + Slivers, QuickActionTray positioned second in the sliver list).

---

_Verified: 2026-03-30_
_Verifier: Claude (gsd-verifier)_
