---
phase: 03-events
plan: 01
subsystem: database
tags: [firestore, supabase-bridge, riverpod, security-rules, events, gear-seeding]

# Dependency graph
requires:
  - phase: 03-events-00
    provides: Event model (event_model.dart) with EventType, EventModules, Event.fromDoc, toFirestoreMap

provides:
  - EventService with createEvent (Firestore write + Supabase bridge + camping gear seeding)
  - EventService.deleteEvent (soft delete), updateEvent, updateParticipants
  - groupEventsProvider reactive stream (null-date-first sort)
  - eventDetailProvider using Dart record compound key
  - eventLoadingProvider and eventErrorProvider state providers
  - Firestore security rules for events subcollection (group-member read, participant write, no delete)
  - Composite index for events query (isDeleted ASC + createdAt DESC)
  - pull-to-refresh fix on home screen (ref.invalidate instead of ref.refresh)

affects:
  - 03-events-02 (event creation UI uses eventServiceProvider + groupEventsProvider)
  - 03-events-03 (event hub uses eventDetailProvider)
  - 03-events-04 (group detail event timeline uses groupEventsProvider)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - EventService.withFirestore test constructor injects FakeFirebaseFirestore + MockGearService
    - Supabase bridge uses same UUID for eventId and bridgeTripId
    - Bridge failure is caught and logged — never throws from createEvent
    - Camping gear seeding only runs when bridge succeeded (Pitfall 4)
    - Security rules: specific match /events/{eventId} shadows generic /{subcollection}/{docId}

key-files:
  created:
    - lib/features/events/services/event_service.dart
    - lib/features/events/providers/event_provider.dart
  modified:
    - test/unit/event_service_test.dart
    - security/firestore.rules
    - firestore.indexes.json
    - lib/features/home/screens/home_screen.dart

key-decisions:
  - "EventService.withFirestore test constructor sets _skipBridgeInTest=true so gear seeding can be verified without Supabase"
  - "Supabase isAuthenticated check wrapped in try-catch to handle uninitialized Supabase in test environments"
  - "Camping gear seeding happens only when bridge succeeded in production; test constructor bypasses this check"
  - "eventDetailProvider uses Dart record type ({String groupId, String eventId}) as family key — no separate class needed"
  - "pull-to-refresh uses ref.invalidate(userGroupsProvider) to close/reopen Firestore stream subscription"

patterns-established:
  - "EventService test constructor pattern: .withFirestore(FakeFirebaseFirestore, MockGearService) for unit testing"
  - "Supabase bridge: fire-and-forget, no throw, log only"
  - "Security rules for subcollection: specific match block before generic /{subcollection}/{docId}"

requirements-completed: [EVT-01, EVT-04, EVT-06]

# Metrics
duration: 6min
completed: 2026-03-26
---

# Phase 3 Plan 01: Events Data Layer Summary

**EventService with Firestore write + Supabase bridge pattern + camping gear seeding, reactive event providers, hardened security rules, and pull-to-refresh fix**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-26T10:04:48Z
- **Completed:** 2026-03-26T10:10:48Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- EventService creates events in Firestore at `groups/{groupId}/events/{eventId}` with all required fields
- Supabase bridge trip created with same UUID (fire-and-forget, failure never throws)
- Camping type auto-seeds Tent (high), Sleeping Bag (high), Cooler (normal) via GearService
- groupEventsProvider reactive stream with null-date-first client-side sort
- Firestore security rules: group members read, participants write, hard delete blocked
- Composite index added for isDeleted+createdAt events query
- Home screen pull-to-refresh fixed: ref.invalidate closes/reopens the Firestore stream

## Task Commits

Each task was committed atomically:

1. **Task 1: EventService + providers + tests** - `3268f4a` (feat)
2. **Task 2: Security rules + index + pull-to-refresh** - `17f9c60` (feat)

**Plan metadata:** pending (docs commit)

## Files Created/Modified

- `lib/features/events/services/event_service.dart` - EventService with createEvent, deleteEvent, updateEvent, updateParticipants
- `lib/features/events/providers/event_provider.dart` - groupEventsProvider, eventDetailProvider, eventServiceProvider, eventLoadingProvider, eventErrorProvider
- `test/unit/event_service_test.dart` - 13 unit tests replacing all skip markers
- `security/firestore.rules` - Events subcollection rules (group-member read, participant write, no delete)
- `firestore.indexes.json` - Composite index for events query
- `lib/features/home/screens/home_screen.dart` - Pull-to-refresh fix using ref.invalidate

## Decisions Made

- EventService uses a `withFirestore` test constructor that sets `_skipBridgeInTest=true`. This allows GearService.addItem calls to be verified without needing Supabase initialized in unit tests.
- `SupabaseConfig.isAuthenticated` is wrapped in a try-catch because `Supabase.instance` throws an assertion error when not initialized (unit test env and Firebase-only mode). This was an auto-fix (Rule 1 - Bug) discovered during GREEN phase.
- Dart record type `({String groupId, String eventId})` used as eventDetailProvider family key — cleaner than creating a separate data class for a two-field compound key.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Supabase.instance assertion error in test environment**
- **Found during:** Task 1 (GREEN phase — tests ran and failed)
- **Issue:** `SupabaseConfig.isAuthenticated` calls `Supabase.instance` which throws `_instance._isInitialized` assertion when Supabase is not initialized (unit test context)
- **Fix:** Wrapped the `SupabaseConfig.isAuthenticated` and `SupabaseConfig.currentUser` calls in a try-catch that sets `isAuthenticated = false` when Supabase is unavailable. Also added `_skipBridgeInTest` flag to the test constructor so gear seeding can be verified without bridge.
- **Files modified:** lib/features/events/services/event_service.dart
- **Verification:** All 13 unit tests pass
- **Committed in:** 3268f4a (Task 1 commit)

**2. [Rule 1 - Bug] Missing default GearService mock stub caused test failures**
- **Found during:** Task 1 (camping preset tests failing with "Null is not a subtype of Future<GearItem?>")
- **Issue:** Tests using EventType.camping (e.g., bridgeTripId test) triggered gear seeding but MockGearService.addItem had no stub, returning null synchronously instead of `Future<null>`
- **Fix:** Added a default `when()` stub in setUp that returns `async => null` for all addItem calls. Individual tests override with `verify()` assertions as needed.
- **Files modified:** test/unit/event_service_test.dart
- **Verification:** All 13 tests pass
- **Committed in:** 3268f4a (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (2 Rule 1 bugs)
**Impact on plan:** Both auto-fixes needed for tests to pass correctly. No scope creep.

## Issues Encountered

- Dart `final` variables inside try/catch blocks can't be reassigned in catch — used `bool isAuthenticated = false` (non-final) instead of `final bool isAuthenticated`. Standard Dart pattern.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- EventService data layer is complete — Plans 03-02 through 03-04 can use `eventServiceProvider` and `groupEventsProvider`
- No blockers for event creation UI (Plan 03-02)
- Security rules deployed to Firestore emulator or production before UI tests work end-to-end

## Self-Check: PASSED

- lib/features/events/services/event_service.dart: FOUND
- lib/features/events/providers/event_provider.dart: FOUND
- .planning/phases/03-events/03-01-SUMMARY.md: FOUND
- commit 3268f4a: FOUND
- commit 17f9c60: FOUND

---
*Phase: 03-events*
*Completed: 2026-03-26*
