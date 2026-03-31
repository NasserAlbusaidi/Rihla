---
phase: 19-navigation-restructuring
plan: 03
subsystem: routing
tags: [gorouter, edit-expense, navigation, test-migration, dead-code-removal]
dependency_graph:
  requires:
    - 19-02
  provides:
    - EditExpenseScreen as GoRouter route at /edit/:expId
    - Back-navigation widget tests (5 tests)
    - Full test suite passing at 744 tests
  affects:
    - lib/features/ledger/screens/ (edit_expense_sheet.dart deleted, edit_expense_screen.dart created)
    - lib/core/router/app_router.dart
    - lib/core/utils/page_transitions.dart (deleted)
    - test/helpers/navigation_test.dart
    - Multiple test files in test/features/
tech_stack:
  added: []
  patterns:
    - "expenseId string constructor with deferred controller initialization"
    - "firstOrNull pattern for provider-loaded entity lookup"
    - "materialapp-router for screens using context.push in tests"
    - "testRouter factory for GoRouter navigation widget tests"
key_files:
  created:
    - lib/features/ledger/screens/edit_expense_screen.dart
    - test/helpers/navigation_test.dart
  modified:
    - lib/features/ledger/screens/ledger_screen.dart
    - lib/core/router/app_router.dart
    - CLAUDE.md
    - test/features/events/event_command_center_test.dart
    - test/features/events/event_module_list_test.dart
    - test/features/events/create_event_test.dart
    - test/features/events/group_detail_events_test.dart
    - test/features/groups/group_settle_up_screen_test.dart
    - test/features/group_settle_up_screen_test.dart
    - test/features/ledger_test.dart
    - test/features/gear_screen_mutations_test.dart
    - test/features/logistics_screen_mutations_test.dart
  deleted:
    - lib/core/utils/page_transitions.dart
    - test/unit/page_transitions_test.dart
decisions:
  - "EditExpenseSheet converted to EditExpenseScreen with expenseId string constructor per D-07"
  - "showModalBottomSheet removed from LedgerScreen, replaced with context.push for deep-link compatibility"
  - "page_transitions.dart deleted after confirming zero remaining imports"
  - "Test files that wrap screens using context.push now use MaterialApp.router for correct GoRouter resolution"
  - "eventDetailProvider and groupDetailProvider overrides added to all migrated screen tests"
  - "_testGroup fixtures removed from gear/logistics tests after D-14 migration made them unused"
metrics:
  duration_minutes: ~45
  completed_date: "2026-03-30"
  tasks_completed: 2
  files_created: 2
  files_modified: 13
  files_deleted: 2
  tests_total: 744
  tests_added: 5
---

# Phase 19 Plan 03: EditExpenseScreen Conversion and Test Suite Completion Summary

**One-liner:** EditExpenseSheet converted to full-page GoRouter route with expenseId string constructor, page_transitions.dart deleted, and all 12 test files updated for D-14 constructor migrations — 744 tests pass.

## What Was Built

### Task 1: EditExpenseScreen Conversion + Back-Navigation Tests

**EditExpenseSheet → EditExpenseScreen** (D-07):
- Renamed file from `edit_expense_sheet.dart` to `edit_expense_screen.dart`
- Changed constructor from `final Expense expense` to `final String expenseId`
- Added deferred controller initialization with `bool _initialized` guard:
  ```dart
  void _initializeControllers(Expense expense) {
    if (_initialized) return;
    _amountController = TextEditingController(text: ...);
    _initialized = true;
  }
  ```
- Expense loaded from `eventExpensesProvider` via `expenses.firstWhere((e) => e.id == widget.expenseId, orElse: () => null)`
- D-11 not-found state shows `EmptyStateView` with "Expense not found" message
- `context.pop()` replaces all `Navigator.pop(context, ...)` calls

**LedgerScreen updated:**
- Removed `showModalBottomSheet(...)` call and `EditExpenseSheet` import
- Added `context.push('/group/${widget.groupId}/event/${widget.eventId}/ledger/edit/${expense.id}')`

**app_router.dart wired:**
- `edit/:expId` placeholder replaced with real `EditExpenseScreen` via `CustomTransitionPage`

**Dead code deleted (D-09):**
- `lib/core/utils/page_transitions.dart` — zero remaining imports confirmed before deletion
- `test/unit/page_transitions_test.dart` — accompanying test deleted

**Back-navigation test (`test/helpers/navigation_test.dart`):**
- 5 `router.pop()` tests using `testRouter()` factory:
  1. Ledger → EventHub
  2. EventHub → GroupDetail
  3. Gear → EventHub
  4. Add Expense → Ledger
  5. Event SettleUp → Ledger
- Covers ROADMAP Success Criterion 2 (hardware back button at every route depth)

### Task 2: Test Suite Migration + CLAUDE.md

**12 test files updated for D-14 constructor migrations:**

| Test File | Changes |
|-----------|---------|
| `event_command_center_test.dart` | MaterialApp.router, eventDetailProvider + groupDetailProvider overrides |
| `event_module_list_test.dart` | EventModuleList(groupId:, eventId:, modules:) |
| `create_event_test.dart` | GoRouter + MaterialApp.router for context.push navigation test |
| `group_detail_events_test.dart` | _makeRouter() factory, groupBalancesProvider + groupActivityProvider overrides, navigation stub verification |
| `groups/group_settle_up_screen_test.dart` | Removed group: param, added groupDetailProvider override |
| `group_settle_up_screen_test.dart` (old) | Same: removed group: param, added groupDetailProvider override |
| `ledger_test.dart` | Added eventDetailProvider override, LedgerScreen(groupId:, eventId:) constructor |
| `gear_screen_mutations_test.dart` | GearScreen(groupId:, eventId:) + eventDetailProvider override, removed unused _testGroup |
| `logistics_screen_mutations_test.dart` | LogisticsScreen(groupId:, eventId:) + eventDetailProvider override, removed unused _testGroup |

**CLAUDE.md updated (D-12):**
- "Routing: Mixed" section renamed to "Routing: GoRouter (Declarative)"
- Full route tree documented including `/group/:gid/event/:eid/ledger/edit/:expId`
- Page Transitions section updated: AppPageRoute/AppBottomSheetRoute references removed, CustomTransitionPage documented as the replacement

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed set mutation immutability in EditExpenseScreen**
- **Found during:** Task 1 (during implementation)
- **Issue:** Original code used `_customSplitParticipants.add(p.id)` — mutating a Set in place
- **Fix:** Changed to `_customSplitParticipants = {..._customSplitParticipants, p.id}` (immutable spread)
- **Files modified:** `lib/features/ledger/screens/edit_expense_screen.dart`

**2. [Rule 2 - Missing functionality] Added eventDetailProvider/groupDetailProvider overrides to tests outside the plan's listed files**
- **Found during:** Task 2 (running test suite revealed failures in files not listed in the plan)
- **Issue:** `group_detail_events_test.dart`, `gear_screen_mutations_test.dart`, and `logistics_screen_mutations_test.dart` were not in the plan's files list but failed due to D-14 constructor migrations in Plan 02
- **Fix:** Applied same migration pattern (eventDetailProvider override, string ID constructor) to all three
- **Files modified:** `test/features/events/group_detail_events_test.dart`, `test/features/gear_screen_mutations_test.dart`, `test/features/logistics_screen_mutations_test.dart`
- **Commit:** 8c8c758

**3. [Rule 1 - Bug] Removed unnecessary_import lint warning in edit_expense_screen.dart**
- **Found during:** Task 1 analyze run
- **Issue:** `event_ref.dart` was imported redundantly — `EventRef` is re-exported by `expense_provider.dart`
- **Fix:** Removed redundant import
- **Files modified:** `lib/features/ledger/screens/edit_expense_screen.dart`

## Verification Results

All plan success criteria met:

- `flutter test` — 744 tests, 0 failures
- `flutter test test/helpers/navigation_test.dart` — 5 pop-navigation tests pass
- `grep -rn 'page_transitions' lib/ test/` — zero results
- `grep -rn 'AppPageRoute\|AppBottomSheetRoute' lib/ test/` — zero results
- `grep -rn 'Navigator.push\|showModalBottomSheet' lib/features/ledger/` — zero results
- CLAUDE.md contains `/group/:gid/event/:eid/ledger/edit/:expId`
- CLAUDE.md contains `GoRouter (Declarative)` and `CustomTransitionPage`

## Commits

| Hash | Message |
|------|---------|
| `2ba0031` | feat(19-03): convert EditExpenseSheet to EditExpenseScreen GoRouter route, delete page_transitions.dart, add back-nav tests |
| `97e1257` | feat(19-03): update test files for constructor migrations and update CLAUDE.md navigation docs |
| `8c8c758` | fix(19-03): migrate gear and logistics test files to D-14 string ID constructors |

## Known Stubs

None — all routes in the route tree are wired to real screens or labeled placeholder screens. EditExpenseScreen loads from Firestore via `eventExpensesProvider` and shows a not-found state when the expense is absent.

## Self-Check: PASSED

Files verified:
- `lib/features/ledger/screens/edit_expense_screen.dart` — exists
- `test/helpers/navigation_test.dart` — exists
- `lib/core/utils/page_transitions.dart` — correctly absent
- `test/unit/page_transitions_test.dart` — correctly absent

Commits verified:
- `2ba0031` — found in git log
- `97e1257` — found in git log
- `8c8c758` — found in git log

Test suite: 744 tests, 0 failures confirmed.
