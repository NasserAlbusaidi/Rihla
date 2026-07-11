# #1129 — Transactional settlement callable (server-side outstanding cap) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move every settlement CREATE behind one transactional Cloud Functions callable (`recordSettlement`) that recomputes the pair's outstanding balance **on the settle's scope basis** inside the transaction via the shared oracle, caps `amountFils` at it, and writes with the #1093 deterministic idempotency key — closing #1093's accepted residuals 1 (different-amount concurrent settles over-settle), 4 (hostile client writes any `positiveInt` amount), and 9 (cross-pair id squat), and closing the **over-credit direction** of residual 2 (a divergent-cache device can no longer land an amount the live ledger doesn't support; the dedup-*drop* direction of residual 2 remains — see Accepted residual 2).

**Architecture:** One callable, three modes (`event` solo, `group` solo, `groupSettleUp` decomposed), one `db.runTransaction` per call (the `correctSettlement`/`correctLogicalSettleUp` idiom — NOT the #1144 3-phase departure lock; see "Why one transaction"). The server derives the settlement doc id from the client's *observed* pair-epoch (retry-idempotent), enforces the cap from its own transaction-consistent recompute (over-settle-proof), and writes the settlement doc(s) + the ONE #1140 activity row atomically. `firestore.rules` then denies client settlement creates outright — the callable becomes the only writer, so the forged-amount hole closes. Settlement recording becomes **online-only** (the #889 corrections precedent, extended to creates — a cost #1129 explicitly accepts).

**Decision lineage:** Option (a) of #1093's fork, deferred 2026-07-10, activated 2026-07-11 by explicit direction (built ahead of the launch-telemetry trigger). The #1093 client-side dedup (option c) stays live semantics — same id grammar, same epoch concept — but derivation moves server-side.

**Tech stack:** TypeScript (functions/src, Node 22) — new callable + TS ports of `deterministicSettlementId`/leg/residual ids and `outstandingForPair`. Dart — client services rewired onto the callable; `crypto` usage for settlement ids REMOVED from the client. `security/firestore.rules` — settlement create denied, dead validators deleted, activity type allow-list tightened.

---

## Product trade-offs accepted (named up front — the Gate should challenge these, not rediscover them)

1. **Offline settlement recording dies.** HTTPS callables have no offline queue. Pre-flight connectivity check (`== ConnectivityStatus.offline` — NEVER `!= online`: `syncing` means the device IS online draining its queue and the callable would succeed; `!= online` would false-block it) → the existing `settleUpRecordFailed` "check your connection" copy, no call attempted; the queued/"will sync" snackbar branches for settlement creates become dead code and are deleted. Precedent: #889 corrections are already documented "ONLINE-ONLY … never the queued/'will sync' copy" (`firebase_functions_service.dart:129-137`). Expenses keep offline writes — untouched.
2. **The `writeRateMonitor.ts:6-9` header stance ("routing them through a callable/queue is forbidden") is explicitly superseded for settlements** — that comment and the CLAUDE.md line it cites are amended in Task 12. Expenses remain client-direct.
3. **Deploy freely** — no real users yet (CLAUDE.md), so rules flip + callable ship in one PR with no client-compat ordering. Deploy ceremony after merge.

## Invariants this plan relies on (each verified against code this session; Gate R1 corrections folded in)

1. **Pairwise outstanding is derived from per-person NETS, not a pairwise ledger.** `BalanceCalculator.outstandingForPair` (`lib/features/ledger/providers/expense_provider.dart:970-987`) = `min(max(-fromNet,0), max(toNet,0))` over one currency bucket. The server oracle `computeNetFromSnapshot` (`functions/src/callables/groupNetBalance.ts:592`) already produces those nets per currency (`RecomputeResult.net`). The TS port is a ~15-line pure mirror, not a new allocator.
2. **Three cap bases, each mirroring the exact client basis** (this is the parity trap):
   - `event` mode: client #773 revalidates against the **single event's** balances on the #249 universe (`settle_up_screen.dart:555-617` `_freshOutstandingForPair`). Server mirror: run `computeNetFromSnapshot` on a snapshot containing ONLY that event and `groupSettlements: []` — the aggregate `.net` of a one-event snapshot IS that event's full-universe fold. No new fold logic. (Gate R1 adversary re-verified: both bases include #752 decomposed legs living in that event's settlements subcollection and both exclude the group residual.)
   - `group`/`groupSettleUp` total: client caps against the group aggregate (`group_settle_up_screen.dart:658` → `outstandingForPair` on fresh group balances). Server mirror: full snapshot → `.net`.
   - `groupSettleUp` legs: client `decomposeGroupSettlement` (`expense_provider.dart:840-874`) pins `perEvent[e] <= min(|payerNet_e|, recipientNet_e)` on the **participantIds-only per-event drill-down**. Server mirror: `RecomputeResult.perEventNet` — which is participantIds-only BY DESIGN (groupNetBalance.ts; CLAUDE.md #366 note). Do NOT "fix" leg validation onto the #249 universe; the client's legs come from the participantIds-only breakdown.
3. **`db.runTransaction` reading whole subcollections is established precedent**: `correctSettlement.ts:123-127` (one settlements collection), `correctLogicalSettleUp.ts:115-121` (ALL live events' settlements + group settlements, uncapped). The #1144 3-phase lock (leaveGroup/removeMember/deleteGroup) exists to block CLIENT-direct balance-input writes during a multi-transaction window; `recordSettlement` has no such window (single tx) and, post-flip, no client-direct settlement writes exist to race. Client-direct EXPENSE writes racing the tx invalidate its read-set → automatic retry with fresh reads.
4. **Deterministic id grammar (#1093) is shared-namespace and must stay byte-identical**: `'sd1' + sha256('sd1\x1f<scopeKey>\x1f<payer>\x1f<recipient>\x1f<currency>\x1f<amountFils>\x1f<pairEpoch>').hex[0:40]` (`settlement_service.dart:140-159`); scopeKeys `event:<gid>:<eid>` / `group:<gid>` / `gsu:<gid>`; leg id `'sd1' + sha256('sd1leg\x1f<gsuId>\x1f<eventId>').hex[0:40]`, residual `'sd1' + sha256('sd1res\x1f<gsuId>').hex[0:40]` (`settlement_service.dart:183-189` — note the `'sd1'` prefix and 40-hex truncation apply to leg/residual ids too). Pre-#1129 client-minted docs and post-#1129 server-minted docs share one namespace — same observed state collides across the transition. Golden vectors pin the TS port to Dart-era outputs (Task 1). Correction reverse ids (`correction_<shortHash>`, `settlementCorrection.ts:165-173`) are a disjoint namespace — no cross-collision (Gate R1 adversary verified).
5. **Doc shapes** (server must write byte-compatible docs; rules stop validating them):
   - Event: `{id, eventId, payerParticipantId, recipientParticipantId, payerName, recipientName, amountFils(int), currency, note, isDeleted:false, deletedAt:null, settledAt(ISO), createdBy, groupSettleUpId?}` (`buildSettlementDoc`, `settlement_service.dart:90-124`).
   - Group: same + `{groupId, eventId:groupId(sentinel), scope:'group'}` (`buildGroupSettlementDoc`, `group_settlement_service.dart:90-125`).
   - Activity row: `{id, type, actorId, actorName, description, metadata, timestamp}` (`GroupActivityService.buildActivityDoc`); ONE row per logical settle (#1140). **`actorId = request.auth.uid` (the RECORDER)** — display-load-bearing: `activity_display.dart` renders paid/received/between by comparing `log.actorId` to `fromUserId`/`toUserId` (#595 third-party recorder → "between"); a wrong actorId misclassifies the row (Gate R2 P2). **The metadata shapes DIVERGE per mode and must be ported verbatim, never homogenized** (#808 type-guarded readers + #814 value floors key on these exact fields):
     - `event` mode (`settle_up_screen.dart:912-922`): type `event_settlement`, id `'stl_' + <settlement id>`, metadata `{amountFils: <int subunits>, currency, fromUserId, toUserId, fromName, toName, eventId, eventName?}` (`eventName` only when non-empty — server sources it from the event doc's `name` field, already read in the tx).
     - `group` + `groupSettleUp` modes (`group_settle_up_screen.dart:1101-1109` and `:929-937` — identical shape): type `group_settlement`, id `'stl_' + <group settlement id>` (solo) / `'gstl_' + <groupSettleUpId>` (gsu — verified `group_settlement_service.dart:339-360`), metadata `{amount: <Decimal.toString() STRING — not fils, no eventId>, recipientId, currency, fromUserId, toUserId, fromName, toName}`.
     - `description` (all modes): `'settled <formatted> with <counterpartyName>'` where formatted = `AppFormatters.formatCurrency(amount, currency)` and `counterpartyName = (callerUid == toUserId) ? payerName : recipientName` (#282 — name the OTHER party relative to the actor). Server ports a minimal TS formatter mirroring `AppFormatters.formatCurrency` output; Task 4 pins it with a golden string test against a client-built literal.
     - `actorName`: client sourced it from device-local `settingsProvider.deviceName` — impossible server-side. Server derives it from the RECORDER's member doc `displayName` (**matched by the `userId` FIELD, never the doc id** — member keying is mixed, CLAUDE.md), falling back to `payerName` when the recorder is the payer / `recipientName` otherwise, and validated by the shared display-name mirror. Unforgeable and consistent with #1124 name propagation. Scope note (Gate R3): the settlement text renderer never reads `actorName` (classification runs on `actorId` + metadata) — this field feeds only the actor avatar chip; the fallback is cosmetic, don't over-invest.
6. **Rules gates the callable must mirror server-side** (Admin SDK bypasses rules): group write-lock five-flag OR (`correctSettlement.ts:85-94` — isDeleted/deletingInProgress/claimingInProgress/accountDeletionInProgress/departureInProgress); writer ∈ `memberIds`; event mode: event `!isDeleted` (`eventAllowsClientWrites` — settlements stay writable after close, `correctSettlement.ts:109-114`), counterparties ∈ `participantIds` AND ∈ `memberIds` (#1144, `firestore.rules:1044-1068`); group mode: counterparties ∈ `memberIds` (`firestore.rules:1320-1328`); `payer != recipient`; `createdBy == auth.uid`; currency strictly supported (write-path REJECTS unsupported — the `currencyOf` OMR-fence at `groupNetBalance.ts:52-54` is for untrusted READS, never for accepting a write); names via the shared `displayName.ts` validator (nullable); note ≤ 280 mirror (`settlementCorrection.ts:26`).
7. **Existing triggers fire on server-created docs unchanged** (onDocumentCreated is writer-agnostic): `settlementNotifier` (FCM, per-recipient localized, description-blind), `balanceAggregator` (post-commit aggregate refresh). The callable does NOT write the aggregate doc. **ONE deliberate trigger change (Gate R3 adversary P2): `writeRateMonitor` STOPS counting settlement-collection creates and settlement-typed activity rows** — post-flip they are Admin-SDK-only (unforgeable, already capped + authenticated), so counting them is vestigial for the monitor's client-abuse purpose, and the new 400-leg bound would let ONE legitimate large settle-up (~N+2 counted writes, same uid, one commit) cross the `WRITE_RATE_LIMIT=100`/60s threshold the old 8-leg cap silently protected — false-flagging AND pre-consuming the per-uid budget that exists to catch expense abuse. Skip mirrors the existing correction-marker skips in the same file (Task 4b). Expense counting unchanged.
8. **Client callable seam exists**: `FirebaseFunctionsService` (`lib/core/services/firebase_functions_service.dart`) + provider override in tests; correction flow already consumes `shouldBumpLedgerRevision` from a callable result (`group_settle_up_screen.dart:1211-1220`).
9. **`kMaxDecomposeLegsAtomic = 8`** (`group_settlement_service.dart:27` — NOT 9; CLAUDE.md's "=9" is stale and is corrected in Task 12) exists solely for the client WriteBatch's 20-access-call rules budget. Inside the callable's transaction that budget does not exist; the `> kMax` single-group-write carve-out is deleted. New bound: legs ≤ `MAX_FAN_IN_EVENTS` (=400, `functions/src/callables/shared/eventFanIn.ts:19`) against the 500-write tx cap.
10. **`RecomputeResult.net` values are whole-subunit by allocator quantization** (#596 lockstep) — `outstandingFils = net × scale` must land on an integer; the port asserts this and FLOORS toward zero on legacy garbage (cap may only shrink, never grow).
11. **The `perEvent.isEmpty → single group settlement` fallback is REACHABLE and STAYS** (Gate R1 adversary P1): a cross-event pair (payer owes in E1, recipient owed in E2 — no single event overlaps) and the #249 departed-explicit-split case both yield empty `perEvent` with `residual == amount` (`expense_provider.dart:857-874`; sole `_recordSettlement` callsite `group_settle_up_screen.dart:815-830`). Post-#1129 that routing maps to mode `'group'` (scopeKey `group:<gid>`, epoch over `groupSettlementsProvider` only — #1093 Task 4 parity). Only the `!bothLiveMembers` and `> kMaxDecomposeLegsAtomic` routing conditions are deleted; `groupSettleUp` mode server-side REQUIRES `legs.length ≥ 1`.

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
  legs?: RecordSettlementLeg[];      // required iff mode === 'groupSettleUp'; length ≥ 1, ≤ 400, distinct eventIds, positive ints
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
- **Idempotency branch:** inside the tx, `tx.get` the derived id (for gsu: the residual id AND first leg id — see Task 4). Exists + payload-match (pair, currency, amountFils) → return `alreadyRecorded: true` (a network retry OR the #1093 same-observed-state racer; the payment is recorded — success, not error). Exists + mismatch → `already-exists` (client maps it to the balance-changed refresh UX). The epoch is a dedup nonce, NEVER an equality gate — epoch mismatch with server state does not block a write (a legit settle after unrelated pair activity must not false-block); the CAP is the money guard.
- **Cap enforcement:** `amountFils > outstandingFils` → `failed-precondition` with `details: {kind: 'over-outstanding', outstandingFils, currency}`. REJECT, never clamp — clamping silently changes what the user confirmed. Cap bases per invariant 2. `groupSettleUp` additionally: every `leg.amountFils ≤ max(0, min(-payerNet_e, recipientNet_e) × scale)` from `perEventNet`, every leg eventId ∈ live events, `residual = amountFils − Σ legs ≥ 0` (else `failed-precondition {kind:'stale-decomposition'}` — the client refreshes and re-stages); residual doc written only if `> 0` (client parity, `group_settlement_service.dart:319-321`).
- **Writes (all `tx.create` — create-fails-on-exists is defense-in-depth under any phantom-read edge):** the settlement doc(s) + ONE activity row per invariant 5 (types, ids, descriptions, per-mode metadata shapes verbatim). `settledAt`/activity `timestamp` = ONE server `new Date().toISOString()` shared by every doc of the call — **ISO STRINGS, never a bare JS `Date`, Firestore `Timestamp`, or `FieldValue.serverTimestamp()`** (Gate R2 P1): `Settlement.fromFirestore` parses `settledAt` only `is String` (else epoch-0, `settlement_model.dart:166-169`), and the watch streams + activity feed `orderBy('settledAt'/'timestamp')` would type-bucket Timestamps apart from every legacy String doc, breaking ordering and the activity pagination cursor. `correctSettlement.ts:200` (`nowIso = new Date().toISOString()`) is the precedent. `deletedAt: null`.
- **Error surface:** `unauthenticated`; `invalid-argument` (shape/currency/names/note/legs incl. empty-legs gsu); `not-found` (group missing or write-locked — masking, per `correctSettlement.ts:78-94`; event missing/deleted); `permission-denied` (writer not member); `failed-precondition` (`over-outstanding`, `stale-decomposition`, party-not-member #1144, party-not-participant); `already-exists` (conflicting payload at id).

## Why one transaction (recorded so the Gate argues with the reasoning, not the absence of it)

The #1144 3-phase shape (lock tx → plain recompute → verify-and-mutate tx) protects a recompute window against CLIENT-direct writes that rules can't otherwise freeze. Here: (a) settle-vs-settle races serialize inside Firestore's transaction contract — both transactions read the settlements collection they both write, so the loser retries and re-derives cap+state; (b) expense-vs-settle races invalidate the read-set → retry; (c) post-flip there is no client-direct settlement write. A group-wide lock flag would serialize ALL settlement recording behind flag flips (2 extra transactions per settle) to protect against nothing the single tx doesn't already handle. Group/gsu-mode reads are `correctLogicalSettleUp`-scale (all live events × 2 subcollections + expenses — strictly more: + expenses); acceptable at current scale, bounded by MAX_FAN_IN_EVENTS on writes, revisit with telemetry (same posture as `correctLogicalSettleUp`'s uncapped reads).

## Rules changes (the security payoff)

- Event polymorphic block `firestore.rules:1094-1095`: `allow create: if validExpenseCreate() || validEventSettlementCreate();` → `allow create: if validExpenseCreate();` + comment (settlement creates are callable-only, #1129).
- Group block `:1353`: `allow create: if validGroupSettlementCreate();` → `allow create: if false;` + comment.
- DELETE now-dead validators — the full set, both scope twins (Gate R1 P1: the group update twin was missing and dangles a reference that fails the WHOLE ruleset publish): `validEventSettlementCreate`, `validEventSettlementUpdate` (`:1070-1085`), `validEventSettlementBase`, `validGroupSettlementCreate` (`:1320-1328`), `validGroupSettlementUpdate` (`:1330-1337` — calls `validGroupSettlementBase` at `:1337`), `validGroupSettlementBase` (`:1273`), `validSettlementCore` (`:104` — only refs are the two bases). Scrub the stale comments that reference them: `:240-241` (`requesterIsRecordCreator` — after deletion it has **ZERO live refs** [Gate R3: the expense path explicitly dropped it, `:925`; its only callers were the two deleted update twins]; rewrite as "unreferenced after #1129; retained for #283 settlement corrections" — an unreferenced function is publish-legal, only a call to a MISSING function fails) and `:899`. Net expression-ceiling pressure RELIEF on the event write path.
- Tighten `validGroupActivityCreate`'s client type allow-list: remove `'event_settlement'`/`'group_settlement'` — the callable now authors those rows; leaving them client-writable would let a member forge phantom "settled" history rows with no settlement doc behind them (and #1093 residual 3, the orphan replay row, dies with the queue). Expense/member/event types remain client-written.
- `allow update: if false` / `allow delete: if false` on both settlement blocks: UNTOUCHED (B3 append-only; also what makes stray legacy client `set()`-replays at an existing id die).

## Client changes

- `FirebaseFunctionsService.recordSettlement(...)` → `RecordSettlementResult` model (`lib/features/ledger/models/record_settlement_result.dart`), mirroring the `correctSettlement` wrapper idiom.
- `SettlementService.addSettlement` / `GroupSettlementService.addGroupSettlement` / `stageDecomposedSettleUp`: Firestore-direct bodies REPLACED by callable invocations through an injected `FirebaseFunctionsService` (constructor param, provider-wired) — signatures shrink (no `id`, no activity params; the server authors both), return the callable result. `buildSettlementDoc`/`buildGroupSettlementDoc` writers die client-side; `Settlement.fromFirestore` and the watch streams are UNTOUCHED (read path). Deleting rather than deprecating: the compiler forces every callsite + test to the new seam (the #1093 `required id` philosophy).
- Screens (`settle_up_screen.dart`, `group_settle_up_screen.dart`): keep #773/#1106 pre-write revalidation as advisory UX (avoids a doomed round trip; server is authoritative); compute + send `observedPairEpoch` via retained `directedPairEpoch` on the #1093 bases (fail-closed unchanged); pre-flight `connectivity == ConnectivityStatus.offline` → `settleUpRecordFailed` copy, no call (`syncing` proceeds — invariant/trade-off 1); delete `awaitServerAck`/queued/"will sync" branches for settlement creates (callable await IS the server ack); bump `ledgerRevisionProvider` when `shouldBumpLedgerRevision` (replaces per-event-write bumps — one bump per successful call; the once-provider re-reads once); decompose path: stage legs from `decomposeGroupSettlement` exactly as today (WYSIWYG display == legs payload), route `perEvent.isEmpty` → mode `'group'` (invariant 11), drop ONLY the `kMaxDecomposeLegsAtomic` and `bothLiveMembers` routing conditions (server enforces #1144; #720 defer-to-server); `alreadyRecorded: true` → success flow with "already recorded" copy (new l10n key `settleUpAlreadyRecorded`, en+ar — the ONLY new key; offline + over-outstanding reuse existing copy).
- Error mapping: extend `classifySettlementWriteError` (`lib/core/utils/settlement_write_error.dart:14-48` — kinds `network`/`denied`/`unknown`; note `FirebaseFunctionsException extends FirebaseException`, so the real work is CODE+DETAILS branching, not a new catch type). Mechanism (Gate R2): add ONE new kind `SettlementWriteErrorKind.staleBalance` mapped to the existing `settleUpBalanceChangedReviewAgain` copy (en:825/ar:317 — AR pair verified); route `failed-precondition` (`details.kind` ∈ {`over-outstanding`, `stale-decomposition`} or absent) AND `already-exists` there; `permission-denied`→denied; `unavailable`/`deadline-exceeded`→network (`settleUpRecordFailed`); else generic.
- Post-success connectivity notes (Gate R2 P3): keep `connectivity.noteLocalWrite(groupId:)` after a successful callable return (the #357 post-write nudge stays — the device provably just reached the server); `noteQueuedWrite` is DEAD for settlement creates (nothing queues) — delete those callsites with the queued branches.
- `alreadyRecorded: true` maps to a distinct step outcome that shows the `settleUpAlreadyRecorded` copy and **suppresses the #367 WhatsApp nudge** (Gate R2 P3 — a network-retry replay must not re-offer the nudge for a payment the user already recorded once).
- Dart id helpers `deterministicSettlementId`/`decomposeLegSettlementId`/`decomposeResidualSettlementId` DELETED (ported to TS); `directedPairEpoch` STAYS (feeds `observedPairEpoch`); `crypto` dependency dropped if nothing else imports it (grep first).
- WhatsApp nudge (#367), recap CTA, correction flows: untouched (all keyed on in-memory outcome / server callables already).

---

### Task 1: TS ports — settlement ids + outstandingForPair (pure, golden-vectored)

**Files:**
- Create: `functions/src/callables/shared/settlementIds.ts`
- Create: `functions/src/callables/shared/outstanding.ts`
- Test: `functions/test/settlementIds.test.ts`, `functions/test/outstanding.test.ts` (pure jest — no emulator)

**Step 1 (RED):** Golden-vector tests. Compute 6+ vectors with the CURRENT Dart helpers (one-off `dart run` scratch script against `deterministicSettlementId`/leg/residual — paste literal expected ids into the TS test): event/group/gsu scopes, OMR 3dp vs JPY scale-1 vs USD 2dp at equal `amountFils`, epoch 0 vs 1, reversed pair; leg + residual vectors. Plus shape `^sd1[0-9a-f]{40}$`. `outstanding.test.ts`: table-driven (money code): both-sided debt → min; same-sign → 0; absent uid → 0; whole-subunit × scale exact int; legacy non-integer → floored, never rounded up; **bucket key looked up case-preserved verbatim — the port must NOT `.toUpperCase()` the net-bucket key** (client reads `bucketed[currency]` verbatim, `settle_up_screen.dart:617-618`; Gate R2 P3).
**Step 2:** Implement. `settlementIds.ts`: `deterministicSettlementId({scopeKey, payerParticipantId, recipientParticipantId, currency, amountFils, pairEpoch})` (node `crypto.createHash('sha256')`, `\x1f` joins, `sd1` prefix — amountFils passed as int, stringified exactly like Dart's `'$fils'`), `decomposeLegSettlementId`, `decomposeResidualSettlementId`. `outstanding.ts`: `outstandingForPairFils(netBucket: Map<string, Decimal>, from, to, currency): number` mirroring `expense_provider.dart:970-987` then × `currencyScale`, integer-asserted, floored.
**Step 3:** `cd functions && npx jest test/settlementIds.test.ts test/outstanding.test.ts` → PASS. Commit `feat(functions): TS ports of settlement id + outstanding-for-pair primitives (#1129)`.

### Task 2: RED — the vulnerability regression tests (rules allow what #1129 exists to stop)

**Files:**
- Test: `functions/test/settlementCreateDenied.rules.test.ts` (new)

**Step 1:** Author DENY pins that FAIL today: (a) event-scope client `set()` of a fully-valid settlement doc → assert DENIED (today: ALLOWED — this is the #1129 hole: any member can direct-write any `positiveInt` `amountFils` with zero outstanding); (b) same for group scope; (c) client create of an `event_settlement`-typed activity row → DENIED (phantom-history forge). Run: `cd functions && npm run test:emulator -- test/settlementCreateDenied.rules.test.ts`. Expected: FAIL (creates currently succeed) — paste the RED output into the PR body.
**Step 2:** Keep the file uncommitted (or commit together with Task 6's flip if a green-suite-every-commit discipline is wanted); the RED evidence run happens NOW either way.

### Task 3: `recordSettlement` — event mode (TDD, emulator)

**Files:**
- Create: `functions/src/callables/recordSettlement.ts`
- Modify: `functions/src/index.ts` (re-export — `export { recordSettlement } from './callables/recordSettlement';` — NEVER a bare const; the awk drift-extractor must see it)
- Test: `functions/test/callables/recordSettlement.event.test.ts`

**Step 1 (RED):** Emulator + `testEnv.wrap` (template: `correctSettlement.test.ts` header incl. runCommand comment). Table-driven:
- happy: member settles pair with real event debt (seed expenses via Admin SDK) → doc at the derived id, byte-shape per invariant 5, **`typeof doc.settledAt === 'string'` (ISO) and `typeof activity.timestamp === 'string'` — a Firestore Timestamp here is the Gate R2 P1 regression**, activity row `event_settlement` with the EXACT event metadata key set (`amountFils` int, `eventId`, `eventName?` — invariant 5), `actorId == caller uid`, `actorName` == recorder's member-doc displayName, output `{alreadyRecorded:false, eventScopeWrites:1, shouldBumpLedgerRevision:true}`;
- description golden: activity `description` string equals a client-built literal (`'settled <AppFormatters.formatCurrency output> with <name>'`) for one OMR + one JPY case;
- cap: `amountFils = outstanding+1` → `failed-precondition` `{kind:'over-outstanding', outstandingFils}`; `amountFils = outstanding` exactly → allowed (boundary);
- idempotent replay: identical second call → `{alreadyRecorded:true}`, still ONE doc, NO second activity row;
- sequential different state: settle 3 of 10, then (epoch+1) settle 7 → both land; then any further → over-outstanding;
- conflicting payload at same id: seed doc at derived id with different recipient → `already-exists`;
- authz: non-member caller → `permission-denied`; counterparty not in `participantIds` → `failed-precondition`; counterparty in participants but NOT in `memberIds` (#1144) → `failed-precondition`; tombstone ghost in both → allowed;
- gates: soft-deleted event → `not-found`; each group write-lock flag → `not-found`; closed event (`isClosed:true`) → ALLOWED (settlements post-close);
- validation: `payer == recipient`, zero/negative/float `amountFils`, unsupported currency, 33-char name, 281-char note, negative `observedPairEpoch` → `invalid-argument`;
- App Check: enforced via `{enforceAppCheck:true}` (config assertion — emulator can't attest).
Run: expected FAIL (callable doesn't exist).
**Step 2:** Implement event mode: auth → input validation (shared `validId`, `displayName.ts`, note mirror, strict `isSupportedCurrency`) → `db.runTransaction`: `tx.get` group (flags+membership per invariant 6) → event doc (`!isDeleted`, participants) → `tx.get` event expenses + settlements + members collections → build one-event snapshot (`groupSettlements: []`) → `computeNetFromSnapshot` → `outstandingForPairFils` → cap → derive id → `tx.get(idRef)` idempotency branch → `tx.create` doc + activity row (invariant 5 shapes; actorName from member doc matched by `userId` field).
**Step 3:** RED file green: `cd functions && npm run test:emulator -- test/callables/recordSettlement.event.test.ts`. Commit `feat(functions): recordSettlement callable — event mode (#1129)`.

### Task 4: group + groupSettleUp modes (TDD, emulator)

**Files:**
- Modify: `functions/src/callables/recordSettlement.ts`
- Test: `functions/test/callables/recordSettlement.group.test.ts`

**Step 1 (RED):** Tables:
- group solo happy (multi-event debt, group-aggregate cap, `group_settlement` activity with the EXACT group metadata key set — `amount` STRING, `recipientId`, NO `amountFils`, NO `eventId` — invariant 5; doc carries `{groupId, eventId: groupId, scope:'group'}`; `typeof settledAt === 'string'` + `typeof activity.timestamp === 'string'`);
- **cross-event pair (empty-perEvent class, invariant 11): payer owes in E1, recipient owed in E2 → mode `'group'` call lands the aggregate settle** (this is the fallback path the client routes here);
- gsu happy: N=2 legs + residual — assert leg docs at `decomposeLegSettlementId(gsuId, eventId)` carrying `groupSettleUpId`, residual at `decomposeResidualSettlementId(gsuId)`, conservation `Σ legs + residual == amountFils` server-verified, ONE `group_settlement` activity row, `eventScopeWrites: N`, `shouldBumpLedgerRevision: true`;
- residual == 0 → no residual doc;
- gsu with `legs: []` or missing → `invalid-argument` (client never sends it — empty decompose routes to mode `'group'`);
- leg > per-event drill-down cap → `failed-precondition {kind:'stale-decomposition'}` and NOTHING persisted (tx atomicity — assert all collections empty);
- Σ legs > total (negative residual) → `stale-decomposition`;
- duplicate leg eventIds / unknown eventId / soft-deleted event leg → `invalid-argument`/`stale-decomposition`;
- legs.length > 400 → `failed-precondition` (MAX_FAN_IN_EVENTS reuse);
- gsu idempotent replay → `alreadyRecorded:true`, doc count unchanged;
- **the #1129 headline case (residual 1):** seed pair debt 5; racer A settles 3 (lands), racer B calls with amount 5 derived from the same pre-A view (epoch unchanged) → B gets `over-outstanding` with `outstandingFils == 2000` (OMR) — the over-settle that #1093 accepted is now impossible;
- per-currency isolation: OMR debt does not fund a USD settle (cap computed in the settle currency's bucket only).
**Step 2:** Implement: full-subtree tx reads (`correctLogicalSettleUp` idiom + expenses), one `computeNetFromSnapshot` call serving BOTH the aggregate cap and `perEventNet` leg validation; gsu idempotency probes residual id, falling back to first-leg id when residual==0.
**Step 3:** Green; full functions suite `npm run test:emulator` green. Commit `feat(functions): recordSettlement group + groupSettleUp modes (#1129)`.

### Task 4b: writeRateMonitor settlement-skip (Gate R3 adversary P2)

**Files:**
- Modify: `functions/src/triggers/writeRateMonitor.ts` (skip counting in the event-module handler when `module == 'settlements'`, in the group-settlement handler entirely, and in the activity handler when `type` ∈ {`event_settlement`, `group_settlement`} — mirroring the existing correction-marker skips; header comment amended per Task 12)
- Test: extend the existing writeRateMonitor test file (locate by grep): settlement create + settlement-typed activity row do NOT increment the counter; an expense create still does.

**Steps:** RED → implement → green → commit `fix(functions): writeRateMonitor stops counting unforgeable settlement writes (#1129)`.

### Task 5: drift-check + docs listing

**Step 1:** `bash tool/list_expected_functions.sh` → output includes `recordSettlement`. `flutter test test/unit/release_workflow_gate_test.dart` green.
**Step 2:** `docs/CLOUD-FUNCTIONS.md`: add the callable (count 13→14 callables); note online-only + cap semantics. Commit `docs(functions): recordSettlement in the callable inventory (#1129)`.

### Task 6: rules flip + dead validator deletion + rules-test surgery

**Files:**
- Modify: `security/firestore.rules` (per "Rules changes" above — BOTH update twins in the deletion list; comment scrub `:240-241`, `:899`, `:1051`)
- Modify: `functions/test/settlementIdempotency.rules.test.ts` (its `(1) create … ALLOWED` pins at `:154-162`/`:218-226` flip to DENIED; the deny-on-existing-id cases collapse into the blanket deny — re-pin as "client settlement create denied regardless of payload/id"; keep the file as the #1093→#1129 lineage record, update its stale `:988`/`:1230` line citations)
- Modify: `functions/test/firestore-rules-publish-readiness.test.ts` (~21 `assertSucceeds` settlement creates + the `#48 shared-settlement-core characterization` block ~`:2603-2680`: DELETE the characterization block [its diagnostic purpose — which predicate rejects — is dead once all client creates are denied; shape validation now lives in `recordSettlement`'s emulator tables]; convert representative creates to DENY pins; settlement READ pins stay; expense pins untouched)
- Test (now green): `functions/test/settlementCreateDenied.rules.test.ts` (Task 2)

**Steps:** flip rules → `firebase_validate_security_rules`-equivalent compile check via the emulator suite (a dangling function reference fails the WHOLE publish — this is what the twin deletion protects) → Task-2 file green → full rules suite `npm run test:emulator` green (expect expression-ceiling warnings DROPPING, not rising) → commit `fix(rules): settlement creates are callable-only — deny client direct writes (#1129)` (include Task 2's test file here if it wasn't committed RED).

### Task 7: client callable wrapper + result model + error mapping

**Files:**
- Create: `lib/features/ledger/models/record_settlement_result.dart`
- Modify: `lib/core/services/firebase_functions_service.dart` (add `recordSettlement`, doc-comment the ONLINE-ONLY contract like the #889 block)
- Modify: `lib/core/utils/settlement_write_error.dart` (code+details branching per "Client changes" — `FirebaseFunctionsException extends FirebaseException`, so extend the existing branch, don't add a parallel catch)
- Test: `test/unit/record_settlement_result_test.dart`, extend the existing settlement-write-error test file (locate by grep; table-driven)

**Steps:** RED (fromData parsing incl. missing/garbage fields fail-safe; error-mapping table incl. over-outstanding details, already-exists, unavailable) → implement → green → `flutter analyze` → commit `feat(client): recordSettlement wrapper + error classification (#1129)`.

### Task 8: services rewired onto the callable

**Files:**
- Modify: `lib/features/ledger/services/settlement_service.dart` (delete `buildSettlementDoc` write use, `addSettlement` Firestore body, `deterministicSettlementId`, `decomposeLegSettlementId`, `decomposeResidualSettlementId`; keep `directedPairEpoch`, watch streams, `Settlement.fromFirestore`; new `addSettlement` = callable call via injected `FirebaseFunctionsService`)
- Modify: `lib/features/groups/services/group_settlement_service.dart` (same treatment for `addGroupSettlement`/`stageDecomposedSettleUp` → single callable call with legs payload; DELETE `kMaxDecomposeLegsAtomic` + batch machinery)
- Modify: providers wiring (`expense_provider.dart:53` `settlementServiceProvider`, `group_balance_provider.dart:30` `groupSettlementServiceProvider`) to inject `firebaseFunctionsServiceProvider`
- Tests: `test/unit/settlement_service_test.dart`, `test/unit/group_settlement_service_test.dart` — REWRITTEN: doc-shape assertions move to the Task 3/4 emulator tables; what remains client-side to pin = payload construction (legs forwarding, epoch forwarding, currency/amount int conversion via `MoneySerializer.toSubunits` at the boundary) against a recording fake functions service

**Steps:** RED (new service tests) → implement → compiler-forced callsite sweep → green → commit `refactor(client): settlement creates route through recordSettlement (#1129)`.

### Task 9: screens — pre-flight, epoch, routing, bump, copy

**Files:**
- Modify: `lib/features/ledger/screens/settle_up_screen.dart`, `lib/features/groups/screens/group_settle_up_screen.dart` (per "Client changes" — incl. invariant-11 routing: `perEvent.isEmpty` → mode `'group'`)
- Modify: `lib/l10n/app_en.arb` + `app_ar.arb`: `settleUpAlreadyRecorded` only (offline reuses `settleUpRecordFailed`; over-outstanding reuses the #773 balance-changed key — locate by grep and confirm its AR pair exists before relying on it)
- Tests: `test/features/ledger/settle_up_screen_test.dart`, `test/features/groups/group_settle_up_screen_test.dart` + siblings (`group_settle_up_atomic_929_test.dart`, `decomposed_settleup_batch_test.dart`, `settle_up_dedup_1093_test.dart`, revalidation tests) — port seams from fake-Firestore doc assertions to recording-fake-service assertions; DELETE queued/"will sync" assertions for settlement creates (obsolete behavior — delete, don't patch); ADD: offline pre-flight test (connectivity `offline` → copy shown, service NOT invoked; and `syncing` → call PROCEEDS); empty-perEvent routing test (mode 'group' payload sent); alreadyRecorded → success + copy; bump fired iff `shouldBumpLedgerRevision`

**Steps:** RED (new behaviors) → implement → full `flutter test` green → `flutter analyze` → `bash tool/check_theme_purity.sh` (touched widgets) → commit `feat(client): online-only settle recording UX + server-authoritative cap handling (#1129)`.

### Task 10: dedup-test lineage port

`test/features/ledger/settle_up_dedup_1093_test.dart` + `test/features/groups/group_settle_up_dedup_1093_test.dart` pinned client-side id determinism that no longer exists client-side. Port their SCENARIO (two records from one observed snapshot → one logical payment) to: both calls send the same `observedPairEpoch` → recording fake asserts identical derived intent; the authoritative one-doc guarantee now lives in Task 3/4's emulator idempotency tables. Delete `test/unit/deterministic_settlement_id_test.dart` (superseded by TS golden vectors — note the supersession in the commit body). Commit `test: port #1093 dedup pins to the callable seam (#1129)`.

### Task 11: full-suite + analyze + coverage gate

`flutter analyze` clean; `flutter test` full green; `cd functions && npm run test:emulator` full green; coverage ≥ 80% (CI mirror). Fix fallout; commit fixes atomically.

### Task 12: docs + landmines + journal

- `CLAUDE.md`: Financial-Calculations settlement paragraph — settlement creates are **callable-only** (`recordSettlement`, online-only, server-derived `sd1` ids from client-observed epoch, server cap at pair outstanding); correct the stale `kMaxDecomposeLegsAtomic` "=9" note (constant was 8 and is now DELETED — decompose legs bounded by MAX_FAN_IN_EVENTS server-side); amend the #752/#929 bullets (single-write >8-leg carve-out REMOVED — atomic server tx replaced it; the `perEvent.isEmpty` group fallback STAYS); amend the #1093 line (ids still deterministic dedup keys, derivation now server-side); note the activity type allow-list tightening.
- `functions/src/triggers/writeRateMonitor.ts:6-9` header: settlements are now callable-routed BY DESIGN (#1129); expenses remain client-direct.
- `docs/SECURITY-RULES.md` settlement section.
- `journal.md`: the trade-off record — offline settle recording deliberately killed for server-side money integrity; what would reverse it (launch telemetry showing offline-settle demand).
- Commit `docs: settlement create is callable-only (#1129)`.

---

## Accepted residuals of THIS design (named, deliberate)

1. **Settlements are online-only.** The product cost #1093 chose (c) to avoid, now accepted per the issue. Offline attempt → immediate honest copy; no queue, no staging (a client-side replay queue is the forbidden custom-sync-queue). `syncing` proceeds (device is online).
2. **The dedup-DROP direction of #1093 residual 2 remains** (Gate R1 rubric): a stale-epoch client intending a genuinely NEW identical-amount payment collides with the recorded one and sees `alreadyRecorded` — the second payment record is dropped, exactly as #1093 drops it today. What #1129 closes is the over-CREDIT direction (the cap makes divergent-view amounts unlandable beyond live outstanding). Mitigation unchanged: visible history + corrections.
3. **Epoch remains client-observed** → a hostile client can vary it to mint several settlements, each ≤ the *live* outstanding at its commit. Money exposure is bounded by actual debt (the cap is the guard); dedup stays an honest-client courtesy exactly as in #1093. Not a hole relative to #1129's goals: over-settle is impossible.
4. **Unsynced offline expenses are invisible to the cap** — the server caps against synced truth. Divergent-cache class, unchanged posture. Includes the SAME-device `syncing`-window sub-case (Gate R3 adversary): a queued offline expense still replaying when the user settles means the advisory local revalidation passes but the callable caps at server truth → `staleBalance` copy, retry succeeds once the replay lands. Pre-#1129 the settle queued behind the expense and always landed; now it's an honest bounce. Safe degradation, named so it isn't re-filed as a bug.
5. **Group/gsu transaction reads the whole group subtree** (events × expenses+settlements). No read cap (correctLogicalSettleUp precedent, now + expenses); contention retries theoretically possible in hot groups. Revisit with telemetry; write side bounded at 400 legs.
6. **Second racer of the same logical payment usually sees success (`alreadyRecorded`)** — except the gsu edge (Gate R1 rubric): two racers with the same total+epoch but DIFFERENT leg splits collide on amount-independent leg ids with mismatched amounts → `already-exists` → the balance-changed refresh UX. Not money-wrong (atomic reject; cap holds); the ledger shows one payment either way.
7. **balanceAggregator recomputes the oracle again post-commit** — double compute per create (once for cap, once for the display cache). Pre-existing trigger economics; not worth threading the callable's figure into the aggregate write (the trigger owns monotonicity).
8. **`payerName`/`recipientName` are caller-supplied mirrors** (as today) — a hostile member can label parties oddly within display-name validity; display-only, money truth in ids. `actorName` is now server-derived (invariant 5) — strictly harder to forge than today.
9. **Activity `description` is server-formatted** — the TS `formatCurrency` mirror could drift from client formatting in future locales; golden string test (Task 3) pins the current format. Display-only; metadata carries money truth.
10. **Legacy uuid-id docs**: pre-#1093 random-id settlements never collide with anything — unaffected; epoch counting includes them (they're live pair rows), same as #1093.
11. **The event-scope cap is per-event, not pair-global** (Gate R2 rubric): a pair partially settled at GROUP scope (standalone group settlement — the old >kMax carve-out, departed-party fallback, or legacy docs) can still be settled up to the EVENT-scope outstanding, over-paying the pair's aggregate (worked example: E1 debt 10, group-scope settle 4 → aggregate 6, event cap still 10). This faithfully mirrors the shipped client basis (`_freshOutstandingForPair` folds only that event's expenses+settlements) — **widening the cap would break client↔server parity and false-block legit event settles; do NOT "fix" it.** Unchanged exposure class from today; corrections-space; the group-scope caps DO see everything.

## Verification-principles report (run while authoring, 2026-07-11; updated post-R1)

1. **Callsite classification:** every input to the callable is OUTBOUND (feeds the write): amountFils (int subunits at the boundary via `MoneySerializer.toSubunits` — client converts exactly where `buildSettlementDoc` did), pair ids, currency code, epoch int. Display-formatted strings never cross INTO money fields; the activity `description` (display string) is server-BUILT, never client-supplied. INBOUND readers of settlement docs (streams, oracle, corrections, aggregator) untouched — verified each folds by path/fields, never by id format.
2. **Concrete claims re-verified this session:** `outstandingForPair` `expense_provider.dart:970-987` (read); `computeNetFromSnapshot`/`loadGroupBalanceSnapshot`/`perEventNet` shapes `groupNetBalance.ts:533-661` (read); `correctSettlement.ts` full read; rules `:1044-1068`/`:1094-1095`/`:1104-1109`/`:1320-1353` + `validGroupSettlementUpdate:1330-1337` + `requesterIsRecordCreator:240-244` (grep post-R1); `kMaxDecomposeLegsAtomic = 8` (grep); `addSettlement` #1140 co-batch body + event activity metadata keys `settle_up_screen.dart:875-922` (read); group/gsu activity metadata keys `group_settle_up_screen.dart:900-937,1075-1109` (read); `perEvent.isEmpty` fallback `group_settle_up_screen.dart:815-830` (read); classifier `lib/core/utils/settlement_write_error.dart:14-48` + `settleUpRecordFailed` `app_en.arb:834` (grep); callable wrapper idiom `firebase_functions_service.dart:129-179` (read); `currencyScale`/`currencyOf` `groupNetBalance.ts:46-54` (read); `decomposeGroupSettlement` invariants `expense_provider.dart:840-874` (read); `MAX_FAN_IN_EVENTS=400` + index.ts convention (researcher-cited, re-grep at implementation).
3. **Read-path per write-path:** settlement docs → watch streams, oracle, `balanceAggregator`, corrections (id-opaque), `groupSettleUpId` filters — ALL consume fields the server writes byte-compatibly (invariant 5). Activity row → activity feed (#808 type-guarded metadata reads) — per-mode key sets enumerated (invariant 5), divergence preserved. New OUTPUT read-path: `RecordSettlementResult` → screens (bump + copy) — spelled in Task 7.
4. **Fields from the type:** doc key sets enumerated from `buildSettlementDoc`/`buildGroupSettlementDoc` + rules `hasOnly` lists; activity metadata keys enumerated from the three construction sites (not from memory); input interface enumerated field-by-field with per-field validation named.
5. **Exact data contracts:** callable input/output interfaces spelled; id grammar + scopeKeys pinned to Dart-era bytes with golden vectors; error `details.kind` strings enumerated; legs payload shape `{eventId, amountFils}`; per-mode activity metadata key sets spelled.
6. **Arithmetic decomposition:** `Σ legs + residual == amountFils` is server-ENFORCED (reject, not trust); legs validated against `perEventNet` overlap caps (participantIds-only basis — deliberately matching the client's drill-down); totals validated against aggregate nets — the two bases deliberately do NOT reconcile (CLAUDE.md #366); leg caps and total cap are independent guards, both must pass.
7. **Orthogonal adversarial pass:** TIME — retry-after-success (idempotent branch), settle-after-unrelated-pair-activity (epoch mismatch does not block; cap governs), sequential re-settle (new epoch → new id → capped). IDENTITY — settle-on-behalf (#595), tombstone ghosts (#1144 mirror), claim re-key (ids opaque). SCOPE — event/group/gsu namespaces disjoint; per-currency buckets never cross-fund; cross-event empty-perEvent pair routes to group mode (invariant 11). MONEY-FLOW — reversed-direction pair derives a different id AND its own directed cap; zero-outstanding pair → any amount rejected. OFFLINE — pre-flight (`offline` blocks, `syncing` proceeds) + error mapping; no write ever queues. CORRECTION-NAMESPACE — `correction_*` ids disjoint from `sd1*` (R1 adversary trace).

## Gate record

- Round 1 (rubric + adversary, fresh-context Opus pair, 2026-07-11): rubric 0 P1 / 4 P2 / 4 P3; adversary 2 P1 / 1 P2 / 1 P3. Union applied in full: [P1] empty-perEvent fallback orphaned → invariant 11 + client routing + Task 4 boundary tests; [P1] `validGroupSettlementUpdate` missing from rules deletion list (dangling ref = ruleset publish failure) → Rules changes + Task 6; [P2] pre-flight `!= online` false-blocks `syncing` → `== offline`; [P2] actorName source unspecified → server-derived from recorder member doc (userId-field match); [P2] per-mode activity metadata divergence un-enumerated → invariant 5; [P2] classifier path wrong + FirebaseFunctionsException subtyping → Client changes/Task 7; P3s: leg/residual id shorthand precision, residual-2 overclaim reframed, gsu already-exists racer residual 6, stale rules comments scrub.
- Round 2 (fresh pair, 2026-07-11): rubric 0 P1 / 1 P2 / 4 P3; adversary 1 P1 / 1 P2 / 2 P3. Union applied: [P1] `new Date()` shorthand would persist Firestore Timestamps where the read-path type-buckets on ISO Strings (`settlement_model.dart:166-169` epoch-0 fallback; orderBy type-splits) → `.toISOString()` spelled + string-type assertions in Task 3/4 tables; [P2] activity `actorId = request.auth.uid` pinned (paid/received/between branching); [P2] event-cap-is-per-event named as residual 11 (mirrors client; do not widen); P3s: noteLocalWrite kept / noteQueuedWrite dead, alreadyRecorded suppresses the WhatsApp nudge, `shared/eventFanIn.ts` path, server `eventName` from event doc, classifier gains `staleBalance` kind, outstanding port case-preserved bucket lookup.
- Round 3 (fresh pair, 2026-07-11): rubric 0 P1 / 0 P2 / 3 P3; adversary 0 P1 / 1 P2 / 1 P3. **UNION P1-CLEAN → GATE CLOSED.** Post-close folds (non-P1): [P2] writeRateMonitor settlement-skip (Task 4b — the 400-leg bound invalidated the 100/60s threshold calibration; settlement counting vestigial post-flip); [P3] `requesterIsRecordCreator` has ZERO live refs after deletion (comment guidance corrected); [P3] actorName is avatar-chip-only (scope note); [P3] same-device syncing-window bounce named in residual 4; [P3] `:1051` scrub was auto-satisfied by deletion (dropped from list).
