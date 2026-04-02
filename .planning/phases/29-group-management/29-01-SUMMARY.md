---
phase: 29-group-management
plan: 01
subsystem: groups
tags: [data-contracts, test-infrastructure, service-methods, tdd]
dependency_graph:
  requires: []
  provides:
    - GroupKeys Phase 29 keys (settingsBackButton, infoSection, membersSection, dangerSection, leaveGroupTile, deleteGroupTile, creatorBadge, memberTile, removeMemberButton, and more)
    - GroupService.leaveGroup — atomic batch removal of current user
    - GroupService.removeMember — creator-only atomic member removal
    - GroupService.deleteGroup — cascade batch delete of group + members + invite code
    - test/features/groups/group_settings_screen_test.dart — 16 widget test stubs (TDD red)
  affects:
    - lib/features/groups/screens/group_settings_screen.dart (Plan 02 refactor target)
    - lib/features/groups/widgets/ (Plan 02 creates GroupInfoSection, GroupMembersSection, GroupDangerSection)
tech_stack:
  added: []
  patterns:
    - WriteBatch for atomic multi-document Firestore writes (leaveGroup, removeMember, deleteGroup)
    - FieldValue.arrayRemove for atomic memberIds mutation
    - TDD red phase — test file compiles, tests fail until Plan 02 creates widgets
key_files:
  created:
    - test/features/groups/group_settings_screen_test.dart
  modified:
    - lib/features/groups/keys/group_keys.dart
    - lib/features/groups/providers/group_provider.dart
decisions:
  - leaveGroup uses member subcollection query (where userId == uid, limit 1) rather than passing memberId as param — avoids requiring callers to know the Firestore doc ID
  - deleteGroup does NOT cascade-delete events — orphaned events are invisible without group membership; cascade adds complexity without user-visible benefit
  - removeMember takes both memberId (Firestore doc ID) and userId (auth UID) — memberId targets the subcollection doc, userId targets the memberIds array
metrics:
  duration: 5m
  completed_date: "2026-04-02"
  tasks_completed: 2
  files_modified: 3
---

# Phase 29 Plan 01: Data Contracts and Test Infrastructure Summary

**One-liner:** Three Firestore WriteBatch service methods (leaveGroup, removeMember, deleteGroup) plus 14 Phase 29 GroupKeys and a 16-test TDD scaffold for GroupSettingsScreen.

## What Was Built

### Task 1: GroupKeys + GroupService methods

Added 14 new keys to `GroupKeys` under a `// Phase 29 — Group Management` comment block. All keys follow the existing naming convention (snake_case string values, camelCase constants).

New keys:
- `settingsBackButton` — back arrow widget key (no AppBar in new layout)
- `infoSection`, `membersSection`, `dangerSection` — section container keys
- `groupNameEditIcon`, `inviteCodeCopyButton` — action icon keys
- `creatorBadge` — the teal "Creator" chip
- `leaveGroupTile`, `deleteGroupTile` — danger zone action tiles
- `leaveGroupDialog`, `deleteGroupDialog` — confirmation dialog keys
- `leaveGroupConfirmButton`, `deleteGroupConfirmButton` — dialog action buttons
- `memberTile(memberId)`, `removeMemberButton(memberId)` — parameterized member list keys

Added three service methods to `GroupService`:

**`leaveGroup({required String groupId})`** — Queries `groups/{groupId}/members` for the current user's member doc, then WriteBatch: arrayRemove from memberIds + delete member doc. Throws `Exception('Not authenticated')` or `Exception('Member not found')` as appropriate.

**`removeMember({required String groupId, required String memberId, required String userId})`** — WriteBatch: arrayRemove `userId` from memberIds + delete `groups/{groupId}/members/{memberId}`. Caller is responsible for verifying creator role and zero balance (UI-side gate per D-07).

**`deleteGroup({required String groupId})`** — Fetches all member subcollection docs + reads group doc for invite code, then WriteBatch: delete all member docs + delete `inviteCodes/{inviteCode}` + delete group doc. Does NOT cascade-delete events (orphaned events are invisible without membership).

### Task 2: Widget test scaffold

Created `test/features/groups/group_settings_screen_test.dart` with 16 tests covering:
- Layout: back button (no AppBar), three sections rendered
- GroupInfoSection: group name, currency, invite code tiles
- GroupMembersSection: member names, creator badge, remove button visibility
- GroupDangerSection: leave tile (all), delete tile (creator only), non-creator exclusions
- Confirmation dialogs: leave dialog, delete dialog
- Balance gate: remove blocked snackbar for member with non-zero balance

Tests compile cleanly (`flutter analyze` passes) but fail intentionally — this is the TDD red phase. Plan 02 will implement the section widgets to make these tests pass.

## Deviations from Plan

None — plan executed exactly as written.

## Commits

| Task | Commit | Files |
|------|--------|-------|
| Task 1: GroupKeys + service methods | d0583e5 | lib/features/groups/keys/group_keys.dart, lib/features/groups/providers/group_provider.dart |
| Task 2: Test scaffold | f248670 | test/features/groups/group_settings_screen_test.dart |

## Self-Check: PASSED
