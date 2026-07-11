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

**Semantic-inversion — the activity op must NEVER independently deny the batch (the load-bearing safety property; Gate R1 P1).** Folding activity into the batch means *any* predicate of `validGroupActivityCreate` — not just its authz — could block a money/lifecycle write. `validGroupActivityCreate` has **seven** predicates beyond the authz pair. An authz-subset argument alone is **insufficient** (the earlier version of this section was wrong). Each predicate must be provably satisfiable at stage time:

| Predicate (rules L1141-1172) | How we guarantee it | Verified |
|---|---|---|
| `isGroupMember(gid)` + `groupAllowsClientWrites(gid)` | **Strict subset** of every domain leg's authz — event-create standard branch L561, event-settlement L980-981 (`eventAllowsClientWrites`⊇`groupAllowsClientWrites`), group-settlement L1240-1241 (identical), event soft-delete L609-610 (`requesterIsEventAdmin` L457-458 ⟹ `uid∈memberIds`). If the activity authz fails, the domain leg already fails. | ✓ vs rules |
| `type in [event_created,event_deleted,event_settlement,group_settlement,…]` | Hardcoded constant per callsite (allow-listed). | ✓ |
| `id == activityId` | We set both to the same derived id. | ✓ |
| `actorId == request.auth.uid` | **Force `actorId = auth.uid`** (see D7). Settlement paths already compute a guarded non-empty `currentUid`; event-delete's `?? ''` is fixed to fall back to the domain-only write if no uid. | D7 |
| `description is string` | Always a Dart `String`. | ✓ |
| `metadata is map` + `validActivityMetadata` | Each callsite builds a fixed-shape map ≤ 8 keys (≤ 16 cap) with code-typed values; verified each already passes today (`amountFils` int≥0, `currency` valid, `amount`/`eventName`/names strings). | ✓ vs L1122-1136 |
| `isValidDisplayName(actorName)` | **Clamp `actorName`** to a guaranteed-valid form before staging (see D7) — 1–32, no control chars, strip the `member_name_resolver.dart` `' (former member)'` suffix, fall back to a safe constant. | D7 |

With D7's clamp in place, no predicate of `validGroupActivityCreate` can independently veto — so the activity op never blocks an otherwise-successful mutation. **This clamp, not the authz subset alone, is the safety argument.**

### D7 — Activity payload sanitization (money-safety, closes Gate R1 P1)
Reachable pre-clamp denials that would convert a would-succeed money/lifecycle write into `permission-denied` once co-batched (today `logGroupEvent`'s `catchError` swallows them and the mutation still commits):
- **(a) actorId:** `event_danger_section.dart:497` sets `actorId = FirebaseConfig.currentUser?.uid ?? ''`; `'' != auth.uid` → deny.
- **(b) actorName:** a live member settling on behalf of a **departed event participant** (#752/#249) with an empty own `deviceName` falls back to `fromName`, which `member_name_resolver.dart:71` can render as `"Name (former member)"` — rejected by `isValidDisplayName` (rules L44); likewise a name pushed `>32` by the #196 disambiguator, or control chars.

Mitigation (single chokepoint): a pure static `GroupActivityService.sanitizeActorName(String raw) → String` — trim; strip control chars (`\x00-\x1f\x7f`); strip a trailing `MemberNameResolver.formerSuffix`; clamp to 32 UTF-16 code units; if the result is empty, return `'Someone'`. `buildActivityDoc` calls it on `actorName`, so **every** activity write (batched paths AND the surviving `logGroupEvent`/`member_joined`) is guaranteed rule-valid — this strictly *improves* `member_joined`, whose fire-and-forget write silently *failed* on a malformed name before. For **actorId**: the settlement/create paths already pass a guarded non-empty `auth.uid`; fix event-delete to compute `actorId` up front and, if it is empty, take the **domain-only** `deleteEvent` path (no activity leg) — preserving D-14 (a delete is never blocked by activity).

### D3 — Shared boundary: one activity-doc builder, deterministic ids, EXTEND-not-add
Hoist a pure static `GroupActivityService.buildActivityDoc({...}) → Map<String,dynamic>` (single source of the activity shape; the fire-and-forget `logGroupEvent` also calls it). Each **domain service** owns its batch and stages the activity leg via this static builder from **its own `db`** (so a single injected fake in tests receives both writes — the two services do NOT share a `db` in tests).

**The activity params are OPTIONAL on the EXISTING domain method — never a parallel `stage…WithActivity` method (Gate R2 P1).** `addSettlement`, `stageEvent`, `deleteEvent`, `addGroupSettlement`, and `stageDecomposedSettleUp` each *gain* optional named activity params and batch internally when they are present (null → legacy single-write, unchanged). Rationale: the affected screen keeps calling the **same** method, and the many test doubles that `extends`-override those methods (`_RecordingSettlementService`/`_FailingSettlementService`/`_DeniedSettlementService` `settle_up_screen_test.dart:2170/2220/2242`, the mocked `EventService`/`GroupSettlementService`) are forced by the analyzer to update their override signatures (adding optional named params invalidates a stale override) — a **compile error, not a silent bypass** of a would-be new method the double doesn't override. This is the single most important structural decision for keeping the test surface honest.

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
- Corrections suppressed & pinned: Task 8 regression re-run (unchanged)
- Existing activity-assertion tests migrated (no phantom re-introduction): Task 7
- Every callsite inventoried; best-effort documented: Task 9 (member_joined)
- Failure copy / queued feedback / nav intact: each task preserves snackbars + `context.go`

---

## Task 1: Shared activity-doc builder + batch stager

**Files:**
- Modify: `lib/features/groups/services/group_activity_service.dart`
- Test: `test/unit/group_activity_service_test.dart`

**Step 1 — Write failing test:** add a group verifying (a) `sanitizeActorName` clamps: `'Bob (former member)' → 'Bob'`, a 40-char name → 32, a control-char name → stripped, `'' → 'Someone'`; (b) `GroupActivityService.buildActivityDoc(...)` returns exactly the 7 keys, applies `sanitizeActorName` to `actorName`, and emits ISO-8601 `timestamp`; (c) `stageActivity(batch, ...)` calls `batch.set` once on `groups/{gid}/activity/{id}` with that map. Use a spy `WriteBatch` (mirror `_StubWriteBatch` from `group_settle_up_atomic_929_test.dart`).

**Step 2 — Run, expect FAIL** (`sanitizeActorName`/`buildActivityDoc`/`stageActivity` undefined):
`flutter test test/unit/group_activity_service_test.dart`

**Step 3 — Implement:** hoist the doc map into a static builder that sanitizes `actorName`; add the sanitizer + a batch stager; make `logGroupEvent` delegate to the builder (member_joined now also gets a guaranteed-valid name).
```dart
/// Coerces any actor label into a value that always passes the rules'
/// `isValidDisplayName` (#1140 D7) so the co-batched activity op can never
/// veto the paired money/lifecycle write on a name-shape check.
static String sanitizeActorName(String raw) {
  // Order matters (Gate R2 P3): strip control chars FIRST so a crafted
  // 'Bob (former member)\x01' can't hide the suffix from the endsWith check.
  var s = raw.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
  // Loop the suffix strip so a (pathological) doubled ' (former member)'
  // can't survive and hit the rules' `.* \(former member\)$` reject.
  while (s.endsWith(MemberNameResolver.formerSuffix)) {
    s = s.substring(0, s.length - MemberNameResolver.formerSuffix.length).trim();
  }
  if (s.length > 32) s = s.substring(0, 32).trim();
  // TOTALITY GUARD (Gate R2 P2): after every transform, assert the result
  // actually satisfies isValidDisplayName; if the 32-clamp re-exposed a
  // trailing suffix or anything else slipped through, floor to the constant.
  // This makes "every input maps to a rule-valid string" trivially true.
  if (s.isEmpty ||
      s.endsWith(MemberNameResolver.formerSuffix) ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(s) ||
      s.length > 32) {
    return 'Someone';
  }
  return s;
}
```
> `'Someone'` is a last-resort floor (unreachable — every `actorName` source is non-empty) kept non-localized to match the existing `'Unknown'`/`'Someone'` persisted defaults (`group_activity_log_model.dart:65`, `event_danger_section.dart:500`); the display layer localizes its own fallback separately (Gate R2 P3, cosmetic).
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
  'actorName': sanitizeActorName(actorName),
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
`event_danger_section._executeDelete`: delete the separate `logGroupEvent` block (L494-513); resolve `actorId` up front **inside a try/catch** (Gate R2 P2 — `FirebaseConfig.currentUser` THROWS `[core/no-app]` when Firebase isn't initialized, per CLAUDE.md, it does NOT return null; the existing code wraps its read at L496-513 for exactly this). On throw **or** empty uid → call the legacy domain-only `deleteEvent` (no activity params) so a delete is never blocked (D7/D-14). Otherwise pass `activityId: 'evt_deleted_${event.id}'` + `activityActorId: actorId` + `activityActorName` (deviceName or 'Someone', also clamped by `buildActivityDoc`) + `activityMetadata: {'eventId': event.id, 'eventName': event.name}`. Keep the existing `awaitServerAck` race, connectivity note, `context.go('/group/$groupId')`, and error snackbar.

> Note (Gate R1 P3): the activity `timestamp` now stamps at batch-stage time (a few ms before the ack) instead of post-ack. The feed orders by client ISO timestamp desc; the shift is negligible. The decomposed path shares the batch's single `now` (already the settlement `settledAt`).

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
- Modify: `lib/features/ledger/services/settlement_service.dart` (**extend** `addSettlement` — NOT a new method, D3)
- Modify: `lib/features/ledger/screens/settle_up_screen.dart:842-937`
- Test: `test/features/ledger/settle_up_phantom_1140_test.dart` (new); `test/features/ledger/settle_up_screen_test.dart` (migrate doubles, Task 7)

**Step 1 — Failing test (RED):** offline queued-then-denied primary settlement + real activity service on the same fake → assert `activity` empty after denial. Plus an **idempotency** case: two `recordOnce` from the identical `#1093` epoch snapshot → assert **one** settlement doc AND **one** `stl_<id>` activity row.

**Step 2 — Run, expect FAIL** (separate post-ack log lands a row).

**Step 3 — Implement:** `addSettlement` gains OPTIONAL activity params and batches internally when present (keeps its `Future<Settlement>` return + server-ack semantics, so the screen still races it via `awaitServerAck`):
```dart
Future<Settlement> addSettlement({
  ...existing params...,
  String? activityId,
  String? activityActorId,
  String? activityActorName,
  String? activityDescription,
  Map<String, dynamic>? activityMetadata,
}) async {
  final data = buildSettlementDoc(...);           // unchanged money shape
  final ref = eventSubcollection(groupId, eventId, 'settlements').doc(id);
  if (activityId == null) {                        // legacy path — unchanged
    await ref.set(data);
    return Settlement.fromFirestore(data);
  }
  final batch = db.batch()
    ..set(ref, data)
    ..set(
      db.collection('groups').doc(groupId).collection('activity').doc(activityId),
      GroupActivityService.buildActivityDoc(
        id: activityId, type: 'event_settlement',
        actorId: activityActorId!, actorName: activityActorName!,
        description: activityDescription!, metadata: activityMetadata!,
        timestampUtc: DateTime.now().toUtc()),
    );
  await batch.commit();
  return Settlement.fromFirestore(data);
}
```
Screen `_recordSettlement`: pass `activityId: 'stl_$id'` + the activity fields to `addSettlement`, drop the separate `logGroupEvent` (L908-937), keep the `ledgerRevision.state++` bump (exactly once, after the ack) and the queued/acked snackbars. Settlement id stays the #1093 deterministic id. Because the screen still calls `addSettlement`, the three `settle_up_screen_test.dart` doubles keep intercepting (after the analyzer forces their signatures to add the optional params — Task 7).

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
- First, **extend `_StubWriteBatch`** (`group_settle_up_atomic_929_test.dart:143-168`) to capture staged writes: `final staged = <(DocumentReference, Object?)>[];` and push `(document, data)` in `set()` (still counting `setCount`). Gate R1 P3: today `set()` is a pure no-op, so nothing lands in the fake — the extension lets a test assert the activity leg's ref/data.
- In the **offline** test: `setCount` `3 → 4` (activity now in the batch), and replace the `logCalls, hasLength(1)` assertion with `expect(queuedBatch.staged.where((s) => s.$1.id == 'gstl_$groupSettleUpId'), hasLength(1))` (the activity is no longer a `logGroupEvent` call). Add a **new** RED-shaped test: offline **rejecting** batch + real `GroupActivityService.withFirestore(fake)` on the same fake → assert `groups/{gid}/activity` empty after denial.
- Add a boundary test: 8-leg decompose stays on the batch path; 9-leg now routes to the single group write (cap moved).

**Step 2 — Run, expect FAIL** (setCount 3, missing `gstl_` staged, or the old cap boundary).

**Step 3 — Implement:** in `stageDecomposedSettleUp`, add the activity params and, before `return`, stage the activity leg onto the batch using **this service's own `db`** (the private `_activityRef` lives on `GroupActivityService`, not here): `batch.set(db.collection('groups').doc(groupId).collection('activity').doc('gstl_$groupSettleUpId'), GroupActivityService.buildActivityDoc(id: 'gstl_$groupSettleUpId', type: 'group_settlement', ..., timestampUtc: now))` — reusing the batch's shared `now`. Change `const kMaxDecomposeLegsAtomic = 9;` → `8` and update its docstring math to `2·N+2 ≤ 20 → N ≤ 9; drop to 8 for a 2-call margin`. Screen `_recordDecomposedSettlement`: pass activity fields into `stageDecomposedSettleUp`; delete the separate `logGroupEvent` (L941-959); keep the single `ledgerRevision.state++` (gated on `eventLegs.isNotEmpty`) and the queued/acked snackbars; the >cap pre-gate now compares against 8.

> The event-settlement and group-settlement fallback services (Tasks 4/5) build the activity ref the same longhand way from their own `db` — do NOT reference `GroupActivityService._activityRef` from another service.

**Step 4 — Run, expect PASS.** Re-run `group_settlement_service_test.dart` / `decomposed_settleup_batch_test.dart` and fix leg-count assertions (`N+1 → N+2` sets when residual, `N → N+1` otherwise... note activity is always +1).

**Step 5 — Commit:** `fix(groups): fold group_settlement activity into the #929 batch; cap 9→8 (#1140)`

---

## Task 7: Migrate existing activity- AND domain-service test doubles (Gate R1 P2 + R2 P1 — mandatory)

Two independent break classes after the fold. **The forbidden fix for either is re-adding a separate `logGroupEvent` to re-green — that silently reintroduces the phantom.**

**Class A — activity-assertion breaks (R1 P2):** the five screens stop calling `groupActivityServiceProvider.logGroupEvent` for the mutation-paired rows, so tests asserting `logCalls`/`verify(logGroupEvent)`/`verifyNever`/`verifyZeroInteractions` go red.

**Class B — domain-double breaks (R2 P1 — the subtle one):** the activity now rides *inside* the domain method (`addSettlement`/`deleteEvent`/`stageEvent`/`addGroupSettlement`/`stageDecomposedSettleUp`). Because those methods **gain optional named params** (D3), every test double that `extends`-overrides them (`_RecordingSettlementService`/`_FailingSettlementService`/`_DeniedSettlementService`, mocked `EventService`, recording/failing `GroupSettlementService`) gets an **analyzer `invalid_override`** until its signature is updated — a compile error that *forces* the migration (no silent bypass). Update each override's signature to include the new optional params; its existing behavior (record/throw/deny) then still intercepts the call. A **mocktail-mocked** domain service (e.g. `event_settings_screen_test.dart`) instead needs its `when(...)`/`verify(...)` extended with the new `any(named:)` args.

**Confirm the live surface before porting:** `grep -rn "logCalls\|logGroupEvent\|_RecordingGroupActivityService\|verifyNever\|verifyZeroInteractions\|addSettlement\|deleteEvent(\|stageEvent(\|addGroupSettlement" test/`.

**Files (enumerated — confirm line numbers at port time; counts are 2026-07-11 grep hits):**
- `test/features/ledger/settle_up_screen_test.dart` — **Class B**: `_RecordingSettlementService:2170`, `_FailingSettlementService:2220`, `_DeniedSettlementService:2242` each override `addSettlement` → add the optional activity params to each signature (behavior unchanged: record/throw/deny still fire on the batched call). Any offline-412 double/Completer that gates on `addSettlement` — re-point to the new signature. The `#831` activity-presence assertion (~L781-789, reads `fakeDb…/activity`) must run against a **real** `SettlementService.withFirestore(fake)` so the batched activity row lands and is readable.
- `test/features/events/event_settings_screen_test.dart:558-631` — **Class A+B**: mock `_MockEventService` + `_RecordingGroupActivityService`. (1) L586-588 `verify(deleteEvent(groupId,eventId))` → extend the `when(...)` stub (L564-569) and the `verify` with the 5 new `any(named:)`/expected args. (2) L590-596 `activityService.calls.single.type=='event_deleted'` → the activity is now a `deleteEvent` PARAM, not a `logGroupEvent` call: assert it via `verify(() => service.deleteEvent(..., activityId: 'evt_deleted_${event.id}', activityActorName: 'Test User', activityMetadata: {'eventId':…,'eventName':…}, activityActorId: any(named:'activityActorId')))`. (3) L599-631 `throwOnLog:true` "logging failure doesn't block delete" → **re-purpose** to the D7 fallback: force an empty/throwing `actorId` and assert `deleteEvent` is called **without** activity params and the screen still routes back — preserving the D-14 "delete never blocked by activity" coverage the old premise loses.
- `test/features/events/create_event_test.dart` (~10 hits: mock `stageEvent` + `verify(logGroupEvent)`/`verifyNever`) → **Class A+B**: extend the mocked `stageEvent` `when/verify` with the new activity args; port the `logGroupEvent` verifies to `verify` the activity params on `stageEvent` (success → passed; failure paths → the domain-only branch, no activity params).
- `test/features/groups/group_settle_up_screen_test.dart` (~37 hits incl. multi-currency `logCalls hasLength(2)`) → **Class A(+B if it uses GroupSettlementService doubles)**: port `logCalls` to activity-collection reads on a real service/fake; two-currency → two disjoint `gstl_`/`stl_` rows.
- `test/features/groups/group_settle_up_decompose_test.dart` (~12 hits incl. `logCalls` content `amount '7.75'` + metadata) → assert the staged `gstl_` activity doc's `metadata`/`description` (via the Task 6 `_StubWriteBatch.staged` capture or a real fake) instead of `logCalls`.
- `test/features/groups/group_settle_up_dedup_1093_test.dart` (~5) and `test/features/ledger/settle_up_dedup_1093_test.dart` (`_RecordingGroupActivityService`) → idempotency: two records from the identical epoch snapshot → exactly ONE `stl_`/`gstl_` activity row (the second batch collides on the deterministic settlement id, denied in toto).
- `test/features/events/event_settings_offline_412_test.dart` (~1 hit, stubs `GroupActivityService`; mocks `deleteEvent`) → **Class B**: extend the `deleteEvent` stub with the new args; the activity now rides the batch, so drop the separate-log stub expectation.
- `test/features/groups/group_settle_up_atomic_929_test.dart` — handled in Task 6; note the old `expect(logCalls, isEmpty)` (L295) is now vacuous — replace it with a real-service-on-fake "denied ⇒ no activity row" assertion (Gate R2 P3).

**Porting patterns:**
- **Activity presence/absence** → real `Service.withFirestore(fake)`, read `groups/{gid}/activity` back from that SAME `fake` (the D3 shape, already used at `settle_up_screen_test.dart:138-147`).
- **Domain-double behavior** (record/throw/deny/offline) → keep the `extends`-override; just widen its signature with the optional activity params (analyzer-forced). It won't write an activity row itself — that's fine; activity atomicity is proven by the new real-service RED/GREEN tests, not by these doubles.
- **`_StubWriteBatch`** (no-op `set`) → assert via the extended `staged` capture (Task 6) or `setCount`.

**Step 1:** `flutter analyze` — fix every `invalid_override` (Class B) first; then run the affected suites and port each red per above. Re-run to green.

**Step 2 — Commit:** `test(activity): migrate activity + domain-service doubles to batched-activity (#1140)`

---

## Task 8: Regression guard — corrections still suppress activity

**Files:**
- Test: `test/features/ledger/settle_up_screen_test.dart` (#831/#283/#889 correction block), `test/features/groups/group_settle_up_screen_test.dart` (#283/#889 block).

The **correction-suppression ASSERTIONS** stay semantically unchanged — corrections route through the `correctSettlement` callable (`_recordSettlement`/`_recordDecomposedSettlement` are NOT on that path; the line-760 comment is stale wording only), so a correction still writes NO activity row. Note: these files' test *doubles* (the SettlementService subclasses / mocks) DO get signature updates in Task 7 — "unchanged" refers to the suppression assertions and their intent, not the whole file compiling untouched.

**Step 1:** after Task 7's double migration, run both correction blocks; expect the suppression assertions still PASS (a corrected settlement produces zero `activity` rows). Never weaken a suppression assertion to re-green — if one fails, the fold wrongly reached the correction path (a real bug).

**Step 2 — Commit** folded into Task 7 (same files) unless a correction-specific fixture tweak stands alone: `test(settle): keep correction-suppression pinned post-#1140`.

---

## Task 9: Document member_joined + update invariants

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
