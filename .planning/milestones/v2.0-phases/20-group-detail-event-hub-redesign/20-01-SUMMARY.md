---
phase: 20-group-detail-event-hub-redesign
plan: 01
subsystem: ui
tags: [flutter, riverpod, dart3-switch, wcag, skeleton-loader, group-detail, event-card]

# Dependency graph
requires:
  - phase: 19-navigation-restructuring
    provides: GoRouter declarative navigation, currentUserIdProvider, context.push patterns
  - phase: 17-animation-library-loading-states
    provides: SkeletonLoader, SkeletonBlock, SkeletonBar, SkeletonCard primitives
  - phase: 15-design-token-system
    provides: AppColors.errorText/successText/textMuted WCAG-safe tokens
provides:
  - GroupStatsGrid widget (2x2 grid with YOUR BALANCE, GROUP TOTAL, ACTIVE MEMBERS, EVENTS)
  - EventCard with left accent bar (teal/gray), inline personal balance (color-coded)
  - GroupDetailScreen redesign with stats grid above fold, settle-up CTA, Events-first section order
  - animations ^2.0.0 dependency (needed by Plan 02 OpenContainer transitions)
  - 6 new GroupKeys: statsGrid, statYourBalance, statGroupTotal, statActiveMembers, statEvents, settleUpCta
affects:
  - phase: 20-plan-02 (EventCommandCenter redesign — depends on EventCard and animations package)
  - phase: 21-module-screens (any screen using EventCard)

# Tech tracking
tech-stack:
  added:
    - animations: ^2.0.0
  patterns:
    - Dart 3 switch expression for three-state balance color coding (errorText/successText/textPrimary)
    - currentUserIdProvider override pattern for test isolation (avoids Firebase in widget tests)
    - GroupStatsGrid: GridView.count with NeverScrollableScrollPhysics inside SingleChildScrollView
    - IntrinsicHeight Row for consistent left accent bar height in EventCard
    - SkeletonLoader factory methods for content-aware loading composites in screen _buildLoading

key-files:
  created:
    - lib/features/groups/widgets/group_stats_grid.dart
  modified:
    - pubspec.yaml (animations dependency)
    - lib/features/groups/keys/group_keys.dart (6 new keys)
    - lib/features/events/widgets/event_card.dart (accent bar, personalBalance, removed icon)
    - lib/features/groups/screens/group_detail_screen.dart (full redesign)
    - test/features/group_detail_screen_test.dart (updated assertions, 6 new tests)
    - test/features/groups/group_screens_test.dart (currentUserIdProvider override)
    - test/features/events/group_detail_events_test.dart (currentUserIdProvider override)

key-decisions:
  - "currentUserIdProvider used instead of FirebaseConfig.currentUser in GroupDetailScreen for test isolation — Phase 18 P03 established this pattern"
  - "Stats grid is always visible (D-08) — no conditional rendering based on totalSpent, unlike old GroupBalanceHero"
  - "EventCard accent bar replaces 48x48 icon + type badge chip — monochrome discrimination (teal=active, gray=past) per D-03"
  - "personalBalance stub parameter added to EventCard in Task 1 for test compilation before full implementation in Task 2"
  - "group_screens_test.dart and group_detail_events_test.dart updated to override currentUserIdProvider — avoiding Firebase init in test environment"

patterns-established:
  - "Dart 3 switch expression for balance color: switch (balance.compareTo(Decimal.zero)) { < 0 => errorText, > 0 => successText, _ => textPrimary }"
  - "currentUserIdProvider.overrideWithValue(null|uid) pattern for all GroupDetailScreen widget tests"
  - "IntrinsicHeight Row with left accent bar Container(width: 3.0) for card-with-indicator layouts"

requirements-completed:
  - SCRN-01

# Metrics
duration: 13min
completed: 2026-03-30
---

# Phase 20 Plan 01: Group Detail Redesign Summary

**GroupDetailScreen rebuilt with 2x2 stats grid above the fold, teal/gray accent-bar EventCards with inline personal balance, and Events-first section ordering satisfying SCRN-01**

## Performance

- **Duration:** 13 min
- **Started:** 2026-03-30T15:08:29Z
- **Completed:** 2026-03-30T15:21:05Z
- **Tasks:** 3
- **Files modified:** 7 (+ 1 created)

## Accomplishments
- Created GroupStatsGrid: 2x2 GridView with 4 keyed stat tiles (YOUR BALANCE color-coded via Dart 3 switch, GROUP TOTAL, ACTIVE MEMBERS, EVENTS)
- Redesigned EventCard: left accent bar (teal/active, gray/past) replaces 48x48 icon + type badge; adds optional `personalBalance` with WCAG-safe color coding
- Rebuilt GroupDetailScreen: stats grid above fold (D-08), conditional settle-up CTA (D-10), Events→Members→Invite→Activity order (D-09), SkeletonLoader replaces CircularProgressIndicator
- All 749 tests pass (previously 744; added 5 new tests, fixed 2 test files for currentUserIdProvider)

## Task Commits

Each task was committed atomically:

1. **Task 1: Infrastructure — Add animations package, extend GroupKeys, prepare tests (TDD red)** - `693aca3` (feat)
2. **Task 2: Create GroupStatsGrid widget and redesign EventCard with accent bar + inline balance** - `dc27ff1` (feat)
3. **Task 3: Rebuild GroupDetailScreen layout — stats grid, settle-up CTA, section reorder, skeleton loading** - `3ef75ec` (feat)

**Plan metadata:** TBD (docs: complete plan)

## Files Created/Modified
- `lib/features/groups/widgets/group_stats_grid.dart` — New: 2x2 stats grid widget (GroupStatsGrid + _StatCard)
- `lib/features/events/widgets/event_card.dart` — Redesigned with left accent bar, inline personalBalance, removed icon container and type badge
- `lib/features/groups/screens/group_detail_screen.dart` — Full redesign: stats grid, settle-up CTA, section reorder, skeleton loading, currentUserIdProvider
- `lib/features/groups/keys/group_keys.dart` — Added 6 new keys: statsGrid, statYourBalance, statGroupTotal, statActiveMembers, statEvents, settleUpCta
- `pubspec.yaml` — Added animations: ^2.0.0
- `test/features/group_detail_screen_test.dart` — Updated old hero assertions → statsGrid, added 6 TDD tests (all pass)
- `test/features/groups/group_screens_test.dart` — Added currentUserIdProvider override, updated member chip test
- `test/features/events/group_detail_events_test.dart` — Added currentUserIdProvider override to all ProviderScope usages

## Decisions Made
- Used `currentUserIdProvider` (injectable via Riverpod override) instead of `FirebaseConfig.currentUser?.uid` directly — enables test isolation without Firebase initialization
- Stats grid is always visible (D-08) instead of conditional on `totalSpent > 0` — cleaner UX, zero-state shows zeros rather than hiding the section
- EventCard left accent bar uses `IntrinsicHeight Row` to stretch the 3dp bar to full card height regardless of content
- `personalBalance` stub added to EventCard in Task 1 so TDD tests compiled before full implementation in Task 2

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added personalBalance stub parameter to EventCard in Task 1**
- **Found during:** Task 1 (TDD red phase setup)
- **Issue:** Test file referenced `EventCard(personalBalance: ...)` but parameter didn't exist yet, causing compile failure — TDD red requires compilation errors, not compilation failures
- **Fix:** Added `Decimal? personalBalance` field and constructor param as stub; full implementation done in Task 2
- **Files modified:** lib/features/events/widgets/event_card.dart
- **Verification:** Test file compiled; test failed at runtime (TDD red) not at compile time
- **Committed in:** `693aca3` (Task 1 commit)

**2. [Rule 1 - Bug] Updated group_screens_test.dart and group_detail_events_test.dart for currentUserIdProvider**
- **Found during:** Task 3 (full test suite run)
- **Issue:** Two existing test files called `FirebaseConfig.currentUser` indirectly through `currentUserIdProvider`'s default implementation — threw FirebaseException in tests without Firebase initialized
- **Fix:** Added `currentUserIdProvider.overrideWithValue(null)` to both `_wrap` helpers and all inline ProviderScope usages
- **Files modified:** test/features/groups/group_screens_test.dart, test/features/events/group_detail_events_test.dart
- **Verification:** All 749 tests pass
- **Committed in:** `3ef75ec` (Task 3 commit)

**3. [Rule 1 - Bug] Updated group_screens_test.dart member count assertion**
- **Found during:** Task 3 (full test suite run)
- **Issue:** `shows member count chip` test expected `'2 members'` text — the stats chip row was removed in the redesign; no such text exists in the new layout
- **Fix:** Updated test to assert `GroupKeys.statsGrid` and `GroupKeys.statActiveMembers` are present instead — verifies the replacement widget
- **Files modified:** test/features/groups/group_screens_test.dart
- **Verification:** Test passes with new assertion
- **Committed in:** `3ef75ec` (Task 3 commit)

---

**Total deviations:** 3 auto-fixed (2 Rule 1 - Bug, 1 Rule 1 - Bug)
**Impact on plan:** All auto-fixes necessary for test correctness and compilation. No scope creep.

## Issues Encountered
- `AppFormatters` was referenced in plan as `lib/core/utils/app_formatters.dart` but the actual file is `lib/core/utils/formatters.dart` — used the correct path without issue
- Dart collection `if` inside `for` spread with ternary conditional containing null-safety operator (`?.`) required extraction to local variable due to parser ambiguity — fixed inline

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- GroupDetailScreen fully redesigned with stats grid, settle-up CTA, and new EventCard
- animations package added — Plan 02 can use OpenContainer for event card transitions
- All 749 tests pass — no regressions
- Plan 02 (EventCommandCenter redesign) ready to proceed

## Self-Check: PASSED

- `lib/features/groups/widgets/group_stats_grid.dart` — FOUND
- `lib/features/events/widgets/event_card.dart` — FOUND
- `lib/features/groups/screens/group_detail_screen.dart` — FOUND
- `lib/features/groups/keys/group_keys.dart` — FOUND
- Commit `693aca3` — FOUND
- Commit `dc27ff1` — FOUND
- Commit `3ef75ec` — FOUND
- Commit `89239c9` (metadata) — FOUND
