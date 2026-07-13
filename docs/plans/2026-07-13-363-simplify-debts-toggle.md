# Spec #363 — Per-group Simplify-Debts toggle (wraps the optimizer; default stays optimized)

**Issue:** #363 (P2, money, decision — core decision resolved in the issue body: default = optimized, per-group not AppSettings, wraps not replaces).
**Gate-category:** money math (`BalanceCalculator`) + `firestore.rules` + schema field with read+write paths. Fresh-context Gate mandatory before code.
**Builder model:** Fable. **Branch:** `feat/363-simplify-debts-toggle` off `origin/main`.
**This spec file is committed with the PR** as `docs/plans/2026-07-13-363-simplify-debts-toggle.md`; the PR body carries a `Spec:` line pointing at it.

**Gate history (2026-07-13, fresh-context Opus pairs, rubric + orthogonal adversary per round):** R1 — 1 P1 (mode-dishonest intro copy `settleUpOptimizedPayments`, EN+AR) → applied. R2 — 1 P1 (two-pass allocator could emit duplicate directed-pair legs; identical `sd1` dedup ids silently drop a payment → per-pair accumulation mandated) + conservation/termination + explainer-copy P2s → applied. **R3 — CLEAN both reviewers (0 P1 / 0 P1)**; R3 P2/P3 clarity directives folded in (id-only `==` propagation test, settings-surface file named, explainer prop-add named, count-amplification expectation, T=0 guard ordering, field-name kept).

## The load-bearing constraint (verified in-session 2026-07-13)

`recordSettlement` (deployed, #1129) rejects `amountFils > outstandingForPairFils(bucket, from, to)` where the TS mirror equals the Dart `BalanceCalculator.outstandingForPair` (`expense_provider.dart:974-991`): **`min(|fromNet|, toNet)` clamped ≥ 0**, computed from FULL current nets on the settle's scope basis. Consequence:

> **True transaction-graph pairwise debts are unrecordable and are NOT what this feature builds.** Triangle: A→B 50, B→C 50 gives nets A=−50, B=0, C=+50; the server cap for A→B is min(50, 0)=0 and for B→C is min(0, 50)=0 — both legs rejected. Any OFF-mode suggestion list MUST stay net-based with every leg ≤ min(|debtorNet|, creditorNet) **by construction**. Widening the server cap basis is forbidden (CLAUDE.md: breaks client↔server parity).

**OFF-mode semantic** ("direct pairwise transfers from raw netBalance pairs", per the issue): each debtor pays **every** creditor their proportional share — a bipartite pro-rata fan-out. No debt concentration onto an arbitrary single counterparty (the "why do I owe only Sara the full amount?" complaint); more, smaller, transparent transfers. The toggle copy must be honest that both modes are **balance-based**, not expense-graph-based (see §UI).

## 1. Schema — `simplifyDebts` on the group doc

- **Field:** `simplifyDebts: bool`. **Absent ⇒ `true` (optimized)** — the shipped default, zero migration, legacy groups unaffected.
- **Write path (only one):** creator toggling it in group settings → client `update` on `groups/{gid}` with `{simplifyDebts: <bool>, updatedAt: <timestamp>}` (rules require `updatedAt is timestamp` on the metadata path).
- **`validGroupCreate` untouched** — the field never appears at create (its `hasOnly` list stays as-is; absent = default true). Client group-create map untouched.
- **Read paths (enumerated):** `Group.fromDoc` → `settle_up_screen.dart` (event scope) and `group_settle_up_screen.dart` (group scope) suggestion generation; the settings toggle row reads it for its current value. Nothing else: NOT read by the oracle (`recomputeNet`), NOT by `balanceAggregator`, NOT by the #366 aggregate doc, NOT by `recordSettlement` — recording caps are unchanged and mode-independent.
- **Model (`lib/features/groups/models/group_model.dart`):** `final bool simplifyDebts;` default `true`; `fromDoc` total-parse style: `data['simplifyDebts'] is bool ? data['simplifyDebts'] as bool : true`; add to `copyWith`; **omit from `toMap`/`fromMap`** (dead SQLite path — mirror the glyph/inkIndex omission comment). **Keep it OUT of `==`/`hashCode`** (they are id-only by convention — `group_model.dart:174-179` — same as name/glyph). Because equality is id-only, add one **retained-screen propagation test**: settle-up mounted, the group stream emits the same group with the flag flipped, the rendered mode updates. If Riverpod's value-equality suppresses the rebuild, fix at the WATCH site (e.g. a `select((g) => g.simplifyDebts)` read alongside the bucket build) — never by widening `Group.==`.

## 2. Rules — `security/firestore.rules`

In `validCreatorMetadataUpdate` (~L348-370):
- `affectedKeys().hasOnly(['name', 'updatedAt', 'glyph', 'inkIndex', 'simplifyDebts'])`
- add guard `&& (!('simplifyDebts' in request.resource.data) || request.resource.data.simplifyDebts is bool)` — absent-or-bool, STRICT style matching glyph (explicit null rejected).
- Creator-only is inherited from `isCreator()` (post-#1132 it already requires current membership). **Decision (assumption, Gate-checkable): the toggle is creator-only**, matching every other group-doc metadata knob (name/glyph). Non-creators get no affordance.
- Group-doc update path is far from the 1000-expression ceiling (that pressure is on EVENT update); still keep the guard in the cheap `get()`-free shape above.
- **Rules change ⇒ deploy ceremony required post-merge** (`tool/pending_deploy.sh` / `deploy-ceremony`); PR body carries the standard `⚠️ NOT deployed` note.

## 3. Money math — new pure allocator in `BalanceCalculator` (`expense_provider.dart`)

```dart
static List<Map<String, dynamic>> calculateDirectSettlements({
  required List<UserBalance> balances,
  required String currency,          // quantization scale — pro-rata divides, unlike the min-only optimizer
  Map<String, String>? userNames,
})
```

Returns the **same map shape** as `calculateOptimalSettlements` (`expense_provider.dart:913-961`) — exact keys `fromUserId, toUserId, fromUserName, toUserName, amount` (Decimal) — so every downstream consumer (SettleBucket record type, suggestion tiles, stepped cards, #1149 `filterDepartedSuggestions` pruning, record sheet prefill, #719/#773 revalidation, #367 WhatsApp nudge) is shape-unchanged.

**Algorithm (integer subunits via `MoneySerializer.toSubunits`/`fromSubunits` — plain `int`, no BigInt; deterministic):**
1. Split nets: debtors (`netBalance < 0`), creditors (`> 0`); sort BOTH alphabetically by `participantId` (deterministic, house style: alphabetical tiebreaks).
2. `capRemaining[c] = toSubunits(net_c)` per creditor; `T = Σ toSubunits(net_c)` (== total debt subunits by conservation of the upstream nets).
3. For each debtor `d` with `D = toSubunits(|net_d|)`: **accumulate into a per-directed-pair map `pairSubunits[(d,c)]`, never emit legs per pass.** First pass over creditors in alpha order: `take = min( floor(D * origCap_c / T), capRemaining[c], remainingRow )` (floor via integer division — never `Decimal` division; stay in int subunits).
4. Second pass (row residual close-out): **ONE BOUNDED sweep** over the same fixed creditor list in alpha order, adding `min(remainingRow, capRemaining[c])` into the SAME `pairSubunits[(d,c)]` accumulator — **never a `while (remainingRow > 0)` loop** (on a non-conserving bucket, capacity can exhaust and an unbounded loop would spin; leftover `remainingRow` after the sweep is DROPPED, mirroring how the two-pointer optimizer leaves surplus unpaired when the other side exhausts). NOTE: alpha-FIRST close-out is a DELIBERATE deviation from the house "remainder → alphabetically-last" rule of the split allocators — here the binding constraint is per-leg cap compliance, not share-remainder placement; say so in a code comment so a reviewer doesn't read it as a bug.
5. Emit **exactly ONE leg per directed pair** — `pairSubunits` entries `> 0` only. **This is load-bearing for money correctness, not style:** settlement doc ids are the deterministic `sd1` dedup keys over (scope, directed pair, currency, amountFils, pairEpoch) (`functions/src/callables/shared/settlementIds.ts`), and `recordSettlement`'s idempotency probe returns `alreadyRecorded:true` on an identical-amount same-pair repeat — two identical suggested legs for one pair would record ONCE and silently drop a real payment. The whole downstream pipeline (`sd1` ids, `totalTransfers` count, suggestion tiles) assumes ≤1 leg per directed pair per epoch, as the optimizer guarantees today.

**Provable invariants (these ARE the test table; the margin-exactness ones hold for CONSERVING buckets, `Σ nets == 0` in subunits — the production case):**
- At most ONE leg per `(fromUserId, toUserId)` directed pair — always, conserving or not.
- Σ legs per debtor row == `toSubunits(|net_d|)` exactly when conserving (total capacity == total debt ⇒ the bounded pass-2 sweep drains every row).
- Σ legs per creditor column == `toSubunits(net_c)` exactly when conserving (every column ≤ cap and totals match ⇒ equality).
- Every leg ≤ `min(toSubunits(|net_d|), toSubunits(net_c))` — always (each pair's accumulated total is bounded by the row total ≤ |net_d| and by `capRemaining` draw-down ≤ net_c) ⇒ **every leg individually passes the server cap against full fresh nets**, and on a conserving bucket, because both margins are exactly conserved, recording the whole list SEQUENTIALLY IN ANY ORDER keeps every later leg within its recomputed cap (each recorded leg shrinks both parties' nets by exactly the amounts the remaining legs assume).
- **Non-conserving buckets (forged/legacy/Admin data — the #249/#1144-R1 residual class where a dropped non-member split key skews Σ nets) degrade gracefully, never spin:** creditor-heavy ⇒ rows drain, columns underfill; debtor-heavy ⇒ bounded sweep terminates with surplus debt unsuggested (same semantics as the optimizer when creditors exhaust). Both directions get table cases asserting termination, per-leg cap, no zero/negative/duplicate legs, and Σ legs == min(totalDebt, totalCredit).
- Whole-subunit legs at the currency scale (OMR/KWD/BHD=1000, 2dp=100, **JPY=1**); no `Decimal` division anywhere (the #596 quantization trap doesn't arise in integer space — say so in a comment).
- Input nets are already whole-subunit (produced by `calculateBalances`); assert/handle defensively the same way the optimizer does (it doesn't — don't add new defensive drift; trust upstream like `calculateOptimalSettlements` does).
- Empty debtors or creditors → `[]` — and this guard runs BEFORE any division, so `T = 0` division is unreachable (state the ordering in code).
- `SettleBucket.optimalSettlements` keeps its field name even when holding direct legs (renaming it is churn across every consumer for zero behavior; the refreshed docstrings carry the nuance).

**Untouched:** `calculateOptimalSettlements`, `outstandingForPair`, `calculateBalances`, the TS oracle (`recomputeNet`), `decomposeGroupSettlement`, `recordSettlement` and all caps, `balanceAggregator`, aggregate doc. **Zero server-side changes except none; zero rules changes on money paths.** Rounding-remainder rule of the existing allocators is not implicated (different function, its own remainder discipline as specced).

## 4. Wiring — the two callers + the intro copy (all verified in-session)

- `lib/features/ledger/screens/settle_up_screen.dart:346-356` (event scope) and `lib/features/groups/screens/group_settle_up_screen.dart:194-204` (group scope): swap per bucket
  ```dart
  optimalSettlements: group.simplifyDebts
      ? BalanceCalculator.calculateOptimalSettlements(balances: ..., userNames: ...)
      : BalanceCalculator.calculateDirectSettlements(balances: ..., currency: c, userNames: ...),
  ```
  `group` is already in scope at both sites (`group.createdBy` / `group.currency`; non-null guarded at `settle_up_screen.dart:211-213` / `group_settle_up_screen.dart:107-109`). The empty-bucket fallback arms stay as-is.
- **Thread the mode into the body — the copy renders there, not at bucket construction.** `SettleUpPageBody` (`lib/features/groups/widgets/settle_up_page_body.dart` — note the groups/widgets dir, NOT ledger/) gains a `required bool simplifyDebts` prop, passed `group.simplifyDebts` from BOTH call sites, and forwarded to `_SettlementIntro` (`settle_up_page_body.dart:396` / `:516-556`). Swapping only the `optimalSettlements:` argument is HALF the change.
- **Intro subtitle must be mode-honest — a FOUR-way branch.** `_SettlementIntro` today branches only on `transferCount` (`settle_up_page_body.dart:543-545`), rendering `settleUpNoOptimizedPayments` / `settleUpOptimizedPayments` (EN `app_en.arb:936/942`, AR `app_ar.arb:347/348`). Under OFF, "Optimized to reduce the number of payments" is factually FALSE over a deliberately-expanded fan-out. Add TWO new l10n pairs (EN+AR): `settleUpDirectPayments` (legs > 0, e.g. EN "Everyone pays their share to each person they owe across {subjectName}.") and `settleUpNoDirectPayments` (zero-state, e.g. EN "No payments are needed across {subjectName}."); `_SettlementIntro` selects across {mode × zero/nonzero} — keep the `transferCount == 0` axis alongside the new flag. Existing ON-mode keys untouched. TRAP: commit the regenerated `lib/l10n/generated/` files with every ARB change.
- **Multi-currency explainer must also be mode-honest.** `currencyExplainerBody` (EN `app_en.arb:1029` + AR counterpart), rendered by `currency_buckets_explainer.dart:86` whenever `buckets.length >= 2` (`settle_up_page_body.dart:405`), ends "You'll record one payment per currency." — false under OFF's per-currency fan-out. Add an OFF variant pair (EN+AR, e.g. `currencyExplainerBodyDirect` ending "You'll record each payment per currency."), **add a `required bool simplifyDebts` param to `CurrencyBucketsExplainer`** (today it takes only `bucketCount`, `currency_buckets_explainer.dart:24-25`), and select by it.
- **Expected, not a regression:** the headline transfer count (`settle_up_page_body.dart:291-294`) and the `settleUpDepartedPairsHidden` count will be materially LARGER under OFF — that's the fan-out semantics, don't "fix" it.
- **Refresh the stale "optimized" docstrings on the touched files** so they don't misdescribe OFF mode: `settle_up_page_body.dart:153` ("optimized transfer cards"), `:165-167` ("Label shown after 'Optimized to minimise…'"), `settle_up_screen.dart:44`, `group_settle_up_screen.dart:45`.
- **The per-group toggle governs BOTH scopes** (event + group settle-up) — one mental model per group. (Assumption, Gate-checkable.)
- gsu decompose path: unchanged — `decomposeGroupSettlement` operates on the recorded pair+amount, independent of how the suggestion was generated; every OFF leg is within the group-scope cap so `recordSettlement` mode `'groupSettleUp'` proceeds normally.
- `_freshOutstandingForPair` (#773) / #719 confirm-time re-reads: unchanged and still correct — OFF legs are ≤ `outstandingForPair` by construction, so the advisory revalidation never false-blocks an untouched balance.

## 5. UI — creator toggle + honest copy

- A switch row in **`lib/features/groups/screens/group_settings_screen.dart`** (the settings surface; the rename/stamp editor modal `group_edit_sheet.dart` is NOT the home for a persistent toggle), in the creator-only section, visible to the creator only. Use existing settings-row components and tokens; no new visual language (⇒ no design-canvas step; assumption, Gate-checked clean).
- Write path: a **NEW, SEPARATE notifier/service method `setSimplifyDebts(groupId, bool value)`** writing exactly the 2-key map `{simplifyDebts: value, updatedAt: <timestamp, same style updateGroupIdentity uses>}`. **Do NOT extend `updateGroupIdentity` (`group_provider.dart:467-479`)** — it writes name/glyph/inkIndex atomically and `FieldValue.delete()`s glyph/inkIndex when null, so bundling the toggle there can silently WIPE the group's trip stamp. No new global repository.
- l10n EN+AR pair for title + subtitle. Copy must be balance-honest, e.g. EN title "Simplify debts", subtitle ON: "Fewest transfers: balances may be settled through any member." / OFF: "Everyone pays each person they owe a share of the balance." **Never claim OFF shows "who actually paid whom"** — both modes derive from net balances (the server cap makes expense-graph pairing unrecordable; see the constraint block).
- Offline: the toggle is a plain Firestore doc write (SDK queues offline) — follow #412: don't gate UI progression on the raw write future; match how rename/glyph writes handle it today (mirror, don't invent). Known and accepted: a toggle queued offline during a departure/deletion quiesce lock replays to permission-denied like rename/glyph do today — NO bespoke offline handling.

## 6. Tests (feature ⇒ failing tests define done; money ⇒ table-driven)

RED-first where testable:
1. **Allocator unit table** (`test/unit/` beside `settlement_optimization_test.dart`) — table-driven clean/edge cases: 2×2 pro-rata exactness; remainder-forcing amounts (OMR 3dp: e.g. debtor 10.000 across creditors 3.333/3.333/3.334-style; JPY scale-1; 2dp currency); **the pass-collision case that forces pass-1 and pass-2 to touch the same creditor** (e.g. JPY debtors 5,5 / creditors 3,3,4 subunits — the RED case for the one-leg-per-pair invariant; without per-pair accumulation this emits a duplicate D→A leg whose identical `sd1` id would silently drop a payment); triangle A(−50)/B(0)/C(+50) ⇒ exactly `[A→C 50]`, **no B legs** (documents the nets-based semantic); single debtor/multi creditor and inverse; empty/all-zero ⇒ `[]`; **non-conserving buckets BOTH directions** (creditor-heavy and debtor-heavy — termination, per-leg cap, no zero/negative/duplicate legs, Σ legs == min(totalDebt, totalCredit)); every invariant from §3 asserted generically over the table (per-pair uniqueness, row sums, column sums [conserving cases], per-leg cap, whole-subunit, determinism — run twice, deep-equal).
2. **Sequential recordability property:** for each table case, fold the legs in order (and in reversed order) against a simulated net vector, asserting each leg ≤ `outstandingForPair` of the *current* vector — pins the §3 any-order claim against the real Dart cap function.
3. **Widget swap test:** fake group with `simplifyDebts: false` renders the direct legs AND the `settleUpDirectPayments` intro copy; `true`/absent renders optimizer output AND the existing `settleUpOptimizedPayments` copy; OFF zero-state renders `settleUpNoDirectPayments`; multi-bucket OFF renders the `currencyExplainerBodyDirect` explainer variant (existing settle-up test harness; override `groupDetailProvider` — it binds real Firestore otherwise, the #261 trap).
4. **Rules emulator tests** (extend the existing `validCreatorMetadataUpdate` coverage in the functions test suite): creator sets `simplifyDebts: false` (+`updatedAt`) → allow; non-creator → deny; non-bool (`"yes"`, `1`, explicit `null`) → deny; combined `{name, simplifyDebts, updatedAt}` → allow. Run via `cd functions && npm run test:emulator -- <file>` (NEVER bare jest, #1157).
5. **Regression floor:** `balance_calculations_test.dart`, `delete_group_balance_parity_test.dart`, `settlement_optimization_test.dart`, `group_balance_provider_test.dart` all untouched and green.
6. `flutter analyze` clean; `tool/check_theme_purity.sh` locally (new widget code, #615 trap); full `flutter test`.

## 7. Out of scope (name it so the Gate doesn't have to)

- No server/oracle/aggregate change of any kind; no new cap basis.
- No expense-graph pairwise ledger (blocked by the deployed cap; would be a 2.0-scale schema project).
- No per-user preference; no AppSettings surface; no event-level override.
- No change to the raw "each person's net" view, stepped cards mechanics, or #1149 pruning semantics.

## Commit / PR

- Conventional commits; final squash body carries `Closes #363`.
- PR body: `Spec: docs/plans/2026-07-13-363-simplify-debts-toggle.md`, Gate round summary, RED evidence for the allocator table (failing before implementation), test plan results, and the **rules-deploy-pending** note.
- Push `-u`, open PR, report PR number. Do NOT enable auto-merge — the lead runs /automerge (Gate-category ⇒ reviewer + refuter).
