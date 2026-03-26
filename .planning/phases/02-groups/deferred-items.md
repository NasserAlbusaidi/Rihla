# Deferred Items — Phase 02-groups

## Pre-existing Failures (Out of Scope)

### happy_path_test.dart: "Happy Path: Navigate to Ledger and Add Expense"

**Status:** Pre-existing failure (confirmed by checking before Plan 02-03 changes)
**Discovered:** Plan 02-03 execution
**Symptom:** `Expected: at least one matching candidate / Actual: _TextWidgetFinder:<Found 0 widgets with text "Integration Test Trip">`
**Root cause:** Integration test expects a trip called "Integration Test Trip" on HomeScreen, but HomeScreen was replaced by the groups-first layout in Plan 02-02. The test is not compatible with the new groups-centric home screen.
**Resolution needed:** Update `test/integration/happy_path_test.dart` to work with the new groups-first HomeScreen layout. This is a separate task for a future plan.
