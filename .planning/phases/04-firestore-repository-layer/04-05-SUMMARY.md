---
phase: 04-firestore-repository-layer
plan: "05"
subsystem: database
tags: [bridge-teardown, eventref-migration, screen-migration, supabase-removal]

# Dependency graph
requires:
  - phase: 04-04
    provides: All 7 module services on Firestore, BalanceCacheRepository, no SyncService

provides:
  - EventModel without bridgeTripId or Supabase bridge fields
  - EventService without Supabase bridge code (D-17 removed)
  - All screens use EventRef-based providers instead of tripId-based providers
  - Deprecated tripXxxProvider shims fully removed (tripExpensesProvider, tripSettlementsProvider, tripBalancesProvider, tripSubGroupsProvider, tripActivityProvider, tripTransactionActivityProvider, tripDocumentsProvider, tripUnifiedLedgerProvider)
  - Dead home/trip widgets deleted (CommandCenter, expense_summary_hero, module_list, preparation_hero, trip_header, trip_recap_card)
  - Stale trip-based test files removed (command_center_test.dart, happy_path_test.dart)

affects:
  - Phase 05+ (clean Firestore-only codebase, no backward-compatibility shims)

# Tech tracking
tech-stack:
  added: []
  removed: []
  upgraded: []

key-decisions:
  - "Removed tripBalancesProvider entirely — its only consumers (command_center_test, happy_path_test) were testing the deleted Trip-based CommandCenter widget"
  - "Kept trip_model.dart imports where Participant/UserBalance types are still used in provider calculations (not yet migrated to Event-centric model)"
  - "expense_provider.dart re-exports event_ref.dart so screens get EventRef transitively without redundant imports"

requirements-completed: [MIG-01, MIG-02]

# Execution tracking
started: "2026-03-26T18:20:00Z"
completed: "2026-03-26T19:24:13Z"

tasks:
  total: 3
  completed: 3

commits:
  - hash: 91b6781
    message: "feat(04-05): remove D-17 bridge from EventModel and EventService"
  - hash: ecbdee0
    message: "feat(04-05): migrate all screens from tripId/Trip to EventRef/Event providers"
  - hash: 07b2d16
    message: "test(04-05): update tests to remove bridgeTripId and use Firestore providers"
  - hash: 603113d
    message: "fix(04-05): replace tripSubGroupsProvider with eventSubGroupsProvider in add/edit screens"
  - hash: fd1e6a3
    message: "chore(04-05): delete dead home/trip widget files"
  - hash: 941c739
    message: "chore(04-05): remove deprecated provider shims (tripXxxProvider)"
  - hash: 1da81cb
    message: "chore(04-05): clean up redundant event_ref.dart imports in screens"
  - hash: 44495fa
    message: "chore(04-05): delete stale test files for removed Trip-based widgets"

key-files:
  created:
    - lib/features/events/screens/event_expense_hero.dart
  modified:
    - lib/features/events/models/event_model.dart
    - lib/features/events/services/event_service.dart
    - lib/features/events/screens/event_command_center.dart
    - lib/features/events/widgets/event_card.dart
    - lib/features/events/widgets/event_module_list.dart
    - lib/features/ledger/providers/expense_provider.dart
    - lib/features/ledger/providers/ledger_provider.dart
    - lib/features/ledger/screens/ledger_screen.dart
    - lib/features/ledger/screens/add_expense_screen.dart
    - lib/features/ledger/screens/settle_up_screen.dart
    - lib/features/ledger/screens/edit_expense_sheet.dart
    - lib/features/logistics/providers/sub_group_provider.dart
    - lib/features/logistics/screens/logistics_screen.dart
    - lib/features/activity/services/activity_service.dart
    - lib/features/activity/screens/activity_feed_screen.dart
    - lib/features/memories/screens/memories_screen.dart
    - lib/features/vault/providers/document_provider.dart
  deleted:
    - lib/features/home/screens/command_center.dart
    - lib/features/home/widgets/expense_summary_hero.dart
    - lib/features/home/widgets/module_list.dart
    - lib/features/home/widgets/preparation_hero.dart
    - lib/features/home/widgets/trip_header.dart
    - lib/features/home/widgets/trip_recap_card.dart
    - test/features/command_center_test.dart
    - test/integration/happy_path_test.dart

deviations:
  - type: "Rule 3 - Blocking"
    description: "Staged file deletions not yet committed in stalled worktree — committed as first recovery step"
  - type: "Rule 1 - Bug"
    description: "command_center_test.dart imported deleted widget and stale providers — deleted"
  - type: "Rule 1 - Bug"
    description: "happy_path_test.dart tested deleted Trip-based navigation flow — deleted"
---

# Plan 04-05 Summary: Bridge Teardown & Screen Migration

**Supabase bridge pattern fully removed from EventModel/EventService and all 8 deprecated tripId-based provider shims deleted — codebase is now Firestore-only for all module data access**

## Performance

- **Duration:** ~65 min (including worktree recovery)
- **Started:** 2026-03-26T18:20:00Z
- **Completed:** 2026-03-26T19:24:13Z
- **Tasks:** 3 completed
- **Commits:** 8
- **Files modified/deleted:** 25

## Accomplishments
- Removed `bridgeTripId` field, `_createBridgeTrip()`, and `_generateBridgeCode()` from EventModel and EventService (D-17 complete)
- Migrated EventCommandCenter, EventCard, EventModuleList from Trip facade to EventRef-based providers
- Removed 8 deprecated `tripXxxProvider` shims across expense, ledger, sub-group, activity, and document providers
- Deleted 6 dead Trip-era home widget files and 2 stale test files

## Task Commits

1. **Task 1: EventModel bridge removal + EventService simplification** - `91b6781` (feat)
2. **Task 2: EventCommandCenter + EventCard + EventModuleList screen updates** - `ecbdee0` (feat)
3. **Task 3: Module screens to EventRef + deprecated shim removal** - `603113d` (fix) + `fd1e6a3`, `941c739`, `1da81cb`, `44495fa` (chore)

## Files Modified/Deleted
- `lib/features/events/models/event_model.dart` - bridgeTripId field removed
- `lib/features/events/services/event_service.dart` - _createBridgeTrip, _generateBridgeCode, all Supabase imports removed
- `lib/features/events/screens/event_command_center.dart` - uses Event+Group directly, no Trip facade
- `lib/features/events/widgets/event_card.dart` - uses eventExpensesProvider(EventRef)
- `lib/features/events/widgets/event_module_list.dart` - uses EventRef providers throughout
- `lib/features/ledger/providers/expense_provider.dart` - tripExpensesProvider, tripSettlementsProvider, tripBalancesProvider removed
- `lib/features/ledger/providers/ledger_provider.dart` - tripUnifiedLedgerProvider removed
- `lib/features/ledger/screens/ledger_screen.dart` - accepts Event+Group, uses eventXxxProvider
- `lib/features/ledger/screens/add_expense_screen.dart` - accepts groupId+eventId (no tripId)
- `lib/features/ledger/screens/settle_up_screen.dart` - accepts Event+Group, uses EventRef providers
- `lib/features/ledger/screens/edit_expense_sheet.dart` - accepts groupId+eventId, uses EventRef
- `lib/features/logistics/providers/sub_group_provider.dart` - tripSubGroupsProvider, subGroupsByTypeProvider removed
- `lib/features/activity/services/activity_service.dart` - tripActivityProvider, tripTransactionActivityProvider removed
- `lib/features/vault/providers/document_provider.dart` - tripDocumentsProvider removed
- Deleted: 6 home/trip widget files + 2 stale test files (8 files, ~2,231 lines)

## Decisions Made
- Removed `tripBalancesProvider` entirely rather than migrating it — its only consumers were tests for the deleted Trip-based CommandCenter widget
- Deleted command_center_test.dart and happy_path_test.dart as both tested Trip-era flows with stale providers; groups-first tests already exist in home_screen_groups_test.dart
- Kept `trip_model.dart` imports where `Participant`/`UserBalance` types are still used in provider calculations (out of scope to migrate these types in this plan)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Stalled worktree had staged file deletions never committed**
- **Found during:** Recovery/startup
- **Issue:** 6 dead home/trip widget files were staged but the agent stalled before committing
- **Fix:** Committed the staged deletions as the first action
- **Committed in:** fd1e6a3

**2. [Rule 1 - Bug] command_center_test.dart tested deleted CommandCenter widget**
- **Found during:** Task 3 (deprecated shim removal)
- **Issue:** Test imported `lib/features/home/screens/command_center.dart` (deleted) and overrode providers being removed (tripBalancesProvider, tripActivityProvider)
- **Fix:** Deleted the test file. EventCommandCenter is tested in test/features/events/event_command_center_test.dart
- **Committed in:** 44495fa

**3. [Rule 1 - Bug] happy_path_test.dart tested stale Trip-based navigation flow**
- **Found during:** Task 3
- **Issue:** Integration test relied on userTripsProvider, old CommandCenter navigation, and 8 deprecated provider overrides
- **Fix:** Deleted the test file. Groups-first home screen is tested in test/features/home/home_screen_groups_test.dart
- **Committed in:** 44495fa

---

**Total deviations:** 3 auto-fixed (1 blocking, 2 bug)
**Impact on plan:** All fixes required for plan completion. Removing tests for deleted widgets is not test coverage loss.

## Issues Encountered
- 4 pre-existing test failures in group_service_test.dart and group_join_test.dart (Firebase not initialized in unit test environment) — confirmed pre-existing by git stash verification, not caused by this plan.

## Known Stubs
None — all EventRef providers are wired to live Firestore services.

## Next Phase Readiness
- Phase 04 complete: Firestore repository layer in place, D-17 bridge removed, zero deprecated shims
- Phase 05 can build on a clean Firestore-only codebase
- `Participant`/`UserBalance` types still reference `trip_model.dart` — a future phase can migrate these if needed

## Self-Check: PASSED
- All 8 plan commits exist in git log
- flutter analyze reports 0 errors (133 warnings/infos, all pre-existing)
- grep confirms 0 matches for all deprecated patterns in lib/

---
*Phase: 04-firestore-repository-layer*
*Completed: 2026-03-26*
