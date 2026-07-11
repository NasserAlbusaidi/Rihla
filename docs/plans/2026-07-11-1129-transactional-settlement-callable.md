# #1129 — Transactional settlement callable (server-side outstanding cap) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move every settlement CREATE behind one transactional Cloud Functions callable (`recordSettlement`) that recomputes the pair's outstanding balance inside the transaction via the shared oracle, caps `amountFils` at it, and writes with the #1093 deterministic idempotency key — closing #1093's accepted residuals 1 (different-amount concurrent settles over-settle), 2 (divergent-cache epoch dedup misses), 4 (hostile client writes any `positiveInt` amount), and 9 (cross-pair id squat).

**Architecture:** One callable, three modes (`event` solo, `group` solo, `groupSettleUp` decomposed), one `db.runTransaction` per call (the `correctSettlement`/`correctLogicalSettleUp` idiom — NOT the #1144 3-phase departure lock; see "Why one transaction"). The server derives the settlement doc id from the client's *observed* pair-epoch (retry-idempotent), enforces the cap from its own transaction-consistent recompute (over-settle-proof), and writes the settlement doc(s) + the ONE #1140 activity row atomically. `firestore.rules` then denies client settlement creates outright — the callable becomes the only writer, so the forged-amount hole closes. Settlement recording becomes **online-only** (the #889 corrections precedent, extended to creates — a cost #1129 explicitly accepts).

**Decision lineage:** Option (a) of #1093's fork, deferred 2026-07-10, activated 2026-07-11 by explicit direction (built ahead of the launch-telemetry trigger). The #1093 client-side dedup (option c) stays live semantics — same id grammar, same epoch concept — but derivation moves server-side.

**Tech stack:** TypeScript (functions/src, Node 22) — new callable + TS ports of `deterministicSettlementId`/leg/residual ids and `outstandingForPair`. Dart — client services rewired onto the callable; `crypto` usage for settlement ids REMOVED from the client. `security/firestore.rules` — settlement create denied, dead validators deleted, activity type allow-list tightened.

---

## Product trade-offs accepted (named up front — the Gate should challenge these, not rediscover them)

1. **Offline settlement recording dies.** HTTPS callables have no offline queue. Pre-flight connectivity check → honest "needs a connection" copy (new l10n en+ar); the queued/"will sync" snackbar branches for settlement creates become dead code and are deleted. Precedent: #889 corrections are already documented "ONLINE-ONLY … never the queued/'will sync' copy" (`firebase_functions_service.dart:129-137`). Expenses keep offline writes — untouched.
2. **The `writeRateMonitor.ts:6-9` header stance ("routing them through a callable/queue is forbidden") is explicitly superseded for settlements** — that comment and the CLAUDE.md line it cites are amended in Task 12. Expenses remain client-direct.
3. **Deploy freely** — no real users yet (CLAUDE.md), so rules flip + callable ship in one PR with no client-compat ordering. Deploy ceremony after merge.

## Invariants this plan relies on (each verified against code this session)

1. **Pairwise outstanding is derived from per-person NETS, not a pairwise ledger.** `BalanceCalculator.outstandingForPair` (`lib/features/ledger/providers/expense_provider.dart:970-987`) = `min(max(-fromNet,0), max(toNet,0))` over one currency bucket. The server oracle `computeNetFromSnapshot` (`functions/src/callables/groupNetBalance.ts:592`) already produces those nets per currency (`RecomputeResult.net`). The TS port is a ~15-line pure mirror, not a new allocator.
2. **Three cap bases, each mirroring the exact client basis** (this is the parity trap):
   - `event` mode: client #773 revalidates against the **single event's** balances on the #249 universe (`settle_up_screen.dart:555-617` `_freshOutstandingForPair`). Server mirror: run `computeNetFromSnapshot` on a snapshot containing ONLY that event and `groupSettlements: []` — the aggregate `.net` of a one-event snapshot IS that event's full-universe fold. No new fold logic.
   - `group`/`groupSettleUp` total: client caps against the group aggregate (`group_settle_up_screen.dart:658` → `outstandingForPair` on fresh group balances). Server mirror: full snapshot → `.net`.
   - `groupSettleUp` legs: client `decomposeGroupSettlement` (`expense_provider.dart:840-874`) pins `perEvent[e] <= min(|payerNet_e|, recipientNet_e)` on the **participantIds-only per-event drill-down**. Server mirror: `RecomputeResult.perEventNet` — which is participantIds-only BY DESIGN (groupNetBalance.ts; CLAUDE.md #366 note). Do NOT "fix" leg validation onto the #249 universe; the client's legs come from the participantIds-only breakdown.
3. **`db.runTransaction` reading whole subcollections is established precedent**: `correctSettlement.ts:123-127` (one settlements collection), `correctLogicalSettleUp.ts:115-121` (ALL live events' settlements + group settlements, uncapped). The #1144 3-phase lock (leaveGroup/removeMember/deleteGroup) exists to block CLIENT-direct balance-input writes during a multi-transaction window; `recordSettlement` has no such window (single tx) and, post-flip, no client-direct settlement writes exist to race. Client-direct EXPENSE writes racing the tx invalidate its read-set → automatic retry with fresh reads.
4. **Deterministic id grammar (#1093) is shared-namespace and must stay byte-identical**: `'sd1' + sha256('sd1\x1f<scopeKey>\x1f<payer>\x1f<recipient>\x1f<currency>\x1f<amountFils>\x1f<pairEpoch>').hex[0:40]` (`settlement_service.dart:140-159`); scopeKeys `event:<gid>:<eid>` / `group:<gid>` / `gsu:<gid>`; leg id `sha256('sd1leg\x1f<gsuId>\x1f<eventId>')`, residual `sha256('sd1res\x1f<gsuId>')` (`settlement_service.dart:183-189`). Pre-#1129 client-minted docs and post-#1129 server-minted docs share one namespace — same observed state collides across the transition. Golden vectors pin the TS port to Dart-era outputs (Task 1).
5. **Doc shapes** (server must write byte-compatible docs; rules stop validating them):
   - Event: `{id, eventId, payerParticipantId, recipientParticipantId, payerName, recipientName, amountFils(int), currency, note, isDeleted:false, deletedAt:null, settledAt(ISO), createdBy, groupSettleUpId?}` (`buildSettlementDoc`, `settlement_service.dart:90-124`).
   - Group: same + `{groupId, eventId:groupId(sentinel), scope:'group'}` (`buildGroupSettlementDoc`, `group_settlement_service.dart:90-125`).
   - Activity: `{id, type:'event_settlement'|'group_settlement', actorId, actorName, description, metadata, timestamp}` (`GroupActivityService.buildActivityDoc`); ONE row per logical settle (#1140: `settlement_service.dart:203-272`, `group_settlement_service.dart:140-360`).
6. **Rules gates the callable must mirror server-side** (Admin SDK bypasses rules): group write-lock five-flag OR (`correctSettlement.ts:85-94` — isDeleted/deletingInProgress/claimingInProgress/accountDeletionInProgress/departureInProgress); writer ∈ `memberIds`; event mode: event `!isDeleted` (`eventAllowsClientWrites` — settlements stay writable after close, `correctSettlement.ts:109-114`), counterparties ∈ `participantIds` AND ∈ `memberIds` (#1144, `firestore.rules:1044-1068`); group mode: counterparties ∈ `memberIds` (`firestore.rules:1320-1328`); `payer != recipient`; `createdBy == auth.uid`; currency strictly supported (write-path REJECTS unsupported — the `currencyOf` OMR-fence at `groupNetBalance.ts:52-54` is for untrusted READS, never for accepting a write); names via the shared `displayName.ts` validator (nullable); note ≤ 280 mirror (`settlementCorrection.ts:26`).
7. **Existing triggers fire on server-created docs unchanged** (onDocumentCreated is writer-agnostic): `settlementNotifier` (FCM), `writeRateMonitor` (detection-only), `balanceAggregator` (post-commit aggregate refresh). No trigger change needed; the callable does NOT write the aggregate doc.
8. **Client callable seam exists**: `FirebaseFunctionsService` (`lib/core/services/firebase_functions_service.dart`) + provider override in tests; correction flow already consumes `shouldBumpLedgerRevision` from a callable result (`group_settle_up_screen.dart:1211-1220`).
9. **`kMaxDecomposeLegsAtomic = 8`** (`group_settlement_service.dart:27` — NOT 9; CLAUDE.md's "=9" is stale and is corrected in Task 12) exists solely for the client WriteBatch's 20-access-call rules budget. Inside the callable's transaction that budget does not exist; the carve-out (and its single-group-write fallback branch) is deleted. New bound: legs ≤ `MAX_FAN_IN_EVENTS` (=400, `eventFanIn.ts:17-19`) against the 500-write tx cap.
10. **`RecomputeResult.net` values are whole-subunit by allocator quantization** (#596 lockstep) — `outstandingFils = net × scale` must land on an integer; the port asserts this and FLOORS toward zero on legacy garbage (cap may only shrink, never grow).

## The callable contract

```ts
// functions/src/callables/recordSettlement.ts
export type RecordSettlementMode = 'event' | 'group' | 'groupSettleUp';
export interface RecordSettlementLeg { eventId: string; amountFils: number }
export interface RecordSettlementInput {
  groupId: string;
  mode: RecordSettlementMode;
  eventId?: string;                  // required iff mode === 'event'
  payerParticipantId: string;
  recipientParticipantId: string;
  amountFils: number;                // positive int; the TOTAL for groupSettleUp
  currency: string;                  // strictly supported code
  note?: string;
  payerName?: string;
  recipientName?: string;
  observedPairEpoch: number;         // int ≥ 0 — the client's #1093 epoch observation, id input ONLY
  legs?: RecordSettlementLeg[];      // required iff mode === 'groupSettleUp'; distinct eventIds, positive ints
}
export interface RecordSettlementOutput {
  alreadyRecorded: boolean;          // idempotent replay — same id, matching payload
  eventScopeWrites: number;
  groupScopeWrites: number;
  shouldBumpLedgerRevision: boolean; // eventScopeWrites > 0
  settledAt: string;                 // server-stamped ISO, shared by every doc of the call
}
```

- **Id derivation:** `deterministicSettlementId(scopeKey, payer, recipient, currency, amountFils, observedPairEpoch)` with scopeKey `event:<gid>:<eid>` / `group:<gid>` / `gsu:<gid>`. For `groupSettleUp` that id IS `groupSettleUpId`; legs/residual derive from it (invariant 4). The epoch is the CLIENT's observation on the #1093 bases (event: `eventSettlementsProvider`; group: `groupSettlementsProvider`; gsu: union with `groupTaggedEventSettlementsProvider`) — fail-closed on a valueless basis exactly as #1093 Tasks 3/4 shipped.
- **Idempotency branch:** inside the tx, `tx.get` the derived id (for gsu: the residual id AND first leg id — see Task 5). Exists + payload-match (pair, currency, amountFils, createdBy-any) → return `alreadyRecorded: true` (a network retry OR the #1093 same-observed-state racer; the payment is recorded — success, not error). Exists + mismatch → `already-exists` ("A conflicting settlement already exists — refresh and retry."). The epoch is a dedup nonce, NEVER an equality gate — epoch mismatch with server state does not block a write (a legit settle after unrelated pair activity must not false-block); the CAP is the money guard.
- **Cap enforcement:** `amountFils > outstandingFils` → `failed-precondition` with `details: {kind: 'over-outstanding', outstandingFils, currency}`. REJECT, never clamp — clamping silently changes what the user confirmed. Cap bases per invariant 2. `groupSettleUp` additionally: every `leg.amountFils ≤ max(0, min(-payerNet_e, recipientNet_e) × scale)` from `perEventNet`, every leg eventId ∈ live events, `residual = amountFils − Σ legs ≥ 0` (else `failed-precondition {kind:'stale-decomposition'}` — the client refreshes and re-stages); residual doc written only if `> 0` (client parity, `group_settlement_service.dart:319-321`).
- **Writes (all `tx.create` — create-fails-on-exists is defense-in-depth under any phantom-read edge):** the settlement doc(s) + ONE activity row (`event_settlement` for event mode, `group_settlement` for group/gsu — same types, descriptions, and metadata the client builds today; port the payload construction from the three client sites verbatim). `settledAt`/activity `timestamp` = one server `new Date()`.
- **Error surface:** `unauthenticated`; `invalid-argument` (shape/currency/names/note/legs); `not-found` (group missing or write-locked — masking, per `correctSettlement.ts:78-94`; event missing/deleted); `permission-denied` (writer not member); `failed-precondition` (`over-outstanding`, `stale-decomposition`, party-not-member #1144, party-not-participant); `already-exists` (conflicting payload at id).

## Why one transaction (recorded so the Gate argues with the reasoning, not the absence of it)

The #1144 3-phase shape (lock tx → plain recompute → verify-and-mutate tx) protects a recompute window against CLIENT-direct writes that rules can't otherwise freeze. Here: (a) settle-vs-settle races serialize inside Firestore's transaction contract — both transactions read the settlements collection they both write, so the loser retries and re-derives cap+state; (b) expense-vs-settle races invalidate the read-set → retry; (c) post-flip there is no client-direct settlement write. A group-wide lock flag would serialize ALL settlement recording behind flag flips (2 extra transactions per settle) to protect against nothing the single tx doesn't already handle. Group/gsu-mode reads are `correctLogicalSettleUp`-scale (all live events × 2 subcollections + expenses — strictly more: + expenses); acceptable at current scale, bounded by MAX_FAN_IN_EVENTS on writes, revisit with telemetry (same posture as `correctLogicalSettleUp`'s uncapped reads).

## Rules changes (the security payoff)

- Event polymorphic block `firestore.rules:1094-1095`: `allow create: if validExpenseCreate() || validEventSettlementCreate();` → `allow create: if validExpenseCreate();` + comment (settlement creates are callable-only, #1129).
- Group block `:1353`: `allow create: if validGroupSettlementCreate();` → `allow create: if false;` + comment.
- DELETE now-dead validators: `validEventSettlementCreate`, `validEventSettlementUpdate` (already dead — no allow references; deleting it is compile-forced once its base dies, and un-traps the documented #283 bear trap by removal), `validEventSettlementBase`, `validGroupSettlementCreate`, `validGroupSettlementBase`, `validSettlementCore` (`:104` — only refs are the two bases at `:1041`/`:1317`). Net expression-ceiling pressure RELIEF on the event write path.
- Tighten `validGroupActivityCreate`'s client type allow-list: remove `'event_settlement'`/`'group_settlement'` — the callable now authors those rows; leaving them client-writable would let a member forge phantom "settled" history rows with no settlement doc behind them (and #1093 residual 3, the orphan replay row, dies with the queue). Expense/member/event types remain client-written.
- `allow update: if false` / `allow delete: if false` on both settlement blocks: UNTOUCHED (B3 append-only; also what makes stray legacy client `set()`-replays at an existing id die).

## Client changes

- `FirebaseFunctionsService.recordSettlement(...)` → `RecordSettlementResult` model (`lib/features/ledger/models/record_settlement_result.dart`), mirroring the `correctSettlement` wrapper idiom.
- `SettlementService.addSettlement` / `GroupSettlementService.addGroupSettlement` / `stageDecomposedSettleUp`: Firestore-direct bodies REPLACED by callable invocations through an injected `FirebaseFunctionsService` (constructor param, provider-wired) — signatures shrink (no `id`, no activity params; the server authors both), return the callable result. `buildSettlementDoc`/`buildGroupSettlementDoc` writers die client-side; `Settlement.fromFirestore` and the watch streams are UNTOUCHED (read path). Deleting rather than deprecating: the compiler forces every callsite + test to the new seam (the #1093 `required id` philosophy).
- Screens (`settle_up_screen.dart`, `group_settle_up_screen.dart`): keep #773/#1106 pre-write revalidation as advisory UX (avoids a doomed round trip; server is authoritative); compute + send `observedPairEpoch` via retained `directedPairEpoch` on the #1093 bases (fail-closed unchanged); pre-flight `connectivity != online` → new offline copy, no call; delete `awaitServerAck`/queued/"will sync" branches for settlement creates (callable await IS the server ack); bump `ledgerRevisionProvider` when `shouldBumpLedgerRevision` (replaces per-event-write bumps — one bump per successful call; the once-provider re-reads once); decompose path: stage legs from `decomposeGroupSettlement` exactly as today (WYSIWYG display == legs payload), drop the `kMaxDecomposeLegsAtomic` routing + single-write fallback + `bothLiveMembers` pre-gate (server enforces #1144; #720 defer-to-server); `alreadyRecorded: true` → success flow with "already recorded" copy (new l10n en+ar).
- Error mapping: extend `classifySettlementWriteError` (`settlement_write_error.dart`) with a `FirebaseFunctionsException` branch — `permission-denied`→denied, `failed-precondition(over-outstanding)`→ the #773 balance-changed refresh UX (existing copy), `unavailable`/network→offline kind (new copy), else generic.
- Dart id helpers `deterministicSettlementId`/`decomposeLegSettlementId`/`decomposeResidualSettlementId` DELETED (ported to TS); `directedPairEpoch` STAYS (feeds `observedPairEpoch`); `crypto` dependency dropped if nothing else imports it (grep first).
- WhatsApp nudge (#367), recap CTA, correction flows: untouched (all keyed on in-memory outcome / server callables already).

---

### Task 1: TS ports — settlement ids + outstandingForPair (pure, golden-vectored)

**Files:**
- Create: `functions/src/callables/shared/settlementIds.ts`
- Create: `functions/src/callables/shared/outstanding.ts`
- Test: `functions/test/settlementIds.test.ts`, `functions/test/outstanding.test.ts` (pure jest — no emulator)

**Step 1 (RED):** Golden-vector tests. Compute 6+ vectors with the CURRENT Dart helpers (one-off `dart run` scratch script against `deterministicSettlementId`/leg/residual — paste literal expected ids into the TS test): event/group/gsu scopes, OMR 3dp vs JPY scale-1 vs USD 2dp at equal `amountFils`, epoch 0 vs 1, reversed pair. Plus shape `^sd1[0-9a-f]{40}$`. `outstanding.test.ts`: table-driven (money code): both-sided debt → min; same-sign → 0; absent uid → 0; whole-subunit × scale exact int; legacy non-integer → floored, never rounded up.
**Step 2:** Implement. `settlementIds.ts`: `deterministicSettlementId({scopeKey, payerParticipantId, recipientParticipantId, currency, amountFils, pairEpoch})` (node `crypto.createHash('sha256')`, `\x1f` joins, `sd1` prefix — amountFils passed as int, stringified exactly like Dart's `'$fils'`), `decomposeLegSettlementId`, `decomposeResidualSettlementId`. `outstanding.ts`: `outstandingForPairFils(netBucket: Map<string, Decimal>, from, to, currency): number` mirroring `expense_provider.dart:970-987` then × `currencyScale`, integer-asserted, floored.
**Step 3:** `cd functions && npx jest test/settlementIds.test.ts test/outstanding.test.ts` → PASS. Commit `feat(functions): TS ports of settlement id + outstanding-for-pair primitives (#1129)`.

### Task 2: RED — the vulnerability regression tests (rules allow what #1129 exists to stop)

**Files:**
- Test: `functions/test/settlementCreateDenied.rules.test.ts` (new)

**Step 1:** Author DENY pins that FAIL today: (a) event-scope client `set()` of a fully-valid settlement doc → assert DENIED (today: ALLOWED — this is the #1129 hole: any member can direct-write any `positiveInt` `amountFils` with zero outstanding); (b) same for group scope; (c) client create of an `event_settlement`-typed activity row → DENIED (phantom-history forge). Run: `cd functions && npm run test:emulator -- test/settlementCreateDenied.rules.test.ts`. Expected: FAIL (creates currently succeed) — paste the RED output into the PR body.
**Step 2:** Commit the red tests with `test(rules): pin settlement-create denial (#1129) — RED until rules flip` (suite-excluded? No — they go green in Task 6; if intermediate CI runs matter, land Tasks 2+6 in one commit instead; prefer one commit `git add` both when reaching Task 6 — keep the RED run output).

*(Note: implementation order defers this commit to Task 6 if a green-suite-every-commit discipline is wanted; the RED evidence run happens NOW either way.)*

### Task 3: `recordSettlement` — event mode (TDD, emulator)

**Files:**
- Create: `functions/src/callables/recordSettlement.ts`
- Modify: `functions/src/index.ts` (re-export — `export { recordSettlement } from './callables/recordSettlement';` — NEVER a bare const; the awk drift-extractor must see it)
- Test: `functions/test/callables/recordSettlement.event.test.ts`

**Step 1 (RED):** Emulator + `testEnv.wrap` (template: `correctSettlement.test.ts` header incl. runCommand comment). Table-driven:
- happy: member settles pair with real event debt (seed expenses via Admin SDK) → doc at the derived id, byte-shape per invariant 5, `settledAt` ISO, activity row `event_settlement` present, output `{alreadyRecorded:false, eventScopeWrites:1, shouldBumpLedgerRevision:true}`;
- cap: `amountFils = outstanding+1` → `failed-precondition` `{kind:'over-outstanding', outstandingFils}`; `amountFils = outstanding` exactly → allowed (boundary);
- idempotent replay: identical second call → `{alreadyRecorded:true}`, still ONE doc, NO second activity row;
- sequential different state: settle 3 of 10, then (epoch+1) settle 7 → both land; then any further → over-outstanding;
- conflicting payload at same id (hand-seed a doc at the derived id with a different amount… unreachable via amount [amount is an id input] — use different NOTE? note isn't compared; construct via different payerName? names aren't id inputs and ARE tolerated — the payload-match compares pair+currency+amountFils only) → assert the match rule: seed doc at derived id with different RECIPIENT → `already-exists`;
- authz: non-member caller → `permission-denied`; counterparty not in `participantIds` → `failed-precondition`; counterparty in participants but NOT in `memberIds` (#1144) → `failed-precondition`; tombstone ghost in both → allowed;
- gates: soft-deleted event → `not-found`; each group write-lock flag → `not-found`; closed event (`isClosed:true`) → ALLOWED (settlements post-close);
- validation: `payer == recipient`, zero/negative/float `amountFils`, unsupported currency, 33-char name, 281-char note, negative `observedPairEpoch` → `invalid-argument`;
- App Check: enforced via `{enforceAppCheck:true}` (config assertion — emulator can't attest).
Run: expected FAIL (callable doesn't exist).
**Step 2:** Implement event mode: auth → input validation (shared `validId`, `displayName.ts`, note mirror, strict `isSupportedCurrency`) → `db.runTransaction`: `tx.get` group (flags+membership per invariant 6) → event doc (`!isDeleted`, participants) → `tx.get` event expenses + settlements + members collections → build one-event snapshot (`groupSettlements: []`) → `computeNetFromSnapshot` → `outstandingForPairFils` → cap → derive id → `tx.get(idRef)` idempotency branch → `tx.create` doc + activity row (port the client's event activity description/metadata construction from `settle_up_screen.dart` verbatim).
**Step 3:** RED file green: `cd functions && npm run test:emulator -- test/callables/recordSettlement.event.test.ts`. Commit `feat(functions): recordSettlement callable — event mode (#1129)`.

### Task 4: group + groupSettleUp modes (TDD, emulator)

**Files:**
- Modify: `functions/src/callables/recordSettlement.ts`
- Test: `functions/test/callables/recordSettlement.group.test.ts`

**Step 1 (RED):** Tables:
- group solo happy (multi-event debt, group-aggregate cap, `group_settlement` activity, doc carries `{groupId, eventId: groupId, scope:'group'}`);
- gsu happy: N=2 legs + residual — assert leg docs at `decomposeLegSettlementId(gsuId, eventId)` carrying `groupSettleUpId`, residual at `decomposeResidualSettlementId(gsuId)`, conservation `Σ legs + residual == amountFils` server-verified, ONE `group_settlement` activity row, `eventScopeWrites: N`, `shouldBumpLedgerRevision: true`;
- residual == 0 → no residual doc;
- leg > per-event drill-down cap → `failed-precondition {kind:'stale-decomposition'}` and NOTHING persisted (tx atomicity — assert all collections empty);
- Σ legs > total (negative residual) → `stale-decomposition`;
- duplicate leg eventIds / unknown eventId / soft-deleted event leg → `invalid-argument`/`stale-decomposition`;
- legs.length > 400 → `failed-precondition` (MAX_FAN_IN_EVENTS reuse);
- gsu idempotent replay → `alreadyRecorded:true`, doc count unchanged;
- **the #1129 headline case (residual 1):** seed pair debt 5; racer A settles 3 (lands), racer B calls with amount 5 derived from the same pre-A view (epoch unchanged) → B gets `over-outstanding` with `outstandingFils == 2000` (OMR) — the over-settle that #1093 accepted is now impossible;
- per-currency isolation: OMR debt does not fund a USD settle (cap computed in the settle currency's bucket only).
**Step 2:** Implement: full-subtree tx reads (`correctLogicalSettleUp` idiom + expenses), one `computeNetFromSnapshot` call serving BOTH the aggregate cap and `perEventNet` leg validation; gsu idempotency probes residual id, falling back to first-leg id when residual==0.
**Step 3:** Green; full functions suite `npm run test:emulator` green (expect NO existing test touching recordSettlement). Commit `feat(functions): recordSettlement group + groupSettleUp modes (#1129)`.

### Task 5: drift-check + docs listing

**Step 1:** `bash tool/list_expected_functions.sh` → output includes `recordSettlement`. `flutter test test/unit/release_workflow_gate_test.dart` green.
**Step 2:** `docs/CLOUD-FUNCTIONS.md`: add the callable (count 13→14 callables); note online-only + cap semantics. Commit `docs(functions): recordSettlement in the callable inventory (#1129)`.

### Task 6: rules flip + dead validator deletion + rules-test surgery

**Files:**
- Modify: `security/firestore.rules` (per "Rules changes" above)
- Modify: `functions/test/settlementIdempotency.rules.test.ts` (its `(1) create … ALLOWED` pins at `:154-162`/`:218-226` flip to DENIED; the deny-on-existing-id cases collapse into the blanket deny — re-pin as "client settlement create denied regardless of payload/id"; keep the file as the #1093→#1129 lineage record, update its stale `:988`/`:1230` line citations)
- Modify: `functions/test/firestore-rules-publish-readiness.test.ts` (~21 `assertSucceeds` settlement creates + the `#48 shared-settlement-core characterization` block ~`:2603-2680`: DELETE the characterization block [its diagnostic purpose — which predicate rejects — is dead once all client creates are denied; shape validation now lives in `recordSettlement`'s emulator tables]; convert representative creates to DENY pins; settlement READ pins stay; expense pins untouched)
- Test (now green): `functions/test/settlementCreateDenied.rules.test.ts` (Task 2)

**Steps:** flip rules → Task-2 file green → full rules suite `npm run test:emulator` green (watch for expression-ceiling warnings DROPPING, not rising) → commit `fix(rules): settlement creates are callable-only — deny client direct writes (#1129)` (include Task 2's test file here if it wasn't committed RED).

### Task 7: client callable wrapper + result model + error mapping

**Files:**
- Create: `lib/features/ledger/models/record_settlement_result.dart`
- Modify: `lib/core/services/firebase_functions_service.dart` (add `recordSettlement`, doc-comment the ONLINE-ONLY contract like the #889 block)
- Modify: `lib/features/ledger/models/settlement_write_error.dart` (FirebaseFunctionsException branch: permission-denied→denied; failed-precondition + details.kind=='over-outstanding'→ new `overOutstanding` kind; unavailable/deadline-exceeded/network→ new `offline` kind; else generic)
- Test: `test/unit/record_settlement_result_test.dart`, extend `test/unit/settlement_write_error_test.dart` (or create; table-driven)

**Steps:** RED (fromData parsing incl. missing/garbage fields fail-safe; error-mapping table) → implement → green → `flutter analyze` → commit `feat(client): recordSettlement wrapper + error classification (#1129)`.

### Task 8: services rewired onto the callable

**Files:**
- Modify: `lib/features/ledger/services/settlement_service.dart` (delete `buildSettlementDoc` write use, `addSettlement` Firestore body, `deterministicSettlementId`, `decomposeLegSettlementId`, `decomposeResidualSettlementId`; keep `directedPairEpoch`, watch streams, `Settlement.fromFirestore`; new `addSettlement` = callable call via injected `FirebaseFunctionsService`)
- Modify: `lib/features/groups/services/group_settlement_service.dart` (same treatment for `addGroupSettlement`/`stageDecomposedSettleUp` → single callable call with legs payload; DELETE `kMaxDecomposeLegsAtomic` + batch machinery)
- Modify: providers wiring (`expense_provider.dart:53` `settlementServiceProvider`, `group_balance_provider.dart:30` `groupSettlementServiceProvider`) to inject `firebaseFunctionsServiceProvider`
- Tests: `test/unit/settlement_service_test.dart`, `test/unit/group_settlement_service_test.dart` — REWRITTEN: doc-shape assertions move to the Task 3/4 emulator tables; what remains client-side to pin = payload construction (legs forwarding, epoch forwarding, currency/amount int conversion via `MoneySerializer.toSubunits` at the boundary) against a recording fake functions service

**Steps:** RED (new service tests) → implement → compiler-forced callsite sweep → green → commit `refactor(client): settlement creates route through recordSettlement (#1129)`.

### Task 9: screens — pre-flight, epoch, bump, copy

**Files:**
- Modify: `lib/features/ledger/screens/settle_up_screen.dart`, `lib/features/groups/screens/group_settle_up_screen.dart` (per "Client changes")
- Modify: `lib/l10n/app_en.arb` + `app_ar.arb`: `settleUpNeedsConnection`, `settleUpAlreadyRecorded`, over-outstanding copy (reuse the existing #773 refresh copy if the key fits — check before adding)
- Tests: `test/features/ledger/settle_up_screen_test.dart`, `test/features/groups/group_settle_up_screen_test.dart` + siblings (`group_settle_up_atomic_929_test.dart`, `decomposed_settleup_batch_test.dart`, `settle_up_dedup_1093_test.dart`, revalidation tests) — port seams from fake-Firestore doc assertions to recording-fake-service assertions; DELETE queued/"will sync" assertions for settlement creates (obsolete behavior — delete, don't patch); ADD: offline pre-flight test (connectivity offline → copy shown, service NOT invoked); alreadyRecorded → success + copy; bump fired iff `shouldBumpLedgerRevision`

**Steps:** RED (new behaviors) → implement → full `flutter test` green → `flutter analyze` → `bash tool/check_theme_purity.sh` (touched widgets) → commit `feat(client): online-only settle recording UX + server-authoritative cap handling (#1129)`.

### Task 10: dedup-test lineage port

`test/features/ledger/settle_up_dedup_1093_test.dart` + `test/features/groups/group_settle_up_dedup_1093_test.dart` pinned client-side id determinism that no longer exists client-side. Port their SCENARIO (two records from one observed snapshot → one logical payment) to: both calls send the same `observedPairEpoch` → recording fake asserts identical derived intent; the authoritative one-doc guarantee now lives in Task 3/4's emulator idempotency tables. Delete `test/unit/deterministic_settlement_id_test.dart` (superseded by TS golden vectors — note the supersession in the commit body). Commit `test: port #1093 dedup pins to the callable seam (#1129)`.

### Task 11: full-suite + analyze + coverage gate

`flutter analyze` clean; `flutter test` full green; `cd functions && npm run test:emulator` full green; coverage ≥ 80% (CI mirror). Fix fallout; commit fixes atomically.

### Task 12: docs + landmines + journal

- `CLAUDE.md`: Financial-Calculations settlement paragraph — settlement creates are **callable-only** (`recordSettlement`, online-only, server-derived `sd1` ids from client-observed epoch, server cap at pair outstanding); correct `kMaxDecomposeLegsAtomic` note (was stale "=9"; constant now DELETED — decompose legs bounded by MAX_FAN_IN_EVENTS server-side); amend the #752/#929 bullets (single-write >8-leg carve-out REMOVED — atomic server tx replaced it); amend the #1093 line (ids still deterministic dedup keys, derivation now server-side); note the activity type allow-list tightening.
- `functions/src/triggers/writeRateMonitor.ts:6-9` header: settlements are now callable-routed BY DESIGN (#1129); expenses remain client-direct.
- `docs/SECURITY-RULES.md` settlement section; `docs/ACCOUNT-RECOVERY.md` untouched.
- `journal.md`: the trade-off record — offline settle recording deliberately killed for server-side money integrity; what would reverse it (launch telemetry showing offline-settle demand).
- Commit `docs: settlement create is callable-only (#1129)`.

---

## Accepted residuals of THIS design (named, deliberate)

1. **Settlements are online-only.** The product cost #1093 chose (c) to avoid, now accepted per the issue. Offline attempt → immediate honest copy; no queue, no staging (a client-side replay queue is the forbidden custom-sync-queue).
2. **Epoch remains client-observed** → a hostile client can vary it to mint several settlements, each ≤ the *live* outstanding at its commit. Money exposure is bounded by actual debt (the cap is the guard); dedup stays an honest-client courtesy exactly as in #1093. Not a hole relative to #1129's goals: over-settle is impossible.
3. **Unsynced offline expenses on OTHER devices are invisible to the cap** — the server caps against synced truth. Divergent-cache class, unchanged posture.
4. **Group/gsu transaction reads the whole group subtree** (events × expenses+settlements). No read cap (correctLogicalSettleUp precedent, now + expenses); contention retries theoretically possible in hot groups. Revisit with telemetry; write side bounded at 400 legs.
5. **Second racer of the same logical payment sees success (`alreadyRecorded`)**, not an error — better than #1093's `denied` copy, but it means "my tap recorded it" is occasionally "the other device recorded it". The ledger shows one payment either way.
6. **balanceAggregator recomputes the oracle again post-commit** — double compute per create (once for cap, once for the display cache). Pre-existing trigger economics; not worth threading the callable's figure into the aggregate write (the trigger owns monotonicity).
7. **`payerName`/`recipientName` are caller-supplied mirrors** (as today) — a hostile member can label parties oddly within display-name validity; display-only, money truth in ids.
8. **Legacy uuid-id docs**: pre-#1093 random-id settlements never collide with anything — unaffected; epoch counting includes them (they're live pair rows), same as #1093.

## Verification-principles report (run while authoring, 2026-07-11)

1. **Callsite classification:** every input to the callable is OUTBOUND (feeds the write): amountFils (int subunits at the boundary via `MoneySerializer.toSubunits` — client converts exactly where `buildSettlementDoc` did), pair ids, currency code, epoch int. Display-formatted strings never cross (names are display mirrors, validated; note is free text, validated). INBOUND readers of settlement docs (streams, oracle, corrections, aggregator) untouched — verified each folds by path/fields, never by id format (#1093 invariant 3 re-checked: `correctSettlement.ts` id-opaque, `recomputeNet` path-folded).
2. **Concrete claims re-verified this session:** `outstandingForPair` `expense_provider.dart:970-987` (read); `computeNetFromSnapshot`/`loadGroupBalanceSnapshot`/`perEventNet` shapes `groupNetBalance.ts:533-661` (read); `correctSettlement.ts` full read (tx idiom, five-flag mirror `:85-94`, #1144 gate `:159-167`, deterministic reverse id `:197`); rules `:1044-1068` event create gates + `:1094-1095` allow line + `:1104-1109` update/delete deny + `:1320-1353` group block (read); `kMaxDecomposeLegsAtomic = 8` `group_settlement_service.dart:27` (grep — CLAUDE.md "=9" is stale, corrected in Task 12); `addSettlement` #1140 co-batch body `settlement_service.dart:208-283` (read); callable wrapper idiom + ONLINE-ONLY precedent `firebase_functions_service.dart:129-179` (read); `currencyScale`/`currencyOf` read-fence `groupNetBalance.ts:46-54` (read); `decomposeGroupSettlement` invariants doc `expense_provider.dart:840-874` (read); `MAX_FAN_IN_EVENTS=400` `eventFanIn.ts:17-19` (researcher-cited, re-grep at implementation); index.ts re-export convention (researcher-cited `index.ts:6-42`, re-grep at implementation).
3. **Read-path per write-path:** settlement docs → watch streams (screens), oracle (`recomputeNet` + client `calculateBalances`), `balanceAggregator`, corrections (`correctSettlement` by id — server ids remain opaque lookups), `groupSettleUpId` equality filters (client link + `correctLogicalSettleUp`) — ALL consume fields the server writes byte-compatibly (invariant 5). Activity row → activity feed (type-guarded metadata reads, #808) — same types/shapes as the client wrote. New OUTPUT read-path: `RecordSettlementResult` → screens (bump + copy) — spelled in Task 7.
4. **Fields from the type:** doc key sets enumerated from `buildSettlementDoc`/`buildGroupSettlementDoc` + rules `hasOnly` lists (invariant 5), not memory; input interface enumerated field-by-field with per-field validation named (invariant 6).
5. **Exact data contracts:** callable input/output interfaces spelled (TS block above); id grammar + scopeKeys pinned to Dart-era bytes with golden vectors; error `details.kind` strings enumerated; legs payload shape `{eventId, amountFils}`.
6. **Arithmetic decomposition:** `Σ legs + residual == amountFils` is server-ENFORCED (reject, not trust); legs validated against `perEventNet` overlap caps (participantIds-only basis — deliberately matching the client's drill-down, invariant 2); totals validated against aggregate nets — the two bases deliberately do NOT reconcile (CLAUDE.md #366: the maps don't reconcile; leg caps and total cap are independent guards, both must pass).
7. **Orthogonal adversarial pass:** TIME — retry-after-success (idempotent branch), settle-after-unrelated-pair-activity (epoch mismatch does not block; cap governs), sequential re-settle (new epoch → new id → capped). IDENTITY — settle-on-behalf (#595: createdBy=recorder, parties gated), tombstone ghosts (memberIds-swapped, pass #1144 mirror), claim re-key (Admin engine rewrites party FIELDS by doc id; server ids equally opaque). SCOPE — event/group/gsu namespaces disjoint; per-currency buckets never cross-fund (Task 4 table). MONEY-FLOW — reversed-direction pair derives a different id AND its own cap (`outstandingForPair` is directed); zero-outstanding pair → any amount rejected (cap = 0). OFFLINE — pre-flight + error mapping; no write ever queues.

## Gate record

- Round 1 (rubric + adversary, fresh-context): _pending_
