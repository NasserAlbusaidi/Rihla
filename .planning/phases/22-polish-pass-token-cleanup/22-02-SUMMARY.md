---
phase: 22-polish-pass-token-cleanup
plan: "02"
subsystem: polish
tags: [haptic-feedback, animated-currency, balance-hero-card, ledger-hero-card]
dependency_graph:
  requires: [22-01]
  provides: [PLSH-01, PLSH-04]
  affects:
    - lib/features/ledger/screens/add_expense_screen.dart
    - lib/features/ledger/screens/settle_up_screen.dart
    - lib/features/groups/screens/join_group_screen.dart
    - lib/features/home/widgets/balance_hero_card.dart
    - lib/features/ledger/widgets/ledger_hero_card.dart
tech_stack:
  added: []
  patterns:
    - HapticService.success() fire-and-forget pattern (no await, before async write)
    - AnimatedCurrencyText drop-in replacement for static balance Text widgets
key_files:
  created: []
  modified:
    - lib/features/ledger/screens/add_expense_screen.dart
    - lib/features/ledger/screens/settle_up_screen.dart
    - lib/features/groups/screens/join_group_screen.dart
    - lib/features/home/widgets/balance_hero_card.dart
    - lib/features/ledger/widgets/ledger_hero_card.dart
decisions:
  - "HapticService.success() called without await (fire-and-forget) so haptic fires immediately without blocking async write"
  - "LedgerHeroCard _balanceColor getter removed — AnimatedCurrencyText owns color based on animated sign"
  - "BalanceHeroCard stays ConsumerWidget (not ConsumerStatefulWidget) — AnimatedCurrencyText is internally stateful"
  - "flutter/services.dart import retained in join_group_screen.dart for FilteringTextInputFormatter and TextInputFormatter"
metrics:
  duration_minutes: 6
  completed_date: "2026-03-31"
  tasks_completed: 2
  files_modified: 5
---

# Phase 22 Plan 02: Haptic Feedback + Animated Balance Counters Summary

**One-liner:** HapticService.success() wired to 3 write actions (add expense, settle up, join group) and AnimatedCurrencyText integrated into BalanceHeroCard and LedgerHeroCard for smooth 600ms easeOutCubic balance transitions.

## What Was Built

### Task 1: HapticService.success() on 3 write actions (commit: 065bfdf)

Three screens updated to fire the double-tap haptic immediately after validation passes:

**add_expense_screen.dart** — `_submit()` method: `HapticService.success()` added after amount/participant validation passes but before the async Firestore write. Fire-and-forget (no await).

**settle_up_screen.dart** — `_recordSettlement()` method: `HapticService.success()` added at method entry, before the async settlement service call. Added `haptic_service.dart` import.

**join_group_screen.dart** — `_joinGroup()` method: Replaced `await HapticFeedback.mediumImpact()` with `HapticService.success()` (no await). Added `haptic_service.dart` import. Retained `flutter/services.dart` because `FilteringTextInputFormatter`, `LengthLimitingTextInputFormatter`, and `TextInputFormatter` are still used in the file.

### Task 2: AnimatedCurrencyText in BalanceHeroCard and LedgerHeroCard (commit: 51790d5)

**balance_hero_card.dart** — The static `Text(amountText, ...)` with color from switch expression replaced with `AnimatedCurrencyText(value: net, currency: 'OMR', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))`. The switch expression simplified to produce only `(Color color, IconData icon, String descriptionText)` — no longer produces `amountText` since AnimatedCurrencyText handles both formatting and sign-based color.

**ledger_hero_card.dart** — The static `Text('$currency $formattedBalance', style: TextStyle(..., color: _balanceColor))` replaced with `AnimatedCurrencyText(value: netBalance, currency: currency, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.5))`. Removed `_balanceColor` getter entirely since AnimatedCurrencyText owns color. Removed `formattedBalance` local variable (was only used by the replaced Text). Both widgets stay their original base class (ConsumerWidget / StatelessWidget).

## Verification

- `flutter analyze` on all 5 modified files: **No issues found**
- `flutter test test/features/home/`: **41 tests passed**
- `flutter test test/features/ledger/`: **6 tests passed**
- `flutter test test/features/groups/`: **65 tests passed**

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None introduced in this plan.

## Self-Check: PASSED

Files exist:
- lib/features/ledger/screens/add_expense_screen.dart — FOUND
- lib/features/ledger/screens/settle_up_screen.dart — FOUND
- lib/features/groups/screens/join_group_screen.dart — FOUND
- lib/features/home/widgets/balance_hero_card.dart — FOUND
- lib/features/ledger/widgets/ledger_hero_card.dart — FOUND

Commits exist:
- 065bfdf — feat(22-02): add HapticService.success() to 3 write actions
- 51790d5 — feat(22-02): integrate AnimatedCurrencyText into BalanceHeroCard and LedgerHeroCard
