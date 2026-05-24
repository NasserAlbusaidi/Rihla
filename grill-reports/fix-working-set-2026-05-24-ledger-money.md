# Fix Working Set — ledger / money — 2026-05-24

> Authorized 2026-05-24 from `grill-reports/ledger-money-2026-05-23.md` by `/fix-my-code`.
> Mode: foreground, --non-interactive (auto-approve at Gate 2 `go`, between-fixes `next`).
> Multi-currency cluster DEFERred as a coherent post-v1.2 design, not nine spot fixes.

## FIX (user conceded) — 8

### [1] CRITICAL #3 — BalanceCalculator filter isDeleted
- Location: `lib/features/ledger/providers/expense_provider.dart:175-315`
- Principle: Trust boundary violation — pure money function trusts caller to pre-filter deleted rows.
- Test: `test/unit/balance_calculations_test.dart` (extend existing file).

### [2] CRITICAL #4 — UserBalance.totalPaid fold settlements
- Location: `lib/features/ledger/providers/expense_provider.dart:278-305`
- Principle: Naming that misleads — `totalPaid` excludes settlements while `netBalance` folds them.
- Approach: fold (semantics change — `SettlementSummaryCard` 'Total paid' tile now means lifetime paid incl. settlements).
- Test: `test/unit/balance_calculations_test.dart`.

### [3] HIGH #10 — `_persistedInt` validate or rename
- Locations: `lib/features/ledger/models/expense_model.dart:357-362`, `lib/core/services/cache/expense_cache_repository.dart:164-168`.
- Principle: Fail-silent truncation; two duplicate copies; named like a guarantee but truncates.
- Test: extend `test/unit/expense_cache_repository_test.dart` or a new unit test for the model helper.

### [4] HIGH #11 — `_allocateExact` remove silent fallback
- Location: `lib/features/ledger/providers/expense_provider.dart:336-353`
- Principle: Money-math fail-silent — `debugPrint` only signal; rewrites user's distribution.
- Test: `test/unit/balance_calculations_test.dart` — dispatch a distribution that sums off-tolerance, assert throw.

### [5] HIGH #13 — `OptimalSettlement` struct
- Location: `lib/features/ledger/providers/expense_provider.dart:428-476`, callsites `lib/features/ledger/widgets/settlement_tile.dart:76-78`, `lib/features/ledger/screens/settle_up_screen.dart:215-225`.
- Principle: `Map<String, dynamic>` smuggles `Decimal` past type system; non-null casts on nullable resolved names.
- Note: 3-file scope — at fix-my-code boundary, may need split-into-2-PRs if Gate 3 trips.
- Test: `test/unit/balance_calculations_test.dart` — assert struct shape and non-null behavior under unresolved-name path.

### [6] HIGH #15 — Sort tiebreaker on participantId
- Location: `lib/features/ledger/providers/expense_provider.dart:437-438`
- Principle: Non-determinism — `List.sort` not stable; equal-balance debtors flip order across rebuilds.
- Test: `test/unit/balance_calculations_test.dart` — two equal-balance debtors, two consecutive calls, assert identical pair output.

### [7] HIGH #16 — `_allocateExact` run `_toOmaniPrecision`
- Location: `lib/features/ledger/providers/expense_provider.dart:336-353`
- Principle: Broken invariant — exact bypasses precision normalization unlike weighted/percent.
- Test: `test/unit/balance_calculations_test.dart` — persist sub-fils exact split, assert sum-of-persisted-subunits == amount-in-subunits.

### [8] HIGH #17 — `_allocatePercent` distribute slack
- Location: `lib/features/ledger/providers/expense_provider.dart:374-398`
- Principle: Same person always absorbs rounding for percent splits; user-typed percentages get rewritten.
- Approach: distribute (slack split proportionally across all recipients).
- Test: `test/unit/balance_calculations_test.dart` — Charlie 33% / Bob 33% / Alice 34.001%, assert all three close to declared share.

## DEFER (out of scope) — 9 (multi-currency cluster)

Reason for all 9: v1.2 launch is OMR-only by product decision. Multi-currency needs one
coherent design (event-currency single source of truth, every screen/service reading
from it, `MoneySerializer` scoped by event-currency not call-site literal) — not nine
spot fixes. Follow-up via `/grill-my-plan`.

- CRITICAL #1 — `Settlement.toFirestore` hardcodes `'OMR'`
- CRITICAL #2 — `Settlement` model has no `currency` field (round-trip drops it)
- CRITICAL #5 — `ExpenseCacheRepository._decodeSplitValue` hardcodes `'OMR'`
- HIGH #6 — `add_expense_screen._tripCurrency => 'OMR'`
- HIGH #7 — `expense_editor_body._tripCurrency => 'OMR'`
- HIGH #8 — `EditExpenseScreen._save` doesn't pass currency to updateExpense
- HIGH #9 — `settle_up_screen` hardcodes `'OMR'` at 3 callsites
- HIGH #12 — `SettlementCacheRepository.cacheSettlements` writes no currency column
- HIGH #14 — `_splitTolerance = 0.001` is currency-blind

## NOT TRIAGED — 12 MEDIUM + 8 NITPICK

Per protocol, MEDIUM and NITPICK not auto-promoted in mini-grill triage.
Review separately if launch timeline permits.
