# #515 — `Expense.fromFirestore` currency read-fence

**Type:** P1 bug fix (money / data-integrity). Read-path only. Gate-category (money / `MoneySerializer`, `models/**`).
**Base:** `origin/main` @ `852a8487`. Branch `fix/515-expense-currency-fence`, worktree `../Rihla-515`.

## Problem (verified against live code)

`Expense.fromFirestore` (`lib/features/ledger/models/expense_model.dart:168`) reads the currency
code with **no support fence**:

```dart
final currency = data['currency'] as String? ?? 'OMR';   // :169  — unfenced
...
amount: MoneySerializer.fromSubunits(amountFils, currency),   // :185
currency: currency,                                            // :186
splitDistribution: _splitDistributionFromPersisted(data['splitDistribution'], splitMode, currency), // :192-196
```

`MoneySerializer.fromSubunits` → `_scale` **throws `ArgumentError('Unsupported currency: …')`**
(`money_serializer.dart:62`) for any code not in the 10-entry scale map. The exact value path
`_splitValueFromPersisted` → `fromSubunits` (`:360`) throws the same way for `SplitMode.exact`.

The expense stream maps docs with **no per-doc try/catch**
(`expense_service.dart:42`, `:60`, `:89` — `.map((doc) => Expense.fromFirestore(...))`), so **one
legacy/forged doc with a bad currency errors the entire `watchExpenses` stream for every member** →
ledger screen AND home balance once-path both go to an error state. `BalanceCalculator` re-fences
`expense.currency` at `expense_provider.dart:347`, but that is **post-construction** — never reached
because `fromFirestore` throws first.

`Settlement.fromFirestore` already fixed this exact failure (#193/#220, deployed) at
`settlement_model.dart:105-108`. Expense was never given the parallel guard — a model-level
asymmetry on the same money read-path. New bad-currency writes are already rules-blocked
(`validCurrency` floor, #382 PR-6), so the fence only ever fires on legacy/Admin/forged docs.

## Fix (single point, mirrors the deployed settlement precedent)

`expense_model.dart:169`:

```dart
// Unknown/garbage currency (a forged/legacy doc the deployed rules now
// reject on write) must not throw in MoneySerializer and error the whole
// ledger + home-balance stream for every member. Fall back to OMR,
// mirroring the settlement read fence (#193/#220) and BalanceCalculator (#47).
final rawCurrency = data['currency'] as String? ?? 'OMR';
final currency = MoneySerializer.isSupported(rawCurrency) ? rawCurrency : 'OMR';
```

That single local flows into all three sites (`:185` amount, `:186` retained currency,
`:192-196`→`:360` exact-split values), so **one fence covers every throw site**. No other change.

### Why this is the whole fix (callsite classification — principle 1)
- `Expense.fromFirestore` is **INBOUND** (read/display). The fenced value is retained on the model
  and later read by `BalanceCalculator` (re-fences) + ledger/home display.
- The only **OUTBOUND** reachability is read→edit→`toFirestore` re-save (`:216` reads `this.currency`).
  A doc whose raw code was `'XYZ'` re-saves as `'OMR'` — but `'XYZ'` is already rules-blocked on
  write, so the only thing that can be persisted is the fenced value. Behaviour is identical to the
  deployed settlement fence (which retains the fenced value, `settlement_read_fence_test.dart:77-81`).
  No write-path regression.
- Case-insensitive: `isSupported` upper-cases, so a lowercase supported code (`'omr'`) is **retained
  as-is** (`isSupported('omr') == true`), matching settlement (`:83-89`). Only truly-unknown codes fall back.

## RED test (write first) — `test/unit/expense_read_fence_test.dart`

Mirror `settlement_read_fence_test.dart`, plus the **orthogonal split-distribution axis** that
settlements can't exercise (principle 7):

1. supported USD decodes at 2dp; supported OMR at 3dp; missing → OMR (sanity).
2. **unsupported `'XYZ'` does NOT throw — returns normally, OMR-scale amount** (the core RED).
3. **unsupported currency on an `exact`-split expense does NOT throw** — exercises `:360`
   `_splitValueFromPersisted` (the split path; settlement has no `splitDistribution`).
4. unsupported currency retains the fence value `'OMR'`, not raw `'XYZ'`.
5. lowercase supported `'omr'` is retained as-is.

RED proof: cases 2 & 3 throw `ArgumentError` against current `expense_model.dart`.

## Verification (principles 2-6)
- **2 — concrete claims**: every line cited above re-grepped against `origin/main@852a8487`.
- **3 — read-path per write-path**: read = `watchExpenses`→`.map(fromFirestore)`→BalanceCalculator +
  ledger UI + `groupBalancesOnceProvider`. No write-path touched.
- **4 — fields from type**: only `currency` affected; it feeds `amount`, `currency`, exact-split values.
- **5 — data contract**: exact fence expression above; no map-key / signature change.
- **6 — arithmetic decomposition**: N/A — per-doc fence, no aggregation change.

## Done
- [ ] RED test added + proven failing for the right reason (ArgumentError pre-fix)
- [ ] Fence applied at `:169`; all tests GREEN
- [ ] `flutter analyze` clean
- [ ] Gate clean (no P1)
- [ ] PR `Closes #515` (commit body too), `/automerge` (Gate-category → review + refute)
