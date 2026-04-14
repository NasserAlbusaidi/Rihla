---
phase: quick-260414-t2d
plan: 01
type: summary
completed_at: "2026-04-14T21:15:00Z"
duration_minutes: 15
tasks_completed: 3
files_modified: 6
files_created: 1
commits:
  - hash: c22ad33
    message: "fix(260414-t2d): remainder-safe split rounding + Expense.currency from Firestore"
  - hash: 2c8de23
    message: "fix(260414-t2d): edit expense saves category+payer; add expense double-tap guard + error handling"
  - hash: d8c4328
    message: "fix(260414-t2d): validate settlement amount in group settle-up"
key_decisions:
  - "Remainder assigned to last recipient sorted alphabetically by participantId — deterministic, no UI dependency"
  - "Expense._currency is a private backing field with a public getter; constructor param keeps API backward-compatible (defaults to OMR)"
  - "Bug 2 (wrong balance user) was already fixed in the codebase — currentParticipantProvider used correctly"
---

# Quick Task 260414-t2d: Fix 7 Financial / Ledger Bugs

One-liner: Remainder-safe split rounding, Firestore-backed Expense.currency, edit expense saves category+payer, add expense double-tap guard + error snackbar, group settle-up amount validation.

## Tasks

### Task 1: Fix split rounding (Bug 1) + Expense.currency from Firestore (Bug 7)

**Bug 1 — CRITICAL — Split rounding loses money (expense_provider.dart)**

`BalanceCalculator.calculateBalances` truncated `perHead` via `scaleOnInfinitePrecision: 3` then multiplied by the split count — OMR 10.000 ÷ 3 = 3.333 × 3 = 9.999, losing OMR 0.001.

Fix: Compute `remainder = expense.amount - (perHead * splitCount)`. Sort recipients alphabetically (deterministic). Add `perHead` to all except the last; last gets `perHead + remainder`. Sum is now exactly `expense.amount`.

**Bug 7 — HIGH — Expense.currency hardcoded 'OMR' (expense_model.dart)**

`fromFirestore` correctly read `currency` from data but the model had `String get currency => 'OMR'` — a hardcoded getter that ignored the parsed value.

Fix: Added `final String _currency` backing field, `currency` named param on the constructor (default `'OMR'`), wired from `fromFirestore`, propagated through `copyWith`.

**Tests:** `test/unit/split_rounding_test.dart` — 9 tests covering: 10.000/3, 1.000/3, 9.000/2 (even), 7.001/3, custom scope, and Expense.currency round-trips. All pass.

### Task 2: Edit expense saves category+payer (Bug 3) + Add expense guards (Bugs 4, 5)

**Bug 3 — HIGH — Edit expense discards category and payer**

`ExpenseService.updateExpense` lacked `categoryId` and `payerParticipantId` parameters. `EditExpenseScreen._save` tracked `_selectedCategoryId` and `_selectedPayerId` in state but never passed them to `updateExpense`.

Fix: Added both optional params to `updateExpense`; added the corresponding map entries; updated `_save` to pass both with change-detection guards.

**Bug 4+5 — HIGH — No double-tap guard + no error handling on add expense**

`AddExpenseScreen._submit` called `expenseService.addExpense()` with no loading state set before the await (window for duplicate tap) and no `try/catch` (failures silently lost).

Fix: Set `expenseLoadingProvider = true` before any async work. Wrapped the addExpense call and success logic in `try/catch/finally` — catch shows a SnackBar with the error message, finally clears the loading state unconditionally.

### Task 3: Group settle-up amount validation (Bug 6)

**Bug 6 — HIGH — No validation on record payment amount**

`group_settle_up_screen.dart` parsed `editedAmount` from the text field and called `_recordSettlement` directly without checking for zero, negative, or over-balance values.

Fix:
- Added validation block between parse and `_recordSettlement`: rejects `<= Decimal.zero` and `> suggestedAmount` with user-visible SnackBar messages
- Added `inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))]` to the TextField — prevents invalid characters at keyboard level
- Imported `flutter/services.dart`

## Deviations from Plan

### Auto-fixed findings

**1. [Rule 1 - Bug] Bug 2 already fixed in codebase**

Found during Task 1 investigation. The plan cited `participants.first` as the bug source, but `LedgerScreen` in the main branch already uses `currentParticipantProvider(widget.trip.id)` which correctly resolves the authenticated user. No code change needed.

**2. [Deviation] File structure differs from plan**

The plan referenced `edit_expense_screen.dart` but the file is `edit_expense_screen.dart` in the main branch (plan was also correct — it did exist). The plan also referenced `lib/features/ledger/services/expense_service.dart` (standalone file) — in the main branch this is a proper Firestore-backed service class. The fix was applied correctly to the actual files.

**3. [Deviation] Execution in main repo, not worktree**

The worktree `agent-a0e1cd5b` is on an older branch that predates the groups feature and the Firestore-backed ledger. All changes were applied to the main repo at `/Users/nasseralbusaidi/Desktop/Personal/Rihla/`.

## Verified

| Bug | Status | Commit |
|-----|--------|--------|
| Bug 1: Split rounding | Fixed + 9 tests | c22ad33 |
| Bug 2: Wrong balance user | Already fixed (no-op) | — |
| Bug 3: Edit expense loses category+payer | Fixed | 2c8de23 |
| Bug 4: Double-tap duplicate | Fixed | 2c8de23 |
| Bug 5: No error handling on addExpense | Fixed | 2c8de23 |
| Bug 6: No amount validation in settle-up | Fixed | d8c4328 |
| Bug 7: Hardcoded currency | Fixed + 4 tests | c22ad33 |

`flutter test` — 892 tests, all pass.
`flutter analyze` — no new issues.

## Self-Check: PASSED

- `test/unit/split_rounding_test.dart` exists and passes
- Commits c22ad33, 2c8de23, d8c4328 exist in git log
- No stubs introduced
- No new Firestore security surface introduced
