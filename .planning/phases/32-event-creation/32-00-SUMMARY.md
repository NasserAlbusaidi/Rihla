---
phase: 32-event-creation
plan: "00"
subsystem: events/tests
tags: [tdd, wave-0, test-stubs, red-state]
dependency_graph:
  requires: []
  provides: [red-test-stubs-for-32-01, red-test-stubs-for-32-02]
  affects: [test/features/events/create_event_test.dart, test/unit/event_model_test.dart]
tech_stack:
  added: []
  patterns: [TDD Red-Green cycle, wave-0 test stubs]
key_files:
  created: []
  modified:
    - lib/features/events/keys/event_keys.dart
    - test/features/events/create_event_test.dart
    - test/unit/event_model_test.dart
decisions:
  - "selectAllButton key declared in EventKeys before implementation — key is the test contract"
  - "Camping color target is 0xFF047857 (successText, WCAG 4.56:1) not 0xFF10B981 (success, lower contrast)"
  - "AppBar title tests updated to assert both absence of old title and presence of new badge text"
metrics:
  duration: "~4 minutes"
  completed: "2026-04-05T10:22:40Z"
  tasks_completed: 2
  files_modified: 3
---

# Phase 32 Plan 00: Wave-0 Failing Test Stubs Summary

**One-liner:** 7 RED test stubs (3 updated + 4 new) that define the visual contract for Plans 01 and 02 before implementation begins.

## What Was Done

This is a pure TDD Wave-0 plan — no implementation code changed. All changes are in test files and keys.

### Task 1: selectAllButton key + wave-0 failing tests (commit: ac7f242)

Added `EventKeys.selectAllButton = Key('event_select_all_button')` to `lib/features/events/keys/event_keys.dart`.

Updated 3 existing tests in `test/features/events/create_event_test.dart`:

1. **Picker title test** renamed to `'shows ModuleHeader title "New Event"'` — assertion changed from `find.byKey(EventKeys.eventTypePickerTitle)` to `find.text('New Event')`. Fails now (AppBar still says 'Choose Event Type').

2. **Navigation test** — after tap, assertion changed from `find.text('New Trip Event') findsOneWidget` to `find.text('New Trip Event') findsNothing` + `find.text('Trip') findsOneWidget`. Fails now (AppBar title 'New Trip Event' is still present).

3. **Create form title test** renamed to `'shows event type badge with type label, no AppBar title'` — asserts `find.text('New Camping Event') findsNothing` + `find.text('Camping') findsOneWidget`. Fails now (AppBar shows 'New Camping Event').

Added 3 new tests:
- `'shows Select All checkbox in participants card'` — finds `EventKeys.selectAllButton`
- `'Select All selects all participants when tapped'` — taps selectAllButton, verifies all Checkboxes are true
- `'Select All deselects all when all participants are selected'` — taps selectAllButton, verifies all Checkboxes are false

### Task 2: Camping color unit test (commit: 3c471bb)

Added `flutter/material.dart` and `event_type_config.dart` imports to `test/unit/event_model_test.dart`.

Added `EventTypeConfig` test group with 3 tests:
- `'camping color uses successText token hex (#047857) for WCAG compliance'` — FAILS now (current value 0xFF10B981)
- `'trip color uses primary token hex (#0D7B74)'` — passes (already correct)
- `'custom color uses warning token hex (#F59E0B)'` — passes (already correct)

## Verification

Both test files run together: **46 passing, 7 failing** — all 7 failures are in newly added/updated tests.

Pre-existing 8+ tests in create_event_test remain green. Pre-existing 35+ tests in event_model_test remain green.

`flutter analyze` reports zero new errors (one pre-existing info-level `no_leading_underscores_for_local_identifiers` in event_model_test, not introduced by this plan).

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. This plan only adds test stubs, not implementation stubs.

## Self-Check: PASSED

- [x] `lib/features/events/keys/event_keys.dart` — modified, selectAllButton added
- [x] `test/features/events/create_event_test.dart` — modified, 3 tests updated + 3 new
- [x] `test/unit/event_model_test.dart` — modified, EventTypeConfig group added
- [x] Commit ac7f242 exists: `test(32-00): add selectAllButton key + wave-0 failing tests for picker/form redesign`
- [x] Commit 3c471bb exists: `test(32-00): add EventTypeConfig color unit tests with camping RED assertion`
- [x] 7 failing tests confirmed across both files
