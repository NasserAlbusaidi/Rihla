---
phase: 29-group-management
plan: 02
subsystem: groups
tags: [widget-implementation, tdd-green, settings-screen, profile-pattern]
dependency_graph:
  requires:
    - GroupKeys Phase 29 keys (from 29-01)
    - GroupService.leaveGroup, removeMember, deleteGroup (from 29-01)
    - group_settings_screen_test.dart 16-test scaffold (from 29-01)
  provides:
    - GroupInfoSection widget (name/currency/invite code card)
    - GroupMembersSection widget (member list with creator badge, balance gate)
    - GroupDangerSection widget (leave/delete with confirmation dialogs)
    - GroupSettingsScreen refactored to ProfileScreen layout pattern
  affects:
    - test/features/groups/group_screens_test.dart (AppBar test replaced with back button)
tech_stack:
  added: []
  patterns:
    - ProfileAboutSection card pattern (section header + card container + tiles)
    - Stagger animations via flutter_animate (.animate().fadeIn().slideY())
    - Balance gate: groupBalancesProvider check before member removal (D-07)
    - Fire-and-forget service calls in synchronous onTap (Phase 26 P01 pattern)
key_files:
  created:
    - lib/features/groups/widgets/group_info_section.dart
    - lib/features/groups/widgets/group_members_section.dart
    - lib/features/groups/widgets/group_danger_section.dart
  modified:
    - lib/features/groups/screens/group_settings_screen.dart
    - test/features/groups/group_screens_test.dart
decisions:
  - GroupInfoSection is StatefulWidget (owns _isEditing/_isSaving state and TextEditingController for inline name edit)
  - GroupMembersSection and GroupDangerSection are ConsumerWidget (stateless — service calls are fire-and-forget)
  - GroupSettingsScreen changed from ConsumerStatefulWidget to ConsumerWidget (all state migrated to section widgets)
  - Balance gate reads groupBalancesProvider synchronously via ref.read (not ref.watch) in onTap callback
metrics:
  duration: 8m
  completed_date: "2026-04-02"
  tasks_completed: 2
  files_modified: 5
---

# Phase 29 Plan 02: GroupSettingsScreen Widget Implementation Summary

**One-liner:** Three ProfileScreen-pattern section widgets (GroupInfoSection, GroupMembersSection, GroupDangerSection) plus GroupSettingsScreen refactored to ProfileScreen layout, making all 16 TDD-green tests pass.

## What Was Built

### Task 1: Three section widgets

Created three new widget files under `lib/features/groups/widgets/`:

**`GroupInfoSection`** (`StatefulWidget`, owns editing state):
- Section header: `Iconsax.setting_2`, uppercase label `'GROUP'`
- Card container: `cardSurface` background, `BorderRadius.circular(16)`, `AppShadowTokens.standard.raised`
- Group Name tile: inline edit mode for creator (TextEditingController + save/cancel), display mode for non-creator. Keys: `settingsGroupNameTile`, `groupNameEditIcon`
- Currency tile: taps open `showModalBottomSheet` with 9-currency list and teal checkmark on active. Key: `settingsCurrencyTile`
- Invite Code tile: 16sp/w600/letterSpacing:4 code display, copy to clipboard with `HapticService.success()` + SnackBar. Keys: `settingsInviteCodeTile`, `inviteCodeCopyButton`

**`GroupMembersSection`** (`ConsumerWidget`):
- Section header: `Iconsax.people`, uppercase label `'MEMBERS'`
- Member tiles: `InitialsCircle(size: 36)` + display name + creator badge (only for `isCreator` member) + remove button (`Iconsax.user_minus`, only when `isCurrentUserCreator && member.userId != currentUserId`)
- Creator badge: `selectionFill` background, `primary` text color, `BorderRadius.circular(8)`. Key: `creatorBadge`
- Balance gate (D-07): `ref.read(groupBalancesProvider)` → finds member balance by `participantId == member.userId` → shows SnackBar with Settle Up action if `netBalance != Decimal.zero`
- Keys: `memberTile(id)`, `removeMemberButton(id)`, `creatorBadge`

**`GroupDangerSection`** (`ConsumerWidget`):
- Section header: `Iconsax.warning_2`, uppercase label `'DANGER ZONE'`, header text color: `errorText` (not `textSecondary`)
- Leave Group tile: always visible, `error.withValues(alpha: 0.1)` icon container, `errorText` label. Key: `leaveGroupTile`
- Delete Group tile: creator-only, same styling. Key: `deleteGroupTile`
- AlertDialog confirmations: leave dialog (`'Leave group?'` title, `'Stay in group'` / `'Leave group'` actions), delete dialog (`'Delete group?'` / `'Keep group'` / `'Delete group'`). Keys: `leaveGroupDialog`, `deleteGroupDialog`, `leaveGroupConfirmButton`, `deleteGroupConfirmButton`
- Post-action navigation: `context.go('/home')` (replaces route stack, not push)

### Task 2: Refactored GroupSettingsScreen + updated group_screens_test.dart

**GroupSettingsScreen** fully rewritten:
- Changed from `ConsumerStatefulWidget` to `ConsumerWidget` (state moved to section widgets)
- Removed: `AppBar`, `ListView`, inline `_showCurrencyPicker`/`_saveGroupName`, `_nameController`/`_isEditing`/`_isSaving` state
- Added: `ProfileScreen` layout (SafeArea > SingleChildScrollView > Padding(horizontal:24) > Column)
- Inline back button with `GroupKeys.settingsBackButton` key, `GoRouter.of(context).pop()` on press
- Three section widgets with stagger: `GroupInfoSection(.animate().fadeIn(delay:100.ms).slideY(begin:0.1))`, same at 200ms and 300ms
- Loading state: `SkeletonLoader.generic(count: 3)` (not just a spinner)
- Error state: `'Could not load settings'` with `'Try again'` TextButton calling `ref.invalidate`

**`test/features/groups/group_screens_test.dart`** updated:
- Test `'shows Group Settings appbar title'` → `'shows back button instead of AppBar title'`
- Assertion changed from `find.byKey(GroupKeys.settingsTitle)` → `find.byKey(GroupKeys.settingsBackButton)`

## Test Results

- `flutter test test/features/groups/group_settings_screen_test.dart` — **17/17 pass** (16 new Phase 29 tests + setUp)
- `flutter test test/features/groups/group_screens_test.dart` — **14/14 pass** (0 regressions)
- `flutter analyze lib/features/groups/widgets/` — **No issues**
- `flutter analyze lib/features/groups/screens/group_settings_screen.dart` — **No issues**
- Full suite: 10 pre-existing failures in unrelated files (ledger_test.dart, home_screen_*, logistics_screen_mutations_test.dart) — unchanged from before this plan

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — all data flows are wired to real providers (groupDetailProvider, groupMembersProvider, groupBalancesProvider, currentUserIdProvider). No placeholder text or empty data sources.

## Self-Check: PASSED

- `lib/features/groups/widgets/group_info_section.dart` — FOUND
- `lib/features/groups/widgets/group_members_section.dart` — FOUND
- `lib/features/groups/widgets/group_danger_section.dart` — FOUND
- Commit `76b1cb8` (Task 1: section widgets) — FOUND
- Commit `38dabad` (Task 2: screen refactor + test update) — FOUND
