---
phase: 31-event-command-center
plan: "00"
subsystem: testing
tags: [tdd, red-phase, wave-0, event-command-center, test-stubs]
dependency_graph:
  requires: []
  provides:
    - ECC-01 failing test stubs (gear icon + date range)
    - ECC-02 failing test stubs (EventSettingsScreen behaviors)
  affects:
    - test/features/events/event_command_center_test.dart
    - test/features/events/event_settings_screen_test.dart
tech_stack:
  added: []
  patterns:
    - Wave-0 TDD RED phase stub pattern
    - _wrapSettings placeholder returning NOT_IMPLEMENTED scaffold
key_files:
  created:
    - test/features/events/event_settings_screen_test.dart
  modified:
    - test/features/events/event_command_center_test.dart
decisions:
  - "_wrapSettings stub returns MaterialApp with NOT_IMPLEMENTED text — EventSettingsScreen class does not exist yet; imports kept for Plan 02 mock injection"
  - "Unused imports left intentionally in event_settings_screen_test.dart — in preparation for Plan 02 provider override pattern; only warnings, no errors"
metrics:
  duration: "136s"
  completed: "2026-04-05T09:39:45Z"
  tasks_completed: 2
  files_created: 1
  files_modified: 1
---

# Phase 31 Plan 00: Wave 0 TDD Red Phase Stubs Summary

Wave 0 TDD RED baseline established: failing test stubs for EventSettingsScreen (ECC-02) and gear icon / date range behaviors (ECC-01) in EventCommandCenter.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Update _wrapEventHub with settings stub route | b6c891c | test/features/events/event_command_center_test.dart |
| 2 | Create event_settings_screen_test.dart with failing stubs | 92ab71b | test/features/events/event_settings_screen_test.dart |

## What Was Built

### Task 1: event_command_center_test.dart updates

Added to `_wrapEventHub`:
- `settings` GoRoute stub that renders `EventSettings:{eid}` text

Added ECC-01 test group with 4 tests:
- `gear icon is visible in the header` — FAILS (RED) — finder finds 0 Iconsax.setting_2 widgets
- `gear icon tap navigates to settings route` — FAILS (RED) — no gear icon to tap
- `date range shown when event has startDate and endDate` — FAILS (RED) — date range text not rendered
- `date range hidden when both dates are null` — PASSES (vacuous findsNothing on null event)

### Task 2: event_settings_screen_test.dart (new file)

Created stub scaffold with `_wrapSettings` returning `NOT_IMPLEMENTED` placeholder. 5 ECC-02 tests:
- `renders event name in text field` — FAILS (RED)
- `Save Changes button is present` — FAILS (RED)
- `delete event tile is visible for creator` — FAILS (RED)
- `delete event tile is hidden for non-creator` — PASSES (vacuous findsNothing on stub)
- `delete tile tap shows confirmation dialog` — FAILS (RED)

## Test Results

```
flutter test test/features/events/
+52 -7: Some tests failed.
```

- 52 tests passing (all pre-existing tests + 2 vacuous stubs)
- 7 tests failing RED: 3 ECC-01 + 4 ECC-02
- All 15 pre-existing EventCommandCenter tests continue to PASS

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

| File | Stub | Reason |
|------|------|--------|
| test/features/events/event_settings_screen_test.dart | `_wrapSettings` returns `NOT_IMPLEMENTED` | EventSettingsScreen class not yet implemented — Plan 02 will replace |
| test/features/events/event_settings_screen_test.dart | Unused imports (flutter_riverpod, go_router, mocktail, providers) | Pre-staged for Plan 02 mock injection pattern |

## Self-Check

Verified commits:
- `b6c891c` — test(31-00): add settings stub route and ECC-01 failing tests
- `92ab71b` — test(31-00): create event_settings_screen_test.dart with 5 failing ECC-02 stubs

Verified files exist:
- test/features/events/event_command_center_test.dart (modified)
- test/features/events/event_settings_screen_test.dart (created, 117 lines)

## Self-Check: PASSED
