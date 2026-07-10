# #1093 — Deterministic settlement ids (concurrent double-pay dedup) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Kill the cross-device / offline-replay settlement double-record (#1093) by deriving settlement doc ids deterministically from the settle state, so the second identical write collides with the first and is rejected by the already-live `allow update: if false` — no rules change, no Cloud Function, offline settle preserved.

**Architecture:** A settlement written twice from the same observed state is the same logical payment. If both writers derive the doc id from (scope, directed pair, currency, amount-in-subunits, count-of-prior-pair-settlements), they produce the SAME id; Firestore evaluates a `set()` on an existing doc as an *update*, and both settlement blocks already hard-deny update (`security/firestore.rules:988` event, `:1230` group — verified 2026-07-11). First write lands, second gets PERMISSION_DENIED (online: surfaced via the existing `classifySettlementWriteError` → `denied` copy; offline replay: silently discarded by the SDK, which is the CORRECT outcome — the debt is already settled). The oracle (`recomputeNet`) folds settlements by collection path and never reads ids, so money truth is untouched.

**Decision lineage:** Option (c) of #1093's fork, chosen 2026-07-10 over (a) transactional callable (deferred post-launch — kills offline settle-up) and (b) pure accepted-risk. Residuals accepted under (c) match the B1 cooperative-trust posture (see "Accepted residuals").

**Tech stack:** Dart only. `crypto` (sha256) promoted from transitive (`pubspec.lock:236`) to direct dependency. No `functions/src`, no `security/firestore.rules` change; one NEW rules-emulator test pins the deny-on-existing-id invariant this design leans on.

---

## Invariants this plan relies on (each verified against code this session)

1. **Settlement update is hard-denied in BOTH scopes.** `security/firestore.rules:988` (`match /settlements/{settlementId}` under events: `allow update: if false`) and `:1230` (group block). A `set()` on an existing doc id is an update in rules terms → denied. Task 5 pins this with an emulator test so a future rules edit can't silently remove the floor this design stands on.
2. **`data.id == docId`** is enforced on event-settlement create (`security/firestore.rules:914`); `buildSettlementDoc`/`buildGroupSettlementDoc` already thread the id into the doc body, so a deterministic id flows to both places unchanged.
3. **Ids are opaque to every reader.** `correctSettlement.ts` looks docs up by id (no format check); `settlement_correction_affordance.dart:37` explicitly treats ids as non-deterministic opaque strings; `recomputeNet` folds by path; activity metadata carries no settlement id (`settle_up_screen.dart:885-899`). No `Uuid.parse`/format validation anywhere (grepped lib/ + functions/src 2026-07-11).
4. **Current id minting sites (all replaced by this plan):** `settlement_service.dart:150` (`addSettlement`), `group_settlement_service.dart:152` (`addGroupSettlement`), `group_settlement_service.dart` decompose loop + residual (inside `stageDecomposedSettleUp`, two `const Uuid().v4()` sites), `group_settle_up_screen.dart:802` (`groupSettleUpId`).
5. **Write-path callers (exhaustive in lib/):** `settle_up_screen.dart:847` → `addSettlement`; `group_settle_up_screen.dart:849` → `stageDecomposedSettleUp`; `group_settle_up_screen.dart:995` → `addGroupSettlement`. Nothing else creates settlements client-side; `correctSettlement` (server) uses Admin SDK and is out of scope (its reverse rows must NOT dedupe — see Task 2 note).
6. **The classifier already handles the loser.** `settlement_write_error.dart:30-35` maps `permission-denied` → `SettlementWriteErrorKind.denied` → `settleUpRecordFailedDenied` copy. No new UX surface required in v1 (copy polish = follow-up, non-blocking).

## What the id is derived from — and what it is NOT

`id = 'sd1' + sha256("sd1\x1f<scopeKey>\x1f<payerParticipantId>\x1f<recipientParticipantId>\x1f<currency>\x1f<amountFils>\x1f<pairEpoch>").hex[0..39]` (43 chars, hex — valid Firestore doc id, no charset risk).

- **scopeKey:** `event:<groupId>:<eventId>` | `group:<groupId>` | `gsu:<groupId>` (decompose parent). Distinct namespaces — no cross-scope collision.
- **amountFils:** derived INSIDE the helper via `MoneySerializer.toSubunits(amount, currency)` — the exact same conversion `buildSettlementDoc` performs, so id-amount and stored `amountFils` cannot drift (OMR=1000, JPY=1 handled once).
- **pairEpoch:** count of settlement docs for the directed pair (payer→recipient) visible in the id's scope basis (defined per callsite below). The watch streams filter `isDeleted == false` at the query (`settlement_service.dart:37`, `group_settlement_service.dart:60`), so the epoch counts **provider-visible live rows** — both devices apply the identical filter, so determinism holds; the helper itself is pure and counts whatever list it is given. (Do NOT "widen" the provider filters to include soft-deleted rows — that would shift every epoch.)
- **Per-callsite epoch basis:**
  - event settle → `eventSettlementsProvider((groupId, eventId))` — the exact provider the #773 revalidation reads (`settle_up_screen.dart:579-580`), so id basis and cap basis are genuinely one snapshot;
  - group fallback settle → `groupSettlementsProvider(groupId)`;
  - decompose (`gsu:` scope) → the union `groupSettlementsProvider(groupId)` ∪ `groupTaggedEventSettlementsProvider(groupId)` — group docs plus #752-tagged event legs, BOTH already watched by the screen (`group_settle_up_screen.dart:141,144`; provider at `group_balance_provider.dart:267-283`). This basis increments whenever a decompose (tagged legs) or a fallback group settle (group doc) lands for the pair. A plain untagged event settle does not move it — harmless, because it changes the pair's outstanding, so the decompose TOTAL (an id input) changes instead. `GroupBalances` carries NO settlement list field (typedef `group_balance_provider.dart:104-111` — six fields only), so the epoch is a separate synchronous `ref.read` adjacent to the cap read: cross-provider coherence is not transactional, and a settlement landing between two providers' emissions is the divergent-view residual (#2), not a new class.
- **Deliberately EXCLUDED:** `settledAt` (differs per device — would break dedup entirely), `payerName`/`recipientName` (deviceName mirrors differ per device), `note` (a different note on the same payment is still the same payment), `createdBy` (Device B settling on-behalf per #595 must collide with Device A self-settling — that is THE scenario).

**Why epoch makes sequential legit settles safe — once the prior write is locally visible:** pay 5 → doc lands and the watched stream emits → pair count goes 0→1 → next legit settle of a re-accrued 5 derives epoch 1 → different id. Two RACING settles both observe count 0 → same id → second denied. An offline device's queued write replays with its capture-time id: if the counterparty settled meanwhile (same observed state → same id) the replay is discarded — correct; if nobody settled, it lands — correct. The window before the local emit is residual #7 below (two genuinely distinct identical-value payments recorded back-to-back before the stream reflects the first).

---

### Task 1: Pure id helpers + crypto promotion

**Files:**
- Modify: `pubspec.yaml` (add `crypto: ^3.0.7` to `dependencies` — resolved version at `pubspec.lock:243`, key at `:236`)
- Modify: `lib/features/ledger/services/settlement_service.dart`
- Test: `test/unit/deterministic_settlement_id_test.dart` (new)

**Step 1: failing tests first.** Table-driven (money code — clean/warning/error rows):
- same inputs → same id, twice (determinism);
- each input perturbed (scopeKey, payer, recipient, currency, amount, epoch) → different id;
- OMR `2.900` and JPY `2900` at the same epoch → different ids (subunit scale flows through: 2900 fils vs 2900 yen — assert ids differ from each other AND from USD `29.00` = 2900 cents; all three have amountFils 2900 but different currency → different ids);
- id shape: 43 chars, `^sd1[0-9a-f]{40}$`;
- `directedPairEpoch`: empty list → 0; reversed pair NOT counted; other-pair rows not counted; the helper is PURE — it counts exactly the list it is given (callers feed provider-filtered `isDeleted == false` rows; assert that in a doc comment, not in the helper).

**Step 2: implement** in `SettlementService` (static, pure):
```dart
static String deterministicSettlementId({
  required String scopeKey,
  required String payerParticipantId,
  required String recipientParticipantId,
  required String currency,
  required Decimal amount,
  required int pairEpoch,
}) {
  final fils = MoneySerializer.toSubunits(amount, currency);
  final canonical = [
    'sd1', scopeKey, payerParticipantId, recipientParticipantId,
    currency, '$fils', '$pairEpoch',
  ].join('\x1f');
  return 'sd1${sha256.convert(utf8.encode(canonical)).toString().substring(0, 40)}';
}

static int directedPairEpoch(
  Iterable<Settlement> settlements, {
  required String payerParticipantId,
  required String recipientParticipantId,
}) => settlements
    .where((s) =>
        s.payerParticipantId == payerParticipantId &&
        s.recipientParticipantId == recipientParticipantId)
    .length;
```
Plus decompose derivations (Task 2 consumes them):
```dart
static String decomposeLegSettlementId(String groupSettleUpId, String eventId) =>
    'sd1${sha256.convert(utf8.encode('sd1leg\x1f$groupSettleUpId\x1f$eventId')).toString().substring(0, 40)}';
static String decomposeResidualSettlementId(String groupSettleUpId) =>
    'sd1${sha256.convert(utf8.encode('sd1res\x1f$groupSettleUpId')).toString().substring(0, 40)}';
```

**Step 3:** run the unit file (green), `flutter analyze`, commit.

### Task 2: Services take the id from the caller — no internal Uuid

**Files:**
- Modify: `lib/features/ledger/services/settlement_service.dart` (`addSettlement`: delete `final id = const Uuid().v4();`, add `required String id` param)
- Modify: `lib/features/groups/services/group_settlement_service.dart` (`addGroupSettlement`: same; `stageDecomposedSettleUp`: replace both internal `Uuid().v4()` with `SettlementService.decomposeLegSettlementId(groupSettleUpId, leg.eventId)` / `decomposeResidualSettlementId(groupSettleUpId)`)
- Tests: every existing caller of these methods in `test/` gains an explicit id (grep `addSettlement(`/`addGroupSettlement(` across `test/`; pass any literal id — determinism is not what those tests pin)

Notes:
- `required` (not defaulted) so the compiler forces every future call site to decide its id — an optional param silently reopens #1093.
- Decompose legs are per-event unique — add an `assert` in `stageDecomposedSettleUp` that `eventLegs` eventIds are distinct (duplicate eventIds would derive duplicate leg ids and `batch.set` last-wins would silently drop a leg). The true duplicate-immunity invariant at the live callsite: the loop at `group_settle_up_screen.dart:837-839` iterates `eventOrder`, which is duplicate-free because it is built from unique event doc ids (`:174-176`) — **do NOT rewrite that loop to iterate `perEvent.keys`**; `eventOrder` feeding both the display breakdown and the write IS the #752 WYSIWYG guarantee. Pin the invariant with the assert + a comment at the loop, nothing more.
- `correctSettlement` reverse rows are server-written with Admin SDK ids — untouched; corrections must NEVER dedupe against each other (each correction is a distinct offsetting row), which is another reason id derivation lives on the CLIENT create path only.
- Remove the now-unused `uuid` import from `settlement_service.dart` if nothing else in the file uses it (group service keeps whatever it still needs).

Steps: update signatures → fix compile errors in tests by threading literal ids → full `flutter test` green → commit.

### Task 3: Event settle callsite derives id from its revalidation snapshot

**Files:**
- Modify: `lib/features/ledger/screens/settle_up_screen.dart` (`_recordSettlement`, ~L811-860)
- Test: `test/features/ledger/settle_up_dedup_1093_test.dart` (new)

**Step 1: RED regression test** (the test that would have caught #1093): against `FakeFirebaseFirestore`, issue TWO records for the same pair/amount **derived from the same epoch-0 snapshot — i.e. WITHOUT pumping/emitting the settlement stream between them** (this models the concurrent race: neither device has seen the other's write). Concretely: capture the provider state once, trigger both record calls back-to-back before any `pump` that lets `eventSettlementsProvider` re-emit. Assert the settlements collection holds **ONE** doc. RED today: two uuid docs (count 2). GREEN after: both writes derive the same id, the fake overwrites, count 1. **Timing matters:** if the stream re-emits between the two records, the second legitimately derives epoch 1 → a different id → count 2, which is CORRECT sequential behavior (the converse of residual #7) — that is not the scenario this test pins. (The fake doesn't enforce rules — the *production* second write is denied, pinned by Task 5; this test pins client-side id determinism, which is what makes the denial fire.)

**Step 2: implement.** In `_recordSettlement`, before the service call:
```dart
final settlements =
    ref.read(eventSettlementsProvider((groupId: widget.groupId, eventId: widget.eventId))).valueOrNull;
if (settlements == null) {
  // Fail-closed, mirroring the #1028 valueless-read skip: no basis → no write.
  // Surfaces via the existing catch → settleUpRecordFailedGeneric.
  throw StateError('settlement basis unavailable — cannot derive dedup id');
}
final id = SettlementService.deterministicSettlementId(
  scopeKey: 'event:${widget.groupId}:${widget.eventId}',
  payerParticipantId: fromUserId,
  recipientParticipantId: toUserId,
  currency: currency,
  amount: amount,
  pairEpoch: SettlementService.directedPairEpoch(
    settlements, payerParticipantId: fromUserId, recipientParticipantId: toUserId),
);
```
Pass `id:` to `addSettlement`. The throw lands in the existing `catch (e)` → `_StepOutcomeKind.failed` + error snackbar (no new UI surface; the stepped walk stops on it, per L4).

**Step 3:** RED test now green; existing `settle_up_screen` tests green; commit.

### Task 4: Group screen — deterministic `groupSettleUpId` + fallback single settle

**Files:**
- Modify: `lib/features/groups/screens/group_settle_up_screen.dart` (`:802` and the fallback `_recordSettlement` feeding `:995`)
- Test: `test/features/groups/group_settle_up_dedup_1093_test.dart` (new)

**Step 1: RED tests.** (a) Decomposed settle staged twice from identical state → assert total settlement docs across event subcollections + group collection equals N+1 (not 2·(N+1)) in the fake. (b) Fallback single group settle recorded twice from identical state → 1 group doc.

**Step 2: implement.**
- **Placement:** the derivation below must live INSIDE the `try {` at `group_settle_up_screen.dart:808` (the current `:802` mint sits ABOVE it — a fail-closed throw placed literally at `:802` would propagate uncaught instead of reaching the classified snackbar; move the mint down into the try, alongside the other reads):
```dart
final groupDocs =
    ref.read(groupSettlementsProvider(widget.groupId)).valueOrNull;
if (groupDocs == null) {
  // Fail-closed, mirroring Task 3: no epoch basis → no write. Surfaces via
  // the existing catch → the classified error snackbar.
  throw StateError('group settlement basis unavailable — cannot derive dedup id');
}
final taggedLegs = ref.read(groupTaggedEventSettlementsProvider(widget.groupId));
final pairSettlements = [...groupDocs, ...taggedLegs];
final groupSettleUpId = SettlementService.deterministicSettlementId(
  scopeKey: 'gsu:${widget.groupId}',
  payerParticipantId: fromUserId,
  recipientParticipantId: toUserId,
  currency: currency,
  amount: amount, // the TOTAL being decomposed
  pairEpoch: SettlementService.directedPairEpoch(
    pairSettlements, payerParticipantId: fromUserId, recipientParticipantId: toUserId),
);
```
  Basis rationale in "Per-callsite epoch basis" above: both providers are ALREADY watched by this screen (`:141,144`), `groupTaggedEventSettlementsProvider` is a plain (non-async) `Provider.family` returning `List<Settlement>` directly (`group_balance_provider.dart:267-283` — its own body folds valueless event streams to `[]`, which is the same divergent-view exposure as the #244 loading-skip, residual #2). `GroupBalances` itself carries no settlement list (typedef `:104-111`), which is WHY the epoch reads sit beside — not inside — the `groupBalancesProvider` cap read; the reads are synchronous and adjacent, and any incoherence between them is residual-#2 class, orders of magnitude smaller than the cross-device window this plan closes.
- Legs + residual ids: already handled inside the service (Task 2) — two racing decomposes derive the same `groupSettleUpId` → every leg + residual collides → the loser's WHOLE batch is denied atomically (#929 all-or-nothing), nothing partial persists.
- Fallback single group settle (`:995` path): same pattern, `scopeKey: 'group:${widget.groupId}'`, epoch over `groupSettlementsProvider` docs only.

**Step 3:** RED tests green; existing group settle tests green; commit.

### Task 5: Rules-emulator test pinning deny-on-existing-id (test-only, no rules change)

**Files:**
- Test: `functions/test/settlementIdempotency.rules.test.ts` (new, or a describe block in the existing rules-readiness suite — match its harness)

Cases (event + group scope): (1) create settlement at id `sd1aaa…` with a valid payload → ALLOWED; (2) second `set()` at the SAME id, valid payload, same or different auth member → DENIED (update path, `allow update: if false`); (3) `set(..., {merge: true})` at the same id → DENIED. Run via `cd functions && npm run test:emulator -- <file>` (never bare `npm test` — hangs without emulator).

### Task 6: Docs + landmine

- `CLAUDE.md` Financial-Calculations section, one line: settlement doc ids are deterministic dedup keys (`sd1…`, #1093) derived from (scope, directed pair, currency, subunits, pair-epoch) — never revert to random uuids on a create path, and never add inputs that differ across devices (names, timestamps, notes).
- PR body: `Closes #1093`, `Spec:` line pointing at this file, RED output pasted for Task 3/4 tests.

---

## Accepted residuals (named, deliberate — do not "fix" silently)

1. **Different-amount concurrent settles both land** (3 partial vs 5 full → over-settle by 3). Correction-space (#889 UI). The server value-cap that would catch it is option (a) — deferred post-launch as its own issue.
2. **Divergent caches derive different epochs → dedup misses.** If devices disagree on the existing settlement set, their outstanding checks disagreed too — pre-existing class, same trust posture as B1 open-edit. Includes the #1106 convergence window (cold-push entry undercounts `allEventSettlements`) — cross-referenced there; #1106's fix (gating record on convergence) also tightens this.
3. **Orphan activity row on a discarded offline replay.** The queued settle logs its activity row immediately; if the replay is denied the settlement vanishes but the row stays. Display-only, money truth unaffected, pre-existing class for ANY replay-denied write (#929 documents the same for decompose legs). Follow-up candidate, non-blocking.
4. **A hostile member can still write `amountFils: 999999`.** Rules only check `positiveInt` today; unchanged by this plan; that is option (a)'s territory.
5. **Loser-device UX says "recording refused" rather than "already settled".** Honest but generic (`settleUpRecordFailedDenied` — present in BOTH `app_en.arb` and `app_ar.arb`, verified). Copy polish = follow-up, needs en+ar keys; not worth blocking the money fix.
6. **Namespace divergence across write mechanisms.** (a) Decompose-vs-fallback: the path choice at `group_settle_up_screen.dart:784-786` (`bothLiveMembers`, `perEvent` emptiness, ≤9-leg cap) is cache-dependent; two devices racing the SAME logical settle-up that disagree on membership or event count derive ids in disjoint namespaces (`gsu:`+legs vs `group:`) → no collision → both land. (b) Cross-screen: one device settling from the EVENT settle sheet (`event:` scope) while another settles the overlapping debt from the GROUP settle-up screen (`gsu:`/leg scope) likewise never collides. Both require divergent views or different user paths — residual-#2 class, no worse than today's always-double-record, corrections handle it.
7. **Two genuinely distinct identical-value payments recorded before the first is locally visible collide.** Same scope/pair/currency/amount recorded back-to-back before the watched stream reflects the first → same epoch → same id → the second is refused (online, honest `denied` copy, retry works once the stream emits) or **silently discarded at replay (offline — the loser device showed "will sync" success and gets NO error or retry prompt; the payment record simply never lands).** Behavior change vs today (two uuids both landed); deliberately accepted — a same-observed-state identical repeat payment is overwhelmingly the double-record this plan exists to kill. Be honest about the offline branch: the mitigation is corrections/visible history, not a retry path.
8. **Task 3/4 fail-closed is a (deliberate) new blocker on a valueless basis read.** Previously a settle could be recorded even if the settlements provider had no value; now it throws (surfaced via the existing classified snackbar). Low exposure — the settle sheet cannot meaningfully render without this data — and it mirrors the #1028/#1030 valueless-read-skip semantics on the revalidation itself.
9. **Predictable ids enable a cross-pair squat (member denial-of-settlement).** Id inputs are member-readable, so a member can pre-create a valid settlement doc OF A DIFFERENT PAIR (their own on-behalf pair, `createdBy==self`) at a victim pair's next deterministic id — the exact-pair epoch filter means the plant doesn't move the victim's epoch, so the victim's next settle collides → denied. Partially self-defeating (a SAME-pair plant bumps the epoch and misses; the squat doc is itself a real, visible, append-only settlement polluting the squatter's own ledger — self-incriminating) and recoverable (any landed pair settlement moves the epoch; a different amount also escapes). New capability vs random uuids, accepted under the same B1 cooperative-trust posture as residual #4; the server value-cap callable (#1129) is where adversarial members get addressed if telemetry ever demands it.

## Verification-principles report (run while authoring, 2026-07-11)

1. **Callsite classification:** id derivation is OUTBOUND (feeds the write). All inputs are canonical write-domain values (participant ids, ISO currency code, integer subunits via `MoneySerializer.toSubunits`, doc count) — no display-formatted string reaches the id (RAmount/formatters never touched). The three lib write callsites enumerated in Invariant 5; INBOUND readers enumerated in Invariant 3.
2. **Concrete claims re-verified this session:** rules `:988`/`:1230` update-deny (sed), `:914` `data.id == docId` (sed), Uuid sites (grep), classifier mapping `settlement_write_error.dart:30-35` (read), `crypto 3.0.7` in `pubspec.lock:244` (grep), `groupTaggedEventSettlementsProvider` shape + screen watches (`group_balance_provider.dart:267-283`, `group_settle_up_screen.dart:141,144`, read). **Round-1 Gate correction:** the spec originally cited a `GroupBalances.allEventSettlements` field that does not exist (it is a provider-body local, typedef `:104-111` has six fields, none a settlement list) — the gsu epoch basis was redefined onto the two real, already-watched providers above.
3. **Read-path per write-path:** doc id consumers = `correctSettlement` (lookup by id, opaque), `groupSettleUpId` equality filters (`group_settle_up_screen.dart:1104`, affordance util), oracle (path-folded, id-blind), activity metadata (carries no settlement id). Named and verified — none parse id format.
4. **Fields from the type:** id inputs enumerated against `buildSettlementDoc`'s full key set (mirrored by rules `hasOnly` at `firestore.rules:900-913`): id, eventId, createdBy, payer/recipient ids+names, amountFils, currency, note, isDeleted, deletedAt, settledAt, groupSettleUpId. Each is either an id input (pair, currency, amount) or explicitly excluded with a per-field reason ("What the id is NOT" above).
5. **Exact data contracts:** helper signatures spelled out (Task 1 code); scopeKey grammar fixed (`event:<gid>:<eid>` / `group:<gid>` / `gsu:<gid>`); epoch source per callsite named (event: `eventSettlementsProvider`; group fallback: `groupSettlementsProvider`; decompose: `groupSettlementsProvider ∪ groupTaggedEventSettlementsProvider` — see "Per-callsite epoch basis").
6. **Arithmetic decomposition:** ids embed per-doc amounts only; the decompose conservation invariant (`Σ legs + residual == total`) is untouched and stays pinned by existing tests; leg/residual ids derive from `groupSettleUpId`, not from amounts, so id math cannot contradict money math.
7. **Orthogonal adversarial pass (axes B):** TIME — sequential legit re-settle gets epoch+1 → distinct id (worked example in "Why epoch…"). IDENTITY — claim/merge re-keys settlement party FIELDS via Admin SDK by existing doc id; deterministic ids are opaque to the engine; post-claim, devices derive future ids from re-keyed uids identically. SCOPE — event/group/gsu namespaces disjoint by construction. MONEY-FLOW — reversed-direction settle (B→A) derives a different id (directed pair), so a genuine opposite-direction payment is never swallowed by the guard.
