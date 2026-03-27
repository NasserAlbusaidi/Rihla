---
phase: 06-testing-and-coverage
plan: 04
subsystem: testing
tags: [flutter-test, sqflite, riverpod, widget-test, offline, balance-calculator]

requires:
  - phase: 06-testing-and-coverage/06-01
    provides: Green test baseline, audit findings for Plans 02-04

provides:
  - 3 offline scenario integration tests verifying SQLite side-write pipeline (D-11, D-12)
  - Balance toggle widget tests for GroupDetailScreen (TST-02)
  - GroupSettleUpScreen widget tests at canonical test/features/groups/ path
  - Extended LedgerScreen widget tests from 2 to 6 (empty state, formatting, subtitle)
  - 83 total feature tests passing, 0 failures

affects: [06-05]

tech-stack:
  added: []
  patterns:
    - "ExpenseService.withFirestore(fakeDb) + BalanceCacheRepository for offline integration tests"
    - "_wrapLedger helper with eventUnifiedLedgerProvider override for LedgerScreen tests"
    - "_wrapWithBalances helper with non-zero balance data for GroupBalanceHero/toggle tests"
    - "Participant() constructor with tripId=eventId for BalanceCalculator in integration tests"

key-files:
  created:
    - test/integration/offline_scenario_test.dart
    - test/features/groups/group_settle_up_screen_test.dart
    - .planning/phases/06-testing-and-coverage/06-04-SUMMARY.md
  modified:
    - test/features/groups/group_screens_test.dart
    - test/features/ledger_test.dart

key-decisions:
  - "BalanceCalculator.calculateBalances takes List<Participant> not Map<String,String> — used Participant constructor with tripId=eventId as sentinel"
  - "eventUnifiedLedgerProvider is Provider.family not StreamProvider.family — override returns AsyncValue.data not Stream"
  - "Event name in LedgerScreen ModuleHeader is uppercased (widget.event.name.toUpperCase()) — test asserts TEST EVENT not Test Event"
  - "test/features/groups/group_settle_up_screen_test.dart created at canonical path per plan — test/features/group_settle_up_screen_test.dart (old path) retained for backward compat"

requirements-completed: [TST-02, TST-06]

duration: 7min
completed: 2026-03-27
---

# Phase 06 Plan 04: Offline Scenario Integration Tests + Widget Tests Summary

**3 offline integration tests + expanded widget tests for 7 key screens, with balance toggle and OMR formatting verified**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-03-27T02:40:00Z
- **Completed:** 2026-03-27T02:48:00Z
- **Tasks:** 3
- **Files created:** 3 | **Files modified:** 2

## Accomplishments

### Task 1: Offline Scenario Integration Tests

Created `test/integration/offline_scenario_test.dart` with 3 scenarios per D-12:

- **Scenario 1:** Expense write via `ExpenseService.withFirestore(fakeDb).addExpense()` → cached to SQLite → read back → Decimal amount matches (25.750 OMR precision verified)
- **Scenario 2:** Expense + settlement written → both cached → `BalanceCalculator.calculateBalances()` fed from SQLite cache → net balances are zero after settlement
- **Scenario 3:** 3 expenses written → all cached → all 3 present in SQLite with correct amounts (10.000, 20.500, 5.250 OMR)

All 3 scenarios use `sqfliteFfiInit()` + `databaseFactoryFfi` for in-memory SQLite on macOS/Linux/Windows.

### Task 2: Widget Tests for GroupDetailScreen, CreateEventScreen, HomeScreen

Extended `test/features/groups/group_screens_test.dart` with balance toggle tests:

- `balance toggle: tapping GroupMemberBalanceCard changes expanded state` (TST-02 requirement)
- `balance toggle: accordion allows only one card expanded at a time`
- `GroupBalanceHero renders when totalSpent > 0 (D-19)`
- `FAB is present for creating new events`

Added `_membersWithBalances` stub (non-zero balances, totalSpent=30.000) and `_wrapWithBalances` helper so GroupBalanceHero renders during tests.

`create_event_test.dart` (7 tests) and `home_screen_groups_test.dart` (6 tests) already had sufficient coverage.

### Task 3: Widget Tests for GroupSettleUpScreen, LedgerScreen, EventCommandCenter

Created `test/features/groups/group_settle_up_screen_test.dart` (canonical path per plan) with 7 tests:
- Screen title, GROUP TOTAL PENDING label
- Settlement tile member names via RichText inspection
- OMR amounts and event count display
- All-settled state (tick circle message)
- Loading indicator
- Error state with Retry button
- Record Settlement bottom sheet

Extended `test/features/ledger_test.dart` from 2 to 6 tests:
- Empty state (0.000 balance display)
- Event name uppercase subtitle in ModuleHeader
- OMR 3 decimal places (7.500 precision)
- SPENDING label in balance header

`event_command_center_test.dart` already had 8 tests — no changes needed.

## Task Commits

1. **Task 1: Offline scenario integration tests (TST-06)** - `ca8198f` (test)
2. **Task 2: Balance toggle and GroupBalanceHero widget tests (TST-02)** - `c3fafaa` (test)
3. **Task 3: GroupSettleUpScreen + LedgerScreen widget tests (TST-02)** - `1153f0a` (test)

## Files Created/Modified

- `test/integration/offline_scenario_test.dart` - CREATED (3 SQLite side-write scenarios)
- `test/features/groups/group_screens_test.dart` - MODIFIED (4 new balance toggle tests + _membersWithBalances stub)
- `test/features/groups/group_settle_up_screen_test.dart` - CREATED (7 widget tests at canonical path)
- `test/features/ledger_test.dart` - MODIFIED (4 new tests: empty state, subtitle, formatting, SPENDING label)

## Decisions Made

- **BalanceCalculator takes List<Participant>**: The integration test initially passed `Map<String,String>` for participants but `BalanceCalculator.calculateBalances` requires `List<Participant>`. Fixed by constructing `Participant()` objects with `tripId=eventId` as sentinel value.
- **eventUnifiedLedgerProvider is a Provider.family**: Returns `AsyncValue<List<Transaction>>` directly (not a stream), so `overrideWith` returns `AsyncValue.data(...)` not `Stream.value(...)`.
- **LedgerScreen uppercases event name**: The ModuleHeader subtitle is `widget.event.name.toUpperCase()`, so the test asserts `'TEST EVENT'` not `'Test Event'`.
- **Canonical test path**: Created `test/features/groups/group_settle_up_screen_test.dart` per the plan's expected path. The existing `test/features/group_settle_up_screen_test.dart` is retained.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] BalanceCalculator requires List<Participant> not Map<String,String>**
- **Found during:** Task 1 (Scenario 2 compilation error)
- **Issue:** Test initially used `Map<String,String>` for participants but the method signature requires `List<Participant>` from `trip_model.dart`
- **Fix:** Imported `trip_model.dart` and constructed `Participant` objects with appropriate fields
- **Files modified:** `test/integration/offline_scenario_test.dart`
- **Committed in:** ca8198f (Task 1)

**2. [Rule 1 - Bug] eventUnifiedLedgerProvider is Provider not StreamProvider**
- **Found during:** Task 3 (LedgerScreen test compilation error)
- **Issue:** Test used `Stream.value()` for overriding `eventUnifiedLedgerProvider` but it's a `Provider.family` returning `AsyncValue`
- **Fix:** Changed override to `AsyncValue.data(<Transaction>[])`
- **Files modified:** `test/features/ledger_test.dart`
- **Committed in:** 1153f0a (Task 3)

**3. [Rule 1 - Bug] LedgerScreen event name is uppercased in ModuleHeader**
- **Found during:** Task 3 (test failure: found 0 widgets with text "Test Event")
- **Issue:** The screen calls `.toUpperCase()` on the event name for the subtitle
- **Fix:** Changed assertion from `'Test Event'` to `'TEST EVENT'`
- **Files modified:** `test/features/ledger_test.dart`
- **Committed in:** 1153f0a (Task 3)

---

**Total deviations:** 3 auto-fixed (all Rule 1 - Bug: type mismatch, provider type, text formatting)
**Impact on plan:** No scope changes — all were compilation/test failures caught immediately.

## Final Verification

- `flutter test test/integration/offline_scenario_test.dart`: 3 tests, 0 failures
- `flutter test test/features/`: 83 tests, 0 failures

## Known Stubs

None — all test assertions verify real behavior (no hardcoded empty responses, no placeholder data).

## Self-Check: PASSED

- FOUND: test/integration/offline_scenario_test.dart
- FOUND: test/features/groups/group_screens_test.dart (modified)
- FOUND: test/features/groups/group_settle_up_screen_test.dart
- FOUND: test/features/ledger_test.dart (modified)
- FOUND commit ca8198f (Task 1 - offline scenario tests)
- FOUND commit c3fafaa (Task 2 - balance toggle tests)
- FOUND commit 1153f0a (Task 3 - GroupSettleUpScreen + LedgerScreen tests)
- CONFIRMED: 83 feature tests pass, 0 failures
- CONFIRMED: offline_scenario_test.dart contains `sqfliteFfiInit()`, `BalanceCacheRepository`, `ExpenseService.withFirestore`, exactly 3 test() calls with 'Scenario 1', 'Scenario 2', 'Scenario 3'

---
*Phase: 06-testing-and-coverage*
*Completed: 2026-03-27*
