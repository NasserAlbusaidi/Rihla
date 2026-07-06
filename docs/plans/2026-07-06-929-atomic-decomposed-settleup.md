# #929 — Atomic decomposed group settle-up record (one WriteBatch)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Status:** DRAFT — pre-Gate.
**Issue:** #929 (#752/#753 successor).
**Gate class:** GATE (money write-path).

**Goal:** The N event-settlement writes + residual group-settlement write of a decomposed group settle-up commit (and offline-queue, and replay) as ONE atomic unit — a rules rejection of any leg persists nothing.

**Architecture:** Extract the two settlement doc-map builders into static, single-source methods on their owning services; add one orchestration method `GroupSettlementService.stageDecomposedSettleUp` that stages all N+1 docs into a single `WriteBatch` (the #874 founding-batch precedent, `lib/features/groups/providers/group_provider.dart:201`) and returns the staged models + the commit future; rewire `_recordDecomposedSettlement` to one stage + one `awaitServerAck`. Doc contents stay byte-identical; the oracle, rules, and correction path are untouched.

**Tech stack:** Dart/Flutter, `cloud_firestore` `WriteBatch`, mocktail (mechanism pin), FakeFirebaseFirestore, Firestore rules emulator (atomicity pin).

---

## Verified problem mechanics (principle 2, read 2026-07-06)

- `group_settle_up_screen.dart` `_recordDecomposedSettlement` :820-843 loops `eventOrder`, each leg `awaitServerAck(eventService.addSettlement(...), skipWait: skipWait)`; residual :845-864 via `addGroupSettlement`. Each `add*` is an independent single-doc `set()` (`settlement_service.dart:111-115`, `group_settlement_service.dart:98`).
- `skipWait = ref.read(connectivityProvider) != ConnectivityStatus.online` (:787-788): offline, `awaitServerAck` returns `queued` immediately → **all N+1 writes enqueue as independent mutations**. The SDK replays each independently at reconnect with rules evaluated at replay time; one rejected leg (membership/participation changed while offline) persists the others → a half-persisted logical settle-up. Settlements are append-only (no delete path); `correctLogicalSettleUp` (#889) reverses whole recorded settle-ups but never repairs a partial one.
- The :816-819 comment documents partial-persist as intentional-for-now — this PR retires it.
- Related (memory `flutterfire-host-call-reorder`, re-verified as the #874 rationale in `group_provider.dart:260-263`): separate Firestore host calls race the native mutation queue; ONE batch is one atomic mutation with no ordering to race.
- Firestore semantics being relied on (the emulator test pins them): a `WriteBatch` is a single Commit; rules evaluate per-op but the commit applies all-or-nothing, offline it is stored and replayed as one batch.

## The binding ceiling: the rules access-call budget (R1 adversary P1 — verified against Firebase docs + rules 2026-07-06)

Security rules give a batched write a **shared budget of 20 document access calls for the ENTIRE commit** (single-doc requests get 10 each; Firebase docs `rules-conditions` "Access call limits", worked example: "3 writes × 2 calls each = 6 of 20"). Caching relief is best-effort only ("some … may be cached") — never design against it. Per-leg cost from `security/firestore.rules`: an event-settlement create reads TWO distinct docs — the group (`isGroupMember` :152-156 + `groupAllowsClientWrites` :140-150) and the event (`eventAllowsClientWrites` :194-199 + `participants()` :663-665) — and the residual group-settlement create reads ONE (group). So one atomic batch costs `2·N + 1` calls: **N ≥ 10 would be `permission-denied` in toto** — and recorded OFFLINE, silently discarded in full at replay. NOT a 500-op question; the budget bites ~50× sooner.

**Design response — cap + existing fallback, NOT chunking:**
- `kMaxDecomposeLegsAtomic = 9` (2·9+1 = 19 ≤ 20), a const beside `stageDecomposedSettleUp` carrying this budget math in its comment.
- The screen's pre-gate gains one clause: `decomposition.perEvent.length > kMaxDecomposeLegsAtomic` → the EXISTING fallback (`_recordSettlement`, one atomic single-doc group settlement — same path, same UX as the departed-member fallback). Aggregate stays exactly correct (the oracle folds group settlements globally); the cost is per-event attribution for >9-event settle-ups — rare, documented, and strictly money-safe.
- Chunked multi-batch was REJECTED: separate batches replay independently offline, so chunks can commit/reject in arbitrary subsets — the events-first/residual-last consistency invariant breaks and the partial-persist seam this PR exists to kill reappears at chunk granularity.
- Net invariant, now STRONGER than the issue's acceptance: **no path — any N, online or offline — can persist a partial logical settle-up.** N ≤ 9 → one atomic batch; N > 9 → one atomic single doc.
- `stageDecomposedSettleUp` also throws `ArgumentError` if `eventLegs.length > kMaxDecomposeLegsAtomic` (defense in depth; the screen pre-gate is the routing decision).

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
  - ONE `final now = DateTime.now().toUtc()` shared by ALL N+1 legs (`settledAtUtc: now`) — stable `settledAt` across the logical settle-up and a tractable builder-level parity test (R1 rubric P3 + adversary P2). Consequence, accepted as cosmetic: the N+1 docs carry an identical `settledAt`, so `orderBy('settledAt', descending: true)` falls to Firestore's implicit doc-id tiebreak among them (today they differ by milliseconds — equally arbitrary as a display order).
  - The activity log (`logGroupEvent`, screen :876-894) stays a separate fire-and-forget write OUTSIDE the batch — pre-existing non-atomic display-only behavior, unchanged; at offline replay the batch can reject while the activity entry commits. This PR does NOT extend atomicity to the activity log (R1 rubric P3 — stated so it isn't mistaken for a new guarantee).

### 3. `lib/features/groups/screens/group_settle_up_screen.dart` `_recordDecomposedSettlement`
- Pre-gate (:764-782) gains the cap clause: fall back to `_recordSettlement` when `!bothLiveMembers || decomposition.perEvent.isEmpty || decomposition.perEvent.length > kMaxDecomposeLegsAtomic`. The review sheet may show a >9-event breakdown while the write is one group row — identical to the existing membership-fallback WYSIWYG posture, no new UX.
- Replace the :820-864 sequential walk with:
  - build `eventLegs` from the SAME `eventOrder` filter (`decomposition.perEvent[eventId]`, skip null) — WYSIWYG invariant intact;
  - one `stageDecomposedSettleUp(...)` + `final ack = await awaitServerAck(result.ack, skipWait: skipWait)`; `anyQueued = ack == WriteAck.queued`;
  - **one** `ledgerRevision.state++` after the ack/queued resolution, only when `eventLegs.isNotEmpty` (any single bump invalidates the once-provider; N sequential bumps were N redundant refetch triggers, and "bump per write so home stays fresh on a partial walk" is moot — there is no partial walk anymore). A pure-residual decomposition (`eventLegs` empty) can't reach this path (pre-gate falls back when `perEvent.isEmpty`), but the guard keeps the CLAUDE.md group-only-no-bump rule literal.
  - On throw (online rules rejection): existing catch — nothing persisted, no bump, no activity log, failure outcome. (Today the bump and legs 1..k-1 both survive a leg-k failure.)
- UNCHANGED (load-bearing, CLAUDE.md #752 contract): the live-membership pre-gate + `perEvent.isEmpty` fallback to `_recordSettlement` (single atomic group write, no bump); shared `groupSettleUpId`; activity-log ONCE after the walk; queued/success snackbar; correct-button hidden on tagged settlements; `decomposeGroupSettlement` itself (`Σ(perEvent)+residual == toSubunits(A)`, residual ≥ 0).
- Rewrite the :816-819 partial-persist comment to state the batch invariant.

### 4. Rules / server: **no change.** `validEventSettlementCreate` (isGroupMember) and `validGroupSettlementCreate` keep identical per-op LOGIC inside a batch (their `get()`s read pre-existing group/event docs, none in the batch — no `getAfter` needed, unlike #874's founding batch where the docs referenced each other). What is NOT identical to sequential writes is the shared 20-access-call BUDGET (§ceiling above) — defended by the client-side cap, not by any rules edit.

## Callsite classification (principle 1)

`stageDecomposedSettleUp` is OUTBOUND (the write path). Its doc maps are produced by the SAME builders the single-write paths use — classified once, at the builders. The `staged` return is INBOUND-shaped (local echo, same as `add*` returns) and is not consumed by the screen today (kept for tests). Display breakdown (INBOUND) continues to read the same `eventOrder` — WYSIWYG.

## Read-path per write-path (principle 3)

Per-event settlement docs → `watchSettlements` → event ledger + `getSettlements` → home once-path; residual group doc → `watchGroupSettlements` → group settle-up + home fold; aggregate doc via server `balanceAggregator` (reads by collection path — decomposition remains byte-identical at the aggregate). All unchanged because the doc shapes are unchanged; the ONLY delta is commit granularity.

## Arithmetic decomposition (principle 6)

Untouched: `decomposeGroupSettlement` still produces `perEvent` + `residual` with `Σ(perEvent)+residual == toSubunits(A)` exactly (pinned by existing `balance_calculations_test.dart` decompose cases). This PR moves the persistence boundary only. The batch stages exactly `perEvent.length + (residual > 0 ? 1 : 0)` docs; the mechanism test pins that count.

## Adversarial pass on an orthogonal axis (principle 7)

Fix axis = write atomicity. Orthogonal example 1 (time × connectivity): user records a decomposed settle-up OFFLINE, then the counterparty is REMOVED from an event before reconnect. Today: event legs for still-valid events commit at replay, the removed-event leg rejects → event ledgers show a partial settle-up that the aggregate never matched. Post-fix: the whole batch rejects at replay → nothing persists; balances stay pre-settle-up-consistent; user re-enters when online. Named trade-off (accepted): the failure mode changes from *silent partial persist* (money-wrong, unrepairable without manual offsetting rows) to *silent no persist* (re-enter). No notification channel for replay-time rejection exists today for ANY queued write; out of scope.

Orthogonal example 2 (scale × offline — the R1 adversary's find, resolved by the cap): a 12-event decompose recorded offline would, uncapped, exceed the 20-call budget at replay → the whole batch silently discarded despite a success-looking "queued" snackbar, where today's 12 sequential writes all succeed. With the cap, N=12 routes to the single-doc group-settlement fallback (atomic, within budget) BEFORE any staging — the budget can never be the rejection cause on the batch path.

## Test plan (RED first)

1. **RED evidence — partial-persist repro against CURRENT code** (in `test/features/groups/group_settle_up_decompose_test.dart` harness style): recording event service throws `FirebaseException(code: 'permission-denied')` on the SECOND leg; drive a 2-event decompose; assert **zero settlement docs persist anywhere** → FAILS today (leg-1 doc found). Paste output in the PR. This exact assertion becomes GREEN via the mechanism below.
2. **Service mechanism pin** (new `test/unit/decomposed_settleup_batch_test.dart`, mocktail): inject `batchFactoryOverride` returning a `MockWriteBatch` → `stageDecomposedSettleUp` with 2 legs + residual issues exactly 3 `batch.set` (captured refs: 2 event subcollection paths + 1 group settlements path; captured data byte-equal to `buildSettlementDoc`/`buildGroupSettlementDoc` output) and exactly ONE `commit()`; ack IS the commit future. Zero-residual → 2 sets. Empty `createdBy` → sync `ArgumentError`, zero interactions. **A revert to sequential `add*` turns this red — the standing regression pin.**
3. **Failure atomicity through the screen** (post-fix twin of test 1): real services on one FakeFirebaseFirestore, `batchFactoryOverride` whose `commit()` throws `FirebaseException` after the (mocked) sets → walk returns failure outcome, fake holds ZERO docs, NO activity log, NO ledger bump, error snackbar path.
4. **Offline #412**: `batchFactoryOverride` commit returns a never-completing `Completer.future`; connectivity offline → walk completes with queued snackbar, `noteQueuedWrite` called once, single ledger bump, 3 sets + 1 commit on the mock.
5. **Happy-path migration** (existing `group_settle_up_decompose_test.dart`): swap the recording services for real ones — **on ONE shared `FakeFirebaseFirestore` instance injected into BOTH services** (the current harness at :105/:157 mints one fake per service; kept two-fake, every event-leg assertion would read the wrong db, since the batch routes ALL legs through `GroupSettlementService.db` — R1 rubric P2). Every current assertion survives: N docs + residual with shared `groupSettleUpId`, eventOrder-slice WYSIWYG, fallback single group write on departed member / no attribution, correct-button hidden. Byte-shape parity is asserted at the BUILDER (R1 rubric P2 — `addSettlement` mints its own uuid/now, so write-vs-write comparison can't be literal): for one fixed `(id, settledAtUtc, params)` tuple, `buildSettlementDoc(...)` returns a map deep-equal to the doc `addSettlement` persists when instrumented with the same values, and same for `buildGroupSettlementDoc`/`addGroupSettlement`.
6. **Emulator pins** (new `functions/test/decomposed-settleup-batch.test.ts` — kebab-case matching the existing `firestore-rules-publish-readiness.test.ts`, whose helpers it reuses; there is no `*.rules.test.ts` convention in this repo): (a) an all-valid batch of 2 event settlements + 1 group settlement (client shapes verbatim) commits; (b) same batch with ONE leg's counterparty not an event participant → the ENTIRE commit rejects, zero docs exist afterward; (c) **cap-safety pin**: an all-valid batch of 9 event settlements (9 distinct events) + 1 group settlement — 19 access calls — commits. NO >cap rejection pin: whether N=10 rejects depends on best-effort rules caching, so it isn't a stable assertion; the cap is derived from the documented budget, and (c) pins its safe side. Run: `cd functions && npm run test:emulator -- decomposed-settleup-batch.test.ts` (runner forwards args).
7. **Cap routing** (unit, in the decompose screen suite): a decomposition with 10 per-event legs routes to the single group-settlement fallback — zero event-settlement docs, one group doc, no ledger bump (group-only write needs none per CLAUDE.md).

## Acceptance (issue boxes → tests)

- [ ] All N+1 legs commit or none do on the decomposed path (N ≤ 9) → tests 2, 3, 6b; N > 9 routes to the single atomic group write → test 7. Net: NO path can persist a partial logical settle-up.
- [ ] Offline: the batch queues and replays atomically → test 4 (queue) + 6 (single-commit semantics; replay atomicity is the SDK's contract on one Commit); the 20-call budget can never reject a capped batch → §ceiling + test 6c.
- [ ] `Σ(perEvent)+residual == toSubunits(A)` unchanged; oracle untouched → decomposition untouched (existing suite) + builder-level byte-shape assertion in test 5.
- [ ] RED-first regression test simulating a rejected leg → test 1 (RED) / tests 2+3 (standing pins).

## Non-goals

- No oracle/`recomputeNet`/rules/aggregate change; `groupSettleUpId` stays oracle-invisible.
- No chunked multi-batch mode for N > 9 (rejected — see §ceiling: independent chunk replays reintroduce the partial-persist seam offline).
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

### Task 5: Cap routing + emulator pins + full verify
Test 7 (cap routing) RED→GREEN with the pre-gate clause; tests 6a-c in `functions/test/decomposed-settleup-batch.test.ts`; `flutter analyze`; full `flutter test`; emulator file green. Final commit message body carries `Closes #929`. PR body: `Spec:` line to this file + RED output. `/automerge` classifies GATE (money) — expected.
