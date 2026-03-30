---
phase: 21-module-screens-redesign
plan: 02
subsystem: ledger
tags: [ui, ledger, redesign, hero-card, timeline, expense-card]
dependency_graph:
  requires: [21-01]
  provides: [LedgerHeroCard, ExpenseCard, SettlementRow, redesigned-LedgerScreen]
  affects: [ledger_screen.dart, ledger widgets]
tech_stack:
  added: []
  patterns:
    - Sealed class for timeline item union type (_ExpenseItem / _SettlementItem)
    - Dart 3 switch expression for three-state balance color
    - Decimal.toDecimal(scaleOnInfinitePrecision: 3) for safe division
    - FadeInList wrapping typed ExpenseCard/SettlementRow widgets
key_files:
  created:
    - lib/features/ledger/widgets/ledger_hero_card.dart
    - lib/features/ledger/widgets/expense_card.dart
    - lib/features/ledger/widgets/settlement_row.dart
  modified:
    - lib/features/ledger/screens/ledger_screen.dart
decisions:
  - Sealed class _TimelineItem with _ExpenseItem/_SettlementItem instead of Transaction union — avoids dependency on eventUnifiedLedgerProvider and keeps type safety in the switch
  - LedgerKeys.spendingLabel re-used on 'TRANSACTIONS' overline — existing test assertion for this key preserved
  - ExpenseCard shows 'group' as participant count when no customSplitParticipants (global scope expenses have no explicit participant list)
  - dynamic event type in _LedgerBody — event comes from eventDetailProvider which returns a typed Event; dynamic used to match existing pattern
metrics:
  duration: 5 minutes
  completed: 2026-03-30
  tasks: 2
  files: 4
---

# Phase 21 Plan 02: Ledger Screen Redesign Summary

Redesigned the Ledger screen with card-style expense rows, a balance hero card, inline settlement rows, and single-scroll layout (no tabs). Satisfies SCRN-03.

## One-liner

LedgerScreen rewritten as single-scroll CustomScrollView with dark ModuleHeader, balance hero card (YOUR BALANCE / EVENT TOTAL / dual CTA), TRANSACTIONS overline, and FadeInList of ExpenseCard/SettlementRow items.

## Completed Tasks

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Create LedgerHeroCard, ExpenseCard, SettlementRow | 01a1f18 | 3 new widget files |
| 2 | Rewrite LedgerScreen with hero + single-scroll timeline | 89934d5 | ledger_screen.dart |

## Artifacts Produced

**LedgerHeroCard** (`lib/features/ledger/widgets/ledger_hero_card.dart`)
- YOUR BALANCE column (28sp, w600, color-coded via Dart 3 switch expression)
- EVENT TOTAL column (20sp, w600, textPrimary)
- Expense+settlement count row (14sp, textSecondary, separated by ·)
- Add Expense ElevatedButton + Settle Up OutlinedButton (both 52dp height)
- Container: surface bg, 24dp radius, cardShadow, 20dp padding

**ExpenseCard** (`lib/features/ledger/widgets/expense_card.dart`)
- Line 1: category icon (Iconsax) + title + amount (right-aligned)
- Line 2: payer · relative date · N people
- Line 3: "Owed to you X" (successText) / "You owe X" (errorText) / "Settled" (textSecondary)
- Container: surface bg, 24dp radius, cardShadow, 16dp padding

**SettlementRow** (`lib/features/ledger/widgets/settlement_row.dart`)
- Teal left accent bar (BorderSide color: AppColors.moduleLedger, width: 3)
- Iconsax.tick_circle checkmark in moduleLedger color
- payer → recipient name, amount in successText, relative date in textMuted

**LedgerScreen** (rewritten, `lib/features/ledger/screens/ledger_screen.dart`)
- ConsumerWidget watching eventDetailProvider + eventExpensesProvider + eventSettlementsProvider
- CustomScrollView with SliverToBoxAdapter slivers
- Dark ModuleHeader with event.name.toUpperCase() subtitle
- LedgerHeroCard with computed net balance + event total
- TRANSACTIONS overline with LedgerKeys.spendingLabel key
- FadeInList of ExpenseCard/SettlementRow (sorted by date desc via sealed _TimelineItem)
- SkeletonLoader.expenseList() for loading state
- EmptyStateView with terracotta gradient for empty state
- EmptyStateView with Reload CTA for error state
- All tabs, MemberBalancesSection, SpendingSummarySection, TransactionList, CircularProgressIndicator removed

## Test Results

- `flutter test test/features/ledger_test.dart --no-pub`: 6/6 pass
- `flutter test --no-pub` (full suite): 752/752 pass — zero regressions

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Decimal division returns Rational, not Decimal**
- **Found during:** Task 2
- **Issue:** `expense.amount / Decimal.fromInt(splitCount)` returns `Rational` type, not `Decimal`, causing type errors in `_expenseUserBalance()`
- **Fix:** Applied `.toDecimal(scaleOnInfinitePrecision: 3)` to convert back to Decimal — matches pattern used in `expense_provider.dart:278`
- **Files modified:** `lib/features/ledger/screens/ledger_screen.dart`
- **Commit:** 89934d5

**2. [Rule 2 - Missing] Sealed class for timeline union type**
- **Found during:** Task 2
- **Issue:** Plan described mixing expenses+settlements into FadeInList but no union type specified — using Transaction from eventUnifiedLedgerProvider was removed per plan
- **Fix:** Introduced sealed class `_TimelineItem` with `_ExpenseItem` and `_SettlementItem` — enables exhaustive switch, type-safe widget dispatch, no dependency on removed `eventUnifiedLedgerProvider`
- **Files modified:** `lib/features/ledger/screens/ledger_screen.dart`
- **Commit:** 89934d5

## Known Stubs

None. ExpenseCard shows real expense data, SettlementRow shows real settlement data, LedgerHeroCard shows computed net balance from BalanceCalculator.

## Self-Check: PASSED
