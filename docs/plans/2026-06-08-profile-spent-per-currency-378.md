# Plan: Profile lifetime "Spent" — per-currency buckets (#378)

**Date:** 2026-06-08
**Issue:** #378 (spun out of #261 PR-B / PR #377)
**Category:** Gate-mandatory — cross-group money aggregation.
**Decision (user, 2026-06-08):** when a user's groups span >1 currency, the
Spent cell shows **per-currency lines (hero-consistent)**, capped at 2 lines +
"+N" overflow. Single-currency users see their correct total, unchanged.

## Problem

`profile_stats_provider.dart:69` sums `balances.totalSpent` across ALL groups
into one currency-blind `Decimal`:

```dart
totalSpent = totalSpent + balances.totalSpent;   // 10 USD + 10 OMR => "20"
```

`profile_screen.dart:530` renders it `RAmount(value: stats.totalSpent,
currency: 'OMR', showCurrency: false)`. Pre-#261 every group was OMR so the
sum was a tautology; with PR-B's create-group currency picker live on `main`, a
user holding ≥2 currency groups sees a fabricated total at OMR 3dp precision.
This is the canonical "no FX → never sum across currencies" failure the money
contract guards.

`showCurrency: false` already hides the code, so the issue's "hide the code"
option is a no-op for the **magnitude** bug — the number itself must become
per-currency.

## Approach (mirror the already-shipped hero bucketing)

`crossGroupBalanceProvider` already buckets the per-user **net** by
`group.currency` into `List<CurrencyBalance>` via `_accumulateBucket` +
`_sortedCurrencyBuckets` (`group_balance_provider.dart:600-620`). Each group has
exactly one immutable `currency` (#261 PR-1). Do the identical thing for
`totalSpent`.

**Inherited assumption (acknowledged, not re-litigated):** keying the spend
bucket by `group.currency` is only correct because every non-legacy expense
satisfies `expense.currency == group.currency` (the #261 PR-1 rule, deployed
`edd6421`), and legacy expenses are OMR-only. `calculateTotalExpenses`
(`expense_provider.dart:~690`) sums `e.amount` ignoring per-expense currency, so
a group with a mixed-currency expense would mis-bucket — but that's exactly the
assumption the already-shipped `crossGroupBalanceProvider` (`:616`) makes. This
spec adopts shipped behavior; it introduces no NEW cross-currency risk. (The
per-expense-currency future is #382, out of scope.)

### Task 1 — `profileStatsProvider` returns per-currency spend

`lib/features/settings/providers/profile_stats_provider.dart`

- New type alias:
  ```dart
  typedef CurrencySpend = ({String currency, Decimal amount});
  ```
- `ProfileStats` shape change — **replace** `Decimal totalSpent` with
  `List<CurrencySpend> spentByCurrency` (replace, not add — so no caller can
  read a currency-blind sum; the compiler surfaces every consumer):
  ```dart
  typedef ProfileStats = ({
    int groupCount,
    int eventCount,
    List<CurrencySpend> spentByCurrency,
  });
  ```
- Accumulate into `Map<String, Decimal>` keyed by `group.currency`; add
  `balances.totalSpent` per group (NEVER across currencies):
  ```dart
  final spentMap = <String, Decimal>{};
  ...
  spentMap[group.currency] =
      (spentMap[group.currency] ?? Decimal.zero) + balances.totalSpent;
  ```
- Sort GCC-first, **identical rank rule** to `_sortedCurrencyBuckets`
  (`kSupportedCurrencies.indexOf`, off-list sorts last, tiebreak alpha). Keep
  only buckets with `amount != Decimal.zero` (a group with no expenses adds no
  line). Empty-groups / no-spend ⇒ `spentByCurrency: const []`.
- The `anyLoading` stay-loading guard updates: was
  `eventCount == 0 && totalSpent == Decimal.zero`; becomes
  `eventCount == 0 && spentMap.isEmpty`.

### Task 2 — render per-currency lines in the Spent cell

`lib/features/settings/screens/profile_screen.dart` (`_StatsGrid`, ~528)

- Build `valueWidget` from `stats.spentByCurrency`:
  - `length == 0` ⇒ one line, `RAmount(Decimal.zero, currency: 'OMR',
    showCurrency: false, size: 24)` (preserve today's zero look; no spend = no
    currency context).
  - `length == 1` ⇒ one line, `RAmount(value: amount, currency: cur,
    showCurrency: false, size: 24)` — same compact look as today but using the
    bucket's **own** currency precision (USD 2dp, JPY 0dp, OMR 3dp), not
    hardcoded OMR. Single currency is unambiguous so the code stays hidden
    (`showCurrency: false`; `RAmount` has no `showCode` prop — precision still
    follows `currency` even when the code is hidden, `r_amount.dart:50-57`).
  - `length >= 2` ⇒ a `Column` (`mainAxisSize.min`, end-aligned) of up to **2**
    `RAmount(value: amount, currency: cur, showCurrency: true, size: 15)` lines
    (code shown — disambiguates), and if `length > 2` a trailing small
    `+{N}` label where `N = length - 2`, styled like the card `sub`.
- Extract a small private `_SpentValue` widget (keeps `_StatsGrid.build` flat;
  ~200-400-line-file discipline).
- The `stats == null` branch (`value: '—'`) is unchanged.

### Task 3 — l10n for the overflow label

`lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb` (+ regenerate)

- `profileStatsSpentMore`: `"+{count}"` (placeholder `count`, type `int`),
  description "Overflow indicator on the Profile Spent stat when lifetime spend
  spans more than 2 currencies; shows how many additional currency lines are
  hidden." EN `+{count}`, AR `+{count}` (digit-only; app renders Western digits
  in 'ar' per existing notation policy).
- Regenerate via the existing l10n step; do not hand-edit `generated/`.

### Task 4 — tests

**Provider (unit)** — `test/unit/profile_stats_provider_test.dart`:
- Update existing 3 tests from `totalSpent` to `spentByCurrency`:
  - no groups ⇒ `spentByCurrency == const []`.
  - two OMR groups (10 + 10) ⇒ `spentByCurrency == [(currency:'OMR',
    amount:20.000)]` (same currency DOES sum — proves we bucket, not cross-sum).
- **NEW RED test (the bug):** group A `OMR 10`, group B `USD 10` ⇒
  `spentByCurrency == [(OMR,10.000),(USD,10.00)]` — two buckets, NEVER a single
  `20`. Assert order (OMR before USD per GCC rank) and that no entry equals 20.

**Widget** — `test/features/profile/profile_screen_test.dart` (the REAL
ProfileScreen widget test; NOT `test/features/settings/`). It already has a
`_statsData({groupCount, eventCount, Decimal? totalSpent})` helper (`:58-66`)
used in ~11 overrides, and STATS-03 (`:428-444`) asserts the Spent cell shows
`42.500`:
- Change `_statsData`'s param `Decimal? totalSpent` ⇒
  `List<CurrencySpend> spentByCurrency = const []`; the default keeps the ~8
  no-spent callers compiling untouched.
- The 3 `totalSpent: Decimal.parse('42.500')` callers (`:368/:398/:428`) ⇒
  `spentByCurrency: [(currency: 'OMR', amount: Decimal.parse('42.500'))]`.
  STATS-03's `42.500` text assertion still holds (single OMR bucket, 3dp).
- NEW cases:
  - single-currency USD ⇒ Spent cell shows the USD total at 2dp, one `RAmount`,
    code hidden.
  - 2-currency (OMR+USD) ⇒ two `RAmount`s, codes shown.
  - 3-currency ⇒ two `RAmount`s + `+1` overflow label.

**Ripple (compile-fix)** — the OTHER `ProfileStats`-constructing test sites.
Replace `totalSpent: Decimal.zero` with `spentByCurrency: const []` in:
- `test/features/auth/delete_account_tile_test.dart:46-49`
- `test/features/auth/sign_out_tile_test.dart:50`

**NOT touched:** `test/features/home/widgets_test.dart:141` — that
`totalSpent: Decimal.zero` is inside a **`groupBalancesProvider`** override
building a **`GroupBalances`** record (`balances`/`perEventBreakdown`/
`memberNames` fields). `GroupBalances.totalSpent` is unchanged; editing it would
break the override. (Gate R1 [P1] — original spec misfiled it.)

## Verification principles (run now)

1. **Callsite classification.** `spentByCurrency` is **INBOUND/display-only** —
   read by `_StatsGrid` to render; no write path. `profileStatsProvider` is a
   derived `Provider`, not persisted; `ProfileStats` is never serialized
   (`grep MoneySerializer`/`toFirestore` over it ⇒ none). No OUTBOUND callsite.
2. **Every concrete claim vs code.** Verified live: provider sum at
   `:69`; render at `profile_screen.dart:530-533` (`showCurrency:false`);
   consumers of `.totalSpent` = the render + 4 tests (grep'd, list above);
   `_sortedCurrencyBuckets`/`_accumulateBucket` exist at `group_balance_provider
   .dart:528/616`; `group.currency` is the per-group code (PR-1 immutable);
   `kSupportedCurrencies` is the GCC-first rank source.
3. **One read-path per write-path.** No write path. The only read is the cell;
   named and covered by Task 2 + widget tests.
4. **Enumerate fields from the type.** `ProfileStats` has exactly 3 fields
   (`groupCount`, `eventCount`, `totalSpent`); only `totalSpent` changes. The
   record is constructed in exactly 2 prod spots (provider's two `return
   AsyncValue.data` — the empty-groups branch and the final return) and **4**
   test sites, all enumerated in Task 4: `profile_stats_provider_test.dart`,
   `delete_account_tile_test.dart`, `sign_out_tile_test.dart`,
   `profile/profile_screen_test.dart`. NOTE: `home/widgets_test.dart:141` is a
   `GroupBalances` construction, NOT `ProfileStats` — excluded (Gate R1 fix).
   Distinguish by fields: `ProfileStats` = `{groupCount, eventCount, spent…}`;
   `GroupBalances` = `{balances, totalSpent, eventCount, perEventBreakdown, …}`.
5. **Data contract, exact.** `CurrencySpend = ({String currency, Decimal
   amount})`. `spentByCurrency`: sorted GCC-first, one entry per currency with
   nonzero spend, no FX cross-sum. Cell render rules per length (0/1/≥2) spelled
   out in Task 2. Overflow `N = length - 2`.
6. **Arithmetic decomposition.** `totalSpent` per group is
   `BalanceCalculator.calculateTotalExpenses(allExpenses)` (`group_balance_
   provider.dart:408`) — already a per-group, single-currency scalar (the group
   is one currency). Bucketing sums these **within** a currency only; it does
   not decompose or re-slice the per-group figure, so no remainder/rounding
   contract is touched. (Unlike `netBalance`, `totalSpent` folds no settlements
   — it's a gross sum, so summing same-currency group totals is exact.)
7. **Adversarial pass (orthogonal axis — identity/scope).** The fix is on the
   *currency* axis; exercise the *scope* axis: a user in 3 groups
   (OMR-with-spend, USD-with-spend, OMR-zero-spend) ⇒ buckets
   `[(OMR, sum of the two OMR groups), (USD, …)]` — the zero-OMR group folds
   into the OMR bucket (no phantom empty line), and OMR still ranks before USD.
   Also identity: `totalSpent` is gross group spend (all events), independent of
   *which* member the viewer is — so it does not change with `currentUserId`
   (unlike net balance). Confirmed: provider reads `balances.totalSpent`, never
   filters by uid.

## Out of scope
- The home hero / `crossGroupBalanceProvider` (already per-currency).
- #70 other OMR-display sites, #383 hero test backfill — separate issues.
- FX / any cross-currency single number (project rejects FX — #382).

## Files
- `lib/features/settings/providers/profile_stats_provider.dart` (logic)
- `lib/features/settings/screens/profile_screen.dart` (render)
- `lib/l10n/app_en.arb`, `app_ar.arb` (+ generated)
- `test/unit/profile_stats_provider_test.dart` (RED + updates)
- `test/features/profile/profile_screen_test.dart` (`_statsData` helper +
  STATS-03 + new single/2/3-currency render cases)
- `test/features/auth/delete_account_tile_test.dart`,
  `test/features/auth/sign_out_tile_test.dart` (compile-fix)
- NOT `home/widgets_test.dart` (that `totalSpent` is `GroupBalances`)
