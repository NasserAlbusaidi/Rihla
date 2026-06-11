# #382 PR-0 — Settlement model retains `currency`

**Issue:** #382 (multi-currency per-expense buckets, post-1.0). This is PR-0 of the 7-PR ladder in the issue body — the smallest standalone rung.
**Gate category:** yes — `models/**` schema-adjacent change with a read-path and an (existing, untouched) write-path.
**Base:** `origin/main` @ `fdf8460b`, worktree `../Rihla-382`, branch `feat/382-pr0-settlement-currency`.

## Why

`Settlement.fromFirestore` (`lib/features/ledger/models/settlement_model.dart:94-131`) reads the persisted `currency` field at `:99-102` (with the #193/#220 fence: unsupported → OMR), uses it to deserialize `amountFils` at the correct scale (`:118`) — then **drops it**. The model has no `currency` field, so every settlement display surface threads the *group's* currency in from outside (`ledger_search_sheet.dart:483-484` documents this explicitly). Expenses already do the right thing: `Expense` retains `_currency` (`expense_model.dart:67,:186,:246`) and `_ExpenseHit.currency => expense.currency` (`ledger_search_sheet.dart:467`).

PR-0 makes `Settlement` mirror `Expense`: retain the per-doc currency, and switch recorded-settlement display sites from threaded group currency to `settlement.currency`. This unblocks PR-1/PR-2 (settlement folding buckets by per-doc currency) without touching any fold.

## Field semantics (the data contract)

`Settlement.currency` = **the fence-validated currency the amount was deserialized with**, i.e. exactly the `currency` local at `settlement_model.dart:100-102`:
- supported code present → stored as-is (including a lowercase `'omr'` — rules reject non-canonical codes on write via `validCurrency` (`firestore.rules:75-77`, uppercase-only allow-list), so lowercase exists only in forged/test docs; storing as-is maximizes parallelism with the expense pattern, which also stores raw. Display lookups (`r_amount.dart:85`, `formatters.dart:40-42`) are case-sensitive, so a forged lowercase doc would render the literal `omr` prefix — canonicalization is enforced by rules at write, not by display. Gate R1 P3, accepted.)
- missing or unsupported → `'OMR'` (matching the scale actually used at `:118` — the label can never disagree with the scale)

Constructor default: `'OMR'` (matches `Expense`'s default at `expense_model.dart:92`; keeps all existing constructor callsites compiling — in `lib/` there are **no** direct `Settlement(...)` constructor calls outside the model's own factories; tests construct it widely and inherit the default).

`fromJson` (legacy Supabase shape, `:48-77`): not changed — inherits the `'OMR'` default. `toJson` (`:79-88`, legacy): not changed; the Firestore write path is `settlement_service.dart`/`group_settlement_service.dart`, which already persist `currency` (`settlement_service.dart:99`, `group_settlement_service.dart:84`).

## Why this is behavior-identical on real data

Non-OMR groups only became creatable with the #377 currency picker, which post-dates #376 (threading `group.currency` into both settlement write paths). Therefore in prod:
- every settlement doc in a non-OMR group carries `currency == group.currency` (written post-#376), and
- docs missing the field exist only in OMR groups → fence fallback `'OMR'` == group currency.

So `settlement.currency` == the currency currently threaded from the group, for every real doc. The switch is observable only for forged docs — where it is *more* correct (label matches deserialization scale).

## Changes (lib/) — 5 files

1. **`lib/features/ledger/models/settlement_model.dart`**
   - Add `final String currency;` + constructor param `this.currency = 'OMR'`.
   - `fromFirestore` passes `currency: currency` (the fenced local from `:100-102`).

2. **`lib/features/ledger/widgets/ledger_search_sheet.dart`**
   - `_SettlementHit` (`:472-507`): drop the `_currency` field, the `currency` constructor param, and the `#261` comment at `:483-484`; `currency => settlement.currency` (mirrors `_ExpenseHit:467`).
   - Dead-param chain removal, compiler-driven: `_filter`'s `currency` param (`:515`, sole use `:555`), the sheet widget's `currency` field (`:59,:69`) and its use (`:108`), `showLedgerSearchSheet`'s `currency` param (`:30,:46`), and `debugFilter`'s pass-through (`:562+`) if present.

3. **`lib/features/ledger/screens/ledger_screen.dart`**
   - Drop `currency: currency` args to `showLedgerSearchSheet` (`:261`) and `LedgerDayCard` (`:337`).

4. **`lib/features/ledger/widgets/ledger_day_card.dart`**
   - `:172`: `currency: currency` → `currency: settlement.currency` (arg to `LedgerSettleRow`).
   - `LedgerDayCard.currency` param (`:96,:107`) becomes dead → remove.
   - **`LedgerSettleRow` keeps its `currency` param** (`:369,:376,:431`) — it is a leaf that receives unbundled fields, not the `Settlement` object.

5. **`lib/features/groups/widgets/settle_up_page_body.dart`**
   - `_HistoryTile` (`:425`, renders a recorded `Settlement`): drop its `currency` param (`:428,:435`); `:455` and `:551` use `settlement.currency`.
   - `_PaymentHistorySection` (`:390`): its `currency` param (`:393,:399`) only feeds `_HistoryTile` (`:415`) → remove; its construction site (`:119`) drops the arg.
   - **`SettleUpPageBody.currency` (`:31`) STAYS** — still consumed by `_NetBalancesSection` (`:113`, computed net balances) and the optimizer-suggestion `GroupSettlementTile` (`:156`).

## Explicitly OUT of scope (PR-1+ territory — do not touch)

- `group_balance_provider.dart:348-356` settlement folds — currency-blind **on purpose** until PR-1.
- `GroupSettlementTile` (`settle_up_page_body.dart:152`) — renders an **optimizer suggestion** (computed transfer from the currency-blind fold; no per-doc currency exists). Stays threaded with group currency.
- `_NetBalancesSection` / hero / totals — fold outputs, PR-1.
- Both settlement **write** services — already persist `currency`; nothing to change.
- Server TS (`groupNetBalance.ts` reads per-doc currency already) — PR-2.
- Rules — untouched (uniformity rules stay live until PR-6; that's the epic's safety property).
- Activity-feed settlement rows (`group_activity_screen.dart:475-486`, `cross_group_activity_screen.dart:389-391`) — these render **activity-log** doc amounts, not `Settlement` objects; the log schema has no currency field. That's PR-4, not a missed site here. (Gate R1 P3.)

## Callsite classification (principle 1)

| Site | Class | Treatment |
|---|---|---|
| `settlement_service.dart:98-99`, `group_settlement_service.dart:83-84` | OUTBOUND (write) | Already persist `currency`; **untouched** |
| `Settlement.fromFirestore` | INBOUND (parse) | Retains the fenced value |
| `_SettlementHit`, `LedgerSettleRow` arg at `ledger_day_card.dart:172`, `_HistoryTile` | INBOUND (display) | Switch to `settlement.currency` |
| `group_balance_provider.dart:348-356` | BOTH-adjacent (feeds settle-up amounts) | **Untouched** (PR-1) |

No path reads a `Settlement` object back into a write — settlements are **append-only** (B3), so the retained field cannot leak display state into persistence. There is no `copyWith`/update path on the model.

## Tests

**RED first** (new group in `test/unit/settlement_read_fence_test.dart` — the existing fence test):
1. USD doc (`currency: 'USD', amountFils: 999`) → `s.currency == 'USD'` (and amount 9.99 — existing assertion style).
2. Missing currency → `s.currency == 'OMR'`.
3. Garbage `'XYZ'` → `s.currency == 'OMR'` (the fence value — label matches the OMR scale used; NOT `'XYZ'`).
4. Lowercase `'omr'` → `s.currency == 'omr'` (documents the as-is contract).

These fail before the model change (no such getter — compile error is the RED), pass after.

**Display regression** (extend existing widget/unit tests):
5. Search sheet: a settlement hit in a list parsed from a USD doc renders `USD` via `RAmount` — extend `test/unit/ledger_search_filter_test.dart` (seam: `debugFilter`) or the search-sheet widget test to assert `hit.currency == 'USD'` from a `Settlement(currency: 'USD')`.
6. Existing-arg cleanup: `ledger_split_ways_test.dart`, `ledger_day_card_former_member_test.dart` construct `LedgerDayCard(currency: …)` → drop the arg; settle-up body tests if they pass `currency` to the history section.

**Suites to run:** `flutter analyze` (clean), `flutter test test/unit/`, `flutter test test/features/ledger/`, `flutter test test/features/groups/`, then full `flutter test`.

## Verification principles report (run while authoring)

1. **Callsites classified** — table above; all touched sites INBOUND.
2. **Claims re-verified against code this session** — every line number above grepped in the worktree at `fdf8460b` (not from the issue text or memory).
3. **Read-path per write-path** — write: services persist `currency`; named readers after change: `fromFirestore` → `_SettlementHit.currency`, `ledger_day_card.dart:172`, `_HistoryTile:455/:551`.
4. **Fields enumerated from the type** — `Settlement` has 13 fields (`id, tripId, payerParticipantId, recipientParticipantId, amount, note, settledAt, payerName, recipientName, isDeleted, deletedAt, scope, groupId, createdBy` — 14 actually, miscounting is exactly why this is enumerated from the file); `currency` becomes the 15th. None collide.
5. **Data contract spelled out** — "fence-validated currency the amount was deserialized with"; exact fallback semantics above.
6. **Arithmetic decomposition** — N/A; no aggregation touched (folds explicitly out of scope).
7. **Orthogonal adversarial axis** — change is on the display/identity axis; worked example on the **data-trust axis**: forged doc `{currency: 'XYZ', amountFils: 5000}` → amount `5.000` (OMR scale), retained currency `'OMR'` → label agrees with scale; today the same doc displays with group currency, which also happens to be the fence's OMR in real OMR groups — identical output, but now correct *by construction* rather than by coincidence. Scope axis: group-scoped and event-scoped settlements share `fromFirestore`; both display paths (`_HistoryTile` for group, `LedgerSettleRow`/`_SettlementHit` for event) are covered above.

## Done means

- [ ] RED test written and observed failing (compile error on missing getter counts; paste output)
- [ ] Model + 4 display files changed; dead params removed end-to-end
- [ ] `flutter analyze` clean
- [ ] Full `flutter test` green
- [ ] PR `Refs #382` (partial — epic stays open) in **commit body** and PR body
- [ ] `/automerge` Gate-category path (fresh review + refuter)
