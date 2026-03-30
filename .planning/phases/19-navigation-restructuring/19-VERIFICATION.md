---
phase: 19-navigation-restructuring
verified: 2026-03-30T14:00:00Z
status: human_needed
score: 6/6 must-haves verified
gaps: []
human_verification:
  - test: "Navigate from a group detail screen through event hub -> ledger -> tap an expense to edit"
    expected: "EditExpenseScreen slides in as a full-page route (not a bottom sheet), shows expense data, ModuleHeader back button returns to ledger"
    why_human: "Requires a running app with real Firestore data to verify the full navigation stack and that the edit screen loads expense data from the provider"
  - test: "Press hardware back button at each route depth: ledger/add -> ledger -> event hub -> group detail -> home"
    expected: "Each back press returns to the correct parent route with no stack anomalies"
    why_human: "Automated navigation_test.dart covers this with testRouter stubs; confirming the same behavior with real screen rendering requires device/emulator"
---

# Phase 19: Navigation Restructuring Verification Report

**Phase Goal:** Migrate all Navigator.push calls to GoRouter declarative routing, restructure screen constructors to accept string IDs, verify hardware back button navigation, delete dead code, and update documentation.
**Verified:** 2026-03-30T14:00:00Z
**Status:** human_needed (6/6 must-haves verified, 2 items need device testing)
**Re-verification:** Gap resolved — edit_expense_sheet.dart deleted in commit 48d4277

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | GoRouter route tree contains all 15 new subroutes matching D-02 + /ledger/settle-up per D-07 | VERIFIED | `app_router.dart` has 23 AppRoutes constants; nested tree contains settle-up, activity, create-event, create-event/:type, event/:eid, ledger, ledger/add, ledger/edit/:expId, ledger/settle-up, gear, logistics, vault, memories, memories/:memId, event/activity |
| 2 | All screen constructors use string IDs (groupId/eventId) not Event/Group objects | VERIFIED | Verified in EventCommandCenter, EventModuleList, LedgerScreen, SettleUpScreen, GearScreen, LogisticsScreen, VaultScreen, MemoriesScreen, GroupSettleUpScreen — all take `final String groupId` / `final String eventId` |
| 3 | All Navigator.push calls replaced with context.push/context.go | VERIFIED | `grep -rn "Navigator.of(context).push"` across lib returns ONLY memories_screen.dart:442 (FullScreenPhoto overlay, permitted exception documented in comments) |
| 4 | Hardware back button navigation verified by automated widget test | VERIFIED | `test/helpers/navigation_test.dart` — 5 router.pop() tests all pass (ledger->EventHub, EventHub->GroupDetail, gear->EventHub, add->ledger, settle-up->ledger) |
| 5 | EditExpenseSheet renamed to EditExpenseScreen and navigated via GoRouter route | PARTIAL | `edit_expense_screen.dart` exists with `class EditExpenseScreen` and `final String expenseId`. Router wires it. But `edit_expense_sheet.dart` (735 lines, old class) was NOT deleted — dead code remains |
| 6 | page_transitions.dart and CLAUDE.md updated, tests pass | VERIFIED | `page_transitions.dart` deleted, `page_transitions_test.dart` deleted, zero `page_transitions` references in lib/test, CLAUDE.md shows "Routing: GoRouter (Declarative)" with full route tree, 122 tests pass across key suites |

**Score:** 5/6 truths verified (1 partial)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/core/router/app_router.dart` | Expanded GoRouter with ~15 new nested GoRoute entries | VERIFIED | 23 AppRoutes constants, full nested tree with real screens, `_slideRightTransition` helper, `:gid` parameter naming |
| `lib/shared/widgets/module_header.dart` | GoRouter-compatible back button using context.pop() | VERIFIED | Line 52: `_LightBackButton(onTap: () => context.pop())`, line 107: `_DarkBackButton(onTap: () => context.pop())`. No Navigator.of(context).pop() remains |
| `test/helpers/test_router.dart` | Shared testRouter() factory for navigation tests | VERIFIED | `GoRouter testRouter(` at line 20, includes `/group/:gid`, `event/:eid`, `ledger`, `settle-up` under both group and ledger |
| `lib/features/events/screens/event_command_center.dart` | EventCommandCenter with groupId/eventId string params | VERIFIED | `final String groupId` at line 25, `final String eventId` at line 26, watches `eventDetailProvider` and `groupDetailProvider`, D-11 not-found state present |
| `lib/features/events/widgets/event_module_list.dart` | EventModuleList with context.push + EventModules? modules param | VERIFIED | `final EventModules? modules` at line 33, all 5 _open* methods use `context.push` |
| `lib/features/ledger/screens/ledger_screen.dart` | LedgerScreen with string IDs, settle-up via context.push | VERIFIED | String ID constructor, `context.push` at lines 49, 409, 414 — no showModalBottomSheet for edit |
| `lib/features/ledger/screens/settle_up_screen.dart` | SettleUpScreen as GoRouter route with string IDs | VERIFIED | `final String groupId` and `final String eventId`, wired in router at `/group/:gid/event/:eid/ledger/settle-up` |
| `lib/features/groups/screens/group_settle_up_screen.dart` | GroupSettleUpScreen without Group object | VERIFIED | No `final Group group`, `final String groupId` at line 30, watches `groupDetailProvider` at line 90 |
| `lib/features/ledger/screens/edit_expense_screen.dart` | EditExpenseScreen as GoRouter route with expenseId string | VERIFIED | `class EditExpenseScreen` at line 27, `final String expenseId` at line 30 |
| `lib/features/ledger/screens/edit_expense_sheet.dart` | Should be DELETED (dead code) | FAILED | Still exists — 735 lines, `class EditExpenseSheet`, `final Expense expense`. No active imports found. Dead code but not removed |
| `lib/core/utils/page_transitions.dart` | Deleted | VERIFIED | File does not exist |
| `test/helpers/navigation_test.dart` | Widget test with 5 pop navigation tests | VERIFIED | 5 router.pop() tests, all pass |
| `CLAUDE.md` | Updated navigation flow with full GoRouter route tree | VERIFIED | "Routing: GoRouter (Declarative)" at line 60, full route tree including `/group/:gid/event/:eid/ledger/edit/:expId`, no AppPageRoute/AppBottomSheetRoute in routing section |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `app_router.dart` | `go_router` | `routes: [` | WIRED | Nested GoRoute structure confirmed |
| `module_header.dart` | `go_router` | `context.pop()` | WIRED | `import 'package:go_router/go_router.dart'` present, `context.pop()` at both back buttons |
| `event_command_center.dart` | `eventDetailProvider` | `ref.watch(eventDetailProvider(` | WIRED | Line 37 — provider watch confirmed |
| `group_detail_screen.dart` | `/group/:gid/event/:eid` | `context.push` | WIRED | `context.push('/group/$groupId/event/${events[i].id}')` at line 401 |
| `create_event_screen.dart` | `/group/:gid/event/:eid` | `context.go` | WIRED | `context.go('/group/${widget.groupId}/event/${event.id}')` at line 121 |
| `ledger_screen.dart` | `/group/:gid/event/:eid/ledger/settle-up` | `context.push` | WIRED | `context.push` at lines 49/409/414 |
| `ledger_screen.dart` | `/group/:gid/event/:eid/ledger/edit/:expId` | `context.push` | WIRED | `context.push('/group/${widget.groupId}/event/${widget.eventId}/ledger/edit/${expense.id}')` |
| `app_router.dart` | `EditExpenseScreen` | GoRoute pageBuilder | WIRED | `EditExpenseScreen(groupId: ..., eventId: ..., expenseId: ...)` in `edit/:expId` route |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| `event_command_center.dart` | `eventAsync`/`event` | `ref.watch(eventDetailProvider(...))` | Yes — Firestore StreamProvider.family | FLOWING |
| `group_settle_up_screen.dart` | `groupAsync`/`group` | `ref.watch(groupDetailProvider(...))` | Yes — Firestore StreamProvider.family | FLOWING |
| `edit_expense_screen.dart` | `expense` | `eventExpensesProvider` via `firstWhere` | Yes — Firestore-backed provider | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Back navigation: ledger -> EventHub | `flutter test test/helpers/navigation_test.dart` | `+1: pop from ledger returns to EventHub` | PASS |
| Back navigation: EventHub -> GroupDetail | `flutter test test/helpers/navigation_test.dart` | `+2: pop from EventHub returns to GroupDetail` | PASS |
| Back navigation: gear -> EventHub | `flutter test test/helpers/navigation_test.dart` | `+3: pop from gear returns to EventHub` | PASS |
| Back navigation: add expense -> ledger | `flutter test test/helpers/navigation_test.dart` | `+4: pop from add expense returns to ledger` | PASS |
| Back navigation: settle-up -> ledger | `flutter test test/helpers/navigation_test.dart` | `+5: pop from event settle-up returns to ledger` | PASS |
| Key test suites pass | `flutter test test/features/events/ test/features/groups/ test/features/ledger/ test/helpers/` | `122 tests, 0 failures` | PASS |

All 5 behavioral spot-checks pass.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| NAV-03 | 19-01, 19-02, 19-03 | All event-level screens are accessible via GoRouter subroutes, replacing Navigator.push with context.push | SATISFIED | All screens verified in router with real constructors; Navigator.push replaced with context.push/go across all 13 migrated files |

No orphaned requirements — NAV-03 is the only requirement declared across all three plans, and it is the only requirement assigned to Phase 19 in REQUIREMENTS.md.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/features/ledger/screens/edit_expense_sheet.dart` | 1-735 | Old class not deleted — dead code (no imports) | Warning | No runtime impact (not imported), but clutters codebase and contradicts Plan 03 acceptance criteria |
| `lib/core/router/app_router.dart` | 363-393 | Two placeholder Scaffold routes: `MemoryDetail` and `EventActivity` | Info | Documented in summaries and CLAUDE.md as deferred. Does not block any active navigation path |

### Human Verification Required

#### 1. Edit Expense Full Navigation Stack

**Test:** From a real event with expenses, tap an expense row in the ledger screen.
**Expected:** EditExpenseScreen slides in as a full-page route (not a bottom sheet), displays the expense data, and ModuleHeader back button returns to the ledger screen.
**Why human:** Requires running app with real Firestore data; the provider lookup (`eventExpensesProvider` + `firstWhere`) and deferred controller initialization pattern cannot be fully exercised with mocked data in a widget test.

#### 2. Hardware Back Button on Android

**Test:** Navigate deep into the route tree (e.g., home -> group detail -> event hub -> ledger -> add expense), then use the Android hardware back button at each level.
**Expected:** Each back press returns to the correct parent route matching the GoRouter tree, with no double-pops or navigation anomalies.
**Why human:** The `router.pop()` tests in navigation_test.dart verify GoRouter's own stack, but Android hardware back gestures go through the OS back-press handler, which requires a physical device or emulator to confirm.

### Gaps Summary

**One gap found:** `lib/features/ledger/screens/edit_expense_sheet.dart` was not deleted.

The Plan 03 acceptance criteria explicitly stated: "File lib/features/ledger/screens/edit_expense_sheet.dart does NOT exist (deleted)." The file is 735 lines of the old `EditExpenseSheet` class with `final Expense expense` constructor. It has zero active imports across the entire codebase — the only reference is a key constant name in `lib/features/ledger/keys/ledger_keys.dart` which contains `static const editExpenseSheet = Key(...)` (a string key, not a class import). The new `EditExpenseScreen` is correctly implemented and wired. This is a cleanup miss, not a functional regression.

**Scope note on two remaining placeholder routes:** The `event/:eid/activity` and `memories/:memId` routes remain as placeholder Scaffolds in `app_router.dart`. These are explicitly documented in the Plan 02 SUMMARY as "deferred to Plan 03" (activity) and "no MemoryDetailScreen yet" (memId). The phase goal did not require these screens to be real — they were out-of-scope per the plans. The CLAUDE.md documents them as "placeholder" routes. These do not constitute gaps against NAV-03.

---

_Verified: 2026-03-30T14:00:00Z_
_Verifier: Claude (gsd-verifier)_
