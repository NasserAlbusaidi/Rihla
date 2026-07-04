# Offline group creation: one atomic batch + `getAfter` create-rules (Option A)

**Issue:** #874
**Category:** Gate ×2 — `security/firestore.rules` + a data-shape write-path. Requires a backend deploy.
**Date:** 2026-07-04
**Files touched:** `lib/features/groups/providers/group_provider.dart`, `security/firestore.rules`,
`functions/test/firestore-rules-publish-readiness.test.ts`, `test/unit/group_service_test.dart`

**Supersedes** the original eager-issue spec, which the codex spec-gate **refuted (P1)**:
FlutterFire's Android plugin offloads `batch.commit()` and `docRef.set()` onto a shared
`cachedThreadPool` (plain 3-arg `BasicMessageChannel`, **no serial `TaskQueue`** — verified
against pinned `cloud_firestore 6.2.0` source), so two eagerly-issued host calls race into the
native mutation queue. Program order ≠ enqueue order ⇒ member/event could replay before the
group commits ⇒ `isGroupMember` fails ⇒ writes dropped ⇒ the empty shell returns
nondeterministically. See memory `flutterfire-host-call-reorder`.

---

## Problem (unchanged, verified against code)

`GroupService.stageGroup` (`group_provider.dart:251-275`) chains the creator-member `.set()`
and the #245 seeded-event `.set()` on `batch.commit().then().then()`. `commit()`'s future
resolves only on **server ack**; offline it never resolves, so the two `.then` callbacks never
fire → member + event are never issued to the SDK → **empty shell offline** + **permanent loss
on process-kill** (group+inviteCode batch replays; member+event were never enqueued).

## Why not the obvious fixes (rejected alternatives — do not re-propose)

- **Eager-issue 3 separate writes + `Future.wait`.** REFUTED by codex (host-call reorder race,
  above). This is the whole reason for Option A.
- **Chain member/event on a local `hasPendingWrites` snapshot instead of the ack.** Avoids the
  rules change but is fragile, hang-prone, and as hard to test as the race. Rejected.
- **A `createGroup` Cloud Function.** Callables don't run offline; offline-create is required
  (#520). Rejected.
- **Globally switch `groupMembers()` / `isGroupMember` to `getAfter`.** REJECTED: `validEventBase`
  (which calls `groupMembers()`) runs on the hot event-**update** OR-chain that CLAUDE.md pins
  near the 1000-expression ceiling, and `requesterIsGroupCreator()` already does `get(group)`
  there — adding a `getAfter(group)` on that path risks tipping the ceiling. After-state is
  confined to the **create** path only.

## Fix — Option A

### 1. Provider (`group_provider.dart`): all four writes in ONE atomic `WriteBatch`

```dart
final batch = db.batch();
batch.set(db.collection('groups').doc(groupId), {... group ...});
batch.set(db.collection('inviteCodes').doc(inviteCode), {... invite ...});
batch.set(db.collection('groups').doc(groupId).collection('members').doc(memberId), {... member ...});
batch.set(db.collection('groups').doc(groupId).collection('events').doc(seededEvent.id),
          seededEvent.toFirestoreMap());
final ack = batch.commit();          // ONE host call, ONE atomic mutation
```

One batch = one FlutterFire host call = one atomic server commit = **no ordering race**. Offline
the batch is applied to the local cache and queued as a **single unit**; it replays atomically
and survives a process-kill. Also closes a latent non-atomicity that exists **today** (a partial
failure between the group batch and the member/event `.set()` leaves a memberless group).

`ack` keeps its exact external shape (`Future<void>`, server-ack, pending offline) — only its
construction changes (a single `batch.commit()` instead of a `.then` chain). All callers
(`createGroup` awaits it; `create_group_screen.dart` races it via `awaitServerAck`; the shadow
fan-out fires on `WriteAck.acked`) are unaffected.

### 2. Rules (`security/firestore.rules`): let the founding batch pass via after-state

The blocker: `validMemberCreate` and `validEventCreate` gate on `isGroupMember` +
`groupAllowsClientWrites`, both of which read **before-batch** state (`get`/`exists`), where the
group does not exist yet in a founding batch → they short-circuit `false` (safe: `exists()` is
`false`, `&&` short-circuits before any `.data` deref, so no rule error — just denial).

Firestore rules already carry the after-state helpers (`groupAfterData` = `getAfter().data`
L130, `existsAfter` L921) — this reuses that established pattern.

**New helper** (load-bearing `!exists` guard explained inline):
```
// #874: a member/event doc created in the SAME atomic batch as its brand-new group.
// isGroupMember/groupAllowsClientWrites read BEFORE-batch state (group absent → false),
// so validate the founding batch against after-state. The !exists guard restricts this
// branch to genuinely-new groups: for an EXISTING group the standard path (with
// groupAllowsClientWrites' soft-delete/deleting checks) is the only door — otherwise a
// creator could bypass those guards on their own deleting group. A founding group is
// clean by construction (validGroupCreate forces isDeleted:false + forbids the *InProgress
// flags), so no groupAllowsClientWrites re-check is needed here.
function groupFoundingBatchByCreator(groupId) {
  return signedIn()
    && !exists(groupPath(groupId))
    && existsAfter(groupPath(groupId))
    && request.auth.uid in groupAfterData(groupId).memberIds
    && groupAfterData(groupId).createdBy == request.auth.uid;
}
```

**`validMemberCreate`** — wrap the membership precondition; swap the CREATOR-role createdBy read
to after-state (safe: for a standalone create `getAfter(group)==get(group)`; this fn is
create-only, not on any hot update path):
```
function validMemberCreate() {
  return (
      (isGroupMember(groupId) && groupAllowsClientWrites(groupId))
      || groupFoundingBatchByCreator(groupId)
    )
    && request.resource.data.keys().hasOnly(['id','userId','displayName','role','joinedAt','isShadow'])
    && request.resource.data.id == memberId
    && request.resource.data.id == request.auth.uid
    && request.resource.data.userId == request.auth.uid
    && isValidDisplayName(request.resource.data.displayName)
    && request.resource.data.role in ['CREATOR', 'MEMBER']
    && (request.resource.data.role == 'MEMBER'
      || groupAfterData(groupId).createdBy == request.auth.uid)   // was groupData(...).createdBy
    && request.resource.data.joinedAt is timestamp
    && request.resource.data.isShadow is bool;
}
```

**`validEventCreate`** — the founding-batch event cannot reuse `validEventBase` as-is, because
`validEventBase` couples field-shape checks with `participantIds.hasOnly(groupMembers())`, and
`groupMembers()` = `groupData(groupId).memberIds` = **`get(group)`**, which is null in the
founding batch → a rule ERROR (terminal, not recoverable by the `||`). So the field checks must
be reachable without the `get`-based membership coupling.

**[Gate P1 — codex rounds 2+3] Approach: DUPLICATION, `validEventBase` LEFT BYTE-IDENTICAL — no
extraction, no ceiling tripwire.** Extracting `validEventFields` and having `validEventBase`
delegate to it would add a function-call frame on the hot light/admin event-**update** OR-chain
(validEventBase runs there, and on a participant-**removal** it runs TWICE: `validEventLightUpdate`
reaches `validEventUpdateCommon`→`validEventBase`, fails its additive-only check, then
`validEventAdminUpdate` reaches `validEventUpdateCommon`→`validEventBase` again). CLAUDE.md pins
that path near the 1000-expression ceiling, and the #723 close tests can't tripwire it
(`validEventCloseToggle` deliberately bypasses `validEventBase`, `firestore.rules:555`).

Rather than gate the extraction on a bespoke tripwire, **avoid the risk entirely**: leave
`validEventBase` (and the entire event-update OR-chain) 100% untouched, and give `validEventCreate`
a **create-only twin** of the field checks. The update path is then *provably* unaffected (zero
rule bytes changed on it), and NO new ceiling tripwire is needed — the existing light/admin update
tests (`firestore-rules-publish-readiness.test.ts:1131-1249`) already cover it and stay green.
Cost: ~17 duplicated field-check lines, guarded by a `// MUST MIRROR validEventBase (L419-437)`
comment. DRY is worth less than a provably-unchanged hot path here.

Note [Gate P3 — Opus round 4, corrected]: the alternative shared-base pattern in this file,
`validExpenseBase(data, enforceParticipantKeys)` (`firestore.rules:662`), is a **parameterized
shared base** — i.e. the extraction/delegation approach we are REJECTING here, not duplication.
The justification for duplicating (rather than parameterizing `validEventBase`) is specific to the
event path: `validEventBase` is double-evaluated per admin participant-removal (light fails the
additive check → admin re-runs it), so it sits on the 1000-expression ceiling; the expense path
has no such double-eval. Duplication is the choice that touches ZERO bytes of that hot path.

```
// #874: create-only twin of validEventBase's field-shape checks, WITHOUT the
// participantIds.hasOnly(groupMembers()) membership coupling (which does get(group) —
// null in a founding batch → terminal rule error). MUST MIRROR validEventBase's field
// list (firestore.rules L419-437); a new event field goes in BOTH. validEventBase and
// the whole event-UPDATE OR-chain are intentionally left byte-identical.
function validEventCreateFields(data) {
  return isValidDisplayName(data.name)
    && data.type in ['trip','camping','travel','night_day_out','custom']
    && data.groupId == groupId
    && data.createdBy is string
    && data.participantIds is list
    && data.participantIds.size() > 0
    && data.participantNames is map
    && displayNameMapValuesAreValid(data.participantNames)
    && validModules(data.modules)
    && (data.startDate == null || data.startDate is timestamp)
    && (data.endDate == null || data.endDate is timestamp)
    && data.isDeleted is bool
    && (data.deletedAt == null || data.deletedAt is timestamp)
    && (data.createdAt is string || data.createdAt is timestamp)
    && (data.serverCreatedAt == null || data.serverCreatedAt is timestamp)
    && (data.updatedAt == null || data.updatedAt is timestamp)
    && nullableString(data.description);
}

// validEventBase — UNCHANGED (not shown). Still: <inline field checks> &&
// participantIds.hasOnly(groupMembers()). Used only by the update path.

function validEventCreate() {
  return request.resource.data.keys().hasOnly([... 18 keys, unchanged ...])
    && request.resource.data.createdBy == request.auth.uid
    && request.auth.uid in request.resource.data.participantIds
    && request.resource.data.isDeleted == false
    && request.resource.data.deletedAt == null
    && (!('isClosed' in request.resource.data) || request.resource.data.isClosed == false)
    && (!('closedAt' in request.resource.data) || request.resource.data.closedAt == null)
    && (!('closedBy' in request.resource.data) || request.resource.data.closedBy == null)
    && validEventCreateFields(request.resource.data)
    && (
      // Standard: existing group, requester is member, participants ⊆ committed members.
      (isGroupMember(groupId) && groupAllowsClientWrites(groupId)
        && request.resource.data.participantIds.hasOnly(groupMembers()))
      ||
      // #874 founding batch: seeded event rides alongside its brand-new group.
      (groupFoundingBatchByCreator(groupId)
        && request.resource.data.participantIds.hasOnly(groupAfterData(groupId).memberIds))
    );
}
```

Note the current `validEventCreate` calls `validEventBase` (which includes
`hasOnly(groupMembers())`); the new version replaces that with `validEventCreateFields` +
the per-branch membership check, so the standard path keeps the exact same
`hasOnly(groupMembers())` semantics and the founding path uses after-memberIds.

## The load-bearing claim (Gate must adjudicate)

> `getAfter(groupPath)` / `existsAfter(groupPath)` in the rule for the member/event write of an
> atomic `WriteBatch` correctly reflects the group document being created in the **same** batch.
> One `WriteBatch` is one atomic mutation, so there is no cross-document ordering to race.

This is Firestore's documented `getAfter`/`existsAfter` use case ("state after a write within the
same batched write or transaction"). Verify against Firebase rules docs + the emulator test.

## Access / expression budget (Principle 6 / ceiling landmine)

- Founding member/event create adds `exists` + `existsAfter` + `getAfter` on the group path.
  A 4-write batch is a multi-doc request (limit **20** document accesses). Literal no-cache count
  [Gate P3 — codex round 2, corrected]: group-create 0, inviteCode-create ≤3, member-create ≤6,
  event-create ≤6 → **~15**, under the 20-call atomic-operation limit (comfortable, not tight).
- **Update path PROVABLY untouched:** `validEventBase` and the entire event-update OR-chain are
  left byte-identical (the create path uses the separate `validEventCreateFields` twin). Zero rule
  bytes change on the ceiling-constrained path, so there is no expression-count regression to
  guard and no tripwire is required. The existing light/admin update tests
  (`firestore-rules-publish-readiness.test.ts:1131-1249`) already exercise it and stay green.

## Callsite classification (Principle 1) + read-path trace (Principle 3)

- `stageGroup` → `({group, ack})`: `group` INBOUND (unchanged); `ack` shape/semantics unchanged,
  construction only.
- The four writes feed: group doc (`userGroupsProvider`, `homeGroupBalanceProvider`), member
  subcollection (roster), seeded event (ledger landing). Post-fix, offline, all four are present
  in the local cache atomically and survive a kill via the replay queue.
- Error/telemetry (Principle 5 / Opus adversary P3): a single `batch.commit()` surfaces ONE
  error; `classifyError` buckets every rules rejection to `permission-denied` →
  `errorPermissionDenied`, so the user-facing message is unchanged. Simpler than the old chain
  (no `Future.wait` first-error-of-three question).

## Scope

**In scope:**
1. `group_provider.dart`: single 4-write batch; ack = `batch.commit()`; update the now-false
   docstrings at `:117-133` and `:152-164`.
2. `firestore.rules`: `groupFoundingBatchByCreator` helper; `validMemberCreate` after-state
   membership + createdBy; `validEventCreate` uses a create-only `validEventCreateFields` twin +
   per-branch membership. `validEventBase` and the whole event-UPDATE OR-chain are LEFT UNTOUCHED.
3. `firestore-rules-publish-readiness.test.ts`: NEW test — all four writes in ONE batch succeed
   (founding-batch getAfter path); NEW negative tests (below); fix the stale comment on the
   existing L361-398 `#245` test (its premise — "group batch, THEN event" — no longer matches
   the client, though the standard-path rule property it asserts still holds).
4. `group_service_test.dart`: fix the inverted test **name + comment** at L~382-406 (Opus
   adversary P2 — it describes the `.then`-chaining contract the fix removes) and any assertion
   that presumes chaining; assert the fake commits all four docs.

**Out of scope:** the join path, shadow fan-out, any UI, `validEventBase`'s update semantics.

## Test plan (RED first)

**Rules (emulator) — the real verification surface:**
1. **GREEN (new):** creator commits group + inviteCode + member + event in ONE batch → `assertSucceeds`. On `main` rules this **fails** (member/event `isGroupMember` sees no group) → RED; post-rules → GREEN.
2. **Negative (security guards must survive):**
   - Non-creator / uid not in the founding group's `memberIds` → member/event create in the batch `assertFails`. (Note [Gate P3 — Opus round 4]: this fails at the `validGroupCreate` leg — `memberIds==[uid]` — so it does NOT isolate `groupFoundingBatchByCreator`'s own `uid in memberIds` guard, which is belt-and-suspenders redundant given same-batch atomicity. The participant-⊄-after-memberIds event test below is the one that isolates a founding-branch guard.)
   - `groupFoundingBatchByCreator` cannot bypass soft-delete on an EXISTING group: a member/event create against a pre-existing `isDeleted:true` (or `deletingInProgress:true`) group still `assertFails` (the `!exists` guard forces the standard path there).
   - Standalone member/event create against an existing group (no group in the write) still behaves exactly as today (`assertSucceeds` for a member; `assertFails` for a non-member).
   - Event founding-batch with a participant NOT in the after-memberIds → `assertFails`.
   - **[Gate P3 — Opus round 3] `groupFoundingBatchByCreator` can't fire without a real same-batch group create:** a standalone member/event create where the group NEITHER exists NOR is in the batch (`existsAfter` false) → `assertFails`. Proves the after-state branch can't be tricked into existence.

**Dart (`group_service_test.dart`):**
3. **RED regression:** mock `FirebaseFirestore`; make `batch.commit()` return a never-completing `Completer`; `verify(() => batch.set(any(), any())).called(4)` and `verifyNever` any bare `docRef.set` outside the batch. Pre-fix: member/event chained off `commit()` → `batch.set` called twice, two `docRef.set` deferred → `called(2)` → RED. Post-fix: `called(4)` → GREEN. (`stageGroup` is synchronous → assert immediately, no pump; never-completing futures are not timers → no "Timer still pending" teardown.)
4. **GREEN (fake):** after awaiting the ack on `FakeFirebaseFirestore`, all four docs are present.

Then: `flutter analyze` clean; `flutter test test/unit/group_service_test.dart test/features/groups/`;
`cd functions && npm run test:emulator -- firestore-rules-publish-readiness.test.ts`.

## Deploy

Rules change ⇒ backend deploy. Per CLAUDE.md "no real users yet → server changes deploy freely."
Run `tool/pending_deploy.sh` / the `deploy-ceremony` skill; the `backend-deployed` tag is the
source of truth.

**Deploy-order is MANDATORY rules-first [Gate P1 — codex round 2].** The new rules ARE
backward-compatible with the OLD client (its chained member/event sets arrive after the group
commits → standard `isGroupMember` path — unchanged). But the reverse is NOT safe: a NEW client's
4-write batch against OLD rules gets **permission-denied** on the member/event writes, because old
rules read pre-batch group state (`isGroupMember` → group absent → deny). So: **deploy rules
first, then ship the client.** ("Either ordering is safe" was wrong and is removed.)

## Gate mapping (fan-out, stated before spending)

- **Spec gate (this revised doc):** primary = **codex** (rubric + the `getAfter`-in-batch claim +
  the ceiling budget); orthogonal adversary = **Opus** (security holes in the after-state branch,
  deploy-order, derived surfaces). Union of P1s; re-run a fresh pair until both clean in one round.
- **Fresh PR diff gate:** primary diff reviewer = **codex**; refuter = **Opus**.
- All other verification (RED evidence, adversary, refuter) = Opus.
