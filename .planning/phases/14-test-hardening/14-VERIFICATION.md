---
phase: 14-test-hardening
verified: 2026-03-28T12:00:00Z
status: gaps_found
score: 3/4 success criteria verified
re_verification: false
gaps:
  - truth: "Renaming any UI label causes zero test failures outside content tests"
    status: failed
    reason: "At least 7 test files still use structural find.text() for UI labels that would break if those labels were renamed. The rename-resilience verification in Plan 03 was run but only covered the 'Ledger→Treasury' rename via event_module_list.dart, which happened to be already migrated. Structural assertions remain for: 'Your Groups', 'SPENDING', 'PAID BY', 'DELETE', 'Settle', 'Settled', 'Group Activity', 'No groups yet', 'Create a Group', 'Join a Group'."
    artifacts:
      - path: "test/features/home/home_screen_groups_test.dart"
        issue: "Still uses find.text('Your Groups'), find.text('No groups yet'), find.text('Create a Group'), find.text('Join a Group'), find.byType(FloatingActionButton) — none converted to find.byKey(HomeKeys.*)"
      - path: "test/features/ledger_test.dart"
        issue: "Still uses find.text('SPENDING') — claimed converted in Plan 03 but LedgerKeys.spendingLabel never added and widget not keyed"
      - path: "test/features/ledger/payer_currency_rewiring_test.dart"
        issue: "Still uses find.text('PAID BY') × 4 — claimed converted in Plan 03 but LedgerKeys.payerSectionLabel never added"
      - path: "test/features/gear_screen_mutations_test.dart"
        issue: "Still uses find.text('DELETE') — claimed converted in Plan 03 but GearKeys.deleteConfirmButton never added"
      - path: "test/features/groups/group_activity_screen_test.dart"
        issue: "Still uses find.text('Group Activity') — claimed converted in Plan 03 but GroupKeys.activityScreenTitle never added"
      - path: "test/features/group_balance_card_test.dart"
        issue: "Still uses find.text('Settle') × 3 and find.text('Settled') × 1 — claimed converted in Plan 03 but GroupKeys.settleButton/settledBadge never added"
      - path: "test/unit/empty_state_view_test.dart"
        issue: "Still uses find.byType(ElevatedButton) for CTA button taps — claimed converted in Plan 03 but SharedKeys.emptyStateCtaButton not wired"
    missing:
      - "Add LedgerKeys.spendingLabel and LedgerKeys.payerSectionLabel to lib/features/ledger/keys/ledger_keys.dart"
      - "Add key: LedgerKeys.spendingLabel to 'SPENDING' Text in lib/features/ledger/widgets/spending_summary_section.dart"
      - "Add key: LedgerKeys.payerSectionLabel to 'PAID BY' Text in lib/features/ledger/widgets/split_scope_selector.dart"
      - "Add GearKeys.deleteConfirmButton to lib/features/gear/keys/gear_keys.dart"
      - "Add key: GearKeys.deleteConfirmButton to DELETE TextButton in lib/features/gear/screens/gear_screen.dart"
      - "Add HomeKeys.yourGroupsHeader to lib/features/home/keys/home_keys.dart"
      - "Add key: HomeKeys.yourGroupsHeader to 'Your Groups' Text in lib/features/home/screens/home_screen.dart"
      - "Add GroupKeys.settleButton and GroupKeys.settledBadge to lib/features/groups/keys/group_keys.dart"
      - "Add key: GroupKeys.settleButton to Settle TextButton and key: GroupKeys.settledBadge to Settled Container in lib/features/groups/widgets/group_member_balance_card.dart"
      - "Add GroupKeys.activityScreenTitle and GroupKeys.activityBackButton to lib/features/groups/keys/group_keys.dart"
      - "Add key: GroupKeys.activityScreenTitle to 'Group Activity' Text and key: GroupKeys.activityBackButton to back IconButton in lib/features/groups/screens/group_activity_screen.dart"
      - "Migrate find.text('SPENDING') in test/features/ledger_test.dart to find.byKey(LedgerKeys.spendingLabel)"
      - "Migrate find.text('PAID BY') × 4 in test/features/ledger/payer_currency_rewiring_test.dart to find.byKey(LedgerKeys.payerSectionLabel)"
      - "Migrate find.text('DELETE') in test/features/gear_screen_mutations_test.dart to find.byKey(GearKeys.deleteConfirmButton)"
      - "Migrate find.text('Your Groups'), find.text('No groups yet'), find.text('Create a Group'), find.text('Join a Group'), find.byType(FloatingActionButton) in test/features/home/home_screen_groups_test.dart to find.byKey(HomeKeys.*)"
      - "Migrate find.text('Settle') and find.text('Settled') in test/features/group_balance_card_test.dart to find.byKey(GroupKeys.settleButton) and find.byKey(GroupKeys.settledBadge)"
      - "Migrate find.text('Group Activity') in test/features/groups/group_activity_screen_test.dart to find.byKey(GroupKeys.activityScreenTitle)"
      - "Migrate find.byType(ElevatedButton) CTA taps in test/unit/empty_state_view_test.dart to find.byKey(SharedKeys.emptyStateCtaButton)"
  - truth: "CI pipeline warns when find.text() count exceeds baseline"
    status: failed
    reason: "The find.text() regression warning step is absent from .github/workflows/release_android.yml. Plan 03 claimed commit dbc0f18 added it, but the actual workflow file has no such step — it goes directly from 'Run Tests with Coverage' to 'Install lcov'."
    artifacts:
      - path: ".github/workflows/release_android.yml"
        issue: "No 'find.text() regression warning' step exists. The step between 'Run Tests with Coverage' and 'Install lcov' is missing entirely."
    missing:
      - "Add the find.text() regression warning step to .github/workflows/release_android.yml after 'Run Tests with Coverage' with BASELINE=135 and ::warning:: (non-blocking)"
human_verification:
  - test: "Verify rename resilience end-to-end after gap closure"
    expected: "Renaming 'SPENDING' to 'EXPENSES', 'PAID BY' to 'PAYER', 'Settle' to 'Pay', 'Your Groups' to 'My Groups' should each cause zero test failures after all structural conversions are done"
    why_human: "Requires manually running rename-and-test protocol across multiple files to confirm full isolation"
---

# Phase 14: Test Hardening Verification Report

**Phase Goal:** The existing test suite can survive any label rename or visual structural change without cascade failures
**Verified:** 2026-03-28T12:00:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Every interactive widget and structural landmark has a semantic Key | VERIFIED | 12 key class files exist with `abstract final class` pattern. All 22 screens have screen-level keys on root Scaffold. 71 `key:` assignments found across lib. |
| 2 | All structural navigation assertions use find.byKey() | PARTIAL | 104 find.byKey() calls exist. 12 high/medium-priority test files migrated (Plans 01-02). 7 low-priority test files claimed in Plan 03 but structural assertions remain. |
| 3 | Renaming any UI label causes zero test failures outside content tests | FAILED | find.text('SPENDING'), find.text('PAID BY'), find.text('DELETE'), find.text('Settle'), find.text('Settled'), find.text('Your Groups'), find.text('No groups yet'), find.text('Create a Group'), find.text('Join a Group'), find.text('Group Activity') are structural assertions that would break on rename. Plan 03 claimed these were converted but the actual test files were not modified. |
| 4 | Full test suite (624 tests) passes without modification after Keys are added | VERIFIED | `flutter test` exits 0: "624 tests passed". |

**Score:** 2/4 truths fully verified (truths 1 and 4). Truth 2 partially verified. Truth 3 failed.

Note on CI criterion: Plan 03 also included a fifth deliverable — the CI regression warning step — which is absent from the actual workflow file, making it a separate gap.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/core/keys/shared_keys.dart` | SharedKeys class with shared widget keys | VERIFIED | Contains `abstract final class SharedKeys` with 9 constants + 2 parameterized keys |
| `lib/features/events/keys/event_keys.dart` | EventKeys class | VERIFIED | Contains `abstract final class EventKeys` with screen, module card, action, and parameterized keys |
| `lib/features/groups/keys/group_keys.dart` | GroupKeys class | VERIFIED (partial) | Has 27 constants. Missing: `settledBadge`, `settleButton`, `activityScreenTitle`, `activityBackButton` claimed in Plan 03 |
| `lib/features/home/keys/home_keys.dart` | HomeKeys class | VERIFIED (partial) | Has 4 constants. Missing: `yourGroupsHeader` claimed in Plan 03 |
| `lib/features/ledger/keys/ledger_keys.dart` | LedgerKeys class | PARTIAL | Only has 4 screen keys. Missing: `spendingLabel`, `payerSectionLabel` claimed in Plan 03 |
| `lib/features/gear/keys/gear_keys.dart` | GearKeys class | PARTIAL | Only has `screen`, `addButton`, `gearItem(id)`. Missing: `deleteConfirmButton` claimed in Plan 03 |
| `lib/features/logistics/keys/logistics_keys.dart` | LogisticsKeys class | VERIFIED | Contains screen key, action buttons, parameterized subgroup key |
| `lib/features/memories/keys/memories_keys.dart` | MemoriesKeys class | VERIFIED | Contains screen key |
| `lib/features/onboarding/keys/onboarding_keys.dart` | OnboardingKeys class | VERIFIED | Contains screen key |
| `lib/features/settings/keys/settings_keys.dart` | SettingsKeys class | VERIFIED | Contains screen key |
| `lib/features/vault/keys/vault_keys.dart` | VaultKeys class | VERIFIED | Contains screen key |
| `lib/features/activity/keys/activity_keys.dart` | ActivityKeys class | VERIFIED | Contains screen key |
| `.github/workflows/release_android.yml` | find.text() regression warning step | MISSING | No such step exists in the workflow file. File ends at 'Install lcov' step after 'Run Tests with Coverage'. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `test/unit/widget_coverage_test.dart` | `lib/core/keys/shared_keys.dart` | `find.byKey(SharedKeys.*)` | WIRED | 11 find.byKey(SharedKeys.*) calls present |
| `test/features/events/event_command_center_test.dart` | `lib/features/events/keys/event_keys.dart` | `find.byKey(EventKeys.*)` | WIRED | 44 find.byKey(EventKeys.*) calls present |
| `test/features/groups/create_join_group_test.dart` | `lib/features/groups/keys/group_keys.dart` | `find.byKey(GroupKeys.*)` | NOT WIRED | Zero find.byKey(GroupKeys.*) calls. SUMMARY noted this as "zero structural conversions needed" — correct per analysis |
| `test/features/groups/group_screens_test.dart` | `lib/features/groups/keys/group_keys.dart` | `find.byKey(GroupKeys.*)` | WIRED | Multiple GroupKeys calls verified |
| `test/features/logistics_screen_mutations_test.dart` | `lib/features/logistics/keys/logistics_keys.dart` | `find.byKey(LogisticsKeys.*)` | WIRED | 10 find.byKey(LogisticsKeys.*) calls present |
| `.github/workflows/release_android.yml` | `test/` | grep count baseline comparison | NOT WIRED | BASELINE= step absent from workflow |
| `test/features/home/home_screen_groups_test.dart` | `lib/features/home/keys/home_keys.dart` | `find.byKey(HomeKeys.*)` | NOT WIRED | Zero byKey calls. find.text('Your Groups') etc. remain structural |
| `test/features/ledger_test.dart` | `lib/features/ledger/keys/ledger_keys.dart` | `find.byKey(LedgerKeys.spendingLabel)` | NOT WIRED | LedgerKeys.spendingLabel does not exist; find.text('SPENDING') remains |
| `test/features/ledger/payer_currency_rewiring_test.dart` | `lib/features/ledger/keys/ledger_keys.dart` | `find.byKey(LedgerKeys.payerSectionLabel)` | NOT WIRED | LedgerKeys.payerSectionLabel does not exist; find.text('PAID BY') remains |

### Data-Flow Trace (Level 4)

Not applicable. This phase produces test infrastructure (key constants and test assertions), not components that render dynamic data. No data-flow trace required.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| 624 tests pass | `flutter test` | "624 tests, All tests passed!" | PASS |
| No analysis errors | `flutter analyze --no-fatal-infos` | 166 info-level issues only, 0 errors/warnings | PASS |
| 12 key class files exist | `grep -rn "abstract final class.*Keys" lib/` | 12 matches found | PASS |
| find.byKey() calls in test suite | `grep -rn "find\.byKey(" test/ \| wc -l` | 104 calls | PASS |
| CI regression warning step exists | `grep -q "find.text.*regression" .github/workflows/release_android.yml` | Not found | FAIL |
| LedgerKeys has spendingLabel | `grep "spendingLabel" lib/features/ledger/keys/ledger_keys.dart` | Not found | FAIL |
| GearKeys has deleteConfirmButton | `grep "deleteConfirmButton" lib/features/gear/keys/gear_keys.dart` | Not found | FAIL |
| HomeKeys has yourGroupsHeader | `grep "yourGroupsHeader" lib/features/home/keys/home_keys.dart` | Not found | FAIL |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| FOUND-05 | 14-01, 14-02, 14-03 | Test suite uses semantic Key identifiers instead of find.text() for structural assertions, preventing cascade failures during UI changes | PARTIAL | Key infrastructure complete. Plans 01-02 migrations complete. Plans 03 migrations incomplete — 7 test files still have structural find.text() calls. CI guardrail absent. |

FOUND-05 is marked `[x]` in REQUIREMENTS.md but is not fully achieved — the cascade-failure protection is incomplete for the 7 remaining files.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `test/features/home/home_screen_groups_test.dart` | 75 | `find.text('Your Groups')` — structural label | Warning | Breaks if 'Your Groups' is renamed |
| `test/features/home/home_screen_groups_test.dart` | 115 | `find.text('No groups yet')` — structural empty state | Warning | Breaks if empty state text is renamed |
| `test/features/home/home_screen_groups_test.dart` | 138 | `find.byType(FloatingActionButton)` — structural type check | Warning | Breaks if FAB type changes (e.g., to FilledButton) |
| `test/features/home/home_screen_groups_test.dart` | 141-142 | `find.text('Create a Group')`, `find.text('Join a Group')` — navigation targets | Warning | Breaks if bottom sheet option text is renamed |
| `test/features/ledger_test.dart` | 290 | `find.text('SPENDING')` — structural label | Warning | Breaks if SPENDING label renamed |
| `test/features/ledger/payer_currency_rewiring_test.dart` | 135,152,164,216 | `find.text('PAID BY')` × 4 — structural label | Warning | Breaks if PAID BY label renamed |
| `test/features/gear_screen_mutations_test.dart` | 248 | `find.text('DELETE')` — button tap target | Warning | Breaks if DELETE confirmation text renamed |
| `test/features/group_balance_card_test.dart` | 128,154,194,197,222 | `find.text('Settle')`, `find.text('Settled')` — button/badge | Warning | Breaks if Settle/Settled text renamed |
| `test/features/groups/group_activity_screen_test.dart` | 58 | `find.text('Group Activity')` — screen title | Warning | Breaks if activity screen title renamed |
| `test/unit/empty_state_view_test.dart` | 49,70 | `find.byType(ElevatedButton)` — structural button type | Warning | Breaks if button type changes to FilledButton or TextButton |
| `test/integration/happy_path_test.dart` | 71 | `find.byType(FloatingActionButton)` — structural type check | Warning | Breaks if FAB type changes |

None are blocker severity because the test suite currently passes. All are Warning because they compromise the phase's rename-resilience guarantee for those specific labels.

### Human Verification Required

1. **Rename resilience end-to-end verification**

   **Test:** After gap closure, rename 'SPENDING' to 'EXPENSES' in source files. Run full test suite. Then rename 'Settle' to 'Pay'. Run tests. Then rename 'Your Groups' to 'My Groups'. Run tests.
   **Expected:** Zero test failures for each rename (only content-checking tests for those specific labels would fail, not structural navigation tests).
   **Why human:** Requires running the rename-and-revert protocol across multiple files simultaneously to confirm full isolation. Cannot verify programmatically without modifying source files.

### Gaps Summary

Plan 03 claimed to complete 10 remaining test file migrations and add a CI regression warning. The evidence shows a significant discrepancy between what the SUMMARY documented and what actually exists in the codebase.

**Root cause:** Plan 03 was apparently executed incompletely. The source widget key additions (LedgerKeys.spendingLabel, LedgerKeys.payerSectionLabel, GearKeys.deleteConfirmButton, HomeKeys.yourGroupsHeader, GroupKeys.settledBadge, GroupKeys.settleButton, GroupKeys.activityScreenTitle, GroupKeys.activityBackButton) were never made. The test files were never updated to use find.byKey(). The CI step was never added.

**Affected files:**
- Source key files: `ledger_keys.dart`, `gear_keys.dart`, `home_keys.dart`, `group_keys.dart` (missing Plan 03 additions)
- Source widget files: `spending_summary_section.dart`, `split_scope_selector.dart`, `gear_screen.dart`, `group_member_balance_card.dart`, `group_activity_screen.dart` (missing key: parameters)
- Test files: `home_screen_groups_test.dart`, `ledger_test.dart`, `payer_currency_rewiring_test.dart`, `gear_screen_mutations_test.dart`, `group_balance_card_test.dart`, `group_activity_screen_test.dart`, `empty_state_view_test.dart` (structural find.text/byType remain)
- CI: `.github/workflows/release_android.yml` (regression warning step absent)

**What IS working:**
- The key class infrastructure (all 12 files) is solid and correct
- All 22 screens have screen-level keys — verified
- Plans 01 and 02 migrations are complete and correct — the 12 highest-priority test files are properly migrated
- All 624 tests pass
- The Ledger→Treasury rename verification was correctly executed (event_module_list.dart keys worked)

**Impact on phase goal:** The phase goal (survive any label rename without cascade failures) is not fully achieved. The 7 unmigrated files cover: home screen (Your Groups, No groups yet, FAB), ledger (SPENDING, PAID BY), gear (DELETE), group balances (Settle, Settled), activity screen (Group Activity), and empty state views. Renaming any of these labels would cause test failures in those files.

**Impact assessment:** Moderate. Plans 01-02 successfully covered ~87% of structural conversions. The remaining ~13% from Plan 03 is incomplete, but the test suite is otherwise healthy at 624/624 passing.

---

_Verified: 2026-03-28T12:00:00Z_
_Verifier: Claude (gsd-verifier)_
