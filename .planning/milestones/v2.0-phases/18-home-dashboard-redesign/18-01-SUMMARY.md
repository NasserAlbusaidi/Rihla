---
phase: 18-home-dashboard-redesign
plan: "01"
subsystem: theme-tokens, providers, keys
tags: [color-tokens, riverpod, dashboard, aggregation, tdd]
dependency_graph:
  requires: []
  provides:
    - crossGroupBalanceProvider
    - crossGroupActivityProvider
    - weeklyGroupSpendingProvider
    - AppColors.errorText
    - AppColors.successText
    - AppColors.offlineBannerBackground
    - AppColors.bottomNavBackground
    - AppColors.bottomNavActiveIcon
    - AppColors.bottomNavInactiveIcon
    - HomeKeys.balanceHeroCard (+ 11 more keys)
  affects:
    - lib/core/theme/tokens/color_tokens.dart
    - lib/core/theme/app_theme.dart
    - lib/features/home/keys/home_keys.dart
    - lib/features/groups/providers/group_balance_provider.dart
    - lib/features/home/providers/dashboard_providers.dart
tech_stack:
  added:
    - dashboard_providers.dart (new file — cross-group aggregation providers)
    - currentUserIdProvider (injectable UID for testability)
  patterns:
    - Provider-in-loop for variable-length group/event watchers (RESEARCH Pitfall 2)
    - Injectable UID via currentUserIdProvider for Riverpod testability
    - TDD: RED tests first, GREEN implementation, all tests pass
key_files:
  created:
    - lib/features/home/providers/dashboard_providers.dart
    - test/unit/color_tokens_test.dart
    - test/unit/cross_group_balance_test.dart
    - test/unit/dashboard_providers_test.dart
  modified:
    - lib/core/theme/tokens/color_tokens.dart
    - lib/core/theme/app_theme.dart
    - lib/features/home/keys/home_keys.dart
    - lib/features/groups/providers/group_balance_provider.dart
    - test/unit/design_tokens_test.dart
decisions:
  - "Used currentUserIdProvider (injectable Provider) instead of FirebaseConfig.currentUser directly — enables Riverpod override in tests without Firebase Auth mock"
  - "CrossGroupBalance as record typedef (net, groupCount, isLoading) matches the plan spec exactly"
  - "weeklyGroupSpendingProvider uses local DateTime.now() for week computation — consistent with expense.createdAt which is also local time"
  - "Added 4 new required fields to AppColorTokens constructor; updated copyWith and lerp; fixed design_tokens_test.dart lerp test constructors (Rule 1 auto-fix)"
metrics:
  duration_minutes: 8
  completed_date: "2026-03-30"
  tasks_completed: 2
  tasks_total: 2
  files_created: 4
  files_modified: 5
  tests_added: 20
  tests_total: 714
---

# Phase 18 Plan 01: Data Foundation and Token Infrastructure Summary

**One-liner:** Color tokens (offline, bottom-nav), AppColors statics (errorText/successText/nav tokens), HomeKeys expansion (12 new keys), and 3 cross-group aggregation providers (balance, activity, weekly spending) — all TDD with 20 new passing tests.

## Tasks Completed

### Task 1: Add color tokens + HomeKeys expansion

Added 4 new required fields to `AppColorTokens`:
- `offlineBannerBackground` (#F59E0B amber)
- `bottomNavBackground` (#FFFFFF white)
- `bottomNavActiveIcon` (#0D7B74 teal)
- `bottomNavInactiveIcon` (#9CA3AF gray-400)

Added 6 new static constants to the `AppColors` facade:
- `errorText`, `successText` (WCAG-safe semantic text colors)
- `bottomNavBackground`, `bottomNavActiveIcon`, `bottomNavInactiveIcon`
- `offlineBannerBackground`

Added 12 new semantic keys to `HomeKeys`:
- Dashboard sections: `balanceHeroCard`, `quickActionTray`, `activitySection`, `weeklySpendingCard`
- Quick-action buttons: `addExpenseAction`, `settleUpAction`, `inviteAction`, `activityAction`
- Bottom navigation: `bottomNavGroups`, `bottomNavActivity`, `bottomNavChats`, `bottomNavProfile`

**Commit:** `199c47c`

### Task 2: Cross-group balance, activity, and weekly spending providers

Added `currentUserIdProvider` to `group_balance_provider.dart` for injectable UID (testability via Riverpod overrides).

Added `CrossGroupBalance` typedef and `crossGroupBalanceProvider`:
- Aggregates `UserBalance.netBalance` across all groups for the current user
- Handles loading/error states from `userGroupsProvider` and per-group `groupBalancesProvider`

Created `lib/features/home/providers/dashboard_providers.dart` with:
- `CrossGroupActivityEntry` typedef (log, groupName, groupId)
- `crossGroupActivityProvider` — merges per-group activity, sorts newest-first, limits to 5
- `DailySpending` typedef (date, amount)
- `weeklyGroupSpendingProvider` — returns 7 DailySpending entries (Mon-Sun) with expense totals

**Commit:** `1aebc84`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed design_tokens_test.dart lerp test constructors**
- **Found during:** Task 1 implementation
- **Issue:** Adding 4 new required fields to `AppColorTokens` constructor broke 2 lerp tests in `design_tokens_test.dart` that used hard-coded constructors without the new fields
- **Fix:** Added the 4 new fields (`offlineBannerBackground`, `bottomNavBackground`, `bottomNavActiveIcon`, `bottomNavInactiveIcon`) to both `AppColorTokens` const constructor calls in the lerp tests
- **Files modified:** `test/unit/design_tokens_test.dart`
- **Commit:** `199c47c`

**2. [Rule 1 - Bug] Fixed cross_group_balance_test.dart const expression**
- **Found during:** Task 2 RED phase
- **Issue:** Test used `const AsyncValue.data(...)` with `Decimal.zero` inside, which is invalid because `Decimal.zero` is not a const expression
- **Fix:** Removed the intermediate `const` container and simplified the test by removing the redundant container creation
- **Files modified:** `test/unit/cross_group_balance_test.dart`
- **Commit:** `1aebc84`

## Known Stubs

None. All new providers return real data aggregated from existing Firestore-backed providers. The `weeklyGroupSpendingProvider` correctly returns `Decimal.zero` for empty days — this is correct behavior, not a stub.

## Self-Check: PASSED

Files verified:
- `lib/core/theme/tokens/color_tokens.dart` contains `final Color offlineBannerBackground;` ✓
- `lib/core/theme/app_theme.dart` contains `static const Color errorText = Color(0xFFB91C1C);` ✓
- `lib/features/home/keys/home_keys.dart` contains `static const balanceHeroCard` ✓
- `lib/features/groups/providers/group_balance_provider.dart` contains `typedef CrossGroupBalance` ✓
- `lib/features/groups/providers/group_balance_provider.dart` contains `final currentUserIdProvider` ✓
- `lib/features/home/providers/dashboard_providers.dart` contains `crossGroupActivityProvider` ✓
- `test/unit/color_tokens_test.dart` — 10 tests pass ✓
- `test/unit/cross_group_balance_test.dart` — 5 tests pass ✓
- `test/unit/dashboard_providers_test.dart` — 5 tests pass ✓
- Full suite: 714 tests pass (20 new, 0 regressions) ✓

Commits verified:
- `199c47c` feat(18-01): add 4 new color tokens, 6 AppColors statics, and 12 HomeKeys ✓
- `1aebc84` feat(18-01): add crossGroupBalanceProvider, crossGroupActivityProvider, weeklyGroupSpendingProvider ✓
