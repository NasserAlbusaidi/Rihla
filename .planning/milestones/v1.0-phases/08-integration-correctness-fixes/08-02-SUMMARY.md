---
phase: 08-integration-correctness-fixes
plan: 02
subsystem: ui
tags: [flutter, riverpod, formatters, settle-up, group-finances, event-names]

# Dependency graph
requires:
  - phase: 05-cross-event-financials
    provides: GroupSettleUpScreen with _shortEventLabel method and perEventBreakdown
  - phase: 03-events
    provides: groupEventsProvider StreamProvider.family returning List<Event>

provides:
  - AppFormatters.formatShortMonthDay returning 'Mar 15' format (no zero-padding)
  - GroupSettleUpScreen per-event breakdown with human-readable 'Camping Weekend -- Mar 15' labels
  - _buildEventLabel method replacing _shortEventLabel
  - Widget tests covering happy path and fallback scenarios

affects:
  - 08-integration-correctness-fixes

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Watch groupEventsProvider in build() to create eventNameMap for label rendering
    - Thread record types through method signatures to avoid global state
    - TDD RED-GREEN for pure formatter methods

key-files:
  created: []
  modified:
    - lib/core/utils/formatters.dart
    - lib/features/groups/screens/group_settle_up_screen.dart
    - test/unit/formatters_test.dart
    - test/features/groups/group_settle_up_screen_test.dart

key-decisions:
  - "groupEventsProvider watched in build() with valueOrNull for non-blocking event name resolution — empty map on loading/error triggers fallback label"
  - "Record type used for eventNameMap values ({name, type, date}) — avoids creating a new class for a single-method lookup structure"
  - "Fallback test uses events=[] override (not unoverridden provider) to avoid Firestore initialization in widget tests"

patterns-established:
  - "eventId fallback label returns eventId directly when id.length <= 8 (short test IDs); returns 'Event ...{last6}' for realistic Firestore IDs"

requirements-completed: [FIN-04]

# Metrics
duration: 6min
completed: 2026-03-27
---

# Phase 08 Plan 02: GroupSettleUpScreen Event Name Labels Summary

**GroupSettleUpScreen per-event breakdown fixed: shows 'Camping Weekend -- Mar 15' via groupEventsProvider lookup instead of truncated Firestore eventIds**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-03-27T14:49:11Z
- **Completed:** 2026-03-27T14:55:17Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added `AppFormatters.formatShortMonthDay` with TDD (RED-GREEN cycle, 4 test cases)
- Replaced `_shortEventLabel` with `_buildEventLabel` reading real event names from `groupEventsProvider`
- Format: `{name} \u2014 {Mar 15}`, truncated at 30 chars, fallback to EventTypeConfig label when name empty
- Updated per-event breakdown UI to use `Row`/`Flexible` for overflow handling per UI-SPEC typography
- 2 new widget tests: happy path (`Camping Weekend`, `Mar 15`) + fallback (`event-1` label)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add AppFormatters.formatShortMonthDay and formatter tests** - `b38c74e` (feat, TDD)
2. **Task 2: Replace _shortEventLabel with event name lookup in GroupSettleUpScreen** - `c8f84f6` (feat)

**Plan metadata:** (docs commit follows)

_Note: Task 1 followed TDD RED-GREEN cycle: tests written first, confirmed failing, then implementation added._

## Files Created/Modified

- `lib/core/utils/formatters.dart` - Added `_monthAbbr` const and `formatShortMonthDay(DateTime)` static method
- `test/unit/formatters_test.dart` - 4 new `formatShortMonthDay` test cases (Mar 15, Jan 1, Dec 31, Jun 3)
- `lib/features/groups/screens/group_settle_up_screen.dart` - Imports event_model/event_type_config/event_provider; watches groupEventsProvider; new `_buildEventLabel` method; deleted `_shortEventLabel`; Row/Flexible breakdown UI; eventNameMap threaded through 4-level call chain
- `test/features/groups/group_settle_up_screen_test.dart` - `_testEvent` fixture; updated `_wrap` helper with events param; 2 new widget tests

## Decisions Made

- `groupEventsProvider` watched in `build()` using `valueOrNull` — non-blocking, empty map triggers fallback label when events not yet loaded
- Record type `({String name, EventType type, DateTime date})` for eventNameMap values — avoids new class for a transient structure
- Fallback test uses `events: const []` override rather than leaving provider unoverridden, which would attempt Firestore initialization in tests

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed fallback test assertion to match actual eventId label**

- **Found during:** Task 2 widget test run
- **Issue:** Test expected `textContaining('Event')` but `event-1` (length 7, <= 8) falls through to `return eventId` path in `_buildEventLabel`, rendering `'event-1'` not `'Event ...'`
- **Fix:** Updated assertion to `textContaining('event-1')` and used `events: const []` override instead of unoverridden provider
- **Files modified:** test/features/groups/group_settle_up_screen_test.dart
- **Verification:** All 15 widget tests pass
- **Committed in:** c8f84f6 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug in test assertion)
**Impact on plan:** Necessary for test correctness. No scope creep.

## Issues Encountered

- Initial fallback test used `pumpAndSettle` without events override — Firestore uninitialized in test environment caused provider to return `AsyncLoading`, `valueOrNull` returned null. Fixed by providing `events: const []` override which correctly exercises the empty-map fallback path.

## Known Stubs

None - event names are wired from `groupEventsProvider` data, no placeholder values.

## Next Phase Readiness

- FIN-04 complete: per-event breakdown shows meaningful labels
- Remaining phase 08 plans can proceed
- `AppFormatters.formatShortMonthDay` available for any future date formatting needs

## Self-Check: PASSED

- FOUND: lib/core/utils/formatters.dart
- FOUND: lib/features/groups/screens/group_settle_up_screen.dart
- FOUND: test/unit/formatters_test.dart
- FOUND: test/features/groups/group_settle_up_screen_test.dart
- FOUND: .planning/phases/08-integration-correctness-fixes/08-02-SUMMARY.md
- FOUND commit: b38c74e (Task 1 - formatShortMonthDay)
- FOUND commit: c8f84f6 (Task 2 - event name labels)

---
*Phase: 08-integration-correctness-fixes*
*Completed: 2026-03-27*
