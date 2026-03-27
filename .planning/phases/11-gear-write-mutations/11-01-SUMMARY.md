---
phase: 11-gear-write-mutations
plan: 01
subsystem: gear
tags: [gear, firestore, mutations, tdd, widget-tests]
dependency_graph:
  requires: []
  provides: [gear-write-mutations, unclaimGearItem, gear-screen-mutations-tests]
  affects: [gear_screen.dart, gear_service.dart]
tech_stack:
  added: []
  patterns: [fire-and-forget-catchError, loading-guard-pattern, showButtonMenu-test-pattern]
key_files:
  created:
    - test/features/gear_screen_mutations_test.dart
  modified:
    - lib/features/gear/services/gear_service.dart
    - lib/features/gear/screens/gear_screen.dart
    - test/unit/gear_service_test.dart
decisions:
  - "showButtonMenu() used in widget tests to open PopupMenuButton overlay — direct tap unreliable due to FAB z-ordering in test viewport"
  - "togglePacked uses fire-and-forget .catchError() pattern — no await needed for snappy UX"
  - "_eventRef private getter added to _GearScreenState — avoids constructing the record tuple on every method call"
metrics:
  duration: 10 minutes
  completed: 2026-03-27T20:42:06Z
  tasks_completed: 2
  files_modified: 4
---

# Phase 11 Plan 01: Gear Write Mutations Summary

Wired all 6 debugPrint stubs in gear_screen.dart to GearService Firestore methods. Added GearService.unclaimGearItem for null-assignedTo unclaim path. Added widget tests covering all mutation paths and error handling.

## Tasks Completed

### Task 1: Add GearService.unclaimGearItem + wire all 6 gear_screen.dart stubs to GearService

**Commit:** `64cada7`

Added `unclaimGearItem` to `GearService` that sets `assignedTo: null, isPacked: false` atomically in a single Firestore `update()` call. Added 2 unit tests for unclaim behavior.

Wired all 6 mutations in `gear_screen.dart`:
- `_addItem`: calls `addGearItem` with sequenceId computed from current items, loading guard via `gearLoadingProvider`, haptic success, error snackbar
- `_confirmDelete`: calls `deleteGearItem` after dialog confirmation, error snackbar
- `_togglePacked`: fire-and-forget `togglePacked` with `.catchError()` snackbar
- `_handleMenuAction/priority`: async `updateGearItem` with `isHighPriority: !item.isHighPriority`
- `_handleMenuAction/claim`: async `updateGearItem` with `assignedTo: uid` from `currentUserProvider`
- `_handleMenuAction/unclaim`: async `unclaimGearItem`

Removed all 6 `debugPrint('[GearScreen]` stubs and 3 `TODO(04-05)` comments.

Added `EventRef get _eventRef` getter and `event_ref.dart` import.

### Task 2: Widget tests for all 6 gear screen mutations

**Commit:** `d4143c1`

Created `test/features/gear_screen_mutations_test.dart` with 8 widget tests:
1. addItem — calls `addGearItem` with correct args
2. addItem empty guard — `verifyNever` when text field is empty
3. deleteItem — opens menu, confirms dialog, calls `deleteGearItem`
4. togglePacked — taps `AnimatedContainer` checkbox, calls `togglePacked(isPacked: true)`
5. priority — opens menu, calls `updateGearItem(isHighPriority: true)`
6. claim — opens menu, calls `updateGearItem(assignedTo: 'test-user-uid')`
7. unclaim — opens menu on claimed item, calls `unclaimGearItem`
8. error handling — `addGearItem` throws, SnackBar appears with error message

Key testing pattern: `PopupMenuButtonState.showButtonMenu()` called directly instead of simulating a tap — the FAB at `Rect(710,510,758,558)` overlaps/occludes the popup area causing direct taps to not register in test viewports.

## Deviations from Plan

None — plan executed exactly as written. The `showButtonMenu()` approach for widget tests is an implementation detail of the test harness, not a deviation from the plan's intent.

## Known Stubs

None. All 6 mutations are now wired to real Firestore calls.

## Self-Check: PASSED
