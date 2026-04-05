# Phase 33: Ledger - Validation

**Source:** Extracted from 33-RESEARCH.md Validation Architecture section
**Phase:** 33-ledger

## Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (Flutter SDK) + mocktail |
| Config file | none — standard `flutter test` |
| Quick run command | `flutter test test/features/ledger_test.dart` |
| Full suite command | `flutter test` |

## Phase Requirements → Test Map

| Behavior | Test Type | Automated Command | File Exists? |
|----------|-----------|-------------------|-------------|
| LedgerScreen renders ModuleHeader dark gradient | widget | `flutter test test/features/ledger_test.dart --name "renders event name"` | Yes (needs constructor fix in Wave 0) |
| LedgerScreen shows expense list | widget | `flutter test test/features/ledger_test.dart --name "renders expenses"` | Yes (needs constructor fix in Wave 0) |
| LedgerScreen empty state | widget | `flutter test test/features/ledger_test.dart --name "empty state"` | Yes (needs constructor fix in Wave 0) |
| OMR 3 decimal formatting | widget | `flutter test test/features/ledger_test.dart --name "3 decimal"` | Yes (needs constructor fix in Wave 0) |
| LedgerHeroCard CTA buttons present | widget | `flutter test test/features/ledger_test.dart` | Added in Wave 0 (33-00 Task 2) |
| SettleUpScreen ModuleHeader "Settle Up" | widget | `flutter test test/features/ledger_test.dart` | Added in Wave 0 (33-00 Task 2) |

## Sampling Rate

- **Per task commit:** `flutter test test/features/ledger_test.dart`
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

## Wave 0 Gaps (addressed in 33-00)

- [x] `test/features/ledger_test.dart` — fix constructor calls from `(event, group)` to `(groupId, eventId)` with `eventDetailProvider` mock
- [x] `test/features/ledger_test.dart` — add test: `SettleUpScreen renders ModuleHeader with 'Settle Up' title`
- [x] `test/features/ledger_test.dart` — add test: `LedgerHeroCard shows Add Expense and Settle Up buttons`

## Phase Gate Checklist

Before marking phase complete:

```bash
# All ledger tests pass
flutter test test/features/ledger_test.dart

# No CircularProgressIndicator as full-page loader in ledger screens
grep -r 'CircularProgressIndicator' lib/features/ledger/screens/
# Allowed: inline submit spinner (strokeWidth: 2) in EditExpenseScreen Save button

# ModuleHeader present in all 4 screens
grep -l 'ModuleHeader' lib/features/ledger/screens/*.dart
# Expected: 4 files

# No SafeArea in ledger screen bodies
grep -r 'SafeArea' lib/features/ledger/screens/
# Expected: empty (ModuleHeader handles it)

# No textMuted on functional labels
grep -r 'textMuted' lib/features/ledger/screens/settle_up_screen.dart
# Expected: only decorative uses (confirm dialog, amounts, cancel button)

# Full test suite
flutter test
```
