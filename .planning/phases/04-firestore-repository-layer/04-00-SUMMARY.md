---
phase: 04-firestore-repository-layer
plan: "00"
subsystem: database
tags: [firestore, serialization, repository-pattern, money-serialization, security-rules, tdd]

# Dependency graph
requires:
  - phase: 03-events
    provides: EventService.withFirestore pattern and FakeFirebaseFirestore test approach

provides:
  - abstract FirestoreRepository base class with production/test constructors and eventSubcollection helper
  - Expense.fromFirestore/toFirestore with MoneySerializer (amountFils integer subunits)
  - Settlement.fromFirestore/toFirestore with MoneySerializer
  - GearItem.fromFirestore/toFirestore with camelCase field names
  - SubGroup.fromFirestore/toFirestore (members in separate subcollection)
  - ActivityLog.fromFirestore/toFirestore with metadata support
  - Firestore security rules for module subcollections via isEventParticipantForModule
  - 10 Wave 0 test stub files with skip markers for plans 04-01 through 04-04

affects:
  - 04-01-ledger-migration (uses FirestoreRepository, Expense/Settlement serialization)
  - 04-02-gear-migration (uses FirestoreRepository, GearItem serialization)
  - 04-03-logistics-migration (uses FirestoreRepository, SubGroup serialization)
  - 04-04-activity-vault-migration (uses FirestoreRepository, ActivityLog serialization)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "FirestoreRepository abstract base class: production constructor uses FirebaseConfig.firestore, test constructor accepts FakeFirebaseFirestore injection"
    - "Firestore field naming: camelCase (not snake_case as in Supabase)"
    - "tripId field maps to eventId in Firestore for backward compatibility with BalanceCalculator"
    - "Money stored as integer amountFils via MoneySerializer.toSubunits/fromSubunits"
    - "createdAt stored as ISO 8601 string for immediate readback (not FieldValue.serverTimestamp)"
    - "Wave 0 test stubs: skip marker pattern 'Awaiting Plan 04-NN: description'"

key-files:
  created:
    - lib/core/services/firestore_repository.dart
    - test/unit/firestore_repository_test.dart
    - test/unit/expense_service_test.dart
    - test/unit/settlement_service_test.dart
    - test/unit/gear_service_test.dart
    - test/unit/sub_group_service_test.dart
    - test/unit/activity_service_test.dart
    - test/unit/document_service_test.dart
    - test/unit/memory_service_test.dart
    - test/unit/balance_cache_repository_test.dart
    - test/unit/lazy_migration_service_test.dart
    - test/unit/connectivity_provider_test.dart
  modified:
    - lib/features/ledger/models/expense_model.dart
    - lib/features/ledger/models/settlement_model.dart
    - lib/features/gear/models/gear_item_model.dart
    - lib/features/logistics/models/sub_group_model.dart
    - lib/features/activity/models/activity_log_model.dart
    - security/firestore.rules

key-decisions:
  - "Expense.currency is a computed getter defaulting to 'OMR' -- existing model has no currency field, getter avoids a breaking change while enabling MoneySerializer"
  - "Module subcollection security uses nested match /{module}/{docId} under match /events/{eventId} -- Firestore nested syntax, equivalent to flat path match /events/{eventId}/{module}/{docId}"
  - "SubGroup.fromFirestore returns members: const [] -- members are in a separate subcollection, not inlined in the document"

patterns-established:
  - "Repository base pattern: extend FirestoreRepository, call withFirestore(db) in tests"
  - "Model serialization: fromFirestore(Map<String,dynamic> data) + toFirestore() Map<String,dynamic>"
  - "Wave 0 stubs: create test file with skip markers before service implementation plans run"

requirements-completed:
  - MIG-05

# Metrics
duration: 5min
completed: "2026-03-26"
---

# Phase 04 Plan 00: FirestoreRepository Base Class + Model Serialization Summary

**Abstract FirestoreRepository base class with test injection, Firestore fromFirestore/toFirestore on 5 module models (money via MoneySerializer), module subcollection security rules, and 10 Wave 0 test stubs**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-26T17:02:04Z
- **Completed:** 2026-03-26T17:07:00Z
- **Tasks:** 2 of 2
- **Files modified:** 18

## Accomplishments

- Created `FirestoreRepository` abstract base class with production constructor (uses FirebaseConfig.firestore) and test constructor (accepts FakeFirebaseFirestore injection), plus `eventSubcollection` helper returning typed `CollectionReference<Map<String, dynamic>>`
- Added `fromFirestore`/`toFirestore` to Expense (with MoneySerializer amountFils), Settlement, GearItem, SubGroup, and ActivityLog models — all using camelCase fields and `eventId` as the Firestore field name for backward-compatible `tripId` mapping
- Added Firestore security rule `match /{module}/{docId}` nested under `match /events/{eventId}` with `isEventParticipantForModule()` function checking `event.participantIds`
- Created 10 Wave 0 test stub files with `skip: 'Awaiting Plan 04-NN'` markers for all services to be migrated in plans 04-01 through 04-04

## Task Commits

1. **Task 1: FirestoreRepository base class + model serialization** - `509120f` (feat)
2. **Task 2: Security rules + Wave 0 test stubs** - `be30239` (feat)

**Plan metadata:** (created below)

## Files Created/Modified

- `lib/core/services/firestore_repository.dart` - Abstract base class with production/test constructors and eventSubcollection helper
- `lib/features/ledger/models/expense_model.dart` - Added fromFirestore/toFirestore with MoneySerializer, currency getter
- `lib/features/ledger/models/settlement_model.dart` - Added fromFirestore/toFirestore with MoneySerializer
- `lib/features/gear/models/gear_item_model.dart` - Added fromFirestore/toFirestore with camelCase fields
- `lib/features/logistics/models/sub_group_model.dart` - Added fromFirestore/toFirestore (members not inlined)
- `lib/features/activity/models/activity_log_model.dart` - Added fromFirestore/toFirestore with metadata
- `security/firestore.rules` - Added isEventParticipantForModule rule nested under events/{eventId}
- `test/unit/firestore_repository_test.dart` - 13 tests covering base class and all 5 model round-trips
- `test/unit/expense_service_test.dart` - Wave 0 stub (6 tests, all skipped)
- `test/unit/settlement_service_test.dart` - Wave 0 stub (4 tests, all skipped)
- `test/unit/gear_service_test.dart` - Wave 0 stub (5 tests, all skipped)
- `test/unit/sub_group_service_test.dart` - Wave 0 stub (4 tests, all skipped)
- `test/unit/activity_service_test.dart` - Wave 0 stub (3 tests, all skipped)
- `test/unit/document_service_test.dart` - Wave 0 stub (5 tests, all skipped)
- `test/unit/memory_service_test.dart` - Wave 0 stub (5 tests, all skipped)
- `test/unit/balance_cache_repository_test.dart` - Wave 0 stub (3 tests, all skipped)
- `test/unit/lazy_migration_service_test.dart` - Wave 0 stub (3 tests, all skipped)
- `test/unit/connectivity_provider_test.dart` - Wave 0 stub (2 tests, all skipped)

## Decisions Made

- **Expense.currency as computed getter:** The existing Expense model has no currency field. Rather than adding a required constructor parameter (breaking change), a `currency` getter defaulting to 'OMR' was added. This works for the current OMR-primary use case. Services writing expenses should pass currency when available.
- **Nested vs flat rule syntax:** Used `match /{module}/{docId}` nested inside `match /events/{eventId}` rather than a standalone `match /events/{eventId}/{module}/{docId}`. Both are valid Firestore syntax; nesting is cleaner and avoids duplication of the event path variables.
- **Members not inlined in SubGroup.fromFirestore:** SubGroup members are a separate Firestore subcollection per the architecture. `fromFirestore` returns `members: const []` and the service layer loads members separately.

## Deviations from Plan

None - plan executed exactly as written. The `currency` getter approach and nested rule syntax are implementation details within the plan's spec, not deviations from it.

## Issues Encountered

None. TDD RED/GREEN cycle completed cleanly. All 13 real tests pass, 41 stub tests skipped.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- FirestoreRepository base class ready for all module services to extend
- All 5 module models have Firestore serialization — plan 04-01 (ledger migration) can begin immediately
- Security rules deployed to `security/firestore.rules` — needs `firebase deploy --only firestore:rules` when emulator/production rules need updating
- Wave 0 stubs provide the test skeleton; plans 04-01 through 04-04 replace skip markers with real implementations

---
*Phase: 04-firestore-repository-layer*
*Completed: 2026-03-26*
