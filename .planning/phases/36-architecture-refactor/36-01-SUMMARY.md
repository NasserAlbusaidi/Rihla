---
phase: 36-architecture-refactor
plan: "01"
subsystem: groups
tags: [architecture, refactor, decomposition, widget-extraction, testing]
dependency_graph:
  requires: ["36-00"]
  provides: ["SettleUpTabLayout", "SettlementTabContent", "SettleUpHistoryTab", "AllSettledState", "RecordPaymentSheet"]
  affects: ["lib/features/groups/screens/group_settle_up_screen.dart"]
tech_stack:
  added: []
  patterns: ["widget-extraction", "presentational-widget", "callback-delegation"]
key_files:
  created:
    - lib/features/groups/widgets/all_settled_state.dart
    - lib/features/groups/widgets/settlement_tab_content.dart
    - lib/features/groups/widgets/settle_up_history_tab.dart
    - lib/features/groups/widgets/settle_up_tab_layout.dart
    - lib/features/groups/widgets/record_payment_sheet.dart
    - test/features/groups/widgets/all_settled_state_test.dart
    - test/features/groups/widgets/settlement_tab_content_test.dart
    - test/features/groups/widgets/settle_up_history_tab_test.dart
    - test/features/groups/widgets/settle_up_tab_layout_test.dart
  modified:
    - lib/features/groups/screens/group_settle_up_screen.dart
decisions:
  - "Extracted RecordPaymentSheet as a 5th widget (beyond the 4 in PLAN.md) to push screen below 600 LOC — screen reached 639 after Tab/History extractions alone"
  - "SettlementTabContent receives buildBreakdown callback instead of balancesData to keep it presentational (no Riverpod dependency)"
  - "SettleUpHistoryTab uses _HistoryTile and _HistoryAvatar as private classes within the same file — acceptable for internal-only sub-widgets"
  - "Test pump strategy: tester.pump(500ms) to drain flutter_animate zero-duration timers from EmptyStateView and tile entrance animations"
metrics:
  duration_minutes: 15
  completed_date: "2026-04-16"
  tasks_completed: 3
  files_changed: 10
---

# Phase 36 Plan 01: Decompose GroupSettleUpScreen Summary

Decomposed `group_settle_up_screen.dart` (990 LOC) into 5 extracted widgets, reducing the screen to 455 LOC — meeting both the hard ceiling (≤600) and nearly the stretch target (≤400).

## Results

| Metric | Before | After |
|--------|--------|-------|
| Screen LOC | 990 | 455 |
| Widget files | 0 new | 5 new |
| Widget tests | 0 | 8 (across 4 test files) |
| Screen tests | 7 | 7 (unchanged, all passing) |
| Analyze warnings (new) | 0 | 0 |

## Extracted Widgets

| Widget | File | LOC | Purpose |
|--------|------|-----|---------|
| `AllSettledState` | `all_settled_state.dart` | 54 | All-settled empty state (success circle + text) |
| `SettlementTabContent` | `settlement_tab_content.dart` | 123 | Per-tab list of settlement tiles or empty state |
| `SettleUpHistoryTab` | `settle_up_history_tab.dart` | 175 | History tab with `_HistoryTile` + `_HistoryAvatar` private classes |
| `SettleUpTabLayout` | `settle_up_tab_layout.dart` | 168 | `AppTabBar` + `TabBarView` orchestration with bucket-split logic |
| `showRecordPaymentSheet` | `record_payment_sheet.dart` | 213 | Record payment bottom sheet (extracted as top-level function + `RecordPaymentResult`) |

## Screen Responsibilities Post-Extraction

`GroupSettleUpScreen` now owns only:
- Provider watching (`groupDetailProvider`, `groupBalancesProvider`, `groupEventsProvider`, `groupSettlementsProvider`)
- `_autoSelectTab` + `_tabController` + `_tileKeys` (screen-scoped state)
- `_showRecordPaymentSheet` (delegates to `showRecordPaymentSheet`)
- `_recordSettlement` (write operation + activity logging)
- `_buildPerEventBreakdown` + `_buildEventLabel` (breakdown computation helpers)

## Deviations from Plan

### Auto-added: RecordPaymentSheet extraction

**Rule 1 — size ceiling** — After extracting the 4 tab-body widgets (Tasks 1 + 2), screen measured 639 LOC, exceeding the 600 hard ceiling. `_showRecordPaymentSheet` (236 LOC, the bottom sheet builder) was extracted into `record_payment_sheet.dart` as a top-level function returning `RecordPaymentResult`.

- **Found during:** Task 2 LOC verification
- **Fix:** Created `lib/features/groups/widgets/record_payment_sheet.dart`, replaced inline bottom sheet with a 25-line delegator
- **Files modified:** `group_settle_up_screen.dart`, added `record_payment_sheet.dart`
- **Commit:** f8c5710

### Worktree cleanup

The worktree had stale untracked files from the pre-Firebase Supabase branch (`offline_repository.dart`, `supabase_config.dart`, `command_center.dart`, etc.) that caused compilation failures. Removed 15 stale files not present in the base commit `d30c683`. These were leftover artifacts from the `git checkout` that restored the working tree.

## Known Stubs

None — all widget data flows are wired via constructor params. No placeholder or TODO values.

## Threat Flags

None — this plan makes no changes to Firestore access patterns, auth, network endpoints, or security-sensitive logic. It is a pure structural decomposition.

## Self-Check

Files created:
- lib/features/groups/widgets/all_settled_state.dart — FOUND
- lib/features/groups/widgets/settlement_tab_content.dart — FOUND
- lib/features/groups/widgets/settle_up_history_tab.dart — FOUND
- lib/features/groups/widgets/settle_up_tab_layout.dart — FOUND
- lib/features/groups/widgets/record_payment_sheet.dart — FOUND
- test/features/groups/widgets/all_settled_state_test.dart — FOUND
- test/features/groups/widgets/settlement_tab_content_test.dart — FOUND
- test/features/groups/widgets/settle_up_history_tab_test.dart — FOUND
- test/features/groups/widgets/settle_up_tab_layout_test.dart — FOUND

Commit: f8c5710 — FOUND

## Self-Check: PASSED
