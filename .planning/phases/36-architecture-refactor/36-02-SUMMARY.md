---
phase: 36-architecture-refactor
plan: "02"
subsystem: ledger
tags: [architecture, refactor, decomposition, widget-extraction, testing]
dependency_graph:
  requires: ["36-00"]
  provides: ["EditExpenseForm", "EditExpenseScopeSection", "EditExpensePayerSelector"]
  affects: ["lib/features/ledger/screens/edit_expense_screen.dart"]
tech_stack:
  added: []
  patterns: ["widget-extraction", "presentational-widget", "callback-delegation", "controlled-component"]
key_files:
  created:
    - lib/features/ledger/widgets/edit_expense_scope_section.dart
    - lib/features/ledger/widgets/edit_expense_payer_selector.dart
    - lib/features/ledger/widgets/edit_expense_form.dart
    - test/features/ledger/widgets/edit_expense_scope_section_test.dart
    - test/features/ledger/widgets/edit_expense_payer_selector_test.dart
    - test/features/ledger/widgets/edit_expense_form_test.dart
  modified:
    - lib/features/ledger/screens/edit_expense_screen.dart
decisions:
  - "New EditExpenseScopeSection created (not SplitScopeSelector reuse) — edit mode has car sub-group ChoiceChip row and a different tab visual style (primary fill + white text vs card-surface + shadow in SplitScopeSelector)"
  - "EditExpenseForm is a ConsumerWidget (stateless controlled component) — all mutable state lives on the screen; form receives controllers and callbacks"
  - "ValueListenableBuilder used for diff indicator in EditExpenseForm — avoids requiring parent setState for the amount change display"
metrics:
  duration_minutes: 20
  completed_date: "2026-04-16"
  tasks_completed: 3
  files_changed: 7
---

# Phase 36 Plan 02: Decompose EditExpenseScreen Summary

Decomposed `edit_expense_screen.dart` (799 LOC) into an orchestrator screen + 3 extracted widgets, reducing the screen to 318 LOC — meeting both the hard ceiling (≤600) and the stretch target (≤450).

## Results

| Metric | Before | After |
|--------|--------|-------|
| Screen LOC | 799 | 318 |
| Widget files | 0 new | 3 new |
| Widget tests | 0 new | 15 new (across 3 test files) |
| Existing ledger tests | 14 | 14 (all passing) |
| Analyze warnings (new) | 0 | 0 |

## RESEARCH Open Question 2 Answer

**Decision: Create new `EditExpenseScopeSection` (do NOT reuse `SplitScopeSelector`).**

The edit-expense scope section has two edit-mode-specific behaviours absent from `SplitScopeSelector`:

1. **Car sub-group ChoiceChip row** — when scope is `subGroup`, the edit screen shows `ChoiceChip` widgets for each `SubGroupType.car` sub-group (reads `eventSubGroupsProvider`). `SplitScopeSelector` has no sub-group car selector.
2. **Different tab visual style** — edit-mode tabs use `primary` colour fill + white text for the selected state; `SplitScopeSelector` uses `cardSurface` fill + drop shadow.

Reusing `SplitScopeSelector` would have required adding edit-specific branches inside a shared widget, violating single responsibility. The new `EditExpenseScopeSection` wraps the same visual concept cleanly with edit-mode behaviour only.

## Extracted Widgets

| Widget | File | LOC | Purpose |
|--------|------|-----|---------|
| `EditExpenseScopeSection` | `edit_expense_scope_section.dart` | 178 | Scope tabs (Global/My Car/Custom/Personal) + car sub-group ChoiceChips |
| `EditExpensePayerSelector` | `edit_expense_payer_selector.dart` | 90 | Payer dropdown for event leaders (hidden for non-leaders) |
| `EditExpenseForm` | `edit_expense_form.dart` | 296 | Full form body: amount+diff, category picker, scope section, payer selector, note, action buttons |

## Screen Responsibilities Post-Extraction

`EditExpenseScreen` now owns only:
- Provider watching (`eventExpensesProvider`, `eventDetailProvider`)
- Controller lifecycle (`_amountController`, `_noteController`, `_initializeControllers`, `dispose`)
- Mutable state (`_scope`, `_selectedSubGroupId`, `_customSplitParticipants`, `_selectedPayerId`, `_selectedCategoryId`, `_isSubmitting`)
- Submit handler (`_save`) and delete handler (`_confirmDelete`)
- Loading/error/not-found scaffold states
- `EditExpenseForm(...)` composition with all callbacks wired

## Deviations from Plan

None — plan executed exactly as written. The scope section decision (new wrapper vs. reuse) was evaluated during Task 1 and documented as directed. `edit_expense_scope_section.dart` was created (not skipped) due to the edit-mode differences found.

## Known Stubs

None. All data flows are wired. The custom participant selector in `EditExpenseScopeSection` intentionally shows no participants (edit mode limitation pre-existing in the original screen — the original `_buildScopeSection` passed `AsyncValue.data(const [])` to `_buildCustomParticipantSelector`). This is not a stub introduced by this refactor.

## Self-Check: PASSED

Files verified to exist:
- `lib/features/ledger/widgets/edit_expense_scope_section.dart` ✓
- `lib/features/ledger/widgets/edit_expense_payer_selector.dart` ✓
- `lib/features/ledger/widgets/edit_expense_form.dart` ✓
- `test/features/ledger/widgets/edit_expense_scope_section_test.dart` ✓
- `test/features/ledger/widgets/edit_expense_payer_selector_test.dart` ✓
- `test/features/ledger/widgets/edit_expense_form_test.dart` ✓
- `lib/features/ledger/screens/edit_expense_screen.dart` = 318 LOC ✓

Commits verified:
- `1f8dfca` refactor(36-02): decompose edit_expense_screen into 3 sibling widgets ✓
- `925d441` test(36-02): add widget tests for edit_expense extracted widgets ✓
