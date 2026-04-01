---
phase: 23-quick-action-fixes
plan: 01
subsystem: ui
tags: [quick-actions, share-plus, navigation, go-router, riverpod, activity-feed]

# Dependency graph
requires:
  - phase: 22-animations-haptics
    provides: AppColorTokens, AppShadowTokens, ActivityRow widget, GroupActivityScreen layout pattern
  - phase: 18-home-dashboard
    provides: HomeScreen QuickActionTray wiring, crossGroupActivityProvider, userGroupsProvider
provides:
  - Invite Friend quick action triggers native share sheet with group invite code
  - Activity quick action navigates to full-screen CrossGroupActivityScreen at /activity
  - 0-groups SnackBar messages for Add Expense, Settle Up, Invite Friend
  - CrossGroupActivityScreen full-screen cross-group activity feed
  - /activity route registered in app_router.dart
affects: home-screen tests, router integration tests, quick-action-dependent flows

# Tech tracking
tech-stack:
  added: []
  patterns:
    - share_plus Share.share() with subject for native share sheet
    - _handleGroupAction unified dispatcher replacing per-action methods
    - ConsumerWidget full-screen activity screen using existing crossGroupActivityProvider
    - Mock MethodChannel for share_plus in widget tests

key-files:
  created:
    - lib/features/home/screens/cross_group_activity_screen.dart
    - test/features/home/home_screen_quick_actions_test.dart
    - test/features/home/cross_group_activity_screen_test.dart
  modified:
    - lib/features/home/screens/home_screen.dart
    - lib/core/router/app_router.dart

key-decisions:
  - "D-01: context.push('/join-group') replaced with Share.share() — invite action should share, not navigate user to join"
  - "D-02: Share message includes group name, invite code, and Play Store URL for discoverability"
  - "D-03: Single group skips picker — directly calls Share.share() or navigates without showing bottom sheet"
  - "D-04: Multi-group invite shows same picker bottom sheet as expense/settle, then calls Share.share() on selection"
  - "D-05: _showGroupPicker removed and replaced with unified _handleGroupAction dispatcher"
  - "D-06: Activity button uses context.push('/activity') instead of _scrollToActivity"
  - "D-07: CrossGroupActivityScreen reuses crossGroupActivityProvider (top 5 entries) — no new provider needed"
  - "D-08: 0-groups SnackBar messages are specific per action type for clarity"
  - "D-09: _activitySectionKey GlobalKey removed — no longer needed with route-based navigation"
  - "D-10: /activity route added as top-level GoRoute (not nested under /group)"

patterns-established:
  - "share_plus testing: Register no-op MethodChannel mock for dev.fluttercommunity.plus/share in setUpAll/tearDownAll"
  - "Quick action unified handler: single _handleGroupAction method dispatches all 4 actions, handles 0/1/N groups"

requirements-completed: [ACT-01, ACT-02, ACT-03]

# Metrics
duration: 7min
completed: 2026-04-01
---

# Phase 23 Plan 01: Quick Action Fixes Summary

**All 4 home screen quick actions fixed: Invite Friend now opens native share sheet with invite code, Activity navigates to new CrossGroupActivityScreen, 0-groups shows SnackBar for group-dependent actions**

## Performance

- **Duration:** 7 min
- **Started:** 2026-04-01T05:21:53Z
- **Completed:** 2026-04-01T05:29:11Z
- **Tasks:** 2 of 2 auto tasks completed (Task 3 is checkpoint:human-verify, blocked pending user verification)
- **Files modified:** 5

## Accomplishments
- Replaced broken `context.push('/join-group')` with `Share.share()` via native share sheet (invite code + Play Store link)
- Replaced `_scrollToActivity` with `context.push('/activity')` pointing to new full-screen CrossGroupActivityScreen
- Added SnackBar messages for all group-dependent actions when 0 groups exist (Add Expense, Settle Up, Invite Friend)
- Created `CrossGroupActivityScreen` — full-screen feed with empty/loading/error states matching GroupActivityScreen pattern
- Registered `/activity` GoRoute in `app_router.dart` with slide-right transition
- 14 new tests across 2 test files; full test suite passes at 781 tests (up from 767)

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire Invite Friend share flow and fix 0-groups edge cases** - `4dfe84d` (feat)
2. **Task 2: Create CrossGroupActivityScreen and wire /activity route** - `32df892` (feat)

**Plan metadata:** TBD (docs commit — created after checkpoint)

## Files Created/Modified
- `lib/features/home/screens/home_screen.dart` - Added share_plus import, Group import, _handleGroupAction dispatcher, _shareInviteCode method; removed _scrollToActivity and _activitySectionKey
- `lib/core/router/app_router.dart` - Added AppRoutes.activity constant and /activity GoRoute with CrossGroupActivityScreen
- `lib/features/home/screens/cross_group_activity_screen.dart` (NEW) - Full-screen cross-group activity feed with header, list body, skeleton, empty/error states
- `test/features/home/home_screen_quick_actions_test.dart` (NEW) - 9 tests: 0-groups edge cases, 1-group direct actions, multi-group picker, Activity navigation
- `test/features/home/cross_group_activity_screen_test.dart` (NEW) - 5 tests: title, empty state, activity entries with group name, error state, back navigation

## Decisions Made
- Unified `_handleGroupAction` replaces the old `_showGroupPicker` — single dispatcher for all 4 actions avoids parallel maintenance of separate methods
- `_scrollToActivity` removed entirely — in-page scrolling is inferior UX to a dedicated activity screen; the route-based approach supports deep links
- `crossGroupActivityProvider` reused for CrossGroupActivityScreen — no new provider needed since the existing top-5 aggregate is sufficient for a full-screen view
- `/activity` added as top-level route (not nested) — cross-group activity is not scoped to any particular group

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered
- `UserBalance` type was not exported from `group_balance_provider.dart` — it's actually defined in `expense_model.dart`. Fixed by adding the correct import to test files.
- `_makeGroupPicker` test pattern required mock method channel for share_plus — added `setMockMethodCallHandler` in setUpAll/tearDownAll to prevent MissingPluginException.

## User Setup Required
None — no external service configuration required.

## Next Phase Readiness
- All automated tasks complete. Awaiting human-verify checkpoint (Task 3) for on-device testing
- After checkpoint approval, phase 23 is complete and phase 24 can begin
- Home dashboard quick actions are now fully functional and tested

## Known Stubs
None — all quick actions are wired to real behavior.

---
*Phase: 23-quick-action-fixes*
*Completed: 2026-04-01*
