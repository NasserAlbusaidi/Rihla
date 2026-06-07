# #270 — Port the negative-value→equal-split guard into the server allocators

**Type:** tech-debt, money, backend (P3 — defense-in-depth parity, not a live exploit)
**Spec:** this doc. Gate-category (money math inside Cloud Functions) → fresh-context Gate mandatory before implementation.

## Problem

The Dart `BalanceCalculator` defends every weighted/exact allocator against a **negative split value** by falling back to an equal split (the non-negative-owed invariant):

- `_allocateShares` `expense_provider.dart:457`
- `_allocateExact` `expense_provider.dart:492`
- `_allocatePercent` `expense_provider.dart:554`

The guard is identical in all three:
```dart
if (distribution.values.any((value) => value < Decimal.zero)) {
  onSplitFallback(SplitFallbackReason.negative*, expense);
  return _allocateEqual(expense.amount, distribution.keys, currency);
}
```

The TS server allocators (`functions/src/callables/groupNetBalance.ts`, the **shared** oracle used by `deleteGroup`/`leaveGroup`/`removeMember` since the #190/#290 extraction) have **no** such guard:

- `allocateShares` `groupNetBalance.ts:183` — only a `totalShares.lte(0)` guard.
- `allocateExact` `groupNetBalance.ts:195` — only a tolerance guard + residual close-out.
- `allocatePercent` `groupNetBalance.ts:240` — only a drift guard.

So a doc carrying a negative split value flows through verbatim, and client vs. server compute **different nets**. `persistedInt` (`groupNetBalance.ts:85`) uses `Math.trunc`, so a negative stored value survives decode into the allocator's distribution map.

This is the **lone remaining** client↔server allocator divergence (CLAUDE.md oracle note). New negatives are blocked at the rules boundary (`firestore.rules:492` `splitValuesNonNegative`, `^[0-9,]+$`); only a **legacy or Admin-SDK** doc could carry one. None known in prod.

## Why it matters (divergence is observable through the deleteGroup gate)

Take **exact**, amount 10.000 OMR, `splitDistribution {owner:-1.000, member:11.000}` (sum 10.000 == amount → IN-tolerance, residual 0), payer owner, universe {owner, member}:

- **Client** `_allocateExact`: negative guard fires → equal split → owed `{owner:5.000, member:5.000}` → net owner **+5.000**, member **−5.000**. App shows member owes 5.000; member settles 5.000 → client all-zero (**settled**).
- **Server** (current, no guard): total 10.000 in-tolerance, residual 0 → returns distribution **verbatim** → owed `{owner:−1.000, member:11.000}` → net owner +11.000, member −11.000. After the 5.000 settlement member net **−6.000** → gate throws `failed-precondition` → **refuses to delete a group the app shows settled** (the exact #223 failure shape, on a new axis).

Same divergence for shares (`{owner:-1, member:5}`, totalShares 4 > 0 → weighted) and percent (`{owner:-20, member:120}`, sum 100 in-tolerance → weighted).

## Fix

Add the negative-value guard as the **FIRST** statement in each of the three TS allocators, mirroring the Dart ordering byte-for-byte:

```ts
if ([...distribution.values()].some((value) => value.lt(0))) {
  return allocateEqual(amount, distribution.keys(), currency);
}
```

**Ordering is load-bearing — negative guard must precede the existing checks:**
- `allocateExact`: before the tolerance check (a negative distribution can still be in-tolerance — see fixture above — and the in-tolerance/residual path would otherwise keep the negative).
- `allocateShares`: before `totalShares.lte(0)` (a negative entry with a still-positive total, e.g. `{-1, 5}`, would otherwise reach `allocateWeighted`).
- `allocatePercent`: before the drift check (a negative entry summing to 100 would otherwise reach `allocateWeighted`).

No telemetry port — the server allocators are pure (no `onSplitFallback`); the Dart `onSplitFallback` is client-only and is **not** part of the net computation.

This is the single source of truth: the fix lands once in `groupNetBalance.ts` and applies to all three callables automatically.

## Tests (TDD)

### TS gate (RED before fix, GREEN after) — `functions/test/callables/deleteGroup.test.ts`
Model on existing test `7b` (#223 in-tolerance residual). Add one test per mode (exact / shares / percent): seed a negative-value expense whose **client** equal-split fallback is fully settled by an event settlement, then assert the server **deletes** (`mode:'softDelete'`, `isDeleted:true`). RED: server refuses (member net non-zero) because it keeps the negative verbatim/weighted. GREEN: server equal-splits and agrees.

- exact: `{owner:-1000, member:11000}`, amount 10000, settlement member→owner 5000.
- shares: `{owner:-1, member:5}`, amount 8000, settlement member→owner 4000.
- percent: `{owner:-20000, member:120000}` (value×1000), amount 10000, settlement member→owner 5000.

### Dart oracle parity — `test/unit/delete_group_balance_parity_test.dart`
Add cases asserting the **client** equal-split nets for the same three fixtures (the oracle the server must reproduce). Passes today (the Dart guard exists); RED value is differential — pins the exact nets a server that skips the guard diverges from.

**(Gate [P2]) These Dart cases seed EXPENSE ONLY — no settlement** (unlike the TS gate cases), so the asserted net is the expense-only equal-split net (`+5.000/−5.000` etc.), which is the differential value being pinned. Adding a settlement would zero it and lose the oracle signal.

**(Gate [P2]) The genuine RED is the TS gate tests** (red before the `groupNetBalance.ts` change, green after). The Dart cases pass today and are oracle-pinning only — the PR's RED evidence must cite the TS `npm test -- deleteGroup` failing-before output, not the Dart run.

- exact `{owner:-1.000, member:11.000}` / 10.000 → owner +5.000, member −5.000.
- shares `{owner:-1, member:5}` / 8.000 → owner +4.000, member −4.000.
- percent `{owner:-20.0, member:120.0}` / 10.000 → owner +5.000, member −5.000.

## Docs

Update the CLAUDE.md oracle note (§ Financial Calculations) — drop the "lone remaining client-only divergence is the per-allocator negative-value→equal-split guard" caveat; state full byte-for-byte allocator parity (the guard is now mirrored). Keep the #223 in-tolerance residual close-out note.

## Verification

- `cd functions && npm test -- deleteGroup` (RED→GREEN) + full `npm test`.
- `flutter test test/unit/delete_group_balance_parity_test.dart` + relevant ledger suite.
- `flutter analyze` clean (no Dart src change, but the test file).
- Deploy: Functions change → `deploy-ceremony` after merge (no real users → deploy freely).

## Non-goals / out of scope

- No change to the rules (`splitValuesNonNegative` already blocks new negatives — #192/#194).
- No change to the Dart calculator (it's the reference; it already has the guard).
- No telemetry on the server allocators.
