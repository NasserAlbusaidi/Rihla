---
phase: 02-groups
plan: "03"
subsystem: groups-ui
tags: [groups, navigation, screens, widgets, router, firestore, riverpod]
dependency_graph:
  requires: [02-01, 02-02]
  provides: [GroupDetailScreen, GroupSettingsScreen, complete-group-router]
  affects: [home-screen-navigation, group-flow]
tech_stack:
  added: []
  patterns:
    - ConsumerWidget with StreamProvider.family for real-time group data
    - Firebase currentUser access wrapped in try-catch for test safety
    - Inline loading skeleton instead of SkeletonLoader inside scrollable
    - GoRouter nested routes for parent/child screen hierarchy
    - GroupMembersProvider drives real-time members list (GRP-03)
key_files:
  created:
    - lib/features/groups/screens/group_settings_screen.dart
    - lib/features/groups/screens/group_detail_screen.dart
  modified:
    - lib/core/router/app_router.dart
    - test/features/groups/group_screens_test.dart
decisions:
  - "Firebase currentUser wrapped in try-catch to allow widget tests without Firebase initialization"
  - "Inline skeleton placeholders used in members section instead of SkeletonLoader (unbounded height conflict with SingleChildScrollView)"
  - "GroupDetailScreen uses Navigator.push for GroupSettingsScreen (consistent with existing app pattern); GoRouter /group/:id/settings added for deep-link support"
metrics:
  duration: "8 minutes"
  completed_date: "2026-03-26"
  tasks_completed: 3
  files_created: 2
  files_modified: 2
---

# Phase 02 Plan 03: Group Detail, Settings, and Router Summary

GroupDetailScreen and GroupSettingsScreen implemented and wired into GoRouter, completing the full group navigation flow for the groups feature.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Create GroupSettingsScreen for rename and currency change | 623bf82 | group_settings_screen.dart |
| 2 | Create GroupDetailScreen with members list and invite section | 2e8a239 | group_detail_screen.dart, group_screens_test.dart |
| 3 | Wire GoRouter with all group routes | cd23600 | app_router.dart |

## What Was Built

**GroupSettingsScreen** (`lib/features/groups/screens/group_settings_screen.dart`):
- `ConsumerStatefulWidget` with `String groupId` parameter
- Watches `groupDetailProvider(groupId)` stream for live data
- Inline rename TextField shown only to group creator (D-15 — `isCreator` check via `group.createdBy == currentUid`)
- Currency picker via `showModalBottomSheet` with 9-currency list (D-16)
- Read-only invite code tile with clipboard copy + haptic feedback (D-22)
- All writes via `groupServiceProvider.updateGroup()`
- Firebase currentUser access guarded with try-catch for test safety

**GroupDetailScreen** (`lib/features/groups/screens/group_detail_screen.dart`):
- `ConsumerWidget` with `String groupId` parameter
- `ModuleHeader` (dark theme) with group name, created date subtitle, and settings icon action
- Stats row: member count chip + currency chip from `group.memberIds.length` + `group.currency`
- Invite code section: `InviteCodeDisplay` widget + Copy (clipboard) + Share (`Share.share()`) buttons (D-22)
- Real-time members list via `groupMembersProvider(groupId)` (GRP-03) with `GroupMemberTile`
- Event timeline placeholder: `EmptyStateView` with "No events yet" + "Create an event to get started" message (per UI-SPEC, Phase 3 placeholder)
- Inline loading placeholders for members section (avoids `SkeletonLoader` ListView unbounded height in `SingleChildScrollView`)

**GoRouter updates** (`lib/core/router/app_router.dart`):
- Added `AppRoutes.groupSettings = '/group/:id/settings'` constant
- Replaced scaffold placeholder `groupDetail` route with real `GroupDetailScreen` (slide-right transition)
- Added nested `settings` sub-route → `GroupSettingsScreen` (slide-right transition)
- All existing routes preserved (no regressions)

## Verification

```
flutter analyze lib/features/groups/ lib/core/router/app_router.dart
→ No issues found

flutter test test/features/groups/group_screens_test.dart
→ 10 tests passed

flutter test (full suite)
→ 169 passed, 1 pre-existing failure (happy_path_test — out of scope)
```

## Navigation Flow

```
HomeScreen (/home) → tap GroupCard → /group/:id (GroupDetailScreen)
HomeScreen → FAB "Create a Group" → /create-group (CreateGroupScreen)
  → success → share sheet → "Done" → pushReplacement /group/:id
HomeScreen → FAB "Join a Group" → /join-group (JoinGroupScreen)
  → success → pushReplacement /group/:id
GroupDetailScreen → settings icon → Navigator.push → GroupSettingsScreen
  (also deep-linkable via GoRouter /group/:id/settings)
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Firebase static access crashes in test environments**
- **Found during:** Task 2 (GroupDetailScreen tests) and Task 1 (GroupSettingsScreen tests)
- **Issue:** `FirebaseConfig.currentUser` calls `FirebaseAuth.instance` which requires Firebase initialization. Widget tests don't initialize Firebase, causing `[core/no-app]` exception during build.
- **Fix:** Wrapped both `FirebaseConfig.currentUser?.uid` reads in try-catch blocks returning null on exception. This is the same null-guard pattern used elsewhere in the codebase for optional Firebase context.
- **Files modified:** `lib/features/groups/screens/group_detail_screen.dart`, `lib/features/groups/screens/group_settings_screen.dart`
- **Commits:** 2e8a239, 623bf82

**2. [Rule 1 - Bug] SkeletonLoader causes unbounded height in SingleChildScrollView**
- **Found during:** Task 2 (GroupDetailScreen tests)
- **Issue:** `SkeletonLoader.cardList()` renders a `ListView` with `NeverScrollableScrollPhysics`, which requires bounded height. Inside `GroupDetailScreen`'s `SingleChildScrollView`, the height is unbounded → Flutter assertion error.
- **Fix:** Replaced `SkeletonLoader.cardList(count: 2)` with inline `Column` of placeholder `Container` widgets. Removed unused `skeleton_loader.dart` import.
- **Files modified:** `lib/features/groups/screens/group_detail_screen.dart`
- **Commit:** 2e8a239

### Out of Scope

Pre-existing `happy_path_test.dart` integration test failure (expects trip-based HomeScreen from old layout — documented in `deferred-items.md`).

## Known Stubs

**Event timeline section** (`lib/features/groups/screens/group_detail_screen.dart`, `_buildEventsSection`):
- The Events section renders `EmptyStateView(title: 'No events yet', ...)` unconditionally
- This is intentional — events are a Phase 3 feature
- The placeholder is the designed behavior per UI-SPEC D-14 and the plan's explicit "event timeline placeholder" requirement
- Will be replaced with real event list in Phase 3 (events feature)

## Self-Check: PASSED

Files created:
- ✓ `lib/features/groups/screens/group_settings_screen.dart` — exists
- ✓ `lib/features/groups/screens/group_detail_screen.dart` — exists

Commits:
- ✓ 623bf82 — GroupSettingsScreen
- ✓ 2e8a239 — GroupDetailScreen + tests
- ✓ cd23600 — GoRouter wired
