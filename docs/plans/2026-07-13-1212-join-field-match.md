# Spec E — #1212: joinGroupByInviteCode member-create gate matches by userId FIELD

Issue: #1212 (P3, membership-lifecycle). Branch: `fix/1212-join-field-match`. Commit body:
`Closes #1212`. Spec ships in PR as `docs/plans/2026-07-13-1212-join-field-match.md`. Server-only.

## Problem (verified 2026-07-13 against main @2ce0891c)

`functions/src/callables/joinGroupByInviteCode.ts`:
- :244 `const memberRef = groupRef.collection('members').doc(uid);`
- :266 `didJoin = !memberSnap.exists && !memberIds.includes(uid);`
- :317-326 `if (!memberSnap.exists) { tx.set(memberRef, { id: uid, userId: uid, … role: 'MEMBER' }); }`

For a legacy pre-#524 uuid-keyed member (their member doc has `userId == uid` but a random-uuid doc id):
uid ∈ memberIds → `didJoin` false (skips #279 collision check and arrayUnion), but `doc(uid)` doesn't
exist → :317 mints a SECOND member doc for the same userId, `role: 'MEMBER'`, possibly a different
free-typed displayName than the uuid-keyed CREATOR doc. Duplicate roster row that dodged the collision
gate. Every other membership path matches by the `userId` FIELD (leaveGroup.ts:99-105, deleteAccount, and
this file's own :287) — the mixed member-doc keying invariant.

Balance impact: none (liveMemberIds is a Set of userId values); departures self-heal (field-matched
deletes). Display impact: roster shows the member twice.

## Fix

The tx ALREADY loads all member docs: `membersSnap` via `tx.get(membersQuery)` (:247-251). Add:

```ts
const hasMemberDocForUid = membersSnap.docs.some((doc) => doc.get('userId') === uid);
```

- :317 create gate: `if (!hasMemberDocForUid) { tx.set(memberRef, …) }` — the new doc (when created) stays
  uid-keyed at `memberRef`, per the post-#524 client convention.
- :266 didJoin: `didJoin = !hasMemberDocForUid && !memberIds.includes(uid);` — "brand-new member" now
  means no field-matched doc anywhere, keeping the #279 collision check and the #53 G1 announce semantics
  consistent for legacy-keyed members (a legacy rejoin is not a join; today's `!memberSnap.exists`
  conjunct would also mis-fire didJoin=true in the doc-exists-but-not-in-memberIds heal state).
- Semantics to state in code comment + PR body: an existing member (however keyed) re-entering their own
  invite link is an idempotent no-op for the MEMBER DOC — existing doc kept (id, role, displayName all
  unchanged), no member_joined announce, no collision self-reject. NOTE the scope precisely: the event
  fan-in (`applyEventFanIn`, called unconditionally at :328) DOES refresh event-level
  `participantNames` with the free-typed join name — that is pre-existing behavior for every idempotent
  rejoin and is UNCHANGED by this PR; do not claim "name fully ignored" anywhere.

Heal path preserved: uid ∈ memberIds with NO doc at all → `hasMemberDocForUid` false → doc created,
`didJoin` false (memberIds conjunct) → no announce. Identical to today.

Edge-semantics change to state explicitly (intended improvement, Gate round-1 P2): a doc-exists-but-
uid-NOT-in-memberIds state (field-matched doc present, membership array lost) today computes
`didJoin = true` (announces + collision-checks a member who was already there); after this change
`didJoin = false` — the memberIds arrayUnion still heals the array, silently. Pin it with a small test.

## Non-goals

- No data migration for already-minted duplicate docs (none known in prod; if QA finds one, Admin SDK
  cleanup — note it, don't build it).
- No change to the #279 collision check body, rate limiting, fan-in, or `nextActiveMemberIds` handling.
- No client change.

## Tests (RED first — functions emulator; `npm run test:emulator -- <file>`, never bare jest #1157)

Extend the existing joinGroupByInviteCode test file (it already has uuid-keyed-creator fixtures around
:609 and heal-path tests :504/:592/:685 — reuse their seeding helpers):
1. RED: seed group with uuid-keyed member doc (`userId: creatorUid`, uuid doc id, role CREATOR) + uid in
   memberIds → that member joins via code → TODAY two member docs share `userId` (observe & paste);
   AFTER: exactly ONE member doc for that userId, doc id unchanged (still uuid-keyed), role unchanged
   CREATOR, MEMBER-DOC displayName unchanged even when the join passed a different name (scope the
   assertion to the member doc — event-level `participantNames` legitimately picks up the join name via
   the unconditional fan-in; do not assert on it, or assert it separately as the pre-existing behavior).
2. No announce on legacy rejoin (didJoin false → no notify fan-out; assert via whatever the #53 G1 tests
   assert on).
3. Heal path regression: uid ∈ memberIds, no member doc → uid-keyed doc created, no announce (existing
   tests stay green).
4. Brand-new join regression: doc created uid-keyed, didJoin true, #279 collision check still rejects a
   colliding new joiner (existing tests stay green).
5. Edge pin: field-matched doc present but uid NOT in memberIds → rejoin heals memberIds silently
   (didJoin false, no announce, no second doc).

## Acceptance

- [ ] RED evidence pasted (duplicate docs on main), green after.
- [ ] Diff touches joinGroupByInviteCode.ts only (+ its test file + this spec doc).
- [ ] Full functions suite green.
- [ ] PR body + squash commit body: `Closes #1212`; note "functions NOT deployed — pending deploy
      ceremony".
