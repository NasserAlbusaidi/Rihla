# #591 — Ledger row shows real per-person amounts for non-equal splits

**Issue:** #591 (follow-up to #242, merged `729c2a6e`). Labels: `enhancement`, `P3`, `money`, `design`. Milestone: Post-release features.

**One-line:** Make `_ExpenseRow._userShare` in `lib/features/ledger/widgets/ledger_day_card.dart` reuse the public, tested `BalanceCalculator.allocateExpenseOwed(...)` (from #242) for non-equal splits (shares/exact/percent) instead of short-circuiting the per-person sub-line to `Decimal.zero`, so the ledger row's signed sub-line matches the editor preview and the persisted balance.

## Background / current behavior (verified against code 2026-06-20)

`_ExpenseRow` (`ledger_day_card.dart:172-336`) renders, per expense:
- The gross `expense.amount` (always).
- A signed, **current-user-relative** sub-line via `RAmount(value: share, sign: true, ...)` (`:259-269`), shown only when `share != Decimal.zero`.

`share` is computed by the instance method `_userShare(expense)` (`:318-335`):
```dart
Decimal _userShare(Expense expense) {
  if (participantCount == 0 || currentParticipantId == null) return Decimal.zero;
  if (_isNonEqualSplit(expense)) return Decimal.zero;            // <-- the #125 omission
  final isPayer = expense.payerParticipantId == currentParticipantId;
  final splitIds = _effectiveSplitIds(expense);
  final isInSplit = splitIds?.contains(currentParticipantId) ?? true;
  final splitCount = splitIds?.length ?? participantCount;
  if (splitCount == 0) return Decimal.zero;
  final share = (expense.amount / Decimal.fromInt(splitCount))
      .toDecimal(scaleOnInfinitePrecision: 3);
  if (isPayer && isInSplit) return expense.amount - share;       // payer, in split
  if (isPayer && !isInSplit) return expense.amount;              // payer, not in split
  if (!isPayer && isInSplit) return -share;                      // participant
  return Decimal.zero;                                           // uninvolved
}
```

`_isNonEqualSplit` (`:309-316`) is:
```dart
mode != null && mode != SplitMode.equally && distribution != null && distribution.isNotEmpty
```

This was the deliberate #125 omission: the row only knew an equal per-head divide, so it hid the share for non-equal splits "rather than show a misleading equal figure it cannot reproduce" (`:305-308`). #242 removed that limitation by extracting the real allocator as a public function.

`BalanceCalculator.allocateExpenseOwed(...)` (`expense_provider.dart:454-503`) returns **gross owed-by-participantId** (unsigned, what each person owes). Its non-equal gate (`:467-470`) is **byte-identical** to `_isNonEqualSplit`. On that branch it allocates over `splitDistribution` keys via `_allocateShares/_allocateExact/_allocatePercent` and **does not read `participantIds`** (even its internal malformed-split fallback uses `_allocateEqual(amount, distribution.keys, ...)`, `:519/529/...`, not `participantIds`).

## The fix

In `_userShare`, replace the `if (_isNonEqualSplit(expense)) return Decimal.zero;` line with a branch that calls `allocateExpenseOwed` and reconstructs the signed figure:

```dart
final isPayer = expense.payerParticipantId == currentParticipantId;

if (_isNonEqualSplit(expense)) {
  final owed = BalanceCalculator.allocateExpenseOwed(
    amount: expense.amount,
    splitMode: expense.splitMode,
    splitDistribution: expense.splitDistribution,
    scope: expense.scope,
    customSplitParticipants: expense.customSplitParticipants,
    payerId: expense.payerParticipantId,
    participantIds: const <String>[],   // unused on the distribution branch (gate identical to _isNonEqualSplit)
    currency: expense.currency,         // per-doc currency (#382) so precision matches
    onFallback: null,                   // display path — no Sentry telemetry
  );
  final mine = owed[currentParticipantId] ?? Decimal.zero;
  return (isPayer ? expense.amount : Decimal.zero) - mine;
}
```

Keep `participantCount == 0 || currentParticipantId == null → Decimal.zero` as the first guard (unchanged). Keep the entire equal-split tail unchanged. Keep the `if (share != Decimal.zero)` render guard and `sign: true` framing in `build` unchanged.

### Why the signed reconstruction is correct (generalizes the existing equal-split math)

`allocateExpenseOwed` returns `mine` = gross owed by the current user (0 if the user is not a recipient). The row renders `(isPayer ? amount : 0) - mine`. Cross-check against the four equal-split cases the old tail already encodes:

| case | old tail | reconstruction `(isPayer?amount:0) - mine` | mine |
|---|---|---|---|
| payer, in split | `amount - share` | `amount - share` | `share` |
| payer, not in split | `amount` | `amount - 0` | `0` |
| participant | `-share` | `0 - share` | `share` |
| uninvolved | `0` | `0 - 0` | `0` |

Identical. The reconstruction is the same formula generalized from "equal share" to "real owed map".

## Classification (verification principle 1)

`_userShare` → `RAmount` display only. **INBOUND** (display path). It never feeds a write; nothing reads its output into Firestore. `onFallback: null` because it is not the persisted accumulation path (`calculateBalances` keeps its Sentry closure). No OUTBOUND/BOTH callsite touched.

## Read-path / write-path trace (principle 3)

- Write path of `splitMode`/`splitDistribution`: the expense editor (#242) — untouched.
- Read paths of `allocateExpenseOwed`: `calculateBalances` (persisted accumulation, untouched) and `_SplitPreviewCard` (#242 editor preview, untouched). This adds a third **display** reader (`_userShare`). No behavior of the shared function changes.

## `participantIds: const <String>[]` safety (principle 5 — exact contract)

`allocateExpenseOwed` ignores `participantIds` whenever it takes the distribution branch. We only enter this code when `_isNonEqualSplit(expense)` is true, and that predicate is the exact same boolean as the function's distribution gate. Therefore `participantIds` is provably unused here. Passing `const <String>[]` is honest (no fake universe) and cannot affect the result. (If the expense were equal/equally we would never reach this branch — the equal tail handles it with `participantCount`.)

## Out of scope (per issue)

- The editor preview (done in #242).
- Any change to `allocateExpenseOwed` / `calculateBalances` — reuse only.
- No new plumbing from `LedgerDayCard` (`splitMode`/`splitDistribution`/`currency` already in `expense`).

## Tests (TDD: RED first)

File: `test/features/ledger/ledger_split_ways_test.dart` (existing; extend) — the existing pattern `pumpRow(tester, expense, viewerId:, participantCount:)` is reused.

1. **NEW (acceptance, shares 2:1, clean division):** amount `12.000` OMR, `SplitMode.shares`, dist `{orphan:2, alice:1}`, scope global, payer `orphan`.
   - viewer `alice` (participant): row shows `RAmount(value: -4.000, sign: true)` + total → 2 RAmounts; assert the `-4.000` via `byWidgetPredicate`.
   - viewer `orphan` (payer): row shows `RAmount(value: +4.000, sign: true)` (others owe them) → assert `4.000`.
2. **NEW (orthogonal axis — exact mode, principle 7):** amount `12.000` OMR, `SplitMode.exact`, dist `{orphan: 8.000, alice: 4.000}`, payer `orphan`. viewer `alice` sees `-4.000`. Confirms the generalization holds on a different split mode than test 1.
3. **UPDATE existing percent test (`:109-134`):** it currently asserts the OLD omission (`find.byType(RAmount), findsOneWidget`). #591 reverses that. Update to the new WYSIWYG truth: viewer `alice` has 30% of `12.000` = `3.600`, not payer → `-3.600`; assert 2 RAmounts + the `-3.600` value.
4. **Regression (unchanged):** the existing equal/personal/custom-equal tests stay green (they never hit the new branch). Keep as-is.

RED proof: run test 1/2/3 against current code → fail (alice's row blank for non-equal). GREEN after the edit.

## Gate

Money-labeled; the signed reconstruction is the money-sensitive step. Display-only/INBOUND and reuses the tested helper, but I am running the fresh-context Opus Gate on this spec before coding rather than self-certifying exempt.

## Verify

- `flutter analyze` clean (worktree).
- `flutter test test/features/ledger/ledger_split_ways_test.dart` + the broader ledger + balance suites green.
