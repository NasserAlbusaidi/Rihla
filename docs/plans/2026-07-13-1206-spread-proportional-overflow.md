# #1206 — `_spreadProportional` int-multiply overflow guard

**Issue:** #1206 · **Area:** money-math · **Gate-category:** yes (BalanceCalculator)

## Problem (verified against live code this session)

`BalanceCalculator._spreadProportional` (`expense_provider.dart:613-634`):

```dart
final share = (amount * weights[k]!) ~/ total;   // :628 — native int multiply
```

`MoneySerializer.maxSafeSubunits` permits per-amount values up to ~9.0e15, so
`amount * weight` exceeds int64 max (~9.22e18) whenever both factors are ~3.1e9 subunits
(~OMR 3.1M) — silent two's-complement wrap on VM/AOT. Wrapped shares feed `used`, and the
remainder line `:632` forces `Σ == amount`, so the result **conserves, stays non-negative,
passes rules and the exact read-back tolerance** while being grossly mis-proportioned.
Only the int-based itemized path is affected; every Decimal allocator is immune. The item
phase (`~/ n`), `_spreadEqual`, and the weight-sum fold (≤ 64 participants × 9e15 ≈ 6e17)
cannot overflow — the multiply at `:628` is the single overflow site.

## Fix: BigInt intermediate (no throw-path)

```dart
final share =
    ((BigInt.from(amount) * BigInt.from(weights[k]!)) ~/ BigInt.from(total)).toInt();
```

- **Correctness:** `amount` arrives as a valid non-negative int (`< 2^63`; note Phase-3's
  `remaining` is a SUM of owed and can exceed `maxSafeSubunits`, so don't lean on that
  bound), and `weight ≤ total` ⇒ `share ≤ amount < 2^63`, so `.toInt()` is exact — no
  clamp, no wrap.
- **No behavior change** for non-overflowing inputs: integer floor-division semantics are
  identical (all operands positive — weights filtered `>0`, `amount ≥ 0`, `total > 0` — so
  truncation direction never diverges), and every pinned allocator test (remainder
  contract, #596 quantization parity, JPY discount pin) stays byte-identical. A
  hypothetical legacy doc persisted with a WRAPPED distribution self-corrects on
  reopen+re-save through the fixed producer — a deliberate correction of already-wrong
  money (no real users yet), not a regression.
- **Why not guard+throw:** extreme-but-legal inputs (within the documented per-amount cap)
  should keep working; a widening intermediate is strictly safer than a new error path on a
  money write. Perf is irrelevant (itemized tables are tiny).

## Changes

1. `expense_provider.dart` `_spreadProportional:628` — BigInt intermediate as above; extend
   the function doc comment with one line naming the overflow safety.
2. **RED regression test** in `test/unit/` (the existing itemized allocator test file),
   through the **public** `allocateItemizedDistribution` (the helper is private):
   items `A: 3_100_000_000` fils and `B: 3_100_000_000` fils (distinct assignees), discount
   `1` fil ⇒ Phase-3 `remaining ≈ 6.2e9`, `remaining * weight ≈ 1.92e19 > 2^63` wraps
   pre-fix. Assert exact expected shares, conservation, and non-negativity. **The
   exact-per-key-share assertion is the load-bearing RED** — the wrapped pre-fix output
   still conserves and stays non-negative, so those two assertions alone would be
   spuriously green. Must fail before the fix (Dart VM wraps 64-bit ints, so the RED
   reproduces on macOS).
3. Table-drive it (money contract): overflow case + a boundary non-overflow case asserting
   byte-identical results to the pre-fix formula.

## Verification-principles evidence

- **Callsite classification:** `_spreadProportional` is OUTBOUND — its output folds into the
  persisted exact `splitDistribution` (balance truth). Callers: Phase-2 proportional
  additive (`:541`), Phase-3 discount reallocation (`:567`). Both covered by the same fix.
- **Read-path per write-path:** persisted distribution is read by `recomputeNet` (server) and
  `calculateBalances` (client) — both consume the already-materialized map; fixing the
  producer needs no consumer change. Server has no analogous multiply (it reads persisted
  values; per-value cap 9e15 ≈ 2^53 keeps TS numbers exact).
- **Orthogonal axis:** conservation/rules still pass on the WRAPPED output today — reviewers
  should attack whether any OTHER int arithmetic in the itemized path can wrap (item phase,
  `_spreadEqual`, weight-sum fold — argued safe above, verify).

## Out of scope

Server-side changes; `_allocateWeighted`/Decimal allocators; editor input caps
(`fitsSafeSubunits` stays as-is).
