---
phase: 02-groups
plan: 02
subsystem: groups-ui
tags: [groups, ui, home-screen, flutter, riverpod, go_router, widget-tests]
dependency_graph:
  requires: [02-01]
  provides: [group-card-widget, group-member-tile-widget, invite-code-display-widget, home-screen-groups, create-group-screen, join-group-screen]
  affects: [02-03]
tech_stack:
  added: []
  patterns:
    - ConsumerWidget with StreamProvider.when() for reactive list rendering
    - ConsumerStatefulWidget for form screens with loading/error providers
    - GoRouter push/pushReplacement for group navigation
    - share_plus Share.share() for native OS share sheet
    - flutter_animate staggered list entry with reduce motion gate
    - LengthLimitingTextInputFormatter + custom UpperCaseTextFormatter
key_files:
  created:
    - lib/features/groups/widgets/group_card.dart
    - lib/features/groups/widgets/group_member_tile.dart
    - lib/features/groups/widgets/invite_code_display.dart
    - lib/features/groups/screens/create_group_screen.dart
    - lib/features/groups/screens/join_group_screen.dart
  modified:
    - lib/features/home/screens/home_screen.dart (fully replaced — trip code removed)
    - lib/core/router/app_router.dart (added /create-group, /join-group, /group/:id routes)
    - test/features/home/home_screen_groups_test.dart (replaced stubs with 6 real widget tests)
decisions:
  - Home screen fully replaces trip-based layout — no legacy trip UI retained
  - group/id detail route registered as scaffold placeholder (full detail in Plan 03)
  - DropdownButtonFormField uses initialValue not value (deprecated API fix)
metrics:
  duration: 5 minutes
  completed: 2026-03-26
  tasks_completed: 3
  files_created: 5
  files_modified: 3
---

# Phase 02 Plan 02: Groups UI Summary

**One-liner:** Groups-first HomeScreen with GroupCard/GroupMemberTile/InviteCodeDisplay widgets, CreateGroupScreen with post-creation share prompt, and JoinGroupScreen with auto-uppercase 6-char code entry.

## Objective

Build the complete user-facing UI for the groups feature: the home screen replacement showing groups from Firestore, the create/join flows, and the reusable widgets. After this plan, users can see their groups, create new groups, share invite codes, and join groups.

## What Was Built

### Task 1: Three Reusable Widgets (commit 792f290)

**`lib/features/groups/widgets/group_card.dart`**
- `StatelessWidget` with `GestureDetector` wrapping a `Container` using `AppColors.radiusLarge` corners and `AppColors.shadowRaised` elevation
- Displays group name (titleMedium), member count badge (people icon + count in surfaceLight pill), and "0.000 OMR" balance placeholder per D-03

**`lib/features/groups/widgets/group_member_tile.dart`**
- `StatelessWidget` showing `CircleAvatar` with display name initial, display name (with optional "(You)" suffix), and role badge (CREATOR/MEMBER in surfaceLight pill)

**`lib/features/groups/widgets/invite_code_display.dart`**
- `StatelessWidget` showing code in `AppColors.mintSurface` pill with `letterSpacing: 8` at 28sp
- Optional copy and share action buttons rendered below when callbacks provided

### Task 2: Groups-First HomeScreen (commit 7a2a802)

**`lib/features/home/screens/home_screen.dart`** — fully replaced
- `ConsumerWidget` watching `userGroupsProvider` (Firestore StreamProvider)
- Three-state rendering: loading → `SkeletonLoader.groupList(count: 3)`, empty → `EmptyStateView("No groups yet")`, data → `ListView.builder` with `GroupCard` widgets
- Staggered `flutter_animate` list entry (fadeIn 400ms + slideY 0.05, 50ms per card, max 5 staggered)
- Reduce motion gate via `MediaQuery.of(context).disableAnimations`
- FAB with `HapticFeedback.lightImpact()` opening bottom sheet with "Create a Group" and "Join a Group" ListTile options
- `ref.refresh(userGroupsProvider.future)` on pull-to-refresh
- All trip-specific code removed (`userTripsProvider`, `tripSeedProvider`, `CommandCenter`, `Trip`)
- 6 widget tests added covering: header copy, GroupCard rendering, empty state, FAB sheet, navigation, no trip references

### Task 3: CreateGroupScreen + JoinGroupScreen (commit 955b43c)

**`lib/features/groups/screens/create_group_screen.dart`**
- `ConsumerStatefulWidget` with Form validation (group name required, "Group name can't be empty.")
- Currency `DropdownButtonFormField` with 9 supported currencies, OMR default
- Read-only device name display from `settingsProvider` (D-06, D-08)
- `_createGroup()` manages `groupLoadingProvider` / `groupErrorProvider` states, calls `GroupService.createGroup()`
- Post-creation share prompt via `showModalBottomSheet` with `InviteCodeDisplay`, copy (Clipboard + HapticService.success() + "Invite code copied" toast), Share.share() with exact UI-SPEC message
- Navigates to `/group/{id}` via `context.pushReplacement` after "Done"

**`lib/features/groups/screens/join_group_screen.dart`**
- `ConsumerStatefulWidget` with 6-char `TextFormField` — auto-uppercase via `_UpperCaseTextFormatter`, `FilteringTextInputFormatter`, `LengthLimitingTextInputFormatter(6)`
- `letterSpacing: 8` at 24sp for visual character separation per UI-SPEC
- Auto-submit at 6 chars via `onChanged`; button enabled only when 6 chars present
- Exact UI-SPEC error messages: "That code doesn't match any group...", "You're already in this group.", "Couldn't join the group..."
- `HapticFeedback.mediumImpact()` on success

**`lib/core/router/app_router.dart`** — routes added
- `/create-group` → `CreateGroupScreen` (slide-up transition)
- `/join-group` → `JoinGroupScreen` (slide-up transition)
- `/group/:id` → scaffold placeholder (detail screen wired in Plan 03)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed deprecated DropdownButtonFormField.value API**
- **Found during:** Task 3 flutter analyze
- **Issue:** `DropdownButtonFormField(value: ...)` deprecated after Flutter v3.33.0-1.0.pre — use `initialValue`
- **Fix:** Renamed `value:` to `initialValue:` in `create_group_screen.dart`
- **Files modified:** lib/features/groups/screens/create_group_screen.dart
- **Commit:** included in 955b43c

**2. [Rule 3 - Blocking] Added missing group routes to app_router.dart**
- **Found during:** Task 3 — HomeScreen references `/create-group`, `/join-group`, `/group/:id` but these were absent from the router
- **Fix:** Added GoRoute entries for all three paths; `/group/:id` is a placeholder scaffold until Plan 03
- **Files modified:** lib/core/router/app_router.dart
- **Commit:** included in 955b43c

## Test Results

- `test/features/home/home_screen_groups_test.dart` — 6 tests, all passing
  1. shows "Your Groups" header
  2. shows GroupCard for each group from userGroupsProvider
  3. shows empty state when user has no groups
  4. FAB opens bottom sheet with Create and Join options
  5. tapping GroupCard navigates to group detail
  6. does not reference userTripsProvider (trip code removed)

## Known Stubs

- **`/group/:id` route** — placeholder Scaffold body ("Group {id} — coming in Plan 03") until GroupDetailScreen is implemented in Plan 03. GroupCard navigation pushes to this route correctly; the destination is the stub.
- **Balance in GroupCard** — `0.000 ${group.currency}` is intentional per D-03. Real balances are Phase 5.

## Self-Check: PASSED
