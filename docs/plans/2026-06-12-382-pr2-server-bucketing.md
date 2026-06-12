# #382 PR-2 — Server oracle per-currency bucketing + per-bucket-zero gates

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the server balance oracle (`groupNetBalance.ts` `foldEventNet`/`recomputeNet`) return per-currency buckets — byte-for-byte mirroring the merged PR-1 client `calculateBalances`/`computeGroupBalances` — so the deleteGroup/leaveGroup/removeMember gates check **zero in every currency bucket** instead of refusing on `currencies.size > 1`.

**Architecture:** `net` becomes `Map<currency, Map<uid, Decimal>>` and `perEventNet` becomes `Map<eventId, Map<currency, Map<uid, Decimal>>>`. Expenses fold paid+owed into their own fenced currency bucket; event- and group-scope settlements fold their adjustment into their own per-doc currency bucket. The three gates iterate every bucket and refuse on any non-zero actor. A **flatten-singleton adapter (Shim #2)** in `balanceAggregator` collapses the sole bucket back to the flat v1 aggregate doc, so the #366 cache stays byte-identical and `balanceAggregator`/`balanceReconciler` tests pass untouched — letting PR-2 deploy on its own. The expense-only `currencies` Set is **retained, populated, and returned** (the v1 doc's `currencies[]` reads it) but the gates stop consulting it. **No real users → server deploys freely; no client-compat gating** ([[project_no_clients_deploy_freely]]).

**Tech Stack:** Firebase Cloud Functions (Node 22 / TypeScript), `decimal.js` (isolated `Money` clone), Jest under the Firestore emulator (`npm run test:emulator` — raw `jest` hangs), Dart parity test (`flutter test test/unit/delete_group_balance_parity_test.dart`).

---

## 0. Locked decisions (the data contract)

### D1 — `foldEventNet` return shape → `Map<currency, Map<uid, Decimal>>`

`foldEventNet(expenses, settlements, universe, currencies)` currently returns `Map<uid, Decimal>`. It now returns **`Map<currency, Map<uid, Decimal>>`**, mirroring the client `calculateBalances` (`expense_provider.dart:313-484`) which keys three intermediate maps (`paidByCurrency`, `owedByCurrency`, `adjByCurrency`) by fenced currency and seeds each new bucket with the universe at zero.

- **Bucket key = `currencyOf(raw)` — case-preserved, NOT uppercased.** The client buckets by the raw fenced string `MoneySerializer.isSupported(x) ? x : 'OMR'` (`expense_provider.dart:346-348`, `:442-444`); `MoneySerializer.isSupported` (`money_serializer.dart:37-38`) uppercases only for the *containsKey check*, returning the raw code. The server `currencyOf` (`groupNetBalance.ts:52-54`) already does the same. So the **net-bucket key uses `currencyOf(raw)` verbatim** — do **not** `.toUpperCase()` it. (Contrast: the `currencies` Set at `:392` keeps `.toUpperCase()` — see D5.)
- Per bucket: a paid map + an owed map + a settlementAdj map, each lazily created and seeded `{for uid in universe: Money(0)}` (the `bucketFor` helper, mirroring `expense_provider.dart:329-337`).
- **Expense fold** (mirror `:340-435`): `paid[ccy][payer] += amount` (gated on `paid[ccy].has(payer)`); allocations → `owed[ccy][recipient] += value` (gated on `owed[ccy].has(recipient)` — the load-bearing out-of-universe drop). Allocators (`allocateEqual/Shares/Exact/Percent`) are unchanged — already per-expense-currency-correct (#270).
- **Event-settlement fold** (mirror `:441-456`): `adj[ccy][payer] += amount`; `adj[ccy][recipient] -= amount`, gated on `adj[ccy].has(...)`.
- **Bucket union for the net** (mirror `:460-463`): `allCurrencies = union(paid.keys, adj.keys)`. (`owed.keys ⊆ paid.keys` always, because the expense fold seeds paid+owed together — `:349-350`.)
- **Net per bucket** (mirror `:467-482`): for each `ccy in allCurrencies`, for each `uid in universe`: `net[ccy][uid] = (paid[ccy][uid] ?? 0) + (adj[ccy][uid] ?? 0) - (owed[ccy][uid] ?? 0)`. Seed every universe uid in every returned bucket at zero (preserves the v1-doc uid key-set — see D6).
- **No money in this event** → returns an empty outer map `{}` (mirror `:319` `if (participants.isEmpty) return {}`; here: no expenses + no settlements → no buckets).

### D2 — `recomputeNet` return shape

```ts
export interface RecomputeResult {
  net: Map<string /*currency*/, Map<string /*uid*/, Decimal>>;   // CHANGED
  liveEventRefs: DocumentReference[];                            // unchanged
  perEventNet: Map<string /*eid*/, Map<string /*currency*/, Map<string /*uid*/, Decimal>>>; // CHANGED
  eventCount: number;                                            // unchanged
  currencies: Set<string>;                                       // unchanged — expense-only, still .toUpperCase()'d (D5)
}
```

- **Net accumulation** (`recomputeNet` body, mirror client `computeGroupBalances` `group_balance_provider.dart:285-351`): accumulate into `netByCurrency: Map<ccy, Map<uid, Decimal>>` via `addNet(ccy, uid, delta)` (`netByCurrency.get(ccy) ?? new Map`, then `bucket.set(uid, (bucket.get(uid) ?? Money(0)).plus(delta))`). For each event, `foldEventNet` now returns buckets; accumulate `for (const [ccy, bucket] of eventNet) for (const [uid, delta] of bucket) addNet(ccy, uid, delta)`. **Also track `seenUids: Set<string>`** — `seenUids.addAll(universe)` per processed event (BEFORE the fold, so a no-money event's participants are still recorded) and add each group-settlement payer/recipient. This is the server's analog of the client's `allUids` (`group_balance_provider.dart:380-387`), minus bare members — it reproduces today's flat-`net` key-set exactly (∪ event universes ∪ group-settlement parties).
- **`finalizeNet(netByCurrency, seenUids)` — the no-money fallback (mirror client `balances` build, `group_balance_provider.dart:405-424`, + preserve today's flat-net key-set):**
  - `netByCurrency` empty AND `seenUids` empty → `new Map()` (Scenario A: no events, no money → flat `netMilli == {}`, matches `balanceReconciler.test.ts:133`).
  - `netByCurrency` empty AND `seenUids` non-empty → **single `{'OMR': {uid: Money(0) for uid in seenUids}}`** (Scenario B: an event with participants but no money → today's `net == {alice:0,bob:0}`; the sole bucket flattens to it). This fallback fires ONLY when there is no real currency — so it can never inflate `net.size` for a group that has real money.
  - else → for each `ccy in netByCurrency.keys`, build `{uid: netByCurrency[ccy][uid] ?? Money(0) for uid in seenUids}` (list every seen uid, zeros included — mirrors the client listing `allUids` in every bucket; reproduces the cross-event/no-money-event zero entries today's flat `net` carries).
- **Why the fallback lives in `recomputeNet`, not `foldEventNet` (Gate R1 [P1] resolution — see Verification §):** a no-money `foldEventNet` returns `{}` (mirroring the client `calculateBalances` empty return, `expense_provider.dart:319`/`:460-463`). Injecting a phantom `{'OMR': zeros}` *inside* `foldEventNet` (the reviewer's first remedy) would, for a single-currency **USD** group that has any empty event, push a zero OMR bucket into `net` → `net.size == 2` → Shim #2 falsely marks the group `degraded` (reverting #366's O(G) win) and diverges from the client (whose `net.size` stays 1). Deciding the fallback at finalize — only when **no** real currency exists — avoids that.
- **perEventNet** (mirror client `_buildPerEventBreakdown` — participantIds-only universe, explicit zero-rows on a no-money event, `group_balance_provider.dart:461-513`): `perEventNet.set(eid, bucketizeDrill(foldEventNet(expenses, settlements, drillUniverse, currencies), drillUniverse))`, where `bucketizeDrill(slice, drill)` returns `slice` when non-empty, else the fallback `{'OMR': {uid: Money(0) for uid in drill}}`. This preserves today's `perEventNet[eid] == {alice:0,bob:0}` for a no-money event (pinned by `balanceAggregator.test.ts:556`). For a money event the slice is `{ccy: {drill uids}}` already seeded by `foldEventNet`. Under single-currency prod the slice is the sole bucket — Shim #2 flattens it to today's flat slice.
- **Group-scope settlement fold** (`:573-585`, mirror client `groupAdjByCurrency` `group_balance_provider.dart:353-378`): `addNet(currencyOf(s.currency), payer, +amount)`; `addNet(currencyOf(s.currency), recipient, -amount)`; `seenUids.add(payer/recipient)`. **No universe gate** (any uuid can appear — `addNet` creates the bucket+uid). Fenced like expenses (`currencyOf`, OMR fallback).
- **`currencies` Set:** unchanged — still populated expense-only inside `foldEventNet` (`:392`, `.toUpperCase()`), still returned. (`finalizeNet`'s 'OMR' fallback key is internal — flattened away by Shim #2, never reaching the v1 doc's `currencies[]`, which stays `[]` for a no-money group.)

### D3 — Settlements bucket by their own per-doc currency (the behavior change from PR-1)

PR-1 (merged `11685af8`) already made the **client** bucket settlements by their own `currency` field (PR-0 `84dae4bd` retained it on the `Settlement` model). The server MUST mirror this. The old `RecomputeResult.currencies` doc-comment (`:335-356`) — "currencies is EXPENSE-only; settlements deliberately excluded because a legacy OMR settlement against a non-OMR debt would falsely brick the group" — described the **gate** semantics, which this PR replaces. Update that comment to: the `currencies` Set remains expense-only **only because the v1 aggregate doc's `currencies[]` field reads it (Shim #2)** — it is **no longer a gate input**; the gates use the per-currency `net` buckets, which DO include settlement currencies.

**Consequence (intended, Gate-reviewed):** a legacy group with a USD expense settled by an *OMR*-scale settlement is now **unsettled** (USD bucket non-zero; the OMR settlement lands in a separate OMR bucket — no FX). This is correct no-FX behavior and is exactly what the merged client already shows. **There are no real users** ([[project_no_clients_deploy_freely]]) so no prod data is affected. This is the basis for the test-9 rewrite (D8) and a money-safety RED.

### D4 — Gates: per-bucket-zero, drop the `currencies.size > 1` refusal

- **deleteGroup** (`deleteGroup.ts:254-272`): destructure `{ net, liveEventRefs }` (drop `currencies`). **Delete** the `if (currencies.size > 1)` block (`:260-264`). Replace the outstanding check (`:266`):
  ```ts
  const hasOutstanding = [...net.values()].some(
    (bucket) => [...bucket.values()].some((value) => !value.isZero()),
  );
  if (hasOutstanding) {
    throw new HttpsError('failed-precondition',
      'Group has unsettled balances and cannot be deleted.');
  }
  ```
- **leaveGroup** (`leaveGroup.ts:86-103`): destructure `{ net }` (drop `currencies`). **Delete** the `if (currencies.size > 1)` block (`:91-95`). Replace the leaver check (`:97-102`):
  ```ts
  const leaverOutstanding = [...net.values()].some((bucket) => {
    const v = bucket.get(uid);
    return v != null && !v.isZero();
  });
  if (leaverOutstanding) {
    throw new HttpsError('failed-precondition',
      'You have an unsettled balance and cannot leave the group.');
  }
  ```
- **removeMember** (`removeMember.ts:123-140`): destructure `{ net }`. **Delete** the `if (currencies.size > 1)` block (`:128-132`). Replace the target check (`:134-139`) with the same pattern keyed on `targetUserId` and message `'This member has an unsettled balance and cannot be removed.'`.

A missing-uid-in-bucket (`bucket.get(uid)` undefined) is treated as zero → allowed, exactly matching the old `net.get(uid)` missing-entry semantics.

### D5 — `currencies` Set: retained, expense-only, `.toUpperCase()`'d — NOT a gate input

Keep the Set exactly as built today (`foldEventNet:392` adds `currencyOf(e.currency).toUpperCase()`). It is consumed ONLY by the aggregator's v1 `currencies[]` field (`balanceAggregator.ts:98`) and the reconciler fingerprint (`balanceReconciler.ts:42`). Retaining it keeps the v1 doc byte-identical (D7). Do **not** derive `currencies` from `net.keys()` (that would change the doc field and break aggregator tests, and net keys are case-preserved while the doc field is uppercased).

### D6 — Shim #2: flatten-singleton adapter in `balanceAggregator` (removed in PR-3)

Insert immediately after `const result = await recomputeNet(db, groupRef);` (`balanceAggregator.ts:84`), **before** the encode loops (`:86-97`):

```ts
// Shim #2 (#382 PR-2 — REMOVED in PR-3 when the v2 bucketed doc lands).
// The oracle now returns per-currency buckets, but the v1 aggregate doc is
// flat. While the uniformity rules are still LIVE (PR-6 relaxes them last),
// every prod group holds exactly one currency, so net has exactly one bucket;
// collapse it to the flat per-uid map the v1 encode expects. A >1-bucket map
// is unreachable in prod; if it ever appears (legacy/Admin mixed-case doc) we
// mark the doc degraded so the client falls back to the once-path loudly
// rather than write a half-currency cache.
const netBucketCount = result.net.size;
const flatNet: Map<string, Decimal> =
  netBucketCount <= 1 ? (result.net.values().next().value ?? new Map()) : new Map();
const flatPerEventNet = new Map<string, Map<string, Decimal>>();
for (const [eventId, slice] of result.perEventNet) {
  flatPerEventNet.set(
    eventId,
    slice.size <= 1 ? (slice.values().next().value ?? new Map()) : new Map(),
  );
}
const multiCurrency = netBucketCount > 1;
```

Then the existing loops iterate `flatNet` / `flatPerEventNet` instead of `result.net` / `result.perEventNet`, and the `degraded` flag becomes `degraded = multiCurrency || mapsBytes > maxBytes()` (multi-currency forces the no-maps payload, same as the size cap). `currencies` still reads `result.currencies` (D5). Net result: for every single-currency group (= all prod groups), the payload is **byte-identical** to today.

**Why `multiCurrency` never false-fires on a single-currency group:** `result.net.size` equals the count of *real* expense/settlement currencies (the D2 `finalizeNet` 'OMR' fallback fires only when there are **zero** real currencies, yielding `size == 1`). So a single-currency group — even one with empty events — has `net.size == 1` and is never degraded. (A genuinely mixed group, e.g. the legacy USD-expense + OMR-settlement case, has `net.size == 2` → degraded → client once-path fallback, which is consistent with the client's own ≤1-bucket facade chooser. Unreachable in prod under the live uniformity rules.)

### D7 — `balanceReconciler` unchanged

The reconciler (`functions/src/scheduled/balanceReconciler.ts`) only calls `refreshGroupBalanceAggregate` (`:70`) and fingerprints the **doc fields** (`netMilli`/`perEventNetMilli`/`eventCount`/`currencies`, `:37-44`) — it never reads `RecomputeResult` directly. Shim #2 keeps those doc fields identical, so no reconciler code change and its tests stay green.

### D8 — TS test changes

- **DELETE/rewrite `deleteGroup test 9`** (`deleteGroup.test.ts:509-541`): keep the percent /1000 decode setup, but change the settlement from `currency:'OMR', amountFils:4000` to **`currency:'USD', amountFils:400`** (USD scale 100 → $4.00) so the USD bucket nets to a true zero and the group still deletes — the percent-decode-then-settle-then-delete narrative, now currency-correct. (Under bucketing an OMR settlement can no longer zero a USD bucket — D3.)
- **9b / 9c** (`:543-576`, `:578-…`): assertions UNCHANGED (still `failed-precondition`) — each currency bucket is genuinely non-zero per actor, so the per-bucket gate refuses for the *right* reason now. Update the comments (drop "fake scalar zero / currencies guard" → "non-zero in each currency bucket").
- **9d** (mixed-CASE `'omr'`+`'OMR'`, `:608-641`): assertion UNCHANGED — case-preserved net keys give two **all-zero** buckets, the per-bucket gate finds no non-zero → still `softDelete`. (This is the in-repo instance of the D6 "legacy/Admin mixed-case → `net.size>1`" note; on the *aggregate* path such a doc would flatten to `degraded`, which is perf-only + prod-unreachable. No change needed; called out so the unchanged pass is intentional, not an oversight.)
- **leaveGroup 8b** (`leaveGroup.test.ts:279-305`) and **removeMember 10b**: same — assertions UNCHANGED (leaver/target is non-zero in each bucket), update comments.
- **ADD `deleteGroup` headline RED** — "mixed-currency group, every bucket fully settled → DELETES": OMR expense + USD expense, each settled to per-bucket zero (e.g. each currency split equally then settled by a same-currency settlement, or personal-scope per-currency so each actor nets zero). Before PR-2: refused (`size>1`). After: `mode:'softDelete'`.
- **ADD `deleteGroup` money-safety RED** — "a settlement in a different currency does NOT settle the debt (no-FX) → REFUSE": one USD expense leaving a USD debt, one OMR settlement → USD bucket non-zero → `failed-precondition`. (Documents the D3 behavior change explicitly.)
- **ADD leaveGroup + removeMember "mixed but settled in every bucket → ALLOWED"** tests (mirror the deleteGroup headline RED): leaver/target has activity in ≥2 currencies, each netting zero → before: refused (`size>1`); after: allowed.
- **`balanceAggregator.test.ts` / `balanceReconciler.test.ts`**: UNCHANGED — they assert the flat v1 doc shape; Shim #2 keeps it identical. Their staying-green is the proof the shim works.

### D9 — Dart parity test grows a currency dimension

`delete_group_balance_parity_test.dart` (insert INSIDE the top-level `group(...)` — after the last test's closing `);` at `:377`, BEFORE the group-close `});` at `:378`): a mixed-currency case asserting the client `calculateBalances` produces independent per-currency buckets whose values are the hand-computed expecteds the TS oracle now mirrors. Two expenses in one event (10.000 OMR by owner / 5.00 USD by member, both global equal-split over {owner, member}): assert `['OMR']` → owner +5.000, member −5.000; `['AED'|'USD']` → its own independent split. This pins client==server byte-for-byte on a mixed group. Existing OMR-only cases 1/1b/1c/1d/1e/2/3/4 are unchanged (each is intentionally single-axis, verification principle #7). `balance_aggregate_parity_test.dart` is untouched (PR-3 owns its v2 buckets).

### Explicitly OUT of scope (later rungs)

- Aggregate doc **v2** bucketed encode + facade chooser + `crossGroupHomeBalanceProvider` → **PR-3** (Shim #2 is removed there).
- Activity-log currency field → **PR-4**.
- Stepped settle-up + per-currency hero lines → **PR-5**.
- `currencyMatchesGroup` rules relaxation + add-expense currency picker → **PR-6** (makes mixed data creatable; deploy LAST).

---

## Verification-principles run (reported out loud, per the contract)

1. **Classify every callsite of the changed shape (INBOUND/OUTBOUND/BOTH).** `recomputeNet`/`foldEventNet` consumers, exhaustively (grep `recomputeNet` + `result.net|perEventNet|currencies|eventCount` over `functions/src`, non-test): **only 5** — deleteGroup (`:254`, OUTBOUND: gates a destructive cascade), leaveGroup (`:86`, OUTBOUND), removeMember (`:123`, OUTBOUND), balanceAggregator (`triggers/balanceAggregator.ts:84`, INBOUND: display cache, "never OUTBOUND" per its header + [[project_balance_aggregate_366]]), balanceReconciler (`scheduled/balanceReconciler.ts:70`, indirect via the aggregator). No other reader. The type flip surfaces all 4 direct call sites at compile time.
2. **Verify every concrete claim against code, not docs.** Anchors re-grepped against the `../Rihla-382-pr2` worktree (= `origin/main`, PR-1 merged): `calculateBalances` def `expense_provider.dart:313`; client folds `group_balance_provider.dart:273-378`; `foldEventNet` `groupNetBalance.ts:370-452`; `recomputeNet` `:454-594`; group-settlement fold `:573-585`; gates `deleteGroup.ts:254-272` / `leaveGroup.ts:86-103` / `removeMember.ts:123-140`; aggregator encode `balanceAggregator.ts:84-121`; reconciler fingerprint `balanceReconciler.ts:37-44`. `MoneySerializer.isSupported` uppercases only the check (`money_serializer.dart:37-38`) → bucket key is raw (D1).
3. **Trace one read-path per write-path.** The net buckets are written (returned) by `recomputeNet` and read by: the 3 gates (refuse on any non-zero bucket) and the aggregator (Shim #2 flattens → v1 `netMilli` → home display). Named reader for every produced field. `currencies` Set → aggregator `currencies[]` + reconciler fingerprint (D5). `perEventNet` buckets → aggregator (Shim flattens → `perEventNetMilli`).
4. **Enumerate fields from the type, not memory.** `RecomputeResult` (D2): `net`, `liveEventRefs`, `perEventNet`, `eventCount`, `currencies` — all five accounted for; only `net` and `perEventNet` change shape.
5. **Spell out data contracts exactly.** Bucket key: `currencyOf(raw)` case-preserved (D1). `net`: `Map<currency, Map<uid, Decimal>>`. `perEventNet`: `Map<eid, Map<currency, Map<uid, Decimal>>>`. Gate predicate: `[...net.values()].some(b => [...b.values()].some(v => !v.isZero()))`. Shim flatten: sole bucket or empty; `>1` → degraded. v1 doc payload keys unchanged.
6. **Verify arithmetic decomposition.** `net[ccy][uid] = (paid[ccy][uid] + adj[ccy][uid]) − owed[ccy][uid]` per bucket (matches client `:472-473`). The flat v1 `netMilli` is **not** reconstructable from `perEventNetMilli` (different universes + group settlements + drops — the non-decomposition contract, `RecomputeResult` comment `:322-330`); Shim #2 flattens each independently, never reconciles one from the other.
7. **Adversarial pass on an orthogonal axis.** The change axis is *currency bucketing*. Orthogonal exercises in the test suite: **settlements** (D8 money-safety RED: cross-currency settlement does not settle — the deleteGroup test-9 rewrite + the no-FX REFUSE test); **departed/former actors** (group-scope settlement fold has no universe gate — D2 — a settlement uuid not in any event still buckets, mirroring client `:353-378`); **group-scope vs event-scope settlements** (both fold per-currency; deleteGroup test 8 group-settlement path stays green); **the no-money empty case** (event with no money → `{}`; group with no buckets → empty net → deletes).

**Adversarial finding folded into the spec:** the upstream mapping agent claimed "test 9's OMR settlement is NOT in any bucket → USD nets zero → deletes." **False** against the merged client (`expense_provider.dart:441-456` buckets each settlement into its own currency; a no-expense currency still creates a bucket). Verified by hand-evaluating `calculateBalances` on the test-9 fixture: USD bucket non-zero, OMR bucket non-zero → client shows unsettled → server must refuse. Hence the D8 test-9 rewrite (settlement → USD), not a passthrough.

### Gate rounds (fresh-context Opus, per the contract)

**Round 1 — VERDICT 1 P1 / 0 P2 / 1 P3.**
- **[P1] (resolved):** the original D1 "no-money event → `{}`" would flatten to `perEventNetMilli[eid] == {}`, breaking `balanceAggregator.test.ts:556` (pins `{e1:{alice:0,bob:0}}` for the no-money event in test P2) and diverging from the client `_buildPerEventBreakdown` zero-rows (`group_balance_provider.dart:500-505`). **Fix applied:** the no-money zero-rows are restored at the `recomputeNet` finalize level (`finalizeNet` + `bucketizeDrill` fallback, D2), NOT inside `foldEventNet`. **The reviewer's suggested remedy (a phantom `{'OMR': zeros}` inside `foldEventNet`) was verified-and-rejected** against code: it would push a zero OMR bucket into `net` for a single-currency USD group with any empty event → `net.size == 2` → Shim #2 false-`degraded` (a #366 perf regression) + client divergence. Hand-verified the finalize-level fix reproduces `balanceAggregator.test.ts` P2 exactly (`netMilli {ALICE:2500,BOB:-2500}` from the group settlement; `perEventNetMilli {e1:{ALICE:0,BOB:0}}` from the no-money event) — see D2.
- **[P3] (resolved):** reconciler path is `functions/src/scheduled/...` not `triggers/` — corrected in D7 + principle #1.

**Round 2:** re-run with a fresh subagent after these edits (a new `Agent`, never a continuation) — stop when 0 P1s.

---

## Tasks

### Task 0: Preflight

**Step 1:** Confirm worktree is `feat/382-pr2-server-bucketing` off `origin/main` (PR-1 present): `grep -n 'Map<String, List<UserBalance>> calculateBalances' lib/features/ledger/providers/expense_provider.dart` → line 313.
**Step 2:** Baseline green: `cd functions && npm run build` (tsc clean) and note `npm run test:emulator` is the test command (raw `jest` hangs — [[project_durable_credential_rearchitecture_441]]).

### Task 1: RED — TS gate tests (deleteGroup headline + money-safety + leave/remove allow)

**Files:** Modify `functions/test/callables/deleteGroup.test.ts`, `leaveGroup.test.ts`, `removeMember.test.ts`.

**Step 1:** Add the deleteGroup **headline RED** ("mixed-currency, every bucket settled → softDelete"), the **money-safety RED** ("OMR settlement does not settle a USD debt → failed-precondition"), and the leave/remove "mixed but settled → allowed" tests (D8). Follow the existing emulator fixture helpers (`seedGroup/seedMember/seedEvent/seedExpense/seedEventSettlement/seedGroupSettlement`).
**Step 2:** Run `npm run test:emulator` — expect the two "allowed/softDelete" RED tests to FAIL with `failed-precondition` (the current `size>1` refusal), and the money-safety REFUSE test to PASS-for-the-wrong-reason today (it's the regression guard for the rewrite). Record the failing output.

### Task 2: GREEN — `foldEventNet` per-currency (D1)

**Files:** Modify `functions/src/callables/groupNetBalance.ts:370-452`.

**Step 1:** Change the signature/return to `Map<currency, Map<uid, Decimal>>`; add a `bucketFor(maps, ccy, universe)` helper seeding `{uid: Money(0)}`; fold expenses/settlements into per-currency buckets exactly as D1 (gates on `bucket.has(...)` preserved). Keep the `currencies.add(ccy.toUpperCase())` line.
**Step 2:** `npm run build` — fix the call sites it surfaces (next tasks). Do not run tests yet (recomputeNet not updated).

### Task 3: GREEN — `recomputeNet` net + perEventNet bucketing (D2)

**Files:** Modify `functions/src/callables/groupNetBalance.ts:454-594` + the `RecomputeResult` interface (`:319-357`).

**Step 1:** Flip `net`/`perEventNet` types; rewrite `addNet` to `(ccy, uid, delta)` accumulating into `netByCurrency`; track `seenUids`; accumulate event folds per bucket; bucket the group-scope settlement fold (`:573-585`); add `finalizeNet(netByCurrency, seenUids)` (the no-money 'OMR' fallback + list-all-seenUids-per-bucket) and `bucketizeDrill(slice, drillUniverse)` for `perEventNet` (D2); update the `RecomputeResult.currencies` doc-comment per D3/D5.
**Step 2:** `npm run build` — green for groupNetBalance; gates + aggregator now fail to compile (next tasks).

### Task 4: GREEN — gates per-bucket-zero (D4)

**Files:** Modify `deleteGroup.ts:254-272`, `leaveGroup.ts:86-103`, `removeMember.ts:123-140`.

**Step 1:** Apply the D4 edits to all three (drop `currencies` destructure + the `size>1` blocks; per-bucket-zero predicate).
**Step 2:** `npm run build` — gates compile.

### Task 5: GREEN — Shim #2 in the aggregator (D6)

**Files:** Modify `functions/src/triggers/balanceAggregator.ts:84-121`.

**Step 1:** Insert the flatten-singleton adapter; point the encode loops at `flatNet`/`flatPerEventNet`; `degraded = multiCurrency || mapsBytes > maxBytes()`.
**Step 2:** `npm run build` — whole `functions/` compiles clean.

### Task 6: GREEN — run the full TS suite

**Step 1:** `npm run test:emulator`. Expected: Task-1 RED tests now PASS; `balanceAggregator.test.ts`/`balanceReconciler.test.ts` UNCHANGED-green (Shim proof); 9b/9c/8b/10b still green (now per-bucket reasoning).
**Step 2:** Apply the D8 test-9 rewrite (settlement → USD/400) + the 9b/9c/8b/10b comment updates. Re-run — all green.

### Task 7: Dart parity case (D9)

**Files:** Modify `test/unit/delete_group_balance_parity_test.dart`.

**Step 1:** Add the mixed-currency parity case (D9). **Step 2:** `flutter test test/unit/delete_group_balance_parity_test.dart` — green. **Step 3:** `flutter analyze` — clean.

### Task 8: Final verification + ship

**Step 1:** `cd functions && npm run test:emulator` (full) + `flutter analyze` + `flutter test test/unit/delete_group_balance_parity_test.dart`.
**Step 2:** Conventional commit `feat(functions): bucket the balance oracle per currency + per-bucket-zero gates (#382 PR-2)`; PR body carries `Spec: docs/plans/2026-06-12-382-pr2-server-bucketing.md` + `Refs #382` (epic stays open; in the COMMIT body too — squash auto-closes from the commit message).
**Step 3:** `/automerge <N>` (Gate-category: `functions/**` — fresh-context review + refuter).
**Step 4:** On merge: `deploy-ceremony` skill (functions deploy; `backend-deployed` baseline `fdf8460b`, only PR-2 in the delta), advance the `backend-deployed` tag, record in `docs/DEPLOY-LEDGER.md`.
