# ISSUE #47 — BalanceCalculator currency precision (Option B: make calculator currency-correct) — FENCE v1

**Baseline:** `main` @ `c1f708c` (clean tree). Investigated read-only 2026-05-28.
**Decision:** Option B (user-selected). Make `BalanceCalculator` honor each expense's own
currency precision. Behavior **byte-identical for OMR** (today's only currency); latent bug
closed; forward-correct the day the editor stops hardcoding OMR. Does **not** enable
multi-currency end-to-end.
**Gate:** Round 1 GREEN — two independent fresh-context reviewers (verifier + adversarial breaker),
no [P1]s. Non-blocking findings folded: `formatters.dart` added to follow-ups; JPY exact-fallback +
`XYZ` fence tests added. Safe to implement.

---

## INVARIANT (the contract this fix must hold)

> Every allocation quantizes to the precision of **the expense's own currency**
> (`expense.currency` via `MoneySerializer` scale), not a hardcoded OMR 3-dp.
> For an OMR expense the output Decimal is identical to today, bit-for-bit.
> Conservation is preserved: `sum(perPersonOwed) == expense.amount` for every split
> mode and currency (last sorted recipient absorbs the remainder, unchanged).
> An unsupported/garbage currency falls back to OMR precision — it must **never throw**
> out of `calculateBalances` (Firestore data is external/untrusted).

---

## Root cause (verified against code, not the issue text)

The issue named one site; there are **three** in the calculator, plus a guard concern.
All in `lib/features/ledger/providers/expense_provider.dart`:

1. `_toOmaniPrecision` (`:400-405`) — hardcodes `'OMR'`. Used by `_allocateWeighted:388`
   (shares + percent, every non-last allocation).
2. equal-split `perHead` in `calculateBalances` (`:256-258`) — `scaleOnInfinitePrecision: 3`
   (the `3` is OMR's dp). Used by global/custom/subGroup/personal equal splits.
3. `_allocateEqual` `perHead` (`:415-417`) — `scaleOnInfinitePrecision: 3`. Used as the
   invalid-distribution fallback from `_allocateShares:330` / `_allocateExact:349` /
   `_allocatePercent:368`.

`_allocateExact` itself does **not** quantize (returns the validated distribution as-is) —
no change needed there except threading currency to its fallback.

Why it's latent: every **write** path hardcodes `'OMR'`, so `expense.currency` is always
`'OMR'` today → these three sites are currently *correct*. Confirmed:
`add_expense_screen.dart:34` (`_tripCurrency => 'OMR'`), `expense_editor_body.dart:116`
(same), `edit_expense_screen.dart` (`updateExpense` called with no `currency:` → service
`?? 'OMR'`), `create_group_screen.dart` (`createGroup(..., currency: 'OMR')`).

---

## Scope fences

### IN scope
- `lib/core/services/money_serializer.dart` — add `fractionDigits(currency)` + `isSupported(currency)`.
- `lib/features/ledger/providers/expense_provider.dart` — thread the resolved currency
  through the allocation helpers; replace the three OMR-precision sites.
- `test/unit/money_serializer_test.dart` — tests for the two new methods.
- `test/unit/balance_calculations_test.dart` — extend `expense()` helper with `currency`;
  add currency-aware regression cases (USD/JPY).

### OUT of scope (explicit — separate follow-ups, do NOT bundle)
- **Editor/group-create OMR hardcodes** (`_tripCurrency`, `createGroup`) — that's "enable
  multi-currency end-to-end" (Option C), not this bug. Leaving them means behavior is
  unchanged in the running app.
- **SQLite cache currency** — `expense_cache_repository.dart:155` decodes exact-split as
  `'OMR'` while `:146` encodes with real currency. The `expenses` table has **no currency
  column** (verified: `getExpenses:82-108` rebuilds `Expense` with no `currency:`), so a real
  fix needs a schema migration (v8→v9). AND `getExpenses` is read by **zero** live balance
  paths (only `expense_cache_repository_test.dart` + `offline_scenario_test.dart`); the live
  balance reads Firestore via `eventExpensesProvider`. So this does not affect live balances.
  → Follow-up issue.
- **`RAmount` JPY display** (`r_amount.dart:84`, `currency == 'OMR' ? 3 : 2`) — JPY should be
  0-dp; display-only, separate. → Follow-up.
- **`formatters.dart` `currencyConfig` is incomplete** (`:14-21`, only OMR/USD/EUR/GBP/AED/SAR).
  `formatCurrency:31` falls back to `decimals: 3` for the missing JPY/KWD/BHD/QAR — so a JPY
  expense would be *calculated* at 0-dp by this fix but *displayed* at 3-dp. Display-only, no
  write path consumes a formatted string. → Follow-up (fix display precision in the Option-C sweep).
- **`_splitTolerance = 0.001`** (`expense_provider.dart:164`) — exact/percent validation
  threshold, OMR-scaled. Not a precision quantizer; leaving it is harmless (stricter, not
  wrong). Noted, not changed.
- **`MoneySerializer` map / multi-currency support itself** — keep all 10 currencies.

---

## Exact changes

### 1. `money_serializer.dart` — two pure helpers

```dart
/// True if [currency] (case-insensitive) has a known subunit scale.
static bool isSupported(String currency) =>
    _currencyScale.containsKey(currency.toUpperCase());

/// Fractional digits for [currency] (OMR→3, USD→2, JPY→0). Throws
/// ArgumentError on unsupported currency, consistent with toSubunits/fromSubunits.
static int fractionDigits(String currency) {
  var scale = _scale(currency); // throws on unsupported; uppercases internally
  var digits = 0;
  while (scale > 1) {
    scale ~/= 10;
    digits++;
  }
  return digits;
}
```
(Assumes scale is a power of ten — true for all 10 entries: 1/100/1000.)

### 2. `expense_provider.dart` — thread resolved currency

In `calculateBalances`, inside the `for (final expense in expenses)` loop, resolve once
**before** the split branching:
```dart
final currency =
    MoneySerializer.isSupported(expense.currency) ? expense.currency : 'OMR';
```

**(a) split-mode switch** (`:205-210`) — pass `currency`:
```dart
SplitMode.shares  => _allocateShares(expense, distribution, currency),
SplitMode.exact   => _allocateExact(expense, distribution, currency),
SplitMode.percent => _allocatePercent(expense, distribution, currency),
SplitMode.equally => <String, Decimal>{},
```

**(b) equal-split perHead** (`:256-258`) — currency dp instead of literal 3:
```dart
final perHead = (expense.amount / Decimal.fromInt(splitCount))
    .toDecimal(scaleOnInfinitePrecision: MoneySerializer.fractionDigits(currency));
```

**(c) `_toOmaniPrecision` → `_toCurrencyPrecision(value, currency)`** (`:400-405`):
```dart
static Decimal _toCurrencyPrecision(Decimal value, String currency) =>
    MoneySerializer.fromSubunits(
      MoneySerializer.toSubunits(value, currency),
      currency,
    );
```

**(d) `_allocateWeighted(amount, weights, denominator, currency)`** (`:374-398`) — use
`_toCurrencyPrecision(x, currency)` for the non-last branch (last unchanged: `amount - allocated`).

**(e) `_allocateEqual(amount, recipientIds, currency)`** (`:407-426`) — perHead uses
`scaleOnInfinitePrecision: MoneySerializer.fractionDigits(currency)`.

**(f) `_allocateShares` / `_allocateExact` / `_allocatePercent`** — accept `currency`, forward
it to `_allocateWeighted(...)` and `_allocateEqual(...)`.

No other call sites of these private helpers exist (verified).

---

## Behavior-identical proof for OMR (verify, don't gesture)

- `fractionDigits('OMR')` = 3 (1000 → 100 → 10 → 1, three steps) ⇒ sites (b)/(e) become
  `scaleOnInfinitePrecision: 3` — **textually identical** to today.
- `_toCurrencyPrecision(v,'OMR')` = `fromSubunits(toSubunits(v,'OMR'),'OMR')` = old
  `_toOmaniPrecision(v)` — **identical**.
- Resolver: `isSupported('OMR')` = true ⇒ `currency == 'OMR'` for every expense today.
∴ Every existing OMR test passes unchanged, by construction.

New-currency correctness:
- USD shares 1:1:1 of `10.00`: non-last = `_toCurrencyPrecision(3.333…, 'USD')` =
  `fromSubunits(toSubunits(3.333…,'USD')=333, 'USD')` = `3.33`; last = `10.00 - 6.66 = 3.34`.
  ⇒ `3.33 / 3.33 / 3.34` (was `3.333 / 3.333 / 3.334`).
- JPY equal `1000` / 3: `fractionDigits('JPY')=0` ⇒ perHead `(1000/3).toDecimal(scaleOnInfinitePrecision:0)`
  = `333`; remainder `1000 - 999 = 1`; last `334`. ⇒ `333 / 333 / 334` (was `333.333 / 333.333 / 333.334`).
  Conservation holds in both.

---

## Regression surface (must stay GREEN, unchanged)

- `test/unit/balance_calculations_test.dart` — 8 OMR cases (shares/exact/percent/legacy + 2 fallbacks).
- `test/unit/split_rounding_test.dart` — 5 OMR conservation cases + 4 `Expense.currency` model cases.
- `test/unit/money_serializer_test.dart` — existing OMR/USD/JPY + unsupported-throws.
- `test/integration/firebase_money_roundtrip_test.dart`.

## New tests (RED first → GREEN)

`money_serializer_test.dart`:
- `fractionDigits`: OMR→3, USD→2, JPY→0; case-insensitive (`omr`→3); unsupported `XYZ` throws.
- `isSupported`: true for OMR/USD/JPY, false for `XYZ`.

`balance_calculations_test.dart`:
- Extend `expense({... String currency = 'OMR'})` (default keeps all existing calls intact).
- USD shares 1:1:1 of `10.00` ⇒ `3.33 / 3.33 / 3.34` (RED today: calc gives 3.333…).
- JPY equal (null mode, global) `1000` / 3 ⇒ `333 / 333 / 334` (RED today).
- JPY percent or shares case ⇒ currency-correct + conservation.
- JPY **exact-split with invalid sum** ⇒ falls back to `_allocateEqual` at JPY 0-dp (Gate [P3]:
  exercises the exact→equal fallback path at non-OMR precision, not just weighted).
- Unsupported currency `XYZ` ⇒ `calculateBalances` does NOT throw and falls back to OMR precision.
  Keep the fence explicit (Gate [P3]): assert no-throw at the **`calculateBalances`** boundary;
  assert `MoneySerializer.fractionDigits('XYZ')` **does** throw, separately, in the serializer test.

---

## Verification commands
```bash
flutter analyze
flutter test test/unit/balance_calculations_test.dart test/unit/split_rounding_test.dart \
             test/unit/money_serializer_test.dart
flutter test   # full suite; CI gate is 80% line coverage
```

---

## Questions for the Gate (adversarial pass on orthogonal axes)

- **Settlements axis:** `calculateOptimalSettlements` operates on already-summed `netBalance`
  Decimals — does any currency precision assumption hide there? (Believed no: it's pure
  min-cash-flow on existing Decimals; it never quantizes.) Confirm.
- **Mixed-currency-per-event axis:** if one event ever holds expenses in two currencies, the
  per-participant `paidMap`/`owedMap` sum Decimals across currencies (meaningless). This is
  **pre-existing** and unchanged by Option B (today single-currency OMR). Confirm we are not
  making it *worse*, and that it's correctly deferred.
- **Identity/fallback axis:** is resolving unsupported→OMR the right call vs. throwing? Could a
  legitimately-stored currency (one of the 10) ever miss `isSupported` due to casing? (`toUpperCase`
  in both `isSupported` and `_scale` — confirm symmetry.)
- Any 4th OMR-precision site missed? (Searched: `_toOmaniPrecision`, both `scaleOnInfinitePrecision: 3`.)
- Is extending the `expense()` test helper's signature safe for all existing callers? (Default `'OMR'`.)
