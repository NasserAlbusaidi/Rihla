# Financial & Ledger Bugs — CRITICAL + HIGH

**7/7 FIXED | All resolved**

## ~~2. Split Rounding Loses Money (CRITICAL)~~ FIXED

Fixed in commit c22ad33. `expense_provider.dart` now uses remainder-safe distribution: truncated perHead assigned to all recipients except the last (sorted for determinism), who absorbs the rounding remainder so `sum(shares) == expense.amount` exactly.

## ~~3. LedgerScreen Shows the Wrong User's Balance (CRITICAL)~~ FIXED

Now uses `currentParticipantProvider` to resolve the current user, not `participants.first.id`.

## ~~6. Edit Expense Screen Discards Category and Payer Changes (HIGH)~~ FIXED

`_save()` now passes both `categoryId` and `payerParticipantId` to `updateExpense()`. Fields are conditionally passed only if changed.

## ~~7. No Double-Tap Guard on Expense Submission (HIGH)~~ FIXED

`_submit()` now sets `expenseLoadingProvider` to true before async work. Button disabled while loading. Reset in `finally` block.

## ~~12. No Error Handling on Expense Creation (HIGH)~~ FIXED

`_submit()` now wrapped in try/catch/finally. SnackBar shown on failure. Loading state reset in finally.

## ~~14. No Amount Validation in Record Payment (HIGH)~~ FIXED

Validates `amount > 0` (rejects zero/negative) and `amount <= suggestedAmount` (rejects overpayment) with SnackBar feedback.

## ~~25. Hardcoded OMR Throughout (MEDIUM)~~ FIXED

`expense_model.dart` now reads from stored `_currency` field with `'OMR'` fallback for backward compat. No longer a hardcoded getter.

## Files Involved

- `lib/features/ledger/providers/expense_provider.dart` (split rounding — FIXED)
- `lib/features/ledger/screens/ledger_screen.dart`
- `lib/features/ledger/screens/edit_expense_screen.dart`
- `lib/features/ledger/screens/add_expense_screen.dart`
- `lib/features/groups/screens/group_settle_up_screen.dart`
- `lib/features/ledger/models/expense_model.dart`
