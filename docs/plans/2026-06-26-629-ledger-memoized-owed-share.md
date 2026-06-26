# #629 — Memoize the ledger row's per-person owed share

**Date:** 2026-06-26
**Issue:** #629 (P2, perf, money, Gate-category — `model:opus-4.8`)
**Milestone:** 1.6.3 ("bounded ledger performance work")
**Branch:** `perf/629-ledger-memoized-owed-share`

## Problem (verified against live code)

`_ExpenseRow._userShare(expense)` re-runs `BalanceCalculator.allocateExpenseOwed(...)`
(sort keys + per-recipient `Decimal` divide/quantize + `MoneySerializer` subunit
round-trip) **per visible non-equal-split row, inside `build()`**
(`ledger_day_card.dart:333-346`). A category-chip tap is `setState(() => _categoryFilter = …)`
→ rebuilds `_Body` → every visible day card → every `_ExpenseRow` → `_userShare`
re-allocates; newly-revealed rows re-allocate on scroll.

`ledgerViewProvider` already runs `BalanceCalculator.calculateBalances`, which itself
calls `allocateExpenseOwed` **once per expense** (`expense_provider.dart:366`), but
discards the per-expense breakdown (only the accumulated net survives). So each row
recomputes math the memoized provider already produced and threw away.

Equal-split rows (the common case) are cheap arithmetic already and call NOTHING — the
waste is confined to shares/exact/percent rows.

## Fix

Have `ledgerViewProvider` expose a memoized per-expense owed map and thread the
relevant slice down to each row, turning the row's non-equal branch into a map lookup.
**Single-sourced math — the provider memo and the row both go through the same public
`allocateExpenseOwed`, so no oracle divergence and the row still renders byte-for-byte
what gets persisted (#591).** The server oracle `recomputeNet` is unaffected; this is
client display only.

### Why NOT capture it inside `calculateBalances`

`calculateBalances` is the cross-implementation ORACLE mirrored byte-for-byte by the TS
`recomputeNet`, and has 5+ Dart callers (event_recap, group_balance, etc.) that don't
need a breakdown. Changing its return shape adds risk and surface area to the most
sensitive money function. Instead, `ledgerViewProvider` does an **independent second
pass** over `expenses` calling the same pure `allocateExpenseOwed`. The "double call"
(once in calculateBalances, once in the memo pass) costs one extra O(expenses) Decimal
pass **per data-change**, which is memoized — versus the status quo of one pass
**per non-equal row per chip-tap per scroll**. Net win, zero oracle risk.

## Changes (4 files + 2 tests)

### 1. `lib/features/ledger/providers/ledger_view_provider.dart`
- Add `Map<String, Map<String, Decimal>> owedByExpenseId` to the `LedgerView` record
  typedef.
- Build it in the provider: iterate `expenses`; for each **non-equal-split** expense
  (predicate identical to `_ExpenseRow._isNonEqualSplit`: `splitMode != null &&
  splitMode != SplitMode.equally && splitDistribution != null &&
  splitDistribution.isNotEmpty`), key `expense.id` → `BalanceCalculator.allocateExpenseOwed(
  amount, splitMode, splitDistribution, scope, customSplitParticipants, payerId,
  participantIds: const <String>[], currency: expense.currency, onFallback: null)`.
  **Exact same arguments the row passes today** — a literal hoist, so equivalence is by
  construction (same pure inputs, same function).
  - `participantIds: const <String>[]` — the non-equal allocator gate ignores
    `participantIds` (allocates over `splitDistribution` keys), matching the row's
    current call. Documented in `allocateExpenseOwed`.
  - `onFallback: null` — display path; `calculateBalances`'s own closure already fires
    the Sentry telemetry, so the memo pass must stay silent (no double-fire).
- Equal-split expenses get NO entry (the row never reads the map for them).
- Return the new field in BOTH the `event == null` defensive branch (`const {}`) and the
  normal branch.

### 2. `lib/features/ledger/widgets/ledger_day_card.dart`
- `LedgerDayCard`: add `required Map<String, Map<String, Decimal>> owedByExpenseId`.
- `_buildRow`: pass `owedForExpense: owedByExpenseId[expense.id]` (nullable; non-null for
  non-equal expenses) into `_ExpenseRow`.
- `_ExpenseRow`: add `final Map<String, Decimal>? owedForExpense;`.
- `_userShare` non-equal branch: replace the inline `allocateExpenseOwed(...)` call with
  `final mine = owedForExpense?[currentParticipantId] ?? Decimal.zero;` then the
  unchanged signed reconstruction `(isPayer ? expense.amount : Decimal.zero) - mine`.
  - Null-safe `?? Decimal.zero` is defensive (graceful "no share line", never throws) —
    production always populates it for non-equal expenses; a desynced/empty map in a test
    makes the `findsNWidgets(2)` share assertion fail loudly.
- Equal-split branch + `_effectiveSplitIds` + `_isNonEqualSplit` helpers: **unchanged.**
- If `BalanceCalculator`/`allocateExpenseOwed` becomes an unused import in this file after
  the swap, drop it (analyzer will flag).

### 3. `lib/features/ledger/screens/ledger_screen.dart`
- `_Body.build`: read `final owedByExpenseId = data.owedByExpenseId;` (data already
  watched at :149) and pass `owedByExpenseId: owedByExpenseId` to `LedgerDayCard`
  (`:388`).

### 4. `lib/features/events/providers/event_recap_provider.dart` (read-only check)
- It `ref.watch(ledgerViewProvider(...))` and destructures specific fields — adding a
  record field is additive and does not break it. **Verify** it doesn't pattern-match the
  full record shape (it reads named fields, so it's safe). No change expected.

### Tests

**5. NEW `test/features/ledger/ledger_view_owed_memo_test.dart`** (RED first):
- Build `ledgerViewProvider` (ProviderContainer, override the four watched streams with
  fixtures: one shares split, one exact split, one percent split, one equal/global split).
- Assert `view.owedByExpenseId.keys` == the three non-equal expense ids exactly (NO entry
  for the equal-split expense — pins the "equal stays cheap" boundary).
- For each non-equal expense, assert `view.owedByExpenseId[id]` deep-equals
  `BalanceCalculator.allocateExpenseOwed(... same args ...)` (single-source equivalence).

**6. UPDATE `test/features/ledger/ledger_split_ways_test.dart`**:
- `pumpRow` helper computes `owedByExpenseId` the same way the provider does (mirror) and
  passes it to `LedgerDayCard`. The existing #591 non-equal assertions
  (`findsNWidgets(2)` + signed `RAmount(sign:true, value:…)`) then prove end-to-end that
  the row renders the identical signed share **sourced from the threaded map**.

**7. `test/features/ledger/ledger_filter_recompute_test.dart`** (#106): unchanged; must
still pass. The owed memo lives in the same provider pass, so the existing
"chip-tap does not re-enter calculateBalances" guard transitively covers it.

## Done state

- [ ] `view.owedByExpenseId` memoizes exactly the non-equal-split expenses' owed maps.
- [ ] Row's non-equal branch is a map lookup; no `allocateExpenseOwed` call in `build()`.
- [ ] #591 row-share tests still green (identical rendered share, now from the map).
- [ ] #106 filter-recompute test still green.
- [ ] `flutter analyze` clean; full `flutter test` green.
- [ ] Equal-split path and the oracle `calculateBalances`/`recomputeNet` untouched.

## Verification principles (run while authoring)

1. **Classify every callsite (INBOUND/OUTBOUND/BOTH).** `owedByExpenseId` is **INBOUND /
   display-only** — it feeds the row's signed-share text and nothing else. It is NEVER
   read by a write path, `recomputeNet`, or `firestore.rules`. No OUTBOUND use.
2. **Verify every concrete claim against code.** Done: `expense_provider.dart:366`
   (calculateBalances calls allocateExpenseOwed per expense), `ledger_day_card.dart:333`
   (row re-calls it), `ledger_view_provider.dart:51-178` (record shape), `ledger_screen.dart:149,388`
   (single call site). Paths/lines confirmed by Read this session.
3. **Trace one read-path per write-path.** Write-path = the provider memo loop. Read-path =
   `_userShare` non-equal branch → `RAmount(sign:true)`. Named, single reader.
4. **Enumerate fields from the type.** `LedgerView` typedef fully enumerated (6 existing
   fields + 1 new). The defensive `event==null` branch must also return the new field.
5. **Spell out the data contract.** `owedByExpenseId: Map<expenseId, Map<uid, grossOwed>>`,
   populated only for non-equal-split expenses; `allocateExpenseOwed` args = the literal
   set the row passes today (`participantIds: const []`, `onFallback: null`,
   `currency: expense.currency`).
6. **Verify arithmetic decomposition.** N/A to a fold — this exposes the SAME per-expense
   gross owed already computed inside `calculateBalances`; the row reconstructs the signed
   figure exactly as before (`(isPayer? amount : 0) - mine`). No new arithmetic.
7. **Adversarial pass on an orthogonal axis (currency).** Multi-currency: the memo passes
   `expense.currency` per expense (fenced internally by `allocateExpenseOwed`), identical
   to the row's current behavior — a JPY (×1) expense and an OMR (×1000) expense in the
   same event each memoize in their own currency precision. No cross-currency sum (the map
   is per-expense, never aggregated). Equal-split JPY rows still take the cheap branch.

## Gate

Gate-category (money read-path + a record-field data-shape change with read+write paths).
Run `/run-the-gate` (fresh-context Opus) on this plan before implementation; apply [P1]s;
re-run with a new subagent until clean. Then TDD implement, `flutter analyze` + `flutter
test`, and ship via `/automerge` (which re-reviews Gate-category diffs).
