# #366 — Server-Maintained Per-Group Balance Aggregate (O(G×E) → O(G)) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> Gate-mandatory: money math + firestore.rules + Cloud Functions + schema. Do not start Task 1 until the Gate verdict has no [P1]s.

**Goal:** Home reads one server-maintained balance doc per group instead of running O(G×E) client-side Firestore reads per refresh; the doc is maintained by Cloud Function triggers that call the existing shared oracle (`recomputeNet`), so there is no third money-math implementation.

**Architecture:** Four new Firestore triggers + one scheduled reconciler call a shared handler that re-runs `recomputeNet` (extended to also emit the per-event drill-down) and writes `groups/{gid}/aggregates/balance` behind a source-time ordering guard inside a transaction. The doc is a **display cache, never OUTBOUND**: nothing writes or settles money based on it — settle-up, deleteGroup/leaveGroup/removeMember gates, and all in-group screens keep computing live. The home dashboard reads the doc when online; when offline (or the doc is missing/degraded) it falls back to the existing `groupBalancesOnceProvider` path, which is the only source that can see the user's own queued offline writes.

**Tech Stack:** firebase-functions v2 (Node 22, TS), decimal.js `Money` clone, Firestore rules, Flutter/Riverpod 2.x, Jest + Firestore emulator (`firebase-functions-test` wrap pattern), `fake_cloud_firestore`/`mocktail` on the Dart side.

**Branch/worktree:** `feat/366-balance-aggregate` in `/Users/nasseralbusaidi/Desktop/Personal/Rihla-366` (off main `ebecce78`).

---

## Part 0 — The decided contract (acceptance box 1)

### 0.1 Why this shape

The issue text fears a "third money-math surface that must mirror the client `BalanceCalculator` and the TS `deleteGroup` oracle byte-for-byte". The design dissolves that fear instead of managing it: the trigger does **not** implement balance math. It calls `recomputeNet` (`functions/src/callables/groupNetBalance.ts:345`), the same shared oracle `deleteGroup`/`leaveGroup`/`removeMember` already use. Parity with the client is inherited from the existing oracle contract (`delete_group_balance_parity_test.dart` + the single-TS-copy structure). The only **new** parity surface is the per-event drill-down slice (§0.3), which mirrors the client's `_buildPerEventBreakdown` (`lib/features/groups/providers/group_balance_provider.dart:432-471`) and gets its own differential fixtures.

Full recompute-on-write (not incremental deltas) is deliberate:
- **Idempotent under at-least-once delivery** — replaying a trigger event recomputes the same state; no applied-delta ledger needed.
- **Self-healing** — any missed event is corrected by the next write or by the daily reconciler.
- **No drift by construction** — an incremental delta implementation would be the feared third money surface.
- Cost: O(events) reads per money write. Writes are human-scale (a person tapping "Add expense"); groups are small. This is the same cost `deleteGroup` already pays per call.

### 0.2 Who reads what (callsite classification — verification principle 1)

Every consumer of the aggregate doc is **INBOUND (display only)**:

| Surface | Today (main `ebecce78`) | After PR2 |
|---|---|---|
| `BalanceHeroCard` | `crossGroupBalanceOnceProvider` (`balance_hero_card.dart:32`) | new cross-group fold over the facade provider |
| Home `_GroupRow` (net + eventCount) | `groupBalancesOnceProvider(group.id)` (`home_screen.dart:628,637`) | facade `userNet` + `eventCount` |
| Journey tickets (per-event net) | `perEventBreakdown[uid][event.id]` from the once-path (`active_journeys_provider.dart:158-176`) | facade `userPerEventNet[event.id]` |

**OUTBOUND surfaces are untouched and never read the doc:**
- Group settle-up: LIVE `groupBalancesProvider` + `memberRawNames` + `calculateOptimalSettlements` (`group_settle_up_screen.dart:89-160`) — needs the full `GroupBalances` record (names, raw names, breakdown), which the doc deliberately does not carry.
- Event settle-up / ledger: live event streams + `ledgerViewProvider`.
- Server gates: `deleteGroup`/`leaveGroup`/`removeMember` call `recomputeNet` fresh per invocation — they never trust the cached doc.

This single invariant bounds the blast radius of any aggregate bug to: a wrong number *displayed on home* until the next write/reconcile. No money write can be derived from it. The doc's rules block (server-only write) makes the invariant structural, and PR2 adds no write path that reads the doc.

### 0.3 Document contract (verification principle 5 — exact keys)

Path: `groups/{gid}/aggregates/balance` (new `aggregates` subcollection, fixed doc id `balance`).

```jsonc
{
  "schemaVersion": 1,
  "currency": "OMR",                 // group.currency at compute time. Immutable per rules
                                     // (firestore.rules:296-307), so never stale.
  "currencies": ["OMR"],             // sorted recomputeNet.currencies (EXPENSE currencies only —
                                     // the oracle's documented #261 contract). size > 1 ⇒ legacy
                                     // mixed-currency group; client must not render a single-
                                     // currency number from netMilli (falls back, §0.7).
  "netMilli": { "<uid>": -12500 },   // recomputeNet.net × 1000, integer. Full per-event universe
                                     // (participantIds ∪ former financial actors ∪ member-gated
                                     // split recipients) + group-scope settlements folded.
                                     // A uid absent from the map has net zero.
  "perEventNetMilli": {              // drill-down slice for journey tickets. Mirrors the client
    "<eventId>": { "<uid>": 4000 }   // _buildPerEventBreakdown contract: universe =
  },                                 // event.participantIds ONLY, event-scoped expenses +
                                     // event settlements only, NO group settlements, empty-
                                     // participant events omitted.
  "eventCount": 3,                   // count of live (isDeleted === false) events.
  "degraded": false,                 // true ⇒ maps omitted because the encoded doc would
                                     // approach the 1 MiB limit; client must treat as missing.
  "sourceTimeMs": 1760000000000,     // ordering guard (§0.5). CloudEvent time millis for
                                     // triggers; sweep-start millis for the reconciler.
  "computedAt": "<serverTimestamp>"  // observability only; never compared.
}
```

**Keying:** uid = Firebase Auth UID, exactly the keys `recomputeNet.net` already uses (member `userId` field values and event `participantIds` — never member doc ids; the #294 creator-doc trap doesn't apply because the oracle already matches by the `userId` field, `groupNetBalance.ts:357-366`). Firebase UIDs are alphanumeric, so they are always legal Firestore map keys.

**Milli encoding (why ×1000 is exact):** every value the oracle emits is an integer multiple of `1/scale` for its currency, `scale ∈ {1, 100, 1000}` (`CURRENCY_SCALE`, `groupNetBalance.ts:29-40`): allocations are quantized to subunits (`quantize`, `:62-66`), last-recipient remainders and exact-mode residual close-outs are differences of subunit-exact values, and settlement amounts decode from integer `amountFils`. All three scales divide 1000, so `net × 1000` is always an integer — including for legacy mixed-currency folds, which is why the encoding is currency-agnostic milli rather than "group-currency subunits". A defensive non-integer branch truncates toward zero (mirroring `MoneySerializer`) and logs an error; tests pin that it is unreachable for oracle output.

**Non-decomposition warning (verification principle 6):** `netMilli[uid]` is **NOT** `Σ_e perEventNetMilli[e][uid]`. Three deliberate gaps: (a) the drill-down universe is `participantIds`-only, so a former financial actor (e.g. a departed payer, #249) appears in `netMilli` but not in any `perEventNetMilli` slice — this is the client's pinned contract (`group_balance_provider_test.dart` pins the drill-down as participantIds-only); (b) group-scope settlements fold only into `netMilli` (mirror of `group_balance_provider.dart:339-357` / `groupNetBalance.ts:526-536`); (c) out-of-universe owed drops differ between the two universes. Never "reconcile" one map from the other, on either side of the wire.

### 0.4 Maintenance: triggers (acceptance box 2)

New module `functions/src/triggers/balanceAggregator.ts`, four exports, all calling one shared `refreshGroupBalanceAggregate(db, groupId, sourceTimeMs)`:

| Export | Path | In-code gate before recompute |
|---|---|---|
| `eventModuleBalanceAggregator` | `groups/{gid}/events/{eid}/{module}/{docId}` (the `writeRateMonitor.ts:104-110` wildcard precedent) | `module` ∈ {`expenses`, `settlements`} (skips `activity_logs` — the audit logger writes one per expense edit); balance-key diff gate |
| `groupSettlementBalanceAggregator` | `groups/{gid}/settlements/{settlementId}` | balance-key diff gate |
| `eventBalanceAggregator` | `groups/{gid}/events/{eid}` | balance-key diff gate |
| `memberBalanceAggregator` | `groups/{gid}/members/{memberId}` | balance-key diff gate |

All `onDocumentWritten` (covers client creates, soft-deletes, **and Admin-SDK in-place migrations** — `cleanupAnonUidArtifacts` rewrites expense/settlement uid fields, which `onDocumentCreated` would miss). No options object (256MiB/60s defaults, the codebase precedent); **no `retry: true`** — a transiently lost event self-heals on the next write or the daily reconciler, while retry on a deterministic bug would storm for up to 7 days. (Gate may revisit.)

Balance-key diff gates (the `expenseAuditLogger.classify` precedent, `expenseAuditLogger.ts:24-36,64-82` — `deepEqual` over a key set; skip when nothing relevant changed):

```ts
const EXPENSE_BALANCE_KEYS = ['amountFils','currency','payerParticipantId','scope',
  'subGroupId','splitMode','splitDistribution','customSplitParticipants','isDeleted'];
// description/note/categoryId/receiptUrl/lastEditedBy edits don't move money → skip.
const SETTLEMENT_BALANCE_KEYS = ['amountFils','currency','payerParticipantId',
  'recipientParticipantId','isDeleted'];
const EVENT_BALANCE_KEYS = ['participantIds','isDeleted'];
// participantNames-only updates (renames) don't move money → skip.
const MEMBER_BALANCE_KEYS = ['userId','isTombstone'];
// displayName changes don't move money → skip.
```

Mutations covered without a dedicated trigger:
- `joinGroupByInviteCode` → event docs gain `participantIds` entries → `eventBalanceAggregator` fires.
- `leaveGroup`/`removeMember`/`deleteAccount` → member docs deleted/tombstoned → `memberBalanceAggregator` fires.
- `cleanupAnonUidArtifacts` → expense/settlement/member rewrites fire their triggers; the guarded last-write converges the storm.
- `deleteGroup` → the handler **skips** groups with `isDeleted === true` or `deletingInProgress === true` (the cascade owns that window; recomputing mid-cascade is wasted work), and the cascade gains one `delete` of the aggregate doc (PII hygiene + tidiness).

### 0.5 Ordering guard (why last-write-wins is safe)

The recompute reads happen outside any transaction, so two concurrent recomputes could finish out of order. The write is guarded inside a transaction:

```
tx.get(aggRef); if (existing.sourceTimeMs > incoming.sourceTimeMs) skip; else tx.set(...)
```

Soundness argument: trigger `sourceTimeMs` is the CloudEvent time ≈ the Firestore commit time of the triggering write. If `t1 < t2`, then write₁ committed before write₂, so the recompute triggered by write₂ — whose reads all start after write₂'s commit — observes write₁ as well. Therefore the recompute with the **greatest** source time has observed every earlier write, and skipping any recompute with a smaller source time discards only information the surviving write already contains. Equal times (one batch commit fanning out to several trigger events, or an at-least-once redelivery of the same event) pass the guard and overwrite with identical data — idempotent. A write that lands *during* a recompute's reads produces at worst a transiently torn doc; that write's own trigger carries a strictly greater source time and repairs it seconds later. Acceptable for a display cache (§0.2); pinned in tests by the stale-skip and equal-time cases.

The reconciler stamps `sourceTimeMs` = its own per-group sweep-start time, captured **before** its reads — so any write that races the sweep wins the guard with a later trigger time.

### 0.6 Reconciliation + backfill (acceptance box 1, second half)

One new scheduled function `balanceReconciler` (`functions/src/scheduled/balanceReconciler.ts`, the `deletionReaper` precedent: `onSchedule({schedule: 'every 24 hours', timeoutSeconds: 540, memory: '1GiB'})`, env seam `BALANCE_RECONCILER_BATCH` default 200):

1. Query `groups` where `isDeleted == false`, limit batch (single-field auto-index; no composite needed).
2. Per group (try/catch per doc, `deletionReaper.ts:30-50` style): run the same `refreshGroupBalanceAggregate`; before writing, compare the freshly computed maps against the existing doc and `logger.warn` on drift (a trigger should have kept it fresh — drift means a lost event or a bug).
3. Final `logger.info({scanned, refreshed, drift, failures})` — and a loud `logger.warn` if `scanned == batch` (possible truncation; no silent caps).

**Backfill strategy = the reconciler's first run.** Existing groups get their doc within 24h of deploy (or immediately via `gcloud scheduler jobs run` during the deploy ceremony); until then the client fallback (§0.7) serves those groups exactly as today. No separate backfill script, no migration flag day.

**Oracle-version churn:** when balance semantics legitimately change (a future #261 Model-B, a new allocator rule), the deploy of the new Functions revision makes the reconciler rewrite every doc within a day; `schemaVersion` bumps only when the doc *shape* changes (client decode contract).

### 0.7 Client read path + offline stance (acceptance box 3)

New facade `homeGroupBalanceProvider` (Provider.family, in `group_balance_provider.dart`) — the **single** home-side chooser:

```
uid == null                         → zeros
connectivityProvider != online      → once-path (local truth)
aggregate doc loading               → loading
aggregate doc present, !degraded,
  currencies.length <= 1            → aggregate values  (steady state: zero per-event reads)
aggregate doc missing / degraded /
  legacy-mixed (currencies > 1) /
  stream error                      → once-path (today's behavior, incl. #244 partial)
```

- `groupBalanceAggregateProvider = StreamProvider.family<GroupBalanceAggregate?, String>` — a **live single-doc listener** per group: O(G) listeners total, which is the same order as the already-live per-group list providers; this is not a #104-style O(G×E) reopen. Streaming (vs one-shot) removes the need for any revision bump on the aggregate path and makes pull-to-refresh redundant there.
- **Offline stance (the #412 interaction):** the once-path reads the SDK cache *including the user's own queued writes* (post-#412 the `ledgerRevisionProvider` bump fires on queued outcomes too — `add_expense_screen.dart:52`, `edit_expense_screen.dart:112,190`, `settle_up_screen.dart:353`), so it is **fresher than any server doc can be while offline**. The facade therefore prefers local truth whenever `connectivityProvider` ≠ `ConnectivityStatus.online` (`connectivity_provider.dart:9,14-16`). `syncing` counts as not-online on purpose: queued writes may not have replayed yet. Windows: (a) just-went-offline, probe still says online (≤60s, or ≤ ~5s after any money write — `noteQueuedWrite` flips state on the write-timeout path) → home shows last-synced server truth, same numbers as before going offline; (b) just-reconnected → once-path until the probe flips, then a ~1-3s trigger lag before the doc reflects replayed writes. Both windows converge and only affect home display; the ledger/event screens stay live-correct throughout.
- **The `ledgerRevisionProvider` bump contract is unchanged.** New event-level money write paths must still bump it — the fallback/offline path depends on it. (CLAUDE.md gotcha stays as written.)
- The hero's per-currency buckets (#261/#377) come from folding each group's facade `userNet` by `group.currency`, exactly as `crossGroupBalanceOnceProvider` folds today (`_accumulateBucket`/`_sortedCurrencyBuckets` are reused verbatim). `partial` (#244) propagates only from groups on the fallback path; the aggregate path contributes `partial: false` (the server saw every event).
- **Online add-expense latency note:** today home updates instantly after the bump (client recompute from cache); after PR2 the online path updates after the server trigger roundtrip (~1-3s after the write acks, while the user is typically still on the ledger screen). Accepted trade-off; called out for RD-QA re-baselining.

### 0.8 Ledger pagination: deferred by design (acceptance box 4 → re-scope)

The understanding pass falsifies the issue's pairing premise for the **event ledger**:

1. The balance strip / hero statement on `LedgerScreen` needs **all** non-deleted expenses+settlements of the event (`ledgerViewProvider` runs `BalanceCalculator` over the full streams — `ledger_view_provider.dart:52-61`), and must stay client-side live for latency compensation and offline correctness (#412/#357 — just QA'd).
2. Ledger search and category filters are **in-memory** over the full lists (`ledger_screen.dart:60,108-109,217-230,253-262`); paginating the display would break or re-platform both.
3. Rendering is already virtualized (sliver `SliverChildBuilderDelegate`, `ledger_screen.dart:237-381`) — render cost is bounded without pagination.
4. Therefore cursor-paginating the *display* while the *compute/search/filter* stream stays unbounded **doubles** reads instead of reducing them. The genuine unbounded-growth surface (home's O(G×E)) is solved by the aggregate doc; a single event's collection is human-bounded (one event's spending, not a lifetime's).

Decision: **defer** ledger pagination to a new evidence-gated follow-up issue ("paginate when a real event ledger exceeds ~N hundred docs; requires moving strip/search/filter off the full stream, e.g. onto the aggregate's per-event slices + a server-side search design"). #366's box 4 is satisfied as a *decision with rationale* per its `decision` label; the closing PR carries the finding and the follow-up link. (If the user prefers, #366 can instead stay open re-scoped to box 4 per the merge-hygiene rule — surfaced in the PR body either way.)

### 0.9 Verification principles — run log

1. **Callsite classification:** §0.2 table. All aggregate consumers INBOUND; OUTBOUND surfaces enumerated and untouched.
2. **Claims vs code:** every path/line in this spec re-grepped against worktree `ebecce78` on 2026-06-10 (post-#412 fast-forward; the readers' pre-merge citations were re-verified after the merge). Key re-checks: bump sites (4, unconditional post-#412), `connectivityProvider`/`ConnectivityStatus` names, `GroupService` location (`group_provider.dart:37` — not a separate file), oracle location (`functions/src/callables/groupNetBalance.ts` — CLAUDE.md's `deleteGroup.ts:520-585` pointer is stale), trigger wildcard precedent (`writeRateMonitor.ts:104-110`), stale "settle_up hardcodes OMR" comments in `groupNetBalance.ts:330-341` and `firestore.rules:904-911` (both contradicted by live client writes passing `group.currency` — flagged for cleanup in PR1, comments only).
3. **Read-path per write-path:** doc write (trigger) → reads: `homeGroupBalanceProvider` → hero/rows/tickets (PR2); `balanceReconciler` (drift compare); nothing else. Named and tested.
4. **Fields from types:** doc schema enumerated field-by-field in §0.3; `RecomputeResult` extension (`perEventNet`, `eventCount`) enumerated in Task 2; Dart model fields mirror §0.3 exactly.
5. **Data contracts spelled out:** §0.3 (exact keys, exact encoding, exact absence semantics).
6. **Arithmetic decomposition:** §0.3 non-decomposition warning — `netMilli` does NOT decompose across `perEventNetMilli`; three named reasons; pinned by the former-actor parity fixture (Task 8).
7. **Adversarial pass, orthogonal axes:** the perf fix is on the read axis; the worked fixtures exercise the **identity** axis (departed payer → in net, not in drill-down; tombstoned member; duplicate display names are irrelevant because keys are uids) and the **settlements** axis (group-scope settlement moves net but no per-event slice; event settlement moves both) and the **time** axis (stale-trigger skip, reconciler race). See Tasks 7–8 fixtures.

### 0.10 Risks / explicitly accepted

- **Offline home staleness** is fully mitigated by the connectivity-gated fallback (§0.7); residual: the ≤60s probe-lag window before any write attempt.
- **Trigger storm during cleanup migrations**: N recomputes for N rewritten docs; converges via the guard; wasted compute accepted at human scale.
- **1 MiB doc ceiling**: `perEventNetMilli` is E×U entries (≈40 bytes each; a 100-event × 10-member group ≈ 40 KB). The degraded-doc escape hatch (§0.3) keeps the failure mode loud-safe (client falls back) instead of a permanently stale doc behind a failing write.
- **`crossGroupBalanceOnceProvider` is deleted in PR2** (two lib consumers: the hero watch at `balance_hero_card.dart:32` and the pull-to-refresh invalidate at `home_screen.dart:122` — both rewired in Task 11); `groupBalancesOnceProvider` stays (fallback path). Tests migrate, not patch (CLAUDE.md removal rule).
- **5 new deployed functions** (4 triggers + 1 scheduled) via multi-line `export { } from` blocks (extractor contract, `tool/list_expected_functions.sh` + `release_workflow_gate_test.dart:589-623`). Deploy via the deploy-ceremony after PR1 merges; no client-compat gating (no real users).

---

## Part 1 — PR1: server (functions + rules) — branch `feat/366-balance-aggregate-server`

All commands run from the worktree root unless noted. Functions tests: `cd functions && npm run test:emulator` (Java 21; isolated ports). TDD: every task writes the failing test first.

### Task 1: Oracle extension — `recomputeNet` emits the drill-down + eventCount

**Files:**
- Modify: `functions/src/callables/groupNetBalance.ts` (extend `RecomputeResult`; add the participantIds-only fold inside the existing event loop)
- Test: `functions/test/callables/groupNetBalance.test.ts` (new file)

**Step 1: Write the failing test.** Seed (emulator, `fixtures.ts` helpers) a group `g1`, members `alice`/`bob` (live) + `carol` (tombstoned former member), event `e1` with `participantIds: [alice, bob]`:
- expense 9.000 OMR paid by `carol` (former-actor payer, equal split, scope global) — *net* universe = {alice, bob, carol}; *drill-down* universe = {alice, bob}.
- event settlement: alice → bob 1.000 OMR.
- group settlement: bob → alice 2.000 OMR.

Assert `recomputeNet` returns (Decimal equality):
- `net`: carol +6.000 (paid 9, owed 3), alice −2+1−... compute precisely in-test from the oracle's own documented rules; pin literal expected values: carol = 9.000 − 3.000 = +6.000; alice = −3.000 (owed) + 1.000 (settlement paid) + 2.000 (group settlement recipient → −2.000? **recipient nets −amount**) ⇒ alice = −3.000 + 1.000 − 2.000 = −4.000; bob = −3.000 − 1.000 + 2.000 = −2.000. (Sum = 0 ✓ conservation.)
- NEW `perEventNet['e1']`: universe {alice, bob} only — equal split of 9.000 over **2** heads = 4.500 each; carol's paid is dropped (payer outside universe); alice: −4.500 + 1.000 = −3.500; bob: −4.500 − 1.000 = −5.500. **No `carol` key. No group-settlement effect.**
- NEW `eventCount == 1`.
- Existing fields (`currencies == {'OMR'}`, `liveEventRefs.length == 1`) unchanged.

**Step 2: Run it — must fail** with "perEventNet is not a property" (compile error counts as RED for TS).
`cd functions && npm run test:emulator -- --testPathPattern groupNetBalance`

**Step 3: Implement.** In `RecomputeResult` add `perEventNet: Map<string, Map<string, Decimal>>` and `eventCount: number`. Inside the existing per-event loop (after the universe fold, reusing the already-loaded `expenses`/`settlements` arrays — **no second Firestore read**), add a second fold with `universe2 = new Set(participantIds)`; skip when empty; reuse `allocateEqual/Shares/Exact/Percent` verbatim; same `paid.has/owed.has/settlementAdj.has` drop semantics; store `paid2 + adj2 − owed2` per uid into `perEventNet.set(eventDoc.id, …)`. `eventCount = liveEventDocs.length`. Mirror comments pointing at `_buildPerEventBreakdown` (`group_balance_provider.dart:432-471`) as the client contract.

**Step 4: Run the new test (PASS) and the full existing suite (behavior preservation proof):**
`npm run test:emulator` → all green, including `deleteGroup.test.ts` / `leaveGroup` / `removeMember` untouched-green.

**Step 5: Commit** `feat(functions): recomputeNet emits per-event drill-down + eventCount (#366)`

### Task 2: Shared handler `refreshGroupBalanceAggregate` (encode + guard + degraded)

**Files:**
- Create: `functions/src/triggers/balanceAggregator.ts` (handler + `toMilli` + `encodeAggregate`, exported for tests)
- Test: `functions/test/triggers/balanceAggregator.test.ts`

**Step 1: Failing tests** (call the exported handler directly with the emulator db):
1. Fresh group (Task 1 fixture) → handler(sourceTimeMs=1000) → doc exists at `groups/g1/aggregates/balance` with exact `netMilli` {carol: 6000, alice: −4000, bob: −2000}, `perEventNetMilli` {e1: {alice: −3500, bob: −5500}}, `eventCount: 1`, `currency: 'OMR'`, `currencies: ['OMR']`, `degraded: false`, `sourceTimeMs: 1000`, `schemaVersion: 1`, `computedAt` is a Timestamp.
2. Stale skip: pre-write doc with `sourceTimeMs: 2000`; handler(1000) → doc unchanged (compare full data).
3. Equal time: handler(2000) twice → doc identical, no throw (idempotent redelivery).
4. `deletingInProgress: true` on group → handler returns without writing (no doc).
5. `isDeleted: true` on group → same skip.
6. Degraded: set env `BALANCE_AGGREGATE_MAX_BYTES=10` (env seam read at call time, codebase convention) → doc has `degraded: true`, **no** `netMilli`/`perEventNetMilli` keys, but valid `sourceTimeMs`/`schemaVersion`.
7. `toMilli` unit cases: `Decimal('1.234')→1234`, `Decimal('-0.001')→-1`, JPY-style integer `Decimal('7')→7000`; the defensive non-integer branch truncates toward zero (feed `Decimal('0.0005')` directly).

**Step 2: RED.** **Step 3: Implement** per §0.4/§0.5 (transaction guard `existing.sourceTimeMs > incoming → skip`; size estimate via `JSON.stringify(payload).length > maxBytes (default 900_000)` → degraded). **Step 4: GREEN + full suite.** **Step 5: Commit** `feat(functions): guarded balance-aggregate writer (#366)`.

### Task 3: The four trigger exports + diff gates

**Files:**
- Modify: `functions/src/triggers/balanceAggregator.ts` (add `onDocumentWritten` exports + `shouldRecompute(before, after, keys)` pure helper)
- Modify: `functions/src/index.ts` (one multi-line `export { eventModuleBalanceAggregator, groupSettlementBalanceAggregator, eventBalanceAggregator, memberBalanceAggregator } from './triggers/balanceAggregator';`)
- Test: extend `functions/test/triggers/balanceAggregator.test.ts` (wrap pattern from `expenseAuditLogger.test.ts:6-28` — `functionsTest`, `makeChange`, CloudEvent partial `{data, params, id, time}`)

**Step 1: Failing tests:**
1. Expense create event (wrapped `eventModuleBalanceAggregator`, `module: 'expenses'`, time `T`) → doc written with `sourceTimeMs == Date.parse(T)`.
2. `module: 'activity_logs'` event → **no** doc write.
3. Description-only expense update (before/after differ only in `description`) → no write (`shouldRecompute` false).
4. `participantNames`-only event update → no write; `participantIds` change → write.
5. Member `displayName`-only update → no write; `isTombstone` flip → write.
6. Group settlement create → write.
7. Pure-helper table tests for `shouldRecompute` over all four key sets (create: always true when `after` exists & relevant; hard delete (`!after.exists`): true — defensive, Admin-only).
8. Out-of-order delivery convergence via `event.time`: fire trigger event A (time `T2`) then trigger event B (time `T1 < T2`, an earlier write delivered late) → doc reflects the recompute stamped `T2`; B's write is skipped by the guard (Gate R1 P3 — pins `Date.parse(event.time)` as the ordering key end-to-end, not just the guard helper).

**Step 2: RED. Step 3: implement** (thin wrappers: gate → `refreshGroupBalanceAggregate(db, gid, Date.parse(event.time))`). **Step 4: GREEN + `npm run lint` + full suite. Step 5: Commit** `feat(functions): balance-aggregate triggers on money/membership writes (#366)`.

### Task 4: Reconciler

**Files:**
- Create: `functions/src/scheduled/balanceReconciler.ts`
- Modify: `functions/src/index.ts` (`export { balanceReconciler } from './scheduled/balanceReconciler';`)
- Test: `functions/test/scheduled/balanceReconciler.test.ts` (wrap with the `as any` cast — `deletionReaper.test.ts:9-11` precedent)

**Step 1: Failing tests:** (a) two groups, one missing its doc, one with a stale-wrong doc → after run both docs correct (backfill + heal); (b) soft-deleted group → untouched; (c) drift case logs `warn` (spy on logger) and still heals; (d) per-group failure (poison fixture: make one group's read throw via a closed… — simplest: stub `refreshGroupBalanceAggregate` failure path by env? Skip fault-injection; assert summary log shape `{scanned, refreshed, drift, failures}` instead); (e) `BALANCE_RECONCILER_BATCH=1` → processes 1, warns possible truncation.
**Step 2-5:** RED → implement per §0.6 → GREEN + full suite → commit `feat(functions): daily balance-aggregate reconciler (backfill + drift heal) (#366)`.

### Task 5: Rules — `aggregates` read block + deleteGroup cascade delete

**Files:**
- Modify: `security/firestore.rules` (inside `match /groups/{groupId}`, alongside the members block):
  ```
  // #366 — server-maintained balance aggregate (display cache).
  // Written ONLY by the balanceAggregator triggers / balanceReconciler via the
  // Admin SDK (bypasses rules). Clients read, never write — the aggregate must
  // never become an OUTBOUND money surface.
  match /aggregates/{aggregateId} {
    allow read: if isGroupMember(groupId);
    allow create, update, delete: if false;
  }
  ```
- Modify: `functions/src/callables/deleteGroup.ts` — cascade deletes `groups/{gid}/aggregates/balance` (one extra delete alongside the existing child-doc sweep; find the existing subcollection scrub and add `aggregates` to it, or a targeted `delete()` — match the file's local pattern).
- Modify (comments only, same PR — they are this feature's blast radius): refresh the two stale "settle_up hardcodes OMR" comments (`groupNetBalance.ts:330-341` rationale paragraph, `firestore.rules:904-911`) to say the client now writes `group.currency` (#376/#377) and the expenses-only `currencies` contract defends *legacy* docs.
- Test: `functions/test/firestore-rules-publish-readiness.test.ts` — member read allowed, non-member read denied, member create/update/delete denied; `deleteGroup.test.ts` — aggregate doc gone after cascade.

**Steps:** failing rules tests → RED → rules edit → GREEN → full emulator suite → commit `feat(rules): client-read server-write balance aggregate + cascade cleanup (#366)`.

### Task 6: TS-side parity fixtures

**Files:**
- Test: extend `functions/test/triggers/balanceAggregator.test.ts` with the hand-ported mirror block (the `delete_group_balance_parity_test.dart` ↔ `deleteGroup.test.ts` convention: fixture constants cross-referenced by case id in comments)

Cases (subunit ints on the TS side):
- **P1 (identity axis):** the Task 1 former-actor fixture — pins net-includes/drill-down-excludes.
- **P2 (settlement axis):** group settlement only (no expenses) — `netMilli` moves, `perEventNetMilli` empty.
- **P3 (rounding):** 3-way equal split of 0.100 OMR (alphabetically-last absorbs) — pins milli encoding of the remainder contract.
- **P4 (exact-residual, mirrors Dart case 1b):** in-tolerance exact split — pins the residual close-out flows into the doc.
- **P5 (negative legacy, mirrors 1c/1d/1e):** negative split value → equal-split fallback parity in the doc.

**Steps:** write → run → green (these pass once Tasks 1–3 are green; any failure is a parity bug) → commit `test(functions): aggregate parity fixtures P1-P5 (#366)`.

### Task 7: PR1 wrap-up

1. `cd functions && npm run lint && npm run build` clean; `npm run test:emulator` full green.
2. `tool/list_expected_functions.sh` lists all 18 (13 + 5 new); `flutter test test/unit/release_workflow_gate_test.dart` green.
3. `flutter analyze` clean (no Dart changes in PR1, but run it).
4. Push branch, open PR: title `feat(functions): server-maintained per-group balance aggregate (#366)`, body carries `Refs #366` (epic continues in PR2), the §0 contract summary, `Spec: docs/plans/2026-06-10-366-balance-aggregate.md`, RED evidence (pasted failing-first outputs per task), deploy note (deploy-ceremony after merge; reconciler first run = backfill).
5. `/automerge <N>` (Gate-category → fresh review + refuter).
6. After merge: run the **deploy-ceremony** skill (new functions: 4 triggers + balanceReconciler; optionally `gcloud scheduler jobs run` the reconciler for immediate backfill; verify a prod group doc appears).

---

## Part 2 — PR2: client home read path — branch `feat/366-balance-aggregate-client` (after PR1 deploys)

### Task 8: Dart model + Dart-side parity pins

**Files:**
- Create: `lib/features/groups/models/group_balance_aggregate_model.dart`
- Test: `test/unit/group_balance_aggregate_model_test.dart`
- Test: `test/unit/balance_aggregate_parity_test.dart` — Dart half of the P1–P5 fixtures: run `computeGroupBalances` / `_buildPerEventBreakdown`-equivalent inputs through the client and pin the SAME literal nets the TS fixtures pin (cross-referenced case ids). This is the differential lock for the new drill-down surface.

Model: final fields per §0.3 (`netByUid: Map<String, Decimal>` decoded `milli/1000`, `perEventNetByUid`, `eventCount`, `currency`, `currencies`, `degraded`, `computedAt` — plus `schemaVersion` is consumed by the decode gate; `sourceTimeMs` is server-internal and deliberately NOT modeled client-side); `static GroupBalanceAggregate? fromDoc(Map<String,dynamic>? data)` — boundary validation: missing/garbage fields → null (treat as missing → fallback), unknown `schemaVersion > 1` → null, non-int milli values skipped with the entry dropped. Immutable, no mutation.

**Steps:** failing decode tests (golden map → exact Decimals; garbage → null; degraded → null) → RED → implement → GREEN → commit.

### Task 9: Stream provider + service method

**Files:**
- Modify: `lib/features/groups/providers/group_provider.dart` — `GroupService.watchBalanceAggregate(String groupId)` (doc snapshots of `groups/{gid}/aggregates/balance`, mapped through `fromDoc`, emits null when absent)
- Modify: `lib/features/groups/providers/group_balance_provider.dart` — `groupBalanceAggregateProvider = StreamProvider.family<GroupBalanceAggregate?, String>`
- Test: `test/unit/group_balance_aggregate_provider_test.dart` (FakeFirebaseFirestore; seed doc → values; no doc → null; doc update → re-emit)

**Steps:** RED → implement → GREEN → commit.

### Task 10: Facade `homeGroupBalanceProvider`

**Files:**
- Modify: `lib/features/groups/providers/group_balance_provider.dart` (typedef `HomeGroupBalance` = `({Decimal userNet, Map<String, Decimal> userPerEventNet, int eventCount, bool partial, bool fromAggregate})`; the chooser per §0.7)
- Test: `test/unit/home_group_balance_provider_test.dart` (counting fake services from `home_balance_once_104_test.dart:327-339` as template)

**Failing tests pin the chooser table:**
1. Online + doc present → values from doc; **zero** once-path reads (counting fakes assert 0 `getExpenses` calls).
2. Online + doc null → once-path values; reads happen; `partial` propagates.
3. Online + `degraded`/`currencies.length > 1` doc → once-path.
4. `ConnectivityStatus.offline` + doc present → once-path (local truth wins).
5. `ConnectivityStatus.syncing` → once-path.
6. uid null → zeros.
7. Revision bump while offline → once-path re-runs (existing contract preserved).

**Steps:** RED → implement → GREEN → commit.

### Task 11: Rewire hero, rows, tickets; delete `crossGroupBalanceOnceProvider`

**Files:**
- Modify: `lib/features/groups/providers/group_balance_provider.dart` — new `crossGroupHomeBalanceProvider` (folds facade per group via `_accumulateBucket`/`_sortedCurrencyBuckets`; `partial` = OR of fallback-path partials; delete `crossGroupBalanceOnceProvider` after consumers move)
- Modify: `lib/features/home/widgets/balance_hero_card.dart:32` (watch swap)
- Modify: `lib/features/home/screens/home_screen.dart:628-639` (_GroupRow → facade), `:113-124` (pull-to-refresh: invalidate facade-fallback families — keep `groupBalancesOnceProvider` invalidation, swap the cross-group one)
- Modify: `lib/features/home/providers/active_journeys_provider.dart:158-176` (tickets → facade `userPerEventNet`)
- Tests: migrate `test/unit/home_balance_once_104_test.dart` cross-group cases + `#244`/`#410` tests to the new provider; grep for the deleted provider name and remove obsolete assertions (don't patch them); widget test: hero renders from a seeded aggregate doc with FakeFirebaseFirestore overrides.

**Steps:** RED (new expectations) → rewire → GREEN → `flutter analyze` → full `flutter test` → commit.

### Task 12: PR2 wrap-up

1. Full suite + analyze green; goldens untouched (no visual change).
2. PR body: `Closes #366` **or** `Refs #366` + re-scope per §0.8 decision (state which, with the follow-up issue link), `Spec:` line, RED evidence.
3. File the follow-up issue (ledger pagination, evidence-gated, §0.8 text).
4. `/automerge` (Gate-category — money read-path + schema).
5. Post-merge: RD-QA note — re-baseline NS-cards that assert instant home updates after expense writes (online path now has ~1-3s trigger lag; offline path unchanged).
6. CLAUDE.md updates to surface in the PR: aggregate-doc pitfall entry (display-cache-only invariant + "never reconcile netMilli from perEventNetMilli"), stale `deleteGroup.ts:520-585` oracle pointer → `callables/groupNetBalance.ts`, stale #183 gotcha cleanup (already-fixed cursor ordering).

---

## Gate findings log

| Round | Verdict | P1s | Resolution |
|---|---|---|---|
| R1 (2026-06-10, fresh-context Opus) | **0 P1 / 0 P2 / 3 P3 — PASS** | none | Reviewer independently recomputed Task 1 / drill-down fixtures from live allocator code and confirmed (carol +6.000 / alice −4.000 / bob −2.000 net; alice −3.500 / bob −5.500 drill-down). P3s applied: §0.10 consumer-count fix; Task 8 schemaVersion/sourceTimeMs reconciliation; Task 3 out-of-order event.time convergence test added. |
