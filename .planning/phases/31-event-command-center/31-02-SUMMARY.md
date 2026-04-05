---
phase: 31-event-command-center
plan: "02"
subsystem: events/settings
tags: [event-settings, crud, danger-zone, tdd]
dependency_graph:
  requires:
    - 31-00 (EventKeys, test stubs)
    - 31-01 (EventService.updateEvent/deleteEvent with description, placeholder router route)
  provides:
    - EventInfoSection widget (event name/dates/description, save logic)
    - EventDangerSection widget (creator guard, delete dialog, activity log)
    - EventSettingsScreen (full screen mirroring GroupSettingsScreen pattern)
    - Real EventSettingsScreen wired into /group/:gid/event/:eid/settings router
  affects:
    - lib/core/router/app_router.dart (placeholder removed)
    - test/features/events/event_settings_screen_test.dart (6 tests GREEN)
tech_stack:
  added: []
  patterns:
    - ConsumerStatefulWidget for EventInfoSection (form state)
    - ConsumerWidget for EventDangerSection (read-only provider watching)
    - Fire-and-forget async per Phase 26 P01 decision (synchronous onPressed/onTap)
    - try/catch wrapping activity log call (D-14: logging never crashes flow)
    - .then() pattern for date picker (synchronous onTap, async internally)
key_files:
  created:
    - lib/features/events/widgets/event_info_section.dart (352 lines)
    - lib/features/events/widgets/event_danger_section.dart (263 lines)
    - lib/features/events/screens/event_settings_screen.dart (183 lines)
  modified:
    - lib/core/router/app_router.dart (placeholder -> real EventSettingsScreen)
    - test/features/events/event_settings_screen_test.dart (stub -> 6 GREEN tests)
decisions:
  - "Fire-and-forget save: _save() called without await in onPressed; async state managed internally"
  - "Solid primary color for Save Changes button (primary token, not gradient) — acceptable MVP fallback per plan"
  - "Pre-existing test failures in ledger_test.dart and group_settle_up_screen_test.dart are out-of-scope (pre-date this plan)"
metrics:
  duration: "~10 minutes"
  completed: 2026-04-05
  tasks: 3
  files_created: 3
  files_modified: 2
  tests_added: 6
  tests_passing: 6
---

# Phase 31 Plan 02: EventSettingsScreen Summary

Event settings screen with editable info fields, creator-only delete zone, and full widget test coverage. Turns ECC-02 tests GREEN.

## What Was Built

**EventInfoSection** (`event_info_section.dart`, 352 lines): ConsumerStatefulWidget with name TextField, start/end date pickers (fire-and-forget `.then()` pattern), description multi-line field, and Save Changes button. Calls `eventServiceProvider.updateEvent()` with only non-null changes. Shows "Event updated" snackbar on success, "Couldn't save changes. Try again." on error. UTC normalization via `.toUtc()`.

**EventDangerSection** (`event_danger_section.dart`, 263 lines): ConsumerWidget with creator guard (returns SizedBox.shrink if !isCreator). Watches `eventExpensesProvider` + `eventSettlementsProvider` for balance gate. Shows amber warning row when unsettled. Delete tile shows AlertDialog with context-aware body copy. `_executeDelete` logs `event_deleted` activity in try/catch (D-14 compliance) then fire-and-forgets `deleteEvent`, navigates to `/group/$groupId`.

**EventSettingsScreen** (`event_settings_screen.dart`, 183 lines): Mirrors GroupSettingsScreen exactly — no AppBar, inline back button, SingleChildScrollView, 24px horizontal padding. Watches `eventDetailProvider` + `currentUserIdProvider`. Two sections with 100ms/200ms stagger animations via flutter_animate. Loading state shows `SkeletonLoader.generic(count: 3)`. Error state with retry invalidates the provider.

**Router**: Placeholder scaffold replaced with real `EventSettingsScreen`. Import added for `event_settings_screen.dart`.

**Tests**: 6 tests covering renders event name, Save Changes present, delete visible for creator, delete hidden for non-creator, dialog shows on tap, Save Changes calls updateEvent and shows snackbar.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed unnecessary cast and import in EventDangerSection**
- **Found during:** Task 2 analysis
- **Issue:** `as EventRef` cast was flagged as unnecessary; event_ref.dart import was redundant (already re-exported by expense_provider.dart)
- **Fix:** Removed cast and extra import
- **Files modified:** lib/features/events/widgets/event_danger_section.dart
- **Commit:** 5b78966

**2. [Rule 1 - Bug] Fixed unused parameter warning in EventSettingsScreen error builder**
- **Found during:** Task 3 analysis
- **Issue:** `error: (_, __) =>` flagged as `unnecessary_underscores`
- **Fix:** Changed to `error: (e, st) =>`
- **Files modified:** lib/features/events/screens/event_settings_screen.dart
- **Commit:** a36a087

## Known Stubs

None. All plan goals achieved — EventSettingsScreen is fully wired with real data providers.

## Pre-existing Issues (Deferred)

Two test files have pre-existing compilation failures unrelated to this plan:
- `test/features/ledger_test.dart` — `LedgerScreen` missing `event` named parameter
- `test/features/group_settle_up_screen_test.dart` — `GroupSettleUpScreen` missing `group` named parameter

These existed before this plan's changes (confirmed via `git stash` check). Logged to deferred-items.

## Self-Check: PASSED

Files exist:
- `lib/features/events/widgets/event_info_section.dart` — FOUND
- `lib/features/events/widgets/event_danger_section.dart` — FOUND
- `lib/features/events/screens/event_settings_screen.dart` — FOUND

Commits exist:
- `5b78966` (EventInfoSection + EventDangerSection) — FOUND
- `a36a087` (EventSettingsScreen + router + tests) — FOUND

Tests: 6/6 ECC-02 tests GREEN. Full suite: 858 pass, 3 skip, 2 pre-existing failures.
