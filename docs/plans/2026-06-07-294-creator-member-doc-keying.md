# #294 — Server cascades miss uuid-keyed creator member docs

**Status:** Gate-passed (3-lens fresh-Opus review, 2026-06-07 — 0 surviving P1; the lone P1 was refuted as a mis-classified P2 spec-prose issue; P2/P3 corrections applied below)
**Date:** 2026-06-07
**Category:** Gate-mandatory — Cloud Functions auth/validation + member schema read/write contract (recovery + deletion paths).

## Problem (code-verified `main`, 2026-06-07)

Member-subcollection doc id is inconsistent between creation and joining:

- `createGroup` (`lib/features/groups/providers/group_provider.dart:113,152`) writes the creator's member doc at `.doc(uuid.v4())` — a **random uuid** — with `userId: uid` as a field.
- `joinGroupByInviteCode.ts:277` and `cleanupAnonUidArtifacts` recovery-copies key by `.doc(uid)`.

So a **creator's** member doc id ≠ their uid; every other path keys by uid. Two server cascades look members up **by uid as the doc id**, missing creator docs:

### deleteAccount.ts
- `:457` `membersSnap.docs.find((doc) => doc.id === uid)` → `oldMemberData` (feeds `resolveOriginalName`).
- `:571` (Phase C tx) `members.find((m) => m.id === uid)?.data` → `oldTxMember` (drives `membersDeleted`, tombstone `joinedAt`/`isShadow`).
- `:597` `tx.delete(groupRef.collection('members').doc(uid))` → **no-op for a creator**; the real uuid-keyed doc survives.

**Consequence:** account deletion leaves the creator's member doc — `displayName` (**user PII**) + `userId` pointing at the deleted Auth uid — orphaned in every group they created. `membersDeleted` undercounts. Privacy gap for a delete-my-data feature.

### cleanupAnonUidArtifacts.ts
- `:270` `oldMemberRef = groupRef.collection('members').doc(oldUid)`; copy-old→new + delete-old gated on `oldMemberSnap.exists` (`:326-337`), which is **false** for a creator (doc is uuid-keyed).

**Consequence:** on email-link recovery, a creator's member doc is **not migrated**. `memberIds` flips `oldUid→newUid`, but no member doc has `userId == newUid`. The recovered creator has no valid member entry in their own group.

### Not caught by app display / CI
`GroupMember.fromDoc` keeps `id` (doc.id, `group_member_model.dart:34`) and `userId` (`:36`) separate. The client members stream `watchMembers` (`group_provider.dart:374`) reads the **whole** members collection and builds `GroupMember.fromDoc` per doc — it never filters by uid — so a uuid-keyed creator doc renders fine. The one client member query keyed by uid is the display-name sync (`lib/core/providers/settings_provider.dart:125` `where('userId', isEqualTo: uid)`), which matches by the **field** and is also unaffected. So balances/rendering survive; the breakage is confined to the two server cascades. Both Jest harnesses (`deleteAccount.test.ts:66`, `cleanupAnonUidArtifacts.test.ts:84`) seed member docs **only** at `.doc(uid)` — never a creator-style uuid-keyed doc — so the bug is invisible to the suite.

## Reference precedent (already on main)

`leaveGroup.ts:66-72` (#290) already solved the identical problem and explicitly cites #294:

```ts
// Match member docs by the `userId` FIELD, never the doc id: joiners key by
// {uid} but the creator's doc is keyed by a random uuid with `userId:uid`
// (#294) — a `.doc(uid)` lookup would miss it.
const memberDocsSnap = await groupRef
  .collection('members')
  .where('userId', '==', uid)
  .get();
// ...
for (const memberDoc of memberDocsSnap.docs) { batch.delete(memberDoc.ref); }
```

This fix mirrors that pattern into the two remaining cascades.

## Decision: Option B only (server robustness)

Per the issue's recommendation. B locates the member doc by the `userId` **field** (not doc id), healing both **existing** uuid-keyed creator docs and future ones, with **no migration**.

**Option A (make `createGroup` write `.doc(uid)`) is explicitly deferred** — it is a client write-path change that (a) does NOT heal live data (existing groups keep uuid-keyed creator docs), (b) contradicts the established, doc-load-bearing convention "match members by the `userId` field, never the doc id" (CLAUDE.md Key Invariants), and (c) widens the blast radius (client + tests + parity docs) for pure cosmetic consistency. After B, the two server cascades that look members up by uid (leaveGroup — already field-based via #290; deleteAccount + cleanupAnonUidArtifacts — via this fix) are `userId`-field-based. The other member-mutation path, the client `removeMember` (`group_provider.dart:316-334`, still a direct client batch on `main` — the #318 *server* callable lives on a separate **unmerged** branch, do not treat it as landed), already deletes the correct doc because it passes `member.id` = the real doc id from the loaded `GroupMember` (`group_members_section.dart:202`), which is the uuid for a creator. So there is **no functional gap** left by skipping A. Tracked as an optional follow-up.

## Changes

### 1. `functions/src/callables/deleteAccount.ts`

**Phase A (`:457`)** — resolve the deleted user's member doc by `userId` field:
```ts
const oldMemberData = membersSnap.docs.find((doc) => doc.data().userId === uid)?.data();
```

**Phase C transaction (`:562-600`)** — match + delete by `userId` field:
- `const oldTxMembers = members.filter((m) => m.data.userId === uid);` (was `find((m) => m.id === uid)`).
- Tombstone inherits from the matched doc: `oldTxMembers[0]?.data.joinedAt` / `?.isShadow`.
- Delete the actual matched doc(s) at their real refs, not `.doc(uid)`:
  ```ts
  for (const m of oldTxMembers) tx.delete(groupRef.collection('members').doc(m.id));
  ```
- `membersDeleted = oldTxMembers.length > 0 ? 1 : 0` (preserves the per-group "one member removed" semantic; existing 2-group test expects `membersDeleted: 2` = 1+1).
- `oldestRealMemberUid(members, uid)` (`:281-290`) already filters by `data.userId !== uid` — **correct, unchanged** (it never relied on doc id).
- Tombstone is still written at the deterministic `tombstoneId`; the `taken` set (`:453`, includes member doc ids) and `tombstoneClash` check (`:564`) are unaffected.

**Invariant preserved:** when the uid is in `memberIds` but no member doc matches (orphan), behavior is unchanged — tombstone + memberIds-replace still run, `membersDeleted` = 0. The only behavior change is that a creator's uuid-keyed doc is now *found and deleted* (was silently retained).

### 2. `functions/src/callables/cleanupAnonUidArtifacts.ts`

In `processGroup` (`:263-337`), the member lookup currently does two **point reads** inside the existing all-reads-before-writes `Promise.all` (`:272-277`): `tx.get(oldMemberRef)` + `tx.get(newMemberRef)`. **Replace those two point reads with a whole-`members`-collection read in the SAME `Promise.all`** — so reads stay before the first write (`tx.update(groupRef)` at `:319`) and the malformed-`memberIds` guard ordering is unchanged. This mirrors deleteAccount's Phase C `tx.get(collection('members'))` (proven safe):

```ts
// READ PHASE — fold into the existing Promise.all at :272-277, DROPPING
// tx.get(oldMemberRef) and tx.get(newMemberRef):
const [groupSnap, membersSnap, eventsSnap] = await Promise.all([
  tx.get(groupRef),
  tx.get(groupRef.collection('members')),
  tx.get(groupRef.collection('events')),
]);
// ... groupSnap.exists / memberIds malformed-data guards unchanged (still pre-write) ...

const newMemberRef = groupRef.collection('members').doc(newUid);   // copy TARGET, unchanged
const oldMemberDocs = membersSnap.docs.filter((d) => d.data().userId === oldUid);
const newMemberExists = membersSnap.docs.some((d) => d.data().userId === newUid);

// ... WRITE PHASE begins (tx.update(groupRef, groupUpdate) at :319), then: ...
if (!newMemberExists && oldMemberDocs.length > 0) {
  tx.set(newMemberRef, { ...(oldMemberDocs[0].data() ?? {}), id: newUid, userId: newUid });
  actions.push('members.copyOldToNew');
}
for (const d of oldMemberDocs) {
  tx.delete(d.ref);             // real id (uuid for a creator), not .doc(oldUid)
  actions.push('members.deleteOld');
}
```

- `newMemberRef = .doc(newUid)` stays the copy **target** — a recovered creator's doc is **normalized to uid-keyed**, healing the inconsistency for that doc.
- **Delete ALL docs matching `userId == oldUid`** (filter + loop), mirroring deleteAccount Phase C + leaveGroup — not a single `find`. Realistically one doc per userId, but this removes a latent divergence: a prior partial recovery leaving both a uuid- and a uid-keyed doc would otherwise strand a residual `userId==oldUid` doc after the oldUid Auth user is deleted — the same orphan class this PR fixes. Copy source is the deterministic first match.
- Existing tests unaffected: a joiner doc at `.doc(old)` with `userId: old` is found by the field scan (its id == old); copy→`.doc(new)`, delete `.doc(old)` — same outcome. The "both UIDs are members" case (`cleanupAnonUidArtifacts.test.ts:170`): `newMemberExists` true → delete old, no copy — same outcome.
- The whole-collection read **replaces** two point reads (net read count ~neutral); it adds **reads not writes**, so the 500-**write** cliff (obs 24956) is unaffected.

## TDD (RED first)

New Jest cases, each seeding a **creator-style uuid-keyed** member doc (`.doc(<uuid>)` with `userId: <uid>`):

**deleteAccount.test.ts**
1. *Creator doc deleted + PII scrubbed.* Group where the deleted uid's member doc is uuid-keyed (`userId == deletedUid`, `displayName: 'Real Name'`, `createdBy: deletedUid`). After delete: the uuid-keyed doc is **gone** (not orphaned), a tombstone exists with `displayName: 'Deleted member'`, `membersDeleted >= 1`, `createdBy` resolved (sole creator → soft-deleted/sentinel; with a survivor → survivor).
2. *Creator + a real joiner survivor.* uuid-keyed creator (deleted, also an event payer so they sit in the financial universe) + uid-keyed survivor. After: the uuid-keyed creator doc is gone, **no member doc anywhere has `userId == deletedUid`** (orphan fully removed → `recomputeNet`'s `liveMemberIds` no longer carries the deleted uid — the money-adjacent #249 universe axis; today the retained orphan would keep `deletedUid` "live"), survivor untouched, `createdBy` = survivor uid, group not soft-deleted.

**cleanupAnonUidArtifacts.test.ts**
3. *Creator recovery migrates the uuid-keyed doc.* Group where oldUid's member doc is uuid-keyed (`userId: oldUid`). After cleanup: a member doc with `userId == newUid` exists at `.doc(newUid)`, the uuid-keyed old doc is **deleted**, `memberIds` contains newUid not oldUid, `createdBy` migrated. (RED today: copy/delete gated on `.doc(oldUid).exists` == false → recovered creator has no member doc.)

Watch each fail for the right reason against current code, then implement, then GREEN.

## Verification gates
- `cd functions && npx tsc --noEmit` (exit 0)
- `cd functions && npm test` (Jest under emulator/Java 21 — all suites green, incl. the 3 new cases)
- `flutter analyze` (clean — no Dart change expected, B is server-only; run as a guard)

## Out of scope / follow-ups
- Option A (createGroup `.doc(uid)`) — optional consistency, separate PR.
- A one-time backfill/migration of already-orphaned uuid-keyed docs from *already-deleted* accounts (B prevents new orphans + heals on next recovery/delete, but cannot retroactively scrub a doc whose owner already deleted) — note only; likely negligible volume pre-launch.
