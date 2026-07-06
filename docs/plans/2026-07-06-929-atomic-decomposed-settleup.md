# #929 — Atomic decomposed group settle-up record (one WriteBatch)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Status:** DRAFT — pre-Gate.
**Issue:** #929 (#752/#753 successor).
**Gate class:** GATE (money write-path).

**Goal:** The N event-settlement writes + residual group-settlement write of a decomposed group settle-up commit (and offline-queue, and replay) as ONE atomic unit — a rules rejection of any leg persists nothing.

**Architecture:** Extract the two settlement doc-map builders into static, single-source methods on their owning services; add one orchestration method `GroupSettlementService.stageDecomposedSettleUp` that stages all N+1 docs into a single `WriteBatch` (the #874 founding-batch precedent, `group_provider.dart:201`) and returns the staged models + the commit future; rewire `_recordDecomposedSettlement` to one stage + one `awaitServerAck`. Doc contents stay byte-identical; the oracle, rules, and correction path are untouched.

**Tech stack:** Dart/Flutter, `cloud_firestore` `WriteBatch`, mocktail (mechanism pin), FakeFirebaseFirestore, Firestore rules emulator (atomicity pin).

---

## Verified problem mechanics (principle 2, read 2026-07-06)

- `group_settle_up_screen.dart` `_recordDecomposedSettlement` :820-843 loops `eventOrder`, each leg `awaitServerAck(eventService.addSettlement(...), skipWait: skipWait)`; residual :845-864 via `addGroupSettlement`. Each `add*` is an independent single-doc `set()` (`settlement_service.dart:111-115`, `group_settlement_service.dart:98`).
- `skipWait = ref.read(connectivityProvider) != ConnectivityStatus.online` (:787-788): offline, `awaitServerAck` returns `queued` immediately → **all N+1 writes enqueue as independent mutations**. The SDK replays each independently at reconnect with rules evaluated at replay time; one rejected leg (membership/participation changed while offline) persists the others → a half-persisted logical settle-up. Settlements are append-only (no delete path); `correctLogicalSettleUp` (#889) reverses whole recorded settle-ups but never repairs a partial one.
- The :816-819 comment documents partial-persist as intentional-for-now — this PR retires it.
- Related (memory `flutterfire-host-call-reorder`, re-verified as the #874 rationale in `group_provider.dart:260-263`): separate Firestore host calls race the native mutation queue; ONE batch is one atomic mutation with no ordering to race.
- Firestore semantics being relied on (the emulator test pins them): a `WriteBatch` is a single Commit; rules evaluate per-op but the commit applies all-or-nothing, offline it is stored and replayed as one batch. 500-op ceiling — N = events with a slice for one debtor/creditor pair; two orders of magnitude of headroom, assert-free, noted only.

## Change inventory

### 1. `lib/features/ledger/services/settlement_service.dart`
- Extract the `data` map literal of `addSettlement` (:89-109) into `static Map<String, dynamic> buildSettlementDoc({required String id, required String eventId, …all current params…, required DateTime settledAtUtc})` — the ONE source of the event-settlement doc shape. `addSettlement` calls it (behavior byte-identical, incl. the `groupSettleUpId`-omitted-when-null rule).

### 2. `lib/features/groups/services/group_settlement_service.dart`
- Same extraction: `static Map<String, dynamic> buildGroupSettlementDoc(...)` from :77-96 (keeps the `eventId: groupId` sentinel + `scope: 'group'`).
- New method:
```dart
({Future<void> ack, List<Settlement> staged}) stageDecomposedSettleUp({
  required String groupId,
  required List<({String eventId, Decimal amount})> eventLegs, // caller-ordered = eventOrder
  required Decimal residual,                                    // >= 0; group doc staged only when > 0
  required String payerParticipantId,
  required String recipientParticipantId,
  required String currency,
  required String createdBy,
  required String groupSettleUpId,
  String? payerName,
  String? recipientName,
  String? note,
})
```
  - Throws `ArgumentError` synchronously on empty `createdBy` (parity with both `add*`).
  - `final batch = batchFactory();` where `@visibleForTesting WriteBatch Function()? batchFactoryOverride` defaults to `db.batch` — refs and batch MUST come from the same `db` (this service's), which also holds in tests (one fake injected). Event refs via the inherited `eventSubcollection(groupId, eventId, 'settlements')` (`FirestoreRepository` base — no new repository).
  - Per leg: `id = Uuid().v4()`, `data = SettlementService.buildSettlementDoc(...)`, `batch.set(ref.doc(id), data)`, collect `Settlement.fromFirestore(data)`. Residual > 0: same via `buildGroupSettlementDoc` + `_settlementsRef`. Returns `(ack: batch.commit(), staged: [...])`. NO awaiting inside — the caller races the ack (#412).

### 3. `lib/features/groups/screens/group_settle_up_screen.dart` `_recordDecomposedSettlement`
- Replace the :820-864 sequential walk with:
  - build `eventLegs` from the SAME `eventOrder` filter (`decomposition.perEvent[eventId]`, skip null) — WYSIWYG invariant intact;
  - one `stageDecomposedSettleUp(...)` + `final ack = await awaitServerAck(result.ack, skipWait: skipWait)`; `anyQueued = ack == WriteAck.queued`;
  - **one** `ledgerRevision.state++` after the ack/queued resolution, only when `eventLegs.isNotEmpty` (any single bump invalidates the once-provider; N sequential bumps were N redundant refetch triggers, and "bump per write so home stays fresh on a partial walk" is moot — there is no partial walk anymore). A pure-residual decomposition (`eventLegs` empty) can't reach this path (pre-gate falls back when `perEvent.isEmpty`), but the guard keeps the CLAUDE.md group-only-no-bump rule literal.
  - On throw (online rules rejection): existing catch — nothing persisted, no bump, no activity log, failure outcome. (Today the bump and legs 1..k-1 both survive a leg-k failure.)
- UNCHANGED (load-bearing, CLAUDE.md #752 contract): the live-membership pre-gate + `perEvent.isEmpty` fallback to `_recordSettlement` (single atomic group write, no bump); shared `groupSettleUpId`; activity-log ONCE after the walk; queued/success snackbar; correct-button hidden on tagged settlements; `decomposeGroupSettlement` itself (`Σ(perEvent)+residual == toSubunits(A)`, residual ≥ 0).
- Rewrite the :816-819 partial-persist comment to state the batch invariant.

### 4. Rules / server: **no change.** `validEventSettlementCreate` (isGroupMember) and `validGroupSettlementCreate` evaluate per-op inside a batch exactly as for single writes (their `get()`s read pre-existing group/event docs, none of which are in the batch — no `getAfter` needed, unlike #874's founding batch where the docs referenced each other).

## Callsite classification (principle 1)

`stageDecomposedSettleUp` is OUTBOUND (the write path). Its doc maps are produced by the SAME builders the single-write paths use — classified once, at the builders. The `staged` return is INBOUND-shaped (local echo, same as `add*` returns) and is not consumed by the screen today (kept for tests). Display breakdown (INBOUND) continues to read the same `eventOrder` — WYSIWYG.

## Read-path per write-path (principle 3)

Per-event settlement docs → `watchSettlements` → event ledger + `getSettlements` → home once-path; residual group doc → `watchGroupSettlements` → group settle-up + home fold; aggregate doc via server `balanceAggregator` (reads by collection path — decomposition remains byte-identical at the aggregate). All unchanged because the doc shapes are unchanged; the ONLY delta is commit granularity.

## Arithmetic decomposition (principle 6)

Untouched: `decomposeGroupSettlement` still produces `perEvent` + `residual` with `Σ(perEvent)+residual == toSubunits(A)` exactly (pinned by existing `balance_calculations_test.dart` decompose cases). This PR moves the persistence boundary only. The batch stages exactly `perEvent.length + (residual > 0 ? 1 : 0)` docs; the mechanism test pins that count.

## Adversarial pass on an orthogonal axis (principle 7)

Fix axis = write atomicity. Orthogonal example (time × connectivity): user records a decomposed settle-up OFFLINE, then the counterparty is REMOVED from an event before reconnect. Today: event legs for still-valid events commit at replay, the removed-event leg rejects → event ledgers show a partial settle-up that the aggregate never matched. Post-fix: the whole batch rejects at replay → nothing persists; balances stay pre-settle-up-consistent; user re-enters when online. Named trade-off (accepted): the failure mode changes from *silent partial persist* (money-wrong, unrepairable without manual offsetting rows) to *silent no persist* (re-enter). No notification channel for replay-time rejection exists today for ANY queued write; out of scope.

## Test plan (RED first)

1. **RED evidence — partial-persist repro against CURRENT code** (in `test/features/groups/group_settle_up_decompose_test.dart` harness style): recording event service throws `FirebaseException(code: 'permission-denied')` on the SECOND leg; drive a 2-event decompose; assert **zero settlement docs persist anywhere** → FAILS today (leg-1 doc found). Paste output in the PR. This exact assertion becomes GREEN via the mechanism below.
2. **Service mechanism pin** (new `test/unit/decomposed_settleup_batch_test.dart`, mocktail): inject `batchFactoryOverride` returning a `MockWriteBatch` → `stageDecomposedSettleUp` with 2 legs + residual issues exactly 3 `batch.set` (captured refs: 2 event subcollection paths + 1 group settlements path; captured data byte-equal to `buildSettlementDoc`/`buildGroupSettlementDoc` output) and exactly ONE `commit()`; ack IS the commit future. Zero-residual → 2 sets. Empty `createdBy` → sync `ArgumentError`, zero interactions. **A revert to sequential `add*` turns this red — the standing regression pin.**
3. **Failure atomicity through the screen** (post-fix twin of test 1): real services on one FakeFirebaseFirestore, `batchFactoryOverride` whose `commit()` throws `FirebaseException` after the (mocked) sets → walk returns failure outcome, fake holds ZERO docs, NO activity log, NO ledger bump, error snackbar path.
4. **Offline #412**: `batchFactoryOverride` commit returns a never-completing `Completer.future`; connectivity offline → walk completes with queued snackbar, `noteQueuedWrite` called once, single ledger bump, 3 sets + 1 commit on the mock.
5. **Happy-path migration** (existing `group_settle_up_decompose_test.dart`): swap the recording services for real ones on a fake (or record the new method) — every current assertion survives: N docs + residual with shared `groupSettleUpId`, eventOrder-slice WYSIWYG, fallback single group write on departed member / no attribution, correct-button hidden. Byte-shape assertion: doc written by `addSettlement` equals doc staged by the batch for identical inputs.
6. **Emulator atomicity pin** (new `functions/test/decomposedSettleUpBatch.rules.test.ts`, reusing the rules-test harness): (a) an all-valid batch of 2 event settlements + 1 group settlement (client shapes verbatim) commits; (b) same batch with ONE leg's counterparty not an event participant → the ENTIRE commit rejects, zero docs exist afterward. Run: `cd functions && npm run test:emulator -- decomposedSettleUpBatch.rules.test.ts` (runner forwards args). Implementer: mirror an existing rules-test file's setup helpers; verify harness naming before writing.

## Acceptance (issue boxes → tests)

- [ ] All N+1 legs commit or none do → tests 2, 3, 6b.
- [ ] Offline: batch queues and replays atomically → test 4 (queue) + 6 (single-commit semantics; replay atomicity is the SDK's contract on one Commit, pinned at the emulator as one commit).
- [ ] `Σ(perEvent)+residual == toSubunits(A)` unchanged; oracle untouched → decomposition untouched (existing suite) + byte-shape assertion in test 5.
- [ ] RED-first regression test simulating a rejected leg → test 1 (RED) / tests 2+3 (standing pins).

## Non-goals

- No oracle/`recomputeNet`/rules/aggregate change; `groupSettleUpId` stays oracle-invisible.
- No change to the correction path (`correctLogicalSettleUp`), the fallback single group write, `settle_up_screen.dart` (event-level), or the pre-settlement review.
- No repair path for PRE-EXISTING half-persisted settle-ups (manual offsetting rows remain the remedy).
- No replay-rejection user notification (doesn't exist for any queued write today).

## Implementation tasks (bite-sized)

### Task 1: RED repro
Write test 1 against current code → run → paste RED. Commit test skipped/marked or keep on branch pre-fix per RED-evidence convention (`test: RED partial-persist repro (Refs #929)`).

### Task 2: Builders
Extract `buildSettlementDoc` / `buildGroupSettlementDoc`; `add*` delegate; existing service tests green (byte-shape assertion added). Commit `refactor(settlements): extract single-source doc builders (Refs #929)`.

### Task 3: `stageDecomposedSettleUp` + mechanism pin
Test 2 RED (method missing) → implement → GREEN. Commit `feat(groups): atomic WriteBatch staging for decomposed settle-up (Refs #929)`.

### Task 4: Screen rewire
Tests 3+4 RED → rewire `_recordDecomposedSettlement` → GREEN; migrate test 5 harness; test 1's assertion now GREEN via new injection point. Commit `fix(groups): decomposed settle-up records atomically — no partial persist (Refs #929)`.

### Task 5: Emulator pin + full verify
Test 6; `flutter analyze`; full `flutter test`; emulator file green. Final commit message body carries `Closes #929`. PR body: `Spec:` line to this file + RED output. `/automerge` classifies GATE (money) — expected.
