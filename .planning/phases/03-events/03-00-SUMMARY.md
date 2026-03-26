---
phase: 03-events
plan: "00"
subsystem: events
tags: [flutter, firestore, event-model, dart, riverpod]

requires:
  - phase: 02-groups
    provides: Group.fromDoc Firestore serialization pattern and GroupMember model used as reference for Event model design

provides:
  - Event class with full Firestore serialization (fromDoc, toFirestoreMap)
  - EventType enum with 5 string-backed values and fromString fallback
  - EventModules class with forType factory and copyWith (ledger toggleable per D-14)
  - EventTypeConfig static metadata (label, description, icon, color per type)
  - Test stub files for all 4 subsequent event plans (24 skipped tests)
  - events feature directory structure ready for Plans 03-01 through 03-04

affects: [03-01-event-service, 03-02-create-event, 03-03-group-detail-events, 03-04-event-command-center]

tech-stack:
  added: []
  patterns:
    - EventType enum with string-backed values and fromString fallback to custom
    - EventModules.forType switch expression for per-type module configuration
    - Event.fromDoc handles Timestamp/String/null for createdAt (multi-format Firestore timestamps)
    - Separate serverCreatedAt field as FieldValue.serverTimestamp() alongside client-generated createdAt string

key-files:
  created:
    - lib/features/events/models/event_model.dart
    - lib/features/events/models/event_type_config.dart
    - test/unit/event_model_test.dart
    - test/unit/event_service_test.dart
    - test/features/events/create_event_test.dart
    - test/features/events/group_detail_events_test.dart
    - test/features/events/event_command_center_test.dart
  modified: []

key-decisions:
  - "EventModules constructor does not force ledger=true — preset types enforce it via forType(), Custom can toggle via copyWith per D-14"
  - "bridgeTripId falls back to doc.id if not set in Firestore — ensures Supabase bridge always has a valid trip ID"
  - "Test stubs use () {} body form (not positional-only) to satisfy flutter_test's test() signature"

patterns-established:
  - "Pattern 1: EventType enum with string value + fromString(fallback: custom) — use for all future enum serialization in events domain"
  - "Pattern 2: Event.fromDoc handles createdAt as Timestamp | String | null — same pattern for all future Firestore models in Phase 3"
  - "Pattern 3: Test stub files with () {} body and skip: string — established for all Phase 3 stub files"

requirements-completed: [EVT-02, EVT-03, EVT-05]

duration: 4min
completed: 2026-03-26
---

# Phase 3 Plan 0: Event model, EventType, EventModules, EventTypeConfig — type contracts with 30 unit tests and 24 stub files

**Event model with Firestore serialization (fromDoc/toFirestoreMap), EventType 5-value enum, EventModules per-type factory, EventTypeConfig UI metadata, and 24 test stubs for all subsequent phase plans**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-26T09:56:05Z
- **Completed:** 2026-03-26T10:00:00Z
- **Tasks:** 2
- **Files modified:** 7 created

## Accomplishments

- Event model with all 15 fields from D-33, full Firestore serialization, and immutable copyWith
- EventType enum with string-backed values; nightDayOut serializes as 'night_day_out' per D-11
- EventModules.forType covers all 5 types per D-12 with correct module combinations
- EventTypeConfig provides single source of truth for type picker UI (label, description, icon, color)
- 30 passing unit tests via TDD (RED -> GREEN -> analyze)
- 24 test stubs (7+6+6+5) for Plans 03-01 through 03-04 with correct Awaiting Plan markers
- events feature directory structure created: models/providers/screens/services/widgets

## Task Commits

Each task was committed atomically:

1. **Task 1: Event model, EventType enum, EventModules class with TDD** - `a3f5f6d` (feat)
2. **Task 2: EventTypeConfig and test stub files for phase** - `ab975fa` (feat)

## Files Created/Modified

- `lib/features/events/models/event_model.dart` - Event, EventType, EventModules classes
- `lib/features/events/models/event_type_config.dart` - Static UI metadata for all 5 event types
- `test/unit/event_model_test.dart` - 30 unit tests covering serialization, forType, lifecycle, equality
- `test/unit/event_service_test.dart` - 7 skipped stubs (Plan 03-01)
- `test/features/events/create_event_test.dart` - 6 skipped stubs (Plan 03-02)
- `test/features/events/group_detail_events_test.dart` - 6 skipped stubs (Plan 03-03)
- `test/features/events/event_command_center_test.dart` - 5 skipped stubs (Plan 03-04)

## Decisions Made

- EventModules constructor does not force ledger=true — preset types enforce it via forType(), Custom can toggle via copyWith per D-14. This preserves flexibility for the custom event type while ensuring all preset types always have ledger enabled.
- bridgeTripId falls back to doc.id when not present in Firestore. This ensures the Supabase bridge (D-22) always has a valid trip ID, making the field safe to add to existing documents incrementally.
- Test stubs require a `() {}` body because flutter_test's `test()` signature has 2 required positional parameters. Using only named `skip:` without a body results in a compile error.

## Deviations from Plan

**1. [Rule 3 - Blocking] Test stub format corrected from positional-only to body+skip**
- **Found during:** Task 2 (verifying stub compilation)
- **Issue:** Plan showed `test('name', skip: '...')` pattern without a body. flutter_test requires a body callback as the 2nd positional argument.
- **Fix:** Changed all stubs to `test('name', () {}, skip: '...')` form
- **Files modified:** test/unit/event_service_test.dart, test/features/events/create_event_test.dart, test/features/events/group_detail_events_test.dart, test/features/events/event_command_center_test.dart
- **Verification:** All 24 tests compile and run with correct Skip output
- **Committed in:** ab975fa (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (blocking)
**Impact on plan:** Fix necessary for compilation. No scope creep.

## Issues Encountered

None beyond the stub format fix documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Event type contracts (Event, EventType, EventModules, EventTypeConfig) are production-ready
- All subsequent plans in Phase 3 can import from `lib/features/events/models/event_model.dart`
- Test stubs provide a compile-safe skeleton for Plans 03-01 through 03-04
- Feature directory structure is ready: lib/features/events/{models,providers,screens,services,widgets}

---
*Phase: 03-events*
*Completed: 2026-03-26*

## Self-Check: PASSED

- FOUND: lib/features/events/models/event_model.dart
- FOUND: lib/features/events/models/event_type_config.dart
- FOUND: test/unit/event_model_test.dart
- FOUND: test/unit/event_service_test.dart
- FOUND: test/features/events/create_event_test.dart
- FOUND: test/features/events/group_detail_events_test.dart
- FOUND: test/features/events/event_command_center_test.dart
- FOUND commit: a3f5f6d (Task 1)
- FOUND commit: ab975fa (Task 2)
