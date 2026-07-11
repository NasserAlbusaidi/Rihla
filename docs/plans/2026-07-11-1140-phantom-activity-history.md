# Phantom Activity History (#1140) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make every user-visible group-activity row atomic with the domain mutation it claims, so a denied/never-committed mutation can never persist phantom history (and, symmetrically, a committed mutation can never silently lose its row).

**Architecture:** Fold each activity `set()` into the **same Firestore `WriteBatch`** (or single write promoted to a 2-op batch) as its domain mutation. Firestore batch commits are all-or-nothing — online, and on offline replay (the SDK queues+replays the whole batch as one unit; a rules rejection of any op discards the whole commit). This is the exact atomicity the decomposed settle-up already relies on (#929). The activity doc **shape and rules are unchanged** (`validGroupActivityCreate` already allow-lists all four client types); this is a pure client-side write-path refactor plus one money-safety budget adjustment.

**Tech Stack:** Flutter, Riverpod, `cloud_firestore` `WriteBatch`, `fake_cloud_firestore` + `batchFactoryOverride` test seam, Firestore security rules (Java 21 emulator, unchanged here).

---

## Background — the bug

`GroupActivityService.logGroupEvent` is a fire-and-forget `unawaited(...).set()` (D-32/D-33) written **separately** from the mutation it describes. Five mutation-paired callsites are affected; the phantom occurs on the **offline-queued-then-denied** path (online-denied already skips logging via the `catch`):

| # | Callsite | Type | Mutation writer | Today's coupling |
|---|---|---|---|---|
| 1 | `event_danger_section.dart:503` | `event_deleted` | client `update` (soft-delete) | logs **before** the delete even runs |
| 2 | `create_event_screen.dart:194` | `event_created` | client `set` (staged+ack) | logs **after** ack, separate write |
| 3 | `settle_up_screen.dart:914` | `event_settlement` | client `set` (staged+ack) | logs after ack, separate write |
| 4 | `group_settle_up_screen.dart:1109` | `group_settlement` | client `set` (`addGroupSettlement`) | logs after ack, separate write |
| 5 | `group_settle_up_screen.dart:943` | `group_settlement` | client `WriteBatch` (`stageDecomposedSettleUp`, #929) | logs after ack, **outside** the batch |
| 6 | `join_group_screen.dart:201` | `member_joined` | **callable** `joinGroupByInviteCode` (Admin SDK) | logs after a **confirmed** commit — NOT phantom-capable |

Phantom scenario (all of 1–5): device offline → `awaitServerAck(skipWait:true)` returns `WriteAck.queued` **without** the server confirming → code proceeds and writes the activity row (which `FakeFirebaseFirestore`/real-online acks) → later, at replay, the mutation is denied (membership/participation changed, dedup-id collision, stale `participantIds` failing `validEventBase`) → the mutation never persists but the activity row is permanent. The inverse (mutation commits, fire-and-forget activity lost) is also live and is fixed for free by the same batching.

## Design decisions (verified against code, not memory)

### D1 — Client `WriteBatch`, not server triggers
The mutations are all **client-writable** (`set`/`update`), so one client batch per pair is the minimal fix. Server-side (trigger/outbox) activity was rejected: `actorName` comes from `settingsProvider.deviceName` (client-only) and `description` is a localized/formatted client string — a trigger cannot reproduce them without a large new server surface. member_joined (#6) is the only callable-owned mutation; it is documented as best-effort, not moved.

### D2 — No `firestore.rules` change
`validGroupActivityCreate` (rules L1138-1173) already allow-lists `event_created`, `event_deleted`, `event_settlement`, `group_settlement` and validates the activity doc **standalone**. Batch atomicity is a Firestore commit property, not a rules construct — each op still evaluates against its own match block. Verified: activity op cost = **1 document-access call** (both `isGroupMember` and `groupAllowsClientWrites` read only `groups/{gid}`; `validActivityMetadata` does zero gets).

**Semantic-inversion check (the one real risk):** folding activity into the batch means an *activity-op* denial could now block a money write. But the activity op's only authz conjuncts — `isGroupMember(gid)` + `groupAllowsClientWrites(gid)` — are a **strict subset** of what every domain leg already requires (event-settlement create gates on `isGroupMember` + `eventAllowsClientWrites`⊇`groupAllowsClientWrites`; group-settlement create gates on `isGroupMember` + `groupAllowsClientWrites`; event create/soft-delete gate on membership + event/group writability). So the activity op can **never be the sole cause** of a batch denial — if it would be denied, the domain leg is already denied. Folding therefore never blocks an otherwise-successful mutation. (Recorded here so the Gate/refuter can check it directly.)

### D3 — Shared boundary: one activity-doc builder, deterministic ids
Hoist a pure static `GroupActivityService.buildActivityDoc({...}) → Map<String,dynamic>` (single source of the activity shape; the fire-and-forget `logGroupEvent` also calls it). Each **domain service** owns its batch and stages the activity leg via this static builder from **its own `db`** (so a single injected fake in tests receives both writes — the two services do NOT share a `db` in tests).

Activity doc ids become **deterministic from the mutation identity** (satisfies the "no duplicate on retry/replay" acceptance box via the same free-idempotency floor as #1093 — `allow update/delete: if false` denies a colliding replay):
- event create → `evt_created_<eventId>`
- event delete → `evt_deleted_<eventId>`
- event settlement → `stl_<settlementId>` (settlementId already deterministic, #1093)
- group settlement (fallback) → `stl_<settlementId>`
- decomposed group settle-up → `gstl_<groupSettleUpId>`

`request.resource.data.id == activityId` (rule) is satisfied because we set both to the same derived id.

### D4 — Decomposed cap 9 → 8 (money-safety budget)
Adding one activity op to the decomposed batch changes its cost from `2N+1` to `2N+2`. At N=9 that is exactly 20/20 — zero margin, violating #929's deliberate "conservative, assumes zero cross-op caching, keep headroom" doctrine. Drop `kMaxDecomposeLegsAtomic` **9 → 8** (`2·8+2 = 18 ≤ 20`, restores a 2-call margin). Consequence: an exactly-9-event atomic settle-up now falls back to the single atomic group settlement (aggregate-correct; per-event ledgers still show the debt) — the same **sanctioned** #929 carve-out, boundary moved by one. Widening back to 9 needs emulator evidence (out of scope).

### D5 — member_joined stays; document it
No code change. Add a doc-comment at `join_group_screen.dart` / `logGroupEvent` recording that member_joined is a **best-effort informational log emitted only after a confirmed server-side callable commit** — the log is lexically unreachable unless `joinGroupByInviteCode` already returned success, so it cannot record a join that did not happen. Its only failure mode is a *lost* row (display-only feed, D-32 tolerance), never a phantom. This is the one documented best-effort pairing required by the acceptance list.

### D6 — Corrections untouched
Settlement corrections route through the `correctSettlement` callable and write **no** client activity row (#889). This plan only changes the forward-record paths (`_recordSettlement`, `_recordDecomposedSettlement`, event create/delete). The correction-suppression tests (`settle_up_screen_test.dart` #831/#283/#889, `group_settle_up_screen_test.dart` #283/#889) must still pass unchanged.

## Verification principles (run against code)

1. **Callsite classification (INBOUND/OUTBOUND/BOTH):** all 6 activity writes are OUTBOUND (they feed a persisted, user-visible history row). The activity **metadata** is INBOUND/display-only (never read by any oracle) — unchanged. The 5 batched mutations are OUTBOUND money/lifecycle writes; batching does not change their doc shape.
2. **Every concrete claim vs code:** callsite line numbers, `kMaxDecomposeLegsAtomic=9` (`group_settlement_service.dart:24`), `validGroupActivityCreate` allow-list (`firestore.rules:1161-1167`), `2N+1` budget (`group_settlement_service.dart:15-18`) — all re-grepped this session.
3. **One read-path per write-path:** who reads the batched activity row? `GroupActivityService.watchRecentActivity`/`fetchActivityPage` → home RECENTLY + full feed via `activity_display.dart`. Who reads the settlement docs? `recomputeNet`/oracle (unchanged — the activity leg is oracle-invisible, like `groupSettleUpId`). Who reads home balance? `ledgerRevision` bump preserved after the batched settlement ack.
4. **Fields from the type:** activity doc keys are exactly `[id, type, actorId, actorName, description, metadata, timestamp]` (rule `hasOnly`, L1141-1149) — `buildActivityDoc` emits exactly these, no more.
5. **Data contracts spelled out:** `buildActivityDoc({required String id, required String type, required String actorId, required String actorName, required String description, required Map<String,dynamic> metadata, required DateTime timestampUtc}) → Map<String,dynamic>`. Each service method gains named activity params `{required String activityType, required String activityActorId, required String activityActorName, required String activityDescription, required Map<String,dynamic> activityMetadata}` and derives the id internally.
6. **Arithmetic decomposition:** budget is additive across batch ops (no cross-op caching assumed) → `2N+1 + 1 = 2N+2`; N=8 → 18. Money amounts/serialization are untouched (`buildSettlementDoc`/`buildGroupSettlementDoc` reused byte-for-byte).
7. **Adversarial orthogonal axis (identity/membership):** the axis-B worked example — a payer who **leaves the group while a settle-up sits queued offline** — proves the fix: the queued batch's settlement legs AND the co-batched activity leg both fail `isGroupMember` at replay → the whole commit is discarded → **no** phantom `group_settlement` row (today the separate row survives). The activity leg cannot *independently* cause this (D2 subset argument), so no legitimate settle-up is newly blocked.

## Acceptance-box → task map

- Denied event create → no `event_created`: Task 3
- Denied event delete → no `event_deleted`: Task 2
- Denied event/group/decomposed settlement → no settlement activity: Tasks 4, 5, 6
- Success → exactly one matching row: every task's GREEN twin
- Offline replay commits both or neither: batching (Tasks 2–6)
- Retry/idempotency → no duplicate: deterministic ids (D3), asserted in Task 4/6 idempotency tests
- Corrections suppressed & pinned: Task 7 regression re-run (unchanged)
- Every callsite inventoried; best-effort documented: Task 8 (member_joined)
- Failure copy / queued feedback / nav intact: each task preserves snackbars + `context.go`

---

## Task 1: Shared activity-doc builder + batch stager

**Files:**
- Modify: `lib/features/groups/services/group_activity_service.dart`
- Test: `test/unit/group_activity_service_test.dart`

**Step 1 — Write failing test:** add a group verifying (a) `GroupActivityService.buildActivityDoc(...)` returns exactly the 7 keys with the passed values and ISO-8601 `timestamp`, and (b) `stageActivity(batch, ...)` calls `batch.set` once on `groups/{gid}/activity/{id}` with that map. Use a spy `WriteBatch` (mirror `_StubWriteBatch` from `group_settle_up_atomic_929_test.dart`).

**Step 2 — Run, expect FAIL** (`buildActivityDoc`/`stageActivity` undefined):
`flutter test test/unit/group_activity_service_test.dart`

**Step 3 — Implement:** hoist the doc map into a static builder; add a batch stager; make `logGroupEvent` delegate to the builder (behaviour unchanged for member_joined).
```dart
static Map<String, dynamic> buildActivityDoc({
  required String id,
  required String type,
  required String actorId,
  required String actorName,
  required String description,
  required Map<String, dynamic> metadata,
  required DateTime timestampUtc,
}) => {
  'id': id,
  'type': type,
  'actorId': actorId,
  'actorName': actorName,
  'description': description,
  'metadata': metadata,
  'timestamp': timestampUtc.toIso8601String(),
};

/// Stages a group-activity row onto [batch], atomic with the paired mutation
/// (#1140). The caller derives a deterministic [id] from the mutation identity
/// so a retry/replay collides and is denied by `allow update: if false`.
void stageActivity(
  WriteBatch batch, {
  required String groupId,
  required String id,
  required String type,
  required String actorId,
  required String actorName,
  required String description,
  required Map<String, dynamic> metadata,
  required DateTime timestampUtc,
}) {
  batch.set(
    _activityRef(groupId).doc(id),
    buildActivityDoc(
      id: id, type: type, actorId: actorId, actorName: actorName,
      description: description, metadata: metadata, timestampUtc: timestampUtc,
    ),
  );
}
```
Refactor `logGroupEvent`'s inline map to call `buildActivityDoc(...)` (random uuid + `DateTime.now().toUtc()` as today).

**Step 4 — Run, expect PASS.**

**Step 5 — Commit:** `test(activity): pin buildActivityDoc + stageActivity shared boundary (#1140)`

---

## Task 2: Event delete — atomic soft-delete + activity (simplest RED)

**Files:**
- Modify: `lib/features/events/services/event_service.dart` (`deleteEvent`)
- Modify: `lib/features/events/widgets/event_danger_section.dart:493-544`
- Test: `test/features/events/event_delete_phantom_1140_test.dart` (new)

**Step 1 — Write failing test (RED):** model the phantom directly (event delete logs BEFORE the mutation today). One `FakeFirebaseFirestore`; a real `GroupActivityService.withFirestore(fake)`; mock `EventService.deleteEvent` to return a pending-then-`permission-denied` `Completer` (offline queued → denied). Drive the delete confirm. **Assert `groups/{gid}/activity` is empty** after the denial.
Expected today: FAIL — a doc exists (logged before delete).

**Step 2 — Run, expect FAIL:** `flutter test test/features/events/event_delete_phantom_1140_test.dart`

**Step 3 — Implement:**
`EventService.deleteEvent` gains optional activity params; when present, one batch:
```dart
Future<void> deleteEvent({
  required String groupId,
  required String eventId,
  String? activityId,
  String? activityActorId,
  String? activityActorName,
  String? activityDescription,
  Map<String, dynamic>? activityMetadata,
}) async {
  final eventRef = db.collection('groups').doc(groupId)
      .collection('events').doc(eventId);
  final delta = {
    'isDeleted': true,
    'deletedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
  if (activityId == null) {                      // legacy path (tests/scripts)
    await eventRef.update(delta);
    return;
  }
  final batch = db.batch()
    ..update(eventRef, delta)
    ..set(
      db.collection('groups').doc(groupId).collection('activity').doc(activityId),
      GroupActivityService.buildActivityDoc(
        id: activityId, type: 'event_deleted',
        actorId: activityActorId!, actorName: activityActorName!,
        description: activityDescription!, metadata: activityMetadata!,
        timestampUtc: DateTime.now().toUtc(),
      ),
    );
  await batch.commit();
}
```
`event_danger_section._executeDelete`: delete the separate `logGroupEvent` block (L494-513); build the activity payload with safe fallbacks (`actorName` = deviceName or 'Someone'), pass `activityId: 'evt_deleted_${event.id}'` + fields into `deleteEvent`; keep the existing `awaitServerAck` race, connectivity note, `context.go('/group/$groupId')`, and error snackbar.

**Step 4 — Run, expect PASS** + add the GREEN twin (denied → empty; success → exactly one `event_deleted` row keyed `evt_deleted_<id>`).

**Step 5 — Commit:** `fix(events): event delete + activity in one atomic batch (#1140)`

---

## Task 3: Event create — atomic set + activity

**Files:**
- Modify: `lib/features/events/services/event_service.dart` (`stageEvent`, and `createEvent` passthrough)
- Modify: `lib/features/events/screens/create_event_screen.dart:151-216`
- Test: `test/features/events/event_create_phantom_1140_test.dart` (new)

**Step 1 — Failing test (RED):** mock `stageEvent`'s ack to a pending-then-denied `Completer` (offline), real activity service on the same fake, drive create; assert `groups/{gid}/activity` empty after denial. FAIL today (separate post-ack log).

**Step 2 — Run, expect FAIL.**

**Step 3 — Implement:** `stageEvent` gains the same optional activity params; when present it returns `(event, ack: batch.commit())` with `batch.set(eventRef, event.toFirestoreMap())` + `batch.set(activityRef, buildActivityDoc('event_created', id: 'evt_created_${eventId}', ...))`. Screen: delete the separate `logGroupEvent` block (L188-204); pass activity fields; keep the queued `eventCreatedWillSync` global-messenger snackbar and `context.go` to the event hub.

**Step 4 — Run, expect PASS** + GREEN twin (success → one `event_created` row).

**Step 5 — Commit:** `fix(events): event create + activity in one atomic batch (#1140)`

---

## Task 4: Event settlement — atomic settlement + activity (money)

**Files:**
- Modify: `lib/features/ledger/services/settlement_service.dart` (add `stageSettlementWithActivity`)
- Modify: `lib/features/ledger/screens/settle_up_screen.dart:842-937`
- Test: `test/features/ledger/settle_up_phantom_1140_test.dart` (new)

**Step 1 — Failing test (RED):** offline queued-then-denied primary settlement + real activity service on the same fake → assert `activity` empty after denial. Plus an **idempotency** case: two `recordOnce` from the identical `#1093` epoch snapshot → assert **one** settlement doc AND **one** `stl_<id>` activity row.

**Step 2 — Run, expect FAIL** (separate post-ack log lands a row).

**Step 3 — Implement:** add
```dart
({Settlement settlement, Future<void> ack}) stageSettlementWithActivity({
  ...existing addSettlement params...,
  required String activityActorId,
  required String activityActorName,
  required String activityDescription,
  required Map<String, dynamic> activityMetadata,
}) {
  final data = buildSettlementDoc(...);           // unchanged money shape
  final batch = db.batch()
    ..set(eventSubcollection(groupId, eventId, 'settlements').doc(id), data)
    ..set(
      db.collection('groups').doc(groupId).collection('activity').doc('stl_$id'),
      GroupActivityService.buildActivityDoc(id: 'stl_$id', type: 'event_settlement', ...),
    );
  return (settlement: Settlement.fromFirestore(data), ack: batch.commit());
}
```
Screen `_recordSettlement`: replace the `addSettlement` + separate `logGroupEvent` with the single staged call, race `.ack`, keep the `ledgerRevision.state++` bump (exactly once, after the ack) and the queued/acked snackbars. Settlement id stays the #1093 deterministic id.

**Step 4 — Run, expect PASS** + GREEN twin.

**Step 5 — Commit:** `fix(ledger): event settlement + activity in one atomic batch (#1140)`

---

## Task 5: Group settlement fallback — atomic add + activity (money)

**Files:**
- Modify: `lib/features/groups/services/group_settlement_service.dart` (`addGroupSettlement`)
- Modify: `lib/features/groups/screens/group_settle_up_screen.dart:1044-1120`
- Test: `test/features/groups/group_settle_up_phantom_1140_test.dart` (new)

**Step 1 — Failing test (RED):** offline queued-then-denied `addGroupSettlement` + real activity service on the same fake → assert `activity` empty. FAIL today.

**Step 2 — Run, expect FAIL.**

**Step 3 — Implement:** `addGroupSettlement` gains optional activity params and, when present, writes via a 2-op batch (settlement doc via `buildGroupSettlementDoc` + activity `stl_<id>`), returning the `Settlement` after `batch.commit()`. Screen `_recordSettlement`: drop the separate `logGroupEvent` (L1107-1120); pass activity fields; **no** `ledgerRevision` bump (group-only, live-watched).

**Step 4 — Run, expect PASS** + GREEN twin.

**Step 5 — Commit:** `fix(groups): group settlement fallback + activity in one atomic batch (#1140)`

---

## Task 6: Decomposed settle-up — activity in the #929 batch + cap 9→8 (money)

**Files:**
- Modify: `lib/features/groups/services/group_settlement_service.dart` (`stageDecomposedSettleUp`, `kMaxDecomposeLegsAtomic`)
- Modify: `lib/features/groups/screens/group_settle_up_screen.dart:900-960`
- Test: `test/features/groups/group_settle_up_atomic_929_test.dart` (update), `test/unit/decomposed_settleup_batch_test.dart` (update), `test/unit/group_settlement_service_test.dart` (update)

**Step 1 — Update/failing tests (RED):**
- In `group_settle_up_atomic_929_test.dart`: the **offline** test's expectations change — `setCount` `3 → 4` (activity now in the batch), the separate `logCalls` assertion is replaced by asserting a real `gstl_<groupSettleUpId>` doc is staged in the batch (the activity is no longer a `logGroupEvent` call). Add a **new** RED-shaped test: offline **rejecting** batch + real activity service on the same fake → assert `activity` empty after denial.
- Add a boundary test: 8-leg decompose stays on the batch path; 9-leg now routes to the single group write (cap moved).

**Step 2 — Run, expect FAIL** (setCount 3, or the old cap boundary).

**Step 3 — Implement:** in `stageDecomposedSettleUp`, add the activity params and, before `return`, `batch.set(_activityRef(groupId).doc('gstl_$groupSettleUpId'), GroupActivityService.buildActivityDoc(type:'group_settlement', id:'gstl_$groupSettleUpId', ..., timestampUtc: now))` using the batch's shared `now`. Change `const kMaxDecomposeLegsAtomic = 9;` → `8` and update its docstring math to `2·N+2 ≤ 20 → N ≤ 9; drop to 8 for a 2-call margin`. Screen `_recordDecomposedSettlement`: pass activity fields into `stageDecomposedSettleUp`; delete the separate `logGroupEvent` (L941-959); keep the single `ledgerRevision.state++` (gated on `eventLegs.isNotEmpty`) and the queued/acked snackbars; the >cap pre-gate now compares against 8.

**Step 4 — Run, expect PASS.** Re-run `group_settlement_service_test.dart` / `decomposed_settleup_batch_test.dart` and fix leg-count assertions (`N+1 → N+2` sets when residual, `N → N+1` otherwise... note activity is always +1).

**Step 5 — Commit:** `fix(groups): fold group_settlement activity into the #929 batch; cap 9→8 (#1140)`

---

## Task 7: Regression guard — corrections still suppress activity

**Files:**
- Test: `test/features/ledger/settle_up_screen_test.dart` (#831/#283/#889 block), `test/features/groups/group_settle_up_screen_test.dart` (#283/#889 block) — **run unchanged**.

**Step 1:** run both correction tests; expect PASS (corrections route through `correctSettlement`, untouched). If any needs a mechanical fixture tweak (e.g. a service now returns a batch ack), adjust the fixture only — never the suppression assertion.

**Step 2 — Commit** only if a fixture tweak was needed: `test(settle): keep correction-suppression pinned post-#1140`.

---

## Task 8: Document member_joined + update invariants

**Files:**
- Modify: `lib/features/groups/screens/join_group_screen.dart` (doc-comment only)
- Modify: `lib/features/groups/services/group_activity_service.dart` (class doc: fire-and-forget = member_joined only)
- Modify: `CLAUDE.md` (settle-up landmine: `kMaxDecomposeLegsAtomic` 9→8 rationale; activity-atomic-with-mutation invariant)
- Modify: `docs/CLOUD-FUNCTIONS.md` / `docs/SECURITY-RULES.md` if they assert activity write coupling

**Step 1:** add the member_joined best-effort rationale comment (D5). Update `CLAUDE.md`'s `kMaxDecomposeLegsAtomic=9` references to 8 with the `2N+2` budget reason and add a one-line invariant: "mutation-paired activity rows are written in the SAME batch as the mutation (#1140); only member_joined stays best-effort (logged after a confirmed callable)."

**Step 2 — Commit:** `docs(activity): record #1140 atomic-activity invariant + member_joined best-effort`

---

## Final gates
- `flutter analyze` clean (worktree).
- `flutter test` targeted files green, then the affected suites (`test/features/events`, `test/features/ledger`, `test/features/groups`, `test/unit`).
- Rules unchanged → no emulator run required, but re-run `functions/test/firestore-rules-publish-readiness.test.ts` activity block to confirm no drift.
- PR body: `Closes #1140`, RED-before/after evidence pasted, spec link, member_joined best-effort note.
