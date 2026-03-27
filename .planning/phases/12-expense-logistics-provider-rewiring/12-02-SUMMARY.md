---
phase: 12-expense-logistics-provider-rewiring
plan: "02"
subsystem: logistics
tags:
  - logistics
  - sub-groups
  - firestore
  - mutations
  - tdd
dependency_graph:
  requires:
    - "12-01 (eventSubGroupsProvider, subGroupServiceProvider, eventLogisticsParticipantsProvider)"
  provides:
    - "SubGroupService.updateSubGroup method"
    - "All 6 logistics write paths functional"
    - "Error snackbars on write failures"
  affects:
    - "lib/features/logistics/screens/logistics_screen.dart"
    - "lib/features/logistics/services/sub_group_service.dart"
tech_stack:
  added: []
  patterns:
    - "Helper method extraction for BuildContext safety across async gaps"
    - "Phase 11 snackbar error pattern (em dash separator, mounted guard)"
    - "TDD RED/GREEN flow for new service method"
key_files:
  created:
    - test/features/logistics_screen_mutations_test.dart
  modified:
    - lib/features/logistics/services/sub_group_service.dart
    - lib/features/logistics/screens/logistics_screen.dart
    - test/unit/sub_group_service_test.dart
decisions:
  - "Helper methods (_removeMember, _dropMemberOnGroup, _addMemberToGroup, _deleteGroup, _updateGroup, _createGroup) extracted from callbacks to _LogisticsScreenState to ensure mounted/context safety across async gaps"
  - "onRemoveMember and onDrop callbacks delegate to state helper methods rather than performing async work inline — avoids use_build_context_synchronously lint violation"
  - "Member removal uses member.id (Firestore subcollection doc ID), NOT member.participantId — consistent with Research Pitfall 1"
  - "Widget tests tap member avatar initial (text 'A') to trigger remove dialog; tap last IconButton (more icon) for delete dialog; tap first IconButton (add) for create dialog"
metrics:
  duration: "7 minutes"
  completed_date: "2026-03-27"
  tasks_completed: 2
  files_modified: 4
---

# Phase 12 Plan 02: Wire Logistics Screen Write Stubs Summary

Wire all 6 logistics screen debugPrint stubs to SubGroupService methods, add SubGroupService.updateSubGroup with TDD, and pass capacity to createSubGroup.

## What Was Built

**SubGroupService.updateSubGroup** — new method that accepts optional `name` and `capacity`, builds a partial update map, and writes to the Firestore `sub_groups` subcollection. No-op when both params are absent. FirebaseException caught and rethrown with debugPrint.

**Logistics screen write wiring** — all 6 stubs replaced:
1. `removeMember`: delegates to `_removeMember(member, group)` helper — uses `member.id` (Firestore doc ID)
2. `addMember via drag-drop`: delegates to `_dropMemberOnGroup(participant, group)` helper
3. `addMember via picker`: pops sheet, calls `_addMemberToGroup(group, participant)` on screen state
4. `deleteSubGroup`: pops dialog, calls `_deleteGroup(group)` helper
5. `updateSubGroup`: pops sheet, calls `_updateGroup(group, name, capacity)` helper
6. `createSubGroup`: parses capacity from controller, calls `_createGroup(name, type, capacity)` — no longer discards value with `final _`

All 6 operations: try/catch wrapping, snackbar error on failure using Phase 11 pattern (`"Couldn't [verb] [noun] \u2014 try again"`), `mounted` guard before showing snackbar.

## Commits

- `92ab02b` — `feat(12-02): add SubGroupService.updateSubGroup with unit tests`
- `dcc3602` — `feat(12-02): wire all 6 logistics screen stubs to SubGroupService`

## Test Results

```
13 tests passed, 0 failed
- SubGroupService: updateSubGroup (name-only, capacity-only, both-provided) — 3 tests
- LogisticsScreen: removeMember, deleteSubGroup, createSubGroup+capacity, 3 snackbar errors — 6 tests
- Pre-existing SubGroupService tests (createSubGroup, watchSubGroups, addMember, removeMember) — 4 tests
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] BuildContext safety for async callbacks**
- **Found during:** Task 2
- **Issue:** `onRemoveMember` and `onDrop` callbacks in `ListView.itemBuilder` captured the `BuildContext` parameter (`context`) from the builder closure. After `await`, accessing `ScaffoldMessenger.of(context)` with an `itemBuilder` context triggers `use_build_context_synchronously` lint — the context may be invalid after the async gap.
- **Fix:** Extracted all 6 async write operations to named private helper methods on `_LogisticsScreenState`. The helpers use `this.context` and `this.mounted` which are always valid for the screen state lifetime.
- **Files modified:** `lib/features/logistics/screens/logistics_screen.dart`
- **Commit:** `dcc3602`

**2. [Rule 2 - Missing Critical Functionality] Snackbar for removeMember added as 7th error path**
- **Found during:** Task 2, test writing
- **Issue:** Plan specified 6 snackbar catch blocks but the removeMember path also needs one for completeness and test coverage.
- **Fix:** Added `removeMember` snackbar test case (7th test in mutations file). The helper `_removeMember` already had the snackbar — only the test was added.
- **Files modified:** `test/features/logistics_screen_mutations_test.dart`
- **Commit:** `dcc3602`

## Known Stubs

None. All 6 write paths are fully wired to SubGroupService. The screen previously contained only debugPrint stubs — all are replaced.

## Self-Check: PASSED

All created/modified files exist on disk. Both commits (92ab02b, dcc3602) confirmed in git log.
