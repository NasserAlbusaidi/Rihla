# #70 — all-settled cross-group hero hardcodes OMR for non-OMR users

**Status:** Gate PASSED (fresh-context Opus, 0 P1s; 3 P2s folded in below)
**Issue:** #70 (the single remaining LIVE defect; the rest of #70 is dead code → #379)
**Date:** 2026-06-08

## Problem (verified against code @ `0ce20a20`)

`BalanceHeroCard` renders the cross-group balance from `crossGroupBalanceOnceProvider`
(`CrossGroupBalance.byCurrency`). `_sortedCurrencyBuckets`
(`group_balance_provider.dart:526`) drops every zero-activity currency, so a
**fully-settled** user (or a user with **no groups**) gets `byCurrency == []`.

`_LoadedCard` (`balance_hero_card.dart:98`) handles the empty list by rendering
`_CurrencyBlock(bucket: null)`, where `currency = b?.currency ?? 'OMR'` (`:163`).
That hardcoded `'OMR'` then drives:

- the big net `RAmount(value: 0, currency: 'OMR', showCurrency: false)` (`:197`) →
  precision `0.000` (3dp), code hidden.
- the two legend `_LegendLine` `RAmount`s (`:391`) — `showCurrency` **defaults
  `true`** → render literal **`OMR 0.000`**.

**A settled USD user sees `0.000` and `OMR 0.000 / OMR 0.000` in the legend** —
wrong precision and a wrong, *visible* currency code. Reachable since the currency
picker shipped (#377). INBOUND/display-only — no write path, no money math, no
persisted schema.

Active-balance rendering is already correct: a non-empty bucket carries its own
`currency`, threaded into `RAmount`/`formatCurrency` with `currencyConfig[currency]`
precision. The bug is **only** the `bucket == null` (settled / no-groups) path.

## Decision (user-approved)

Show the user's **single distinct group currency** in the settled state; if they
have **zero groups or ≥2 distinct currencies**, render a **currency-agnostic**
zero (no code, 2dp).

| User state (settled) | Today (bug) | After |
|---|---|---|
| 1 OMR group | `0.000`, legend `OMR 0.000` | **unchanged** `0.000`, `OMR 0.000` |
| 1 USD group | `0.000`, legend `OMR 0.000` | `0.00`, legend `USD 0.00` |
| OMR + EUR groups | `0.000`, legend `OMR 0.000` | code-less `0.00` |
| no groups | `0.000`, legend `OMR 0.000` | code-less `0.00` |

Rejected alternatives:
- **Agnostic-everywhere** (drop the code for all settled states incl. OMR):
  smaller diff but regresses the existing OMR look `0.000`→`0` and changes Test 3.
- **Minimal (suppress only the code):** leaves the `0.000` 3dp cosmetic leak for
  USD. Half-measure.
- **Provider record field on `CrossGroupBalance`:** cohesive but a required-field
  record change blasts ~10 test construction helpers. The dedicated provider below
  has a far smaller blast radius and keeps every existing (OMR) literal untouched.

## The fix

### 1. New `settledDisplayCurrencyProvider` (`group_balance_provider.dart`)

```dart
/// #70: the currency for the cross-group ALL-SETTLED hero state — the user's
/// single distinct group currency, or null when they have zero groups or groups
/// spanning MULTIPLE currencies (no single currency is honest → the hero renders
/// a currency-agnostic zero). Used ONLY for the settled/empty render; an active
/// balance carries its own per-currency bucket.
final settledDisplayCurrencyProvider = Provider<String?>((ref) {
  final groups = ref.watch(userGroupsProvider).valueOrNull;
  if (groups == null || groups.isEmpty) return null;
  final distinct = groups.map((g) => g.currency).toSet();
  return distinct.length == 1 ? distinct.single : null;
});
```

Reads `userGroupsProvider` (`group_provider.dart:418`, `StreamProvider<List<Group>>`)
— the same groups source the once-provider awaits, so it cannot meaningfully
disagree. Returns null while groups load (hero is showing the skeleton then anyway).

### 2. Thread it into the settled render (`balance_hero_card.dart`)

- `BalanceHeroCard.build`: `final settledCurrency = ref.watch(settledDisplayCurrencyProvider);`
  pass into `_LoadedCard(settledCurrency: …)`.
- `_LoadedCard`: new `final String? settledCurrency;`; pass into the empty-branch
  `_CurrencyBlock(bucket: null, showCode: false, settledCurrency: settledCurrency)`.
  (The non-empty branch passes `settledCurrency: null` — unused there.)
- `_CurrencyBlock`: new `final String? settledCurrency;`. Derive:
  ```dart
  final resolved = bucket?.currency ?? settledCurrency;   // String?
  final currencyForPrecision = resolved ?? '';            // '' → RAmount 2dp default
  final showLegendCode = resolved != null;                // false ⇒ agnostic, no code
  ```
  - big `RAmount`: `currency: currencyForPrecision` (unchanged `showCurrency: false`).
  - `_SplitLegend`: pass `currency: currencyForPrecision` and a new
    `showCode: showLegendCode`.
- `_SplitLegend` + `_LegendLine`: add `final bool showCode;`, forward to the
  legend `RAmount` as `showCurrency: showCode`.

For an **active** bucket (`bucket != null`): `resolved = bucket.currency`,
`showLegendCode = true` → identical to today (OMR `OMR X.XXX`, USD `USD X.XX`). No
behavior change on any active path.

`currencyForPrecision == ''` ⇒ `currencyConfig['']` is null ⇒ `?? 2` ⇒ 2dp, and
`showCurrency:false`/`showCode:false` ⇒ no code → the agnostic `0.00`.

## Files touched

- `lib/features/groups/providers/group_balance_provider.dart` (+ ~10 lines: 1 provider)
- `lib/features/home/widgets/balance_hero_card.dart` (thread `settledCurrency` +
  `showCode`; ~12 lines across `_LoadedCard`/`_CurrencyBlock`/`_SplitLegend`/`_LegendLine`)
- `test/features/home/balance_hero_card_test.dart` (refactor `buildTestWidget` to
  accept `List<Group> groups = const []`; update Test 3 to pass an OMR group; add 2
  new tests)
- `test/unit/` new small unit test for `settledDisplayCurrencyProvider` (0/1/≥2 distinct)

## Tests (RED first)

**Gate [P2]: the balance must still come from the stubbed `crossGroupBalanceProvider`;
`userGroupsProvider` feeds ONLY the new `settledDisplayCurrencyProvider`.** The
`buildTestWidget` bridge (`:76`) returns a never-completing `Completer.future` via
`orElse` unless `crossGroupBalanceProvider` resolves to `data` — so every settled
test MUST override it to `AsyncValue.data(_omr('0', …))`. The USD group does NOT
drive the balance (that would fan out to the real, unstubbed `groupBalancesProvider`
→ skeleton hang); it only sets the settled currency.

**Gate [P2]: `buildTestWidget` parametrizes the existing `userGroupsProvider`
override** — change line 69 to `userGroupsProvider.overrideWith((ref) =>
Stream.value(groups))` with a new `List<Group> groups = const []` param. Do NOT stack
a second override (Riverpod last-wins works but is implicit). Tests 1/2/6 keep the
default `const []` (Test 6 depends on empty groups). 

1. **RED (widget, e2e):** `crossGroupBalanceProvider → AsyncValue.data(_omr('0'))`
   (settled) + `groups: [USD group]`. On `main` the hero shows `OMR 0.000`
   (`find.textContaining('OMR')` findsNothing → **FAILS**). After fix: `USD 0.00`,
   no `OMR`, no `0.000`. Proves provider→widget chain (balance stays stubbed).
2. Settled + `groups: [OMR group, USD group]` (2 distinct) → code-less `0.00`, no
   currency code, no `0.000`.
3. Existing **Test 3** (OMR settled) → pass `groups: [OMR group]` → keeps `0.000`
   + `OMR` (regression lock that the OMR look is byte-identical).
4. Unit: `settledDisplayCurrencyProvider` returns `'USD'` for [USD], `'OMR'` for
   [OMR,OMR], `null` for [] and for [OMR,USD].

`_SplitLegend.showCode` / `_LegendLine.showCode` are **`required`** (no implicit
default — an active bucket must always pass `true` so its legend code keeps showing).

## Verification principles

1. **Callsite classification:** every touched site is INBOUND (display only). No
   OUTBOUND/write path touches this — `settledCurrency` is never persisted.
2. **Code-not-docs:** all line numbers/fields re-verified against `0ce20a20` this
   session (provider drop logic `:526`, fallback `:163`, legend default `showCurrency:true`).
3. **Read-path per write-path:** N/A — no write path. The only reader of the new
   provider is `BalanceHeroCard`.
4. **Enumerate from the type:** `CrossGroupBalance` is **unchanged** (deliberately —
   avoids the record-field blast radius); the new currency is a *separate* signal.
5. **Data contract:** `settledDisplayCurrencyProvider : Provider<String?>`; null ⇒
   agnostic. `_CurrencyBlock.settledCurrency : String?`; `_SplitLegend.showCode : bool`.
6. **Arithmetic decomposition:** N/A — the value is exactly zero in every settled
   path; only precision/code formatting changes.
7. **Adversarial (orthogonal axis):** the fix is on the *currency* axis; the
   regression lock (Test 3, OMR unchanged) exercises the *identity-preservation*
   axis — proving non-OMR users get the fix while OMR users see zero change.

## Out of scope (→ #379, dead code)

- `event_card.dart` (4 hardcoded-OMR sites) — `EventCard` has 0 `lib/` callers;
  #379 deletes the file.
- `formatOMR` (`formatters.dart:28`) + its tests + `lib/core/README.md` mention —
  0 production callers; folds into #379's dead-code sweep.
- `event_command_center.dart:83` / `profile_screen.dart:559` `?? 'OMR'` — verified
  INTENTIONAL load/empty-state fallbacks (feed currency-aware widgets / `showCurrency:false`).
  No action.
- `profileStatsProvider` (`_sortedSpendBuckets`) — the nearest structural twin; it
  also drops zero buckets but its empty state renders NO amount widget (a "no spend"
  empty state, not a `0.00`), so it has no hardcoded-OMR zero-render path. Already
  per-group-currency-bucketed (#378). Verified unaffected.
