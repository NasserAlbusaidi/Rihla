# R&D: Multi-currency via per-expense buckets (no FX)

**Date:** 2026-06-08
**Status:** R&D / exploration — NOT a spec, NOT scheduled. No code until this becomes a Gate-reviewed plan.
**Relates to:** #61 (OMR-only / aggregation is currency-blind), #261 Model A (one-currency-per-group, deployed `edd6421`), `docs/plans/2026-06-08-multi-currency-phase2.md` (the in-flight single-currency picker — ships first, untouched by this).
**Session:** office-hours builder mode.

---

## The instinct that started it

> Group default currency, creator overrides per event. A Dubai trip in an Oman group is AED.
> At settle-up, snapshot 1 OMR↔AED and show Gemini *one combined number* (1.4 OMR + 41 AED → OMR).

The combined-number idea (FX) was rejected — see "Why no FX". The instinct behind it (don't make settling feel like paying two separate bills) is kept and solved without FX.

## What we landed on

**Per-expense currency, mixed-currency events, per-currency buckets everywhere, zero FX.**

Test case that drove it: a Muscat → Sohar → Shinas → Dubai road trip is **one trip in your head** (one event), but OMR for the drive and AED once you cross the border. Currency-per-*event* would force splitting one real trip into two events. Currency-per-*expense* matches reality.

Three decisions:
- **D1 → currency lives on the expense.** (Started at per-event; the road-trip example broke it. Per-event is just per-expense with a "whole event is one currency" constraint, so this is the more general model and per-event remains a possible first step / fallback.)
- **D2 → "one gesture" stepped settle.** Tap "Settle up with Gemini" once → the app walks each currency bucket ("Pay 1.4 OMR" → "Pay 41 AED" → done), recording N currency-correct settlements. Feels like one act; never invents a rate. This is the honest version of the combined-number instinct.
- **D3 → home hero shows explicit per-currency lines.** "Owed 5 OMR · You owe 41 AED." Single-currency users (the 95%) still see one line. On a money surface, explicit beats clever — never hide a currency behind a tap.

## What makes it good

The "one gesture, two honest records" settle flow. It gives the *feeling* the user wanted (settle Gemini in one move) while every stored settlement is currency-correct and rule-validated on its own. No exchange-rate liability, no conservation break, no lost original-currency obligation.

## Premises (confirmed)

1. **Reverses #261 PR-1.** Live `currencyMatchesGroup` + currency-immutable rules get relaxed. Knowingly reopening a Gate-category rules surface we just closed.
2. **The picker is the easy 10%; currency-aware aggregation is the 90%.** `paidMap`/`owedMap`/`netBalance` (`expense_provider.dart:313–443`) bucket by currency, and *every* reader changes with it — hero, settle-up optimizer, ledger, **and the server parity mirror** `groupNetBalance.ts recomputeNet` (deleteGroup/leaveGroup/removeMember oracle). Client + server in lockstep. This is the #61 blocker, not wiring.
3. **No FX in the ledger, ever.** No rate fetch, no combined number, sealed buckets, per-currency simplification.
4. **Post-1.0, separate from the in-flight Phase 2.** Model A single-currency picker ships first. This is a later feature with its own Gate.
5. **Per-expense grain (P5 corrected).** Currency is an expense property; an event may be mixed. Costs bucketing *within* events + a fat-finger guard, but reuses #47 and simplifies the rule.

## Why no FX (the rejected "crazy" half)

- **Snapshot-when?** Rate-at-settle means the number changes by *when* you open the screen. Debt didn't move; display did → reads as a bug.
- **Conservation breaks.** `sum(shares)==amount` + remainder-to-alphabetically-last assume one currency. Convert per-slice + round and the parts stop summing to the whole, and A's "you owe me X" stops equalling B's "I owe you X".
- **Append-only audit loses info.** Settlements are append-only (B3). Recording "41 AED = 5.42 OMR" destroys the dirham obligation → ledger lies on dispute. Storing original+converted+rate+timestamp is a schema expansion.
- **Offline-first regression.** A live FX fetch that fails offline means settle-up can't compute. Violates the SDK-offline contract.
- **Trust/legal smell.** Display a rate + "pay this OMR amount" and you own the rate. Splitwise deliberately holds balances per-currency and never auto-converts. That's risk avoidance, not laziness.

If FX ever returns, it must be an **optional, manual, human-agreed-rate, both-amounts-stored** layer on top — the app records what people agreed, it never brokers.

## Approaches considered

- **A — per-event currency (constrained).** New `Event.currency`, immutable once funded; rule `expense.currency == event.currency`; only cross-event rollup + hero + settle bucket. Lower risk, ships sooner. Cost: splits one real trip into two events; new field + rules. *A = B with a uniformity constraint.*
- **B — per-expense currency (mixed events). ← chosen.** Currency stays on the expense (already there); rule relaxes to `validCurrency` (already exists); buckets at *every* level incl. within-event; server `recomputeNet` parity + a fat-finger guard are the hard parts. Matches the user's actual travel; reuses #47; deletes rules complexity vs A. Biggest Gate.
- **C — punt (second group per currency).** Keep Model A; Dubai = a new AED group. Zero new work but duplicated roster, split balances, no unified "what does Gemini owe me," and one trip spans two groups. Doesn't solve the example.

**Chosen: B**, with **A available as a lower-risk first step** (ship the constrained version, relax the uniformity constraint later — same bucketing engine).

## Open questions a future Gate-spec must resolve

1. **`calculateBalances` return shape.** `List<UserBalance>` → `Map<String currency, List<UserBalance>>` (cleaner) vs UserBalance-carries-currency with multiple rows per user. Every caller changes. This is *the* refactor.
2. **Server parity, per-currency.** A group is deletable only if **every** currency bucket nets to zero. `recomputeNet` + the deleteGroup gate + `delete_group_balance_parity_test.dart` grow a currency dimension; re-establish the byte-for-byte oracle parity per bucket.
3. **Gate sequencing of the rules reversal.** `currencyMatchesGroup` → `validCurrency`. No real users yet, so deploy freely (per the "no clients" override) — but it's still a Gate-category rules change.
4. **Fat-finger guard.** One mis-tagged expense = a phantom 1-line bucket. Mitigation: smart default (event's most-recent / dominant currency), clear per-row currency display, soft warning when an expense's currency differs from the rest of its event.
5. **Add-expense currency default.** Likely: last currency used in this event → group default. (Avoid device-locale surprises.)
6. **"One gesture" settle data model.** N append-only settlements, each currency-correct; pure client orchestration; bump `ledgerRevisionProvider` after each (home-staleness trap, #104/#233); handle partial completion (OMR recorded, app dies before AED).
7. **Hero/once-providers per-currency.** `crossGroupBalanceOnceProvider` + the #244 wrapper types (`CrossGroupBalanceOnce`) grow a currency dimension. Do **not** reopen the O(G×E) listener leak (don't point home at the live providers).
8. **"Currencies don't net" UX.** The min-transactions optimizer runs per bucket; AED can't cancel OMR. Needs a one-time explainer or users file "simplify is broken."
9. **Event "total spent" header.** Per-currency subtotals or omit a single total. `RAmount` is already per-expense-currency-correct.
10. **leaveGroup / removeMember gates.** "leaver net == 0" becomes "leaver net == 0 in every currency."

## Spike results (2026-06-08) — `calculateBalances` → `Map<currency, List<UserBalance>>`

Method: throwaway worktree off `main`. Changed only the `calculateBalances` return type (`List<UserBalance>` → `Map<String, List<UserBalance>>`), wrapped the body in a single `{'OMR': …}` bucket so the function compiles, ran `flutter analyze`. The compiler then enumerated every consumer. Worktree + branch discarded; `main` untouched.

**Headline: the production blast radius is tiny and contained. The cost is in tests and the rollup fold, not in risky prod code.**

`flutter analyze`: **116 errors — 6 in `lib/`, 110 in `test/`, 0 warnings.**

### Production (lib/) — ring 1: 6 sites, 4 files
| Site | What it needs |
|---|---|
| `group_balance_provider.dart:319` (live fold) | **The core change.** `for (balance in eventBalances)` → iterate per-currency; `GroupBalances` grows a currency dimension. |
| `group_balance_provider.dart:464` (once-path fold) | Same change; factor a shared per-currency fold helper. |
| `expense_provider.dart:150` | `eventBalancesProvider` type `AsyncValue<List<…>>` → `AsyncValue<Map<…>>`. |
| `ledger_view_provider.dart:172` | `LedgerView.balances` field List → Map; ledger screen picks/iterates buckets. |
| `settle_up_screen.dart:195,:203` | Call the optimizer **once per currency bucket**, render per-currency settle sections (this is the D2 stepped-settle surface). |

**Key win: `calculateOptimalSettlements` (the greedy min-transactions optimizer) did NOT error.** It already takes a `List<UserBalance>`, so you call it per-bucket and it works unchanged — the "no cross-currency netting" model falls out for free.

### Production — ring 2 (NOT measured by this spike)
The spike changed only `calculateBalances`, so consumers of `GroupBalances` weren't flagged. Changing `GroupBalances` to bucket triggers a second wave in the hero/UI: `balance_hero_card.dart`, `home_screen.dart`, `profile_stats_provider.dart`, `settle_up_page_body.dart`, `group_settle_up_screen.dart`, `event_command_center.dart`. This is the D3 per-currency-hero rendering — real UI work, mechanical-ish.

### Tests — 6 suites, ~110 sites (the bulk of the labor)
`balance_calculations_test` (53), `issue_195_exact_split_renormalize_boundary` (33), `delete_group_balance_parity` (17), `split_rounding` (5), `settlement_optimization` (1), `issue_250_split_fallback_telemetry` (1). All mechanical: `calculateBalances(...).firstWhere(...)` → `calculateBalances(...)['OMR']!.firstWhere(...)`. Voluminous, low-risk.

### Server (TS) — separate compile, ~4 files
`groupNetBalance.ts recomputeNet` already builds a single currency-blind `net = Map<uid, Decimal>` plus a `currencies` Set used only to *detect/reject* mixing (the #261 PR-0b guard). Bucketing = `net` → `Map<currency, Map<uid, Decimal>>`, `addNet` keys by currency, **drop the mixed-currency guard**. The 3 gate callers (`deleteGroup.ts:254`, `leaveGroup.ts:86`, `removeMember.ts:123`) check "every bucket nets zero" instead of one map. Allocators (`allocateExact/Shares/Percent`) need NO change — already per-expense-currency (#270). `delete_group_balance_parity_test` grows a currency dimension.

### Sizing verdict
- **Shallow-but-wide.** Prod logic change is ~6 Dart sites + ~4 TS files. The optimizer is free. The labor is ~110 test edits + the D3 hero UI + the per-currency parity test.
- **The one Gate-delicate spot:** keeping the Dart `computeGroupBalances` per-currency fold byte-for-byte in parity with the TS `recomputeNet` per-currency fold (the oracle contract). Everything else is mechanical.
- The type system contains the change — flipping the return type surfaces 100% of the Dart consumers at compile time, so there's no "silent currency-blind site we forgot" risk once it compiles green.

## Migration

Trivial. All existing money is OMR (1.0 OMR-only), so every legacy balance is a clean single `{OMR: …}` bucket. No data migration; clean rollout.

## Distribution

In-app feature on the existing Flutter / Play pipeline. No new distribution.

## The assignment (next real-world step)

Before any Gate-spec: **a throwaway spike on the `calculateBalances` return-shape change** (open question #1) to feel the true blast radius across callers + the server oracle. Per-expense buckets reuse more than they look (#47, existing `expense.currency`, existing `validCurrency`), but #1 and #2 are where the cost actually lives. Size those two and the rest of the spec writes itself.

## What I noticed

- You reached for FX first ("truly crazy"). The interesting move wasn't building it — it was keeping the *feeling* it was chasing (D2's one gesture) and dropping the liability. Good product instinct, separable from a bad mechanism.
- You clicked "event-grain holds" and then immediately described a road trip that breaks it. The example was more honest than the answer. That's exactly what the premise pass is for — trust the example.
