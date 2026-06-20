# #596 — `_allocateEqual` quantizes per-head shares (client↔server oracle parity)

**Branch:** `fix/596-allocate-equal-quantize` · **Type:** `fix(money)` · **Gate:** mandatory (BalanceCalculator oracle) · **Deploy:** none (client-only; server already correct)

## Problem (verified against live code)

`BalanceCalculator._allocateEqual` (`lib/features/ledger/providers/expense_provider.dart:671-691`) does **not** quantize the per-head share to whole subunits:

```dart
final perHead = (amount / Decimal.fromInt(splitCount)).toDecimal(
  scaleOnInfinitePrecision: MoneySerializer.fractionDigits(currency),
);
```

`Decimal./` returns a `Rational`; `Rational.toDecimal(scaleOnInfinitePrecision: N)` truncates **only non-terminating** rationals to N places. A **terminating** sub-subunit division — `OMR 2.900 / 8 = 0.3625` (a finite rational) — bypasses `scaleOnInfinitePrecision` entirely and returns `0.3625` exactly. `remainder = 2.900 - 0.3625×8 = 0` → all 8 heads owe `0.3625` (half a baisa).

### Why this is a parity bug, not a display nit

The TS server `allocateEqual` (`functions/src/callables/groupNetBalance.ts:140-159`) quantizes:
```ts
const perHead = quantize(amount.div(count), currency); // ROUND_DOWN to subunits
```
`quantize(0.3625, OMR) = 0.362`; `remainder = 2.900 - 0.362×8 = 0.004` → 7 heads owe `0.362`, the alphabetically-last owes `0.366`. Sum `2.900` ✓.

So **client `0.3625` ≠ server `0.362/0.366`** for any equal split whose `amount/count` terminates below subunit precision. `calculateBalances` is the cross-impl ORACLE the server `recomputeNet` mirrors byte-for-byte (CLAUDE.md) — this breaks that invariant. **The server is correct; the client is wrong.**

`_allocateEqual` is the **lone** allocator that skips quantization: `_allocateWeighted` (`:634-660`) already wraps `_toCurrencyPrecision(...toDecimal(scaleOnInfinitePrecision: 10), currency)`, matching the server `quantize`.

### Real-data repro (prod group "Big D" / SH362P, event الجبل الاخضر, 8 ppl, OMR)

`bread = 2.900` global-equal across 8 → client bills each `0.3625`. Hatim's event total client-net = `7.1335`; server net = `7.131`.

### User-visible symptoms

1. **Settle-up rejects the full balance.** `record_payment_sheet.dart:83` prefills `suggestedAmount.toStringAsFixed(fractionDigits)`; `7.1335 → "7.134"` (half-up). The cap (`settle_up_screen.dart:463`, `group_settle_up_screen.dart:478`) compares the parsed `7.134` against the raw `Decimal` `7.1335` → `7.134 > 7.1335` → "amount cannot exceed the outstanding balance". User must underpay (`7.133`), leaving a `0.001` residual.
2. **Home (server aggregate #366) vs settle-up (live client) disagree** on the same balance (`7.131` vs `7.134`).

Both symptoms are downstream of the non-whole-subunit `netBalance`. Fixing the allocator resolves them at the root — no cap band-aid.

## Fix (client-only — one method)

Mirror `_allocateWeighted`/the server: quantize the per-head share via `_toCurrencyPrecision`, then close the remainder onto the alphabetically-last recipient (unchanged contract).

```dart
final perHead = _toCurrencyPrecision(
  (amount / Decimal.fromInt(splitCount)).toDecimal(scaleOnInfinitePrecision: 10),
  currency,
);
final remainder = amount - (perHead * Decimal.fromInt(splitCount));
```

`_toCurrencyPrecision` round-trips through `MoneySerializer.toSubunits` (`.toBigInt()` = truncate-toward-zero) / `fromSubunits` — **identical** to the server `quantize` (`ROUND_DOWN`). The remainder/last-recipient assignment block is unchanged.

### Invariants preserved (proof)

- **Conservation:** `sum = perHead×(count-1) + (perHead + remainder) = perHead×count + (amount − perHead×count) = amount`. ✓
- **Non-negative owed:** `perHead = quantize(amount/count) ≥ 0` (positive amount); `perHead×count ≤ amount` (truncation rounds down) ⇒ `remainder ≥ 0` ⇒ last head `= perHead + remainder ≥ 0`. ✓ (Negative `amount` never reaches here — the share/exact/percent negative guards equal-split-fallback first.)
- **Non-terminating unchanged:** `10.000/3`: old `toDecimal(scaleOnInfinitePrecision: 3) = 3.333`; new `_toCurrencyPrecision(toDecimal(...,10)=3.3333333333, OMR) = 3.333`. Both truncate to currency precision; truncation is idempotent under further truncation, so every existing non-terminating case (10.000/3, 100 JPY/3, 20.00 AED/3 → 6.66/6.66/6.68) is byte-identical.
- **Already-whole unchanged:** `9.000/2 = 4.500`, `9.000/3 = 3.000` — `_toCurrencyPrecision` is a no-op. ✓

### Verification principles (CLAUDE.md §Verification)

1. **Callsite classification:** `_allocateEqual` feeds `calculateBalances` (balances → settle-up cap, home aggregate, deleteGroup gate) and `allocateExpenseOwed` (split preview). All **OUTBOUND** to money display/gates; none persist split shares (Firestore stores `amountFils` + `splitDistribution` weights, never the computed owed). So the change is display/gate-correctness only — no migration, no persisted-data rewrite.
2. **Concrete claims:** server `quantize` `:62`, server `allocateEqual` `:152`, client `:680`, `_toCurrencyPrecision` `:664`, `toSubunits` `.toBigInt()` `:32`, cap `settle_up_screen.dart:463` / `group_settle_up_screen.dart:478` — all read, not recalled.
3. **One read-path per write-path:** no write-path changes. Read-paths of `netBalance`: settle-up cap, `homeGroupBalanceProvider`, deleteGroup/leaveGroup/removeMember gates — all now see whole-subunit nets matching the server.
4. **Fields from type:** n/a (no schema change).
5. **Data contract:** `_allocateEqual` signature unchanged (`amount, recipientIds, currency → Map<String,Decimal>`). Output values change only for terminating sub-subunit splits.
6. **Arithmetic decomposition:** conservation proof above; `netBalance` folds settlements but the per-event owed slice is now whole-subunit at source.
7. **Adversarial / orthogonal axis (identity + currency):** parity case asserts the **exact per-head distribution** (not just conservation — the axis the bug slipped through) AND a JPY/USD terminating case to prove the fix is currency-scale-general, not OMR-special.

## Tests (RED → GREEN)

All client-side; server untouched.

1. **`test/unit/allocate_expense_owed_test.dart`** (scope/equal group) — primary RED:
   - `OMR 2.900 / 8` equal over 8 ids → 7×`0.362`, alphabetically-last `0.366`, `sum == 2.900`, **no `0.3625`**. (Old code: all `0.3625` → RED.)
   - `USD 0.10 / 8 = 0.0125` → 7×`0.01`, last `0.03`, sum `0.10` (terminating sub-cent; proves currency-general).
2. **`test/unit/balance_calculations_test.dart`** (new test) — `calculateBalances` for `2.900/8`: every `totalOwed` is whole-subunit (`× 1000` is integral), pins the home-vs-settle-up symptom. RED on old code (`0.3625 × 1000 = 362.5`).
3. **`test/unit/delete_group_balance_parity_test.dart`** (new case 4b) — extend the cross-impl parity oracle with a terminating sub-subunit equal split, asserting the **exact** server-matching distribution (the gap conservation-only checks missed). Comment: old client `0.3625`, server `0.362/0.366`.

`flutter analyze` clean; run the 3 files RED-first, then the full `flutter test` suite.

## Out of scope
- Group-vs-event settlement reconciliation (#200).
- Pre-existing `0.002` data artifact on SH362P (data cleanup, not code).
- Server changes (already quantizes; no deploy).

## Gate / merge
Fresh-context Opus Gate before implementation (this doc). Merge via `/automerge` → Gate-category (money) → fresh-context diff review + independent refuter; `Closes #596` in the commit body (squash-merge auto-close).
