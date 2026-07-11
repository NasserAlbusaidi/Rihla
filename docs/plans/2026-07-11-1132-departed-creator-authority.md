# #1132 Departed-Creator Authority Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Revoke a departed group creator's destructive authority — every live `createdBy`-keyed check (3 rules functions + 5 callables) gains a current-membership conjunct, so leaving the group ends creator powers until they rejoin.

**Architecture:** Rules: a same-doc membership conjunct in THREE createdBy-keyed authorities — `isCreator()` (group rename/stamp), `requesterIsEventAdmin()` (one fold covering BOTH the event-creator and group-creator OR branches → event admin-edit/close/reopen), and `validMemberDelete()`'s creator branch (shadow/orphan member-doc delete). Functions: a tiny shared `isCurrentMember(groupData, uid)` helper applied at all 7 callable gate sites (5 callables, incl. both tx re-checks), keeping each site's existing error code+message. No schema change, no client change.

**Tech Stack:** Firestore rules + TS Cloud Functions; emulator tests (`npm run test:emulator`).

**Issue:** #1132 (P2, security). Verified against `main` @ `50d96847`.

---

## Verified declarations (all re-read this session @ `50d96847`)

Rules (`security/firestore.rules`):
- `isCreator()` :313-315 — `signedIn() && uid == resource.data.createdBy`, **no membership term**. Sole caller `validCreatorMetadataUpdate` (:367) → group `allow update` (:401-403). Gates rename + stamp glyph/inkIndex.
- `requesterIsEventCreator()` :428-430 — event `resource.data.createdBy`, membership-blind.
- `requesterIsGroupCreator()` :432-435 — `get(group).data.createdBy`, membership-blind.
- `requesterIsEventAdmin()` :437-439 — OR of the two. Callers: `validEventAdminUpdate` (:581 — event rename/participant-strip/modules/soft-delete) and `validEventCloseToggle` (:637 — close/reopen). **The issue's fix list named only `requesterIsGroupCreator`; that alone is insufficient — a departed group creator still passes the `requesterIsEventCreator` branch on every event they created (which is typically all of them). The fold must sit on `requesterIsEventAdmin`.**
- **`validMemberDelete()` :1062-1074 creator branch — THIRD live createdBy-keyed authority (Gate round 1 caught; issue text missed it).** `groupData(groupId).createdBy == request.auth.uid && (!groupExistsAfter() || !(resource.data.userId in groupAfterMemberIds()))`, wired to `allow delete: if validMemberDelete()` (:1078). Membership-blind. **Reachable for SHADOW member docs:** a shadow's `userId` is a uuid never in `memberIds`, so `!(userId in groupAfterMemberIds())` is true on a lone single-doc delete (no companion group write needed) — a departed creator can delete shadow/orphan member docs, orphaning that shadow's balance (uuid stays in event `splitDistribution`, its roster name vanishes) and breaking the claim flow (`requestClaimShadow` needs the member doc). The #290/#318 comment ("achievable only by the now-blocked group update") reasons only about self/in-`memberIds` targets and does NOT cover already-out-of-`memberIds` shadows. **In scope** — same createdBy-keyed destructive class; omitting it is a #223 half-done-close.
- Event CREATE already requires `isGroupMember(groupId)` (:541) — **no fix needed**; a departed creator cannot create events today.
- `validEventBase` (:454) requires `participantIds.hasOnly(groupMembers())`, and `validEventAdminUpdate` routes soft-delete/participant-strip/modules through it. So a departed creator who is STILL an event participant is ALREADY blocked from those (#249 coupling); the genuine admin hole is: (a) group rename/stamp (`isCreator`, no `validEventBase`), (b) event close/reopen (`validEventCloseToggle` deliberately skips `validEventBase`, :632), (c) admin soft-delete/strip ONLY on events where the departed creator is not a participant and all remaining participants are still members. **RED tests must account for this** (see Task 1).
- **`correctSettlement.ts:94` / `correctLogicalSettleUp.ts:104` already gate `memberIds.includes(uid)` UPSTREAM** of their `assertCorrectionActor(uid, createdBy, …)` createdBy-branch (`shared/correctionActor.ts`) — a departed creator is already blocked. Correctly NOT in the fix list.
- Global `isGroupCreator(groupId)` (:158) has **zero callers** (grep confirmed) — dead helper, not a surface.
- **Reviewed-benign untouched createdBy sites** (acknowledged, deliberately NOT fixed): `inviteCodes` create :265 (idempotent, admin-read-only), `inviteCodes` delete :276 (needs group hard-delete, forbidden by `allow delete: if false`), member-create CREATOR branch :1047 (creating a CREATOR member doc doesn't restore `memberIds`, so grants nothing). None is a destructive departed-creator surface.
- `claimRequests`/`claimShadowLocks` subcollections: `allow read, write: if false` (:1260-1269) — no client surface.
- Write rules evaluate independently of the `allow read: if isGroupMember` gate, so read-loss does NOT block these writes (the issue's mechanism, confirmed).

Callables (all gate solely on `createdBy !== uid`; none check `memberIds`):
- `deleteGroup.ts:145`
- `removeMember.ts:103` + `:175` (fresh-group tx re-check)
- `addShadowMember.ts:78`
- `decideClaimRequest.ts:196` + `:220` (locked-group tx re-check)
- `listGroupClaimRequests.ts:57` — read-only claim listing. The issue text doesn't list it, but it is the same `createdBy`-keyed class ("every authority check keyed on createdBy"); one-line fix, included to close the class. (`listUnclaimedShadows` has no creator gate — joiner-facing; `requestClaimShadow` is joiner-side. Neither is a surface.)

Reachability of the departed-creator state:
- `leaveGroup.ts` has no `createdBy` special-case (creator may leave at own-net-zero), and the client SHOWS Leave to the creator (`group_danger_section.dart:65` renders `_buildLeaveGroupTile` unconditionally) — creator-less groups are a normal UI-reachable state, not a raw-callable exotic.

## Fix shape (decided)

### Rules (3 edits)

```
function isCreator() {
  // #1132: creator authority requires CURRENT membership — leaveGroup never
  // reassigns createdBy, so a departed creator would otherwise keep rename/
  // stamp authority forever (writes don't need read access). Same-doc check,
  // zero extra reads.
  return signedIn()
    && request.auth.uid == resource.data.createdBy
    && request.auth.uid in resource.data.memberIds;
}

function requesterIsEventAdmin() {
  // #1132: fold ONE membership term over BOTH branches — a departed group
  // creator is usually also the event creator, so gating only the group-
  // creator branch would leave the event-creator branch open. The group doc
  // is already read by eventAllowsClientWrites in every caller, so this adds
  // no document access.
  return (requesterIsEventCreator() || requesterIsGroupCreator())
    && isGroupMember(groupId);
}

function validMemberDelete() {
  return signedIn()
    && exists(groupPath(groupId))
    && groupAllowsClientWrites(groupId)
    && (
      (groupExistsAfter()
        && resource.data.userId == request.auth.uid
        && !(request.auth.uid in groupAfterMemberIds()))
      || (groupData(groupId).createdBy == request.auth.uid
        // #1132: creator branch requires CURRENT membership — else a departed
        // creator (createdBy dangles after leaveGroup) can delete shadow member
        // docs (uuid userId never in memberIds → after-guard passes on a lone
        // delete), orphaning the shadow's balance + breaking claim. Same-doc
        // read (groupData already fetched above), no new access.
        && request.auth.uid in groupData(groupId).memberIds
        && (!groupExistsAfter()
          || !(resource.data.userId in groupAfterMemberIds())))
    );
}
```
The self-branch is untouched — a departing member deleting their OWN doc is legitimate (and already `groupAfterMemberIds`-gated). A CURRENT creator deleting a shadow doc still passes (`uid in memberIds` true), so no over-block.

**#723 expression-ceiling risk — this IS the documented near-ceiling path** (the event `allow update` OR-chain re-runs heavy validators). `isGroupMember` adds ~5 expressions; doc-access unchanged (group doc already fetched by `groupAllowsClientWrites` in both callers). Test-gated by the full readiness suite; **fallback:** inline `request.auth.uid in groupData(groupId).memberIds` (drops redundant `signedIn`/`exists`). Method proven on #1131/PR #1134: count per-clause "maximum of 1000" deny-debug artifacts before/after — pre-existing artifacts are benign (fail closed); a NEW hit on an allow-path = a test goes red.

### Functions (1 new helper + 7 sites)

New `functions/src/callables/shared/membership.ts`:
```ts
// #1132: creator authority requires current membership. leaveGroup/removeMember
// shrink memberIds but never reassign createdBy, so a createdBy equality check
// alone grants a DEPARTED creator destructive authority forever. Callers pair
// this with the createdBy check; keep both or the gate regresses.
export function isCurrentMember(groupData: Record<string, unknown>, uid: string): boolean {
  const memberIds = Array.isArray(groupData.memberIds) ? groupData.memberIds : [];
  return memberIds.includes(uid);
}
```

At each of the 7 sites, widen the existing condition (keep each site's existing `HttpsError('permission-denied', …)` code and message — no client/l10n dependency changes):
```ts
if (groupData.createdBy !== uid || !isCurrentMember(groupData, uid)) { …existing throw… }
```
Sites: `deleteGroup.ts:145`, `removeMember.ts:103` AND `:175`, `addShadowMember.ts:78`, `decideClaimRequest.ts:196` AND `:220`, `listGroupClaimRequests.ts:57`. The tx re-checks (`removeMember:175`, `decideClaimRequest:220`) get the conjunct too — they exist to catch state changes racing the first check, and a leave can race exactly there.

### Rejected alternatives

- **Transfer/clear `createdBy` on leave (succession policy)** — a product feature needing a successor-selection decision; separate follow-up issue filed at ship time.
- **Block the creator from leaving** — changes shipped UX (client offers creator-leave today) and doesn't close the class anyway: `deleteAccount` already tombstones `createdBy`, so admin-less groups are ALREADY a reachable end-state. The conjunct makes rules/callables consistent with that reality.

## Consequences (deliberate, spell them out)

- **Creator leaves → the group becomes admin-less** until the creator rejoins via invite code (rejoin restores `memberIds` → full authority). While admin-less: no rename/stamp, no add-shadow, no claim decisions (pending claim requests stay frozen), no member removal, no event admin-edit/close/reopen, no group delete, no shadow-doc cleanup. Members keep full ledger use, light event edits (name/dates/additive participants), self-leave, and invite/join.
- **This fix INTRODUCES a new live-but-admin-less state that the codebase currently AVOIDS.** Corrected precedent (Gate round 1 — my earlier claim was inverted): `deleteAccount.ts:612-628` does creator **succession** — on a creator's account deletion it reassigns `createdBy` to `oldestRealMemberUid`, and only when there is NO real survivor does it tombstone `createdBy` AND soft-delete the whole group. So the code deliberately never leaves a live group admin-less; the conjunct fix is the first path that can.
- **Permanent-lockout sub-case (honest):** creator leaves, THEN deletes their account. `deleteAccount.ts:594` skips any group where `uid ∉ memberIds`, so the departed creator's dangling `createdBy` is never cleaned up → the group is **permanently admin-less** (pending claims frozen forever, group undeletable, shadow docs uncleanable). Recoverable only if the departed creator rejoins via invite code *before* deleting their account. Pre-launch with no real users this availability gap is acceptable, but it is the reason **creator-succession-on-leave is a HIGH-priority follow-up, not a nicety** (Task 5 files it; mirror `deleteAccount`'s succession in `leaveGroup`). The security hole this PR closes (departed creator as ghost admin) strictly outranks the availability gap it opens; they are separable and this PR takes the security half.
- Offline-queued creator metadata write replayed after leaving → denied, silently dropped (same accepted class as #1131). Also: a departed creator whose group is still in offline persistence still SEES admin affordances (rename/delete/manage) until the cache evicts, then taps → permission-denied. No data risk; cosmetic, pre-launch.
- Departed creator's claim-request LIST access also closes (`listGroupClaimRequests` conjunct) — read leak, same class.

## Verification principles report

1. **Callsite classification** — pure authz-gate changes (rules write gates, callable guards, one callable read guard). No data-shape/display-string change; nothing new reaches a write boundary.
2. **Concrete claims** — every file:line above re-read this session, not taken from the issue (which under-scoped the event-admin fix, omitted `listGroupClaimRequests`, and missed the `validMemberDelete` creator branch).
3. **Read-path per write-path** — no schema mutation. Behavior consumers: rules emulator tests + callable emulator tests (named below). Client admin UI (`group_info_section`/`group_danger_section`/`claim_requests_section` gate on an `isCreator` bool derived from the watched group doc) is unreachable for a departed creator — group read already denied — so no client change.
4. **Fields from type** — no field changes; helper reads only `memberIds` with the same `Array.isArray` guard `leaveGroup.ts:74` uses.
5. **Data contracts** — exact fn names/lines listed; helper signature spelled; error codes/messages unchanged at all 7 sites.
6. **Arithmetic decomposition** — N/A. `deleteGroup`/`removeMember` net-zero gating and the `claimShadowEngine` re-key are untouched (only their entry authz); oracle untouched.
7. **Orthogonal axes:**
   - **Identity / anon (D6-R):** anon creators are in `memberIds` from `validGroupCreate` (`memberIds == [uid]`) — the conjunct adds no durable-credential gate; the claim-chain anon-rejects are untouched.
   - **Founding batch (#874):** both touched rules fns are UPDATE-path only; the founding batch only CREATEs. `validEventCreate`'s founding branch doesn't route through `requesterIsEventAdmin`. No interaction.
   - **Time (close/reopen):** a departed creator can no longer close/reopen — intended; `#723 admin can close an event with a departed PARTICIPANT` (readiness test :1535) exercises the admin-still-member case and must stay green (over-block guard).
   - **Race:** leave racing removeMember/decideClaimRequest — the tx re-checks now carry the conjunct, so the race window closes server-side.
   - **#1135 adjacency:** a departed creator still in `participantIds` can still use the LIGHT event path (name/dates/additive participants) — that is #1135's membership-blind hole (all departed participants, not just creators), deliberately out of scope here. RED tests must therefore use ADMIN-ONLY keys (`isDeleted`, `isClosed`, participant-strip), never `name`/dates, or they'd pass the light path and prove nothing.

## Tasks

### Task 1: RED — rules tests

**File:** `functions/test/firestore-rules-publish-readiness.test.ts` — new describe after the #1131 block:

```ts
describe('#1132 departed creator loses admin authority', () => {
  // leaveGroup never reassigns createdBy, so a creator who left kept every
  // createdBy-keyed power. Membership is now a conjunct on isCreator,
  // requesterIsEventAdmin, and validMemberDelete's creator branch.
  //
  // CONFOUND GUARD (Gate round 1 P1): validEventBase (:454) re-asserts
  // participantIds.hasOnly(groupMembers()). If we left the departed creator in
  // e1.participantIds while dropping them from memberIds, the admin soft-delete
  // would deny PRE-fix via that check (not via authority) → false RED. So
  // departCreator ALSO prunes 'owner' from e1.participantIds/participantNames,
  // making requesterIsEventAdmin the SOLE gate. (The close test would be clean
  // either way — validEventCloseToggle skips validEventBase — but we prune
  // uniformly so every event test isolates the conjunct.) We do NOT test
  // 'name'/dates (that's the light path, #1135's separate hole) and we DROP the
  // participant-strip test (degenerate with one remaining member).
  async function departCreator(): Promise<void> {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('groups/g1').update({ memberIds: ['member'], updatedAt: new Date() });
      await db.doc('groups/g1/members/owner').delete();
      // prune the departed creator from the event so validEventBase passes and
      // requesterIsEventAdmin is the only remaining gate (createdBy stays 'owner')
      await db.doc('groups/g1/events/e1').update({
        participantIds: ['member'],
        participantNames: { member: 'Member' },
      });
    });
  }

  test('departed creator cannot rename the group', async () => {
    await departCreator();
    const departed = testEnv.authenticatedContext('owner').firestore();
    await assertFails(departed.doc('groups/g1').update({
      name: 'Hijacked', updatedAt: new Date(),
    }));
  });

  test('departed creator cannot set the group stamp', async () => {
    await departCreator();
    const departed = testEnv.authenticatedContext('owner').firestore();
    await assertFails(departed.doc('groups/g1').update({
      glyph: 'tent', inkIndex: 2, updatedAt: new Date(),
    }));
  });

  test('departed creator cannot admin-soft-delete an event', async () => {
    await departCreator();
    const departed = testEnv.authenticatedContext('owner').firestore();
    // exact key set validEventAdminUpdate's soft-delete branch allows
    await assertFails(departed.doc('groups/g1/events/e1').update({
      isDeleted: true, deletedAt: new Date(), updatedAt: new Date(),
    }));
  });

  test('departed creator cannot close an event', async () => {
    await departCreator();
    const departed = testEnv.authenticatedContext('owner').firestore();
    await assertFails(departed.doc('groups/g1/events/e1').update({
      isClosed: true, closedAt: new Date(), closedBy: 'owner', updatedAt: new Date(),
    }));
  });

  test('departed creator cannot delete a shadow member doc', async () => {
    // seed an unclaimed shadow (uuid userId, never in memberIds)
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('groups/g1/members/shadow-uuid-1').set({
        id: 'shadow-uuid-1', userId: 'shadow-uuid-1', displayName: 'Guest',
        role: 'MEMBER', joinedAt: new Date(), isShadow: true,
      });
    });
    await departCreator();
    const departed = testEnv.authenticatedContext('owner').firestore();
    await assertFails(departed.doc('groups/g1/members/shadow-uuid-1').delete());
  });

  // Over-block guard: a creator who is STILL a member keeps every power,
  // INCLUDING deleting a shadow member doc.
  test('current creator still renames, stamps, closes, soft-deletes, and deletes a shadow', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('groups/g1/members/shadow-uuid-2').set({
        id: 'shadow-uuid-2', userId: 'shadow-uuid-2', displayName: 'Guest2',
        role: 'MEMBER', joinedAt: new Date(), isShadow: true,
      });
    });
    const owner = testEnv.authenticatedContext('owner').firestore();
    await assertSucceeds(owner.doc('groups/g1').update({
      name: 'Renamed Crew', updatedAt: new Date(),
    }));
    await assertSucceeds(owner.doc('groups/g1').update({
      glyph: 'tent', inkIndex: 2, updatedAt: new Date(),
    }));
    await assertSucceeds(owner.doc('groups/g1/members/shadow-uuid-2').delete());
    await assertSucceeds(owner.doc('groups/g1/events/e1').update({
      isClosed: true, closedAt: new Date(), closedBy: 'owner', updatedAt: new Date(),
    }));
    // soft-delete after reopen would need a fresh event; keep close as the last
    // event write, or split into its own test — implementer's call.
  });
});
```

(Before finalizing, verify field types against the existing #723 close tests at `firestore-rules-publish-readiness.test.ts:1469-1560`: `closedAt`/`deletedAt` are `new Date()` → `Timestamp`. Mirror the existing green admin write map. The over-block guard's close+soft-delete on the same event conflict on state — either split into two tests or reseed; implementer's call.)

Run: `cd functions && npm run test:emulator -- firestore-rules-publish-readiness.test.ts -t "#1132"`
Expected RED: all 5 departed-creator tests FAIL ("Expected request to fail, but it succeeded"); over-block guard PASSES. Commit RED.

### Task 2: RED — callable tests

**Files:** `functions/test/callables/deleteGroup.test.ts`, `removeMember.test.ts`, `addShadowMember.test.ts`, `claimRequest.test.ts` — read each file's existing harness/fixtures first and mirror them. One new test per callable: seed group with `createdBy: <uid>` but `memberIds` WITHOUT that uid → invoke as that uid → expect `permission-denied`. (Over-block guards already exist: every file's happy-path tests run as a current-member creator.)

Run each: `npm run test:emulator -- callables/<file> -t "departed"`. Expected RED: the callables currently succeed (or fail with the wrong error) → assertions on `permission-denied` fail. Commit RED.

### Task 3: GREEN — the fix

1. `security/firestore.rules`: the THREE function bodies above (`isCreator`, `requesterIsEventAdmin`, `validMemberDelete` creator branch) — comments included.
2. `functions/src/callables/shared/membership.ts`: the helper above.
3. The 7 callable sites: widen conditions, import the helper.
4. Re-run `-t "#1132"` + each callable file → all green.
5. Full suites (regression + #723 ceiling): `firestore-rules-publish-readiness.test.ts` (220+ green, compare per-clause ceiling-artifact counts pre/post as in PR #1134), `firestore-rules-cut-modules.test.ts`, `settlementIdempotency.rules.test.ts`, `decomposed-settleup-batch.test.ts`, and the touched callable suites in full. `cd functions && npm run lint` if a lint script exists.
6. Commit fix.

### Task 4: Docs truth sweep

- `docs/SECURITY-RULES.md`: §1 table group-update row ("creator metadata" → current-member creator, #1132) + event admin row + members-delete row (creator-branch now current-member, #1132); §2 helper table `isGroupCreator` row (note: dead helper, zero callers) and add the #1132 conjunct note to the creator-authority prose section (§ event admin path + § member deletion).
- `docs/CLOUD-FUNCTIONS.md`: the 5 creator-gated callables' descriptions — "group creator" → "current-member group creator (#1132)".
- `CLAUDE.md` Key Invariants, Name-based members bullet: annotate that claim decisions (`decideClaimRequest`) and `addShadowMember`/`listGroupClaimRequests` now also require the creator to be a current member (#1132) — keep the D6-R anon carve-out text intact.
- Commit docs.

### Task 5: Ship

1. Commit plan file; push `-u`; PR with `Closes #1132`, `Spec:` line, RED evidence pasted for BOTH rules and callable suites.
2. `/automerge` (Gate-category: rules + functions).
3. File follow-up (HIGH priority, not a nicety): **creator succession on leave** — mirror `deleteAccount.ts:612-628`'s `oldestRealMemberUid` succession inside `leaveGroup` (reassign `createdBy` on creator-leave; tombstone + soft-delete only when no real survivor). This closes the availability gap this PR opens (permanent admin-less lockout in the creator-leaves-then-deletes-account path). Reference this spec's Consequences section.
4. Deploy: pending ceremony, batched with #1134's rules change.

## Out of scope

- #1135 (`validEventLightUpdate` membership-blind for ALL departed participants — the light path stays open to a departed creator qua participant until #1135 lands).
- Creator succession policy (follow-up filed at ship time).
- `deleteAccount` tombstone semantics for `createdBy` (#1133 territory).

## Gate record

Round 1 (2026-07-11): rubric 1 P1 / 2 P2 / 1 P3; adversary 1 P1 / 2 P2 / 2 P3. Both P1s = the same two findings cross-confirmed: (a) `validMemberDelete` creator branch is a third membership-blind createdBy authority (folded into the fix + a shadow-delete RED test); (b) two event-admin RED tests were confounded by `validEventBase`'s participant check (fixed — `departCreator` now prunes `participantIds`, strip test dropped). Material P2s folded: `deleteAccount` precedent was inverted (corrected — it does succession, not tombstoning; permanent-lockout sub-case stated honestly; succession elevated to HIGH-priority follow-up); #723 ceiling risk (measure pre/post, don't assert). P3s folded: benign-untouched createdBy sites acknowledged; offline stale-admin-UI noted; callable RED tests must isolate membership as sole failure cause. Re-run with a fresh pair.
