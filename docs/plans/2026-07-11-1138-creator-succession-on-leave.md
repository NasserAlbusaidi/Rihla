# #1138 Creator Succession on Leave Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close the admin-less-group gap #1132 deliberately opened — `leaveGroup` reassigns `createdBy` to the oldest real remaining member on a creator leave (soft-deleting the group when none survives), and `oldestRealMemberUid` stops appointing shadows/non-members.

**Architecture:** Functions-only change (no rules edit, no schema change, no client change). A shared successor helper moves to `shared/membership.ts` with two new filter conjuncts (`isShadow !== true`, `userId ∈ memberIds`); `leaveGroup`'s existing final transaction gains a creator-succession branch mirroring `deleteAccount` Phase C; both succession sites also flip the successor's member-doc `role` to `'CREATOR'` (the roster badge is a derived display surface reading `role`, not `createdBy`).

**Tech Stack:** TS Cloud Functions (Node 22); emulator tests via `cd functions && npm run test:emulator -- <file>`.

**Issue:** #1138 (backend, data-integrity). Verified against `main` @ `58479e4a`.

---

## Verified declarations (all re-read this session @ `58479e4a`)

- `leaveGroup.ts:143-198` — the final transaction: fresh group read + quiesce checks, `assertDepartureLockHeld`, `arrayRemove(uid)` + lock clear (:178-183), leaver member-doc deletes (:184-186), `member_left` activity row (:187-196). **No `createdBy` handling anywhere in the file.** The tx already re-reads `freshMemberIds` (:160-162) and queries member docs by `userId` field (:163-165).
- `deleteAccount.ts:310-319` — `oldestRealMemberUid(members, uid)` filters `userId !== uid && isTombstone !== true && isDeleted !== true`, sorts by `timestampMillis(joinedAt)`. **No `isShadow` conjunct, no memberIds conjunct** — succession can appoint a shadow uuid → admin-less because a shadow **never authenticates**: no `request.auth.uid` ever equals the uuid, so every `createdBy == request.auth.uid` gate (rules `isCreator`, every callable's `createdBy !== uid` guard) is permanently unsatisfiable. (NOT because the uuid is outside `memberIds` — it isn't, see the addShadowMember bullet below; the #1132 plan doc's "uuid ∉ memberIds" rationale is wrong against live code, though its admin-less conclusion holds. Gate R1 rubric catch.) The #1132 Consequences follow-up stands: exclude shadows/**non-members**.
- `deleteAccount.ts:709-766` — Phase C succession precedent: `if (gData.createdBy === uid) groupUpdate.createdBy = remainingRealCreator ?? deletedUserSentinel` (:742-744); `if (!hasRealSurvivor)` → sentinel + `isDeleted: true` + `deletedAt` (:745-749). Reads the FULL members collection inside the tx (:718). **Does not touch the successor's member-doc `role`.**
- `deleteAccount.ts:714` — the skip `if (!currentMemberIds.includes(uid)) return …applied: false` — why leave-then-delete-account leaves `createdBy` dangling **permanently** (the #1132 Consequences "permanent-lockout sub-case").
- `deleteAccount.ts:25` — `const deletedUserSentinel = 'deleted-user'` (file-local). `:159-167` — `timestampMillis` (file-local; sole other use is the successor sort at :316).
- `shared/membership.ts` — `isCurrentMember` (#1132) lives here; natural home for the shared successor helper.
- `addShadowMember.ts:124-140` — shadow member doc: `userId` = freshly-minted uuid, `isShadow: true`, `joinedAt: serverTimestamp()`, **and the uuid IS added to `memberIds`** (`memberIds: FieldValue.arrayUnion(newId)`, :137-139). A shadow is a full roster member (the balance oracle counts it live), it can carry the OLDEST `joinedAt` among survivors, and **a `memberIds` filter can never exclude it — only the `isShadow` flag can**. Test fixtures seeding shadows MUST put the uuid in `memberIds` or they exercise a state production never produces.
- `claimShadow.ts:767` — claiming flips `isShadow: false` and re-keys `userId` to the claimer uid (already in `memberIds` at claim time) → a claimed shadow is a legitimate successor. Unclaimed shadows keep `isShadow: true`.
- `removeMember.ts:85-88` — creator self-remove is rejected (`invalid-argument`, "Use leaveGroup") → **`leaveGroup` is the ONLY creator-departure path besides `deleteAccount`.** Both get succession after this plan; the class is closed.
- Client authority affordances key on the **group doc**: `group_settings_screen.dart:45` (`isCreator = currentUserId == group.createdBy`), `group_detail_screen.dart:261,265`. Live-watched → succession propagates with zero client change.
- Client roster badge keys on the **member doc**: `group_members_section.dart:163,169` read `member.isCreator` (= `role == 'CREATOR'`, `group_member_model.dart:113`). **Derived display surface** — without the role flip, the successor holds full authority while the roster shows no Creator badge (and `deleteAccount` succession already has this cosmetic gap today).
- Rules member-create `firestore.rules:1149-1155` — client may only write `role: 'CREATOR'` when `groupAfterData(groupId).createdBy == request.auth.uid` — consistent with post-succession state; the server-side role flip bypasses rules (Admin SDK) and the client can't edit `role` at all (`validSelfDisplayNameUpdate` diff-gates to displayName). No rules change needed.
- Existing tests: `leaveGroup.test.ts` (harness: `seedGroup` createdBy OWNER / memberIds `[OWNER, MEMBER]`, `seedMember`, wrapped callable; tests 1-9 — none pins `createdBy` after a creator leave, test 9 asserts only memberIds/doc deletion → stays green). `deleteAccount.test.ts:1190` asserts succession `createdBy: otherUid` with `toMatchObject({userId, displayName})` on the survivor doc → tolerant of the added `role` flip, stays green.

## Succession policy (decided — stated assumption)

**Successor = oldest real current member** (`joinedAt` ascending; `timestampMillis` sends missing/garbage `joinedAt` to `MAX_SAFE_INTEGER`, i.e. last).

- This is the `deleteAccount` precedent (issue text names it); two different succession policies across the only two departure paths would be incoherent.
- **Rejected: creator-picks-successor** — a product feature (picker UI + new callable + pending-successor state while the pick is undecided), and the availability fix shouldn't wait on it. Nothing in this plan blocks adding an explicit-transfer feature later; it would simply write `createdBy` before the leave.
- **Rejected: block creator leave** — already rejected in #1132 (changes shipped UX; admin-less groups were already reachable via deleteAccount).
- **Semantic change, deliberate:** pre-#1138 a departed creator regained full authority by rejoining (dangling `createdBy` still matched). Post-#1138 succession is a **permanent handoff** — the ex-creator rejoins as a plain `MEMBER` (`joinGroupByInviteCode` writes `role: 'MEMBER'`), and `createdBy` points at the successor. This is what succession means; stating it so the Gate reviews it as intent, not omission.

## Fix shape

### 1. `functions/src/callables/shared/membership.ts` — shared successor helper

Move `timestampMillis` (verbatim, but **module-private** — it has no caller left outside this file, and exporting it would collide with `groupNetBalance.ts`'s same-named export with different null semantics) from `deleteAccount.ts:159-167` and `deletedUserSentinel` from `deleteAccount.ts:25`; add the successor helper with the two new conjuncts:

```ts
import { Timestamp } from 'firebase-admin/firestore';
import type { DocumentData } from 'firebase-admin/firestore';

/** Sentinel createdBy for a group whose creator departed with no real survivor. */
export const deletedUserSentinel = 'deleted-user';

// Private on purpose: groupNetBalance.ts exports a timestampMillis with
// DIFFERENT garbage semantics (null vs MAX_SAFE_INTEGER); don't offer importers
// two same-named functions.
function timestampMillis(value: unknown): number {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'string') {
    const millis = Date.parse(value);
    return Number.isNaN(millis) ? Number.MAX_SAFE_INTEGER : millis;
  }
  return Number.MAX_SAFE_INTEGER;
}

/**
 * #1138 successor selection (shared by deleteAccount Phase C + leaveGroup):
 * the oldest-joined member doc that is (a) not the departing uid, (b) not a
 * tombstone, (c) not soft-deleted, (d) NOT an unclaimed shadow, and (e) a
 * CURRENT member (userId ∈ memberIds).
 *
 * (d) is the ONLY conjunct that excludes a production shadow — addShadowMember
 * arrayUnions the shadow uuid INTO memberIds, so (e) never catches it. A shadow
 * as createdBy is admin-less because it never AUTHENTICATES: no request.auth.uid
 * ever equals the uuid, so every createdBy-keyed gate is unsatisfiable.
 * (e) is defense-in-depth for torn/legacy docs whose userId fell out of
 * memberIds — equally admin-less as createdBy under the #1132 membership
 * conjunct, since createdBy ∈ memberIds is required by rules isCreator.
 */
export function oldestRealMemberUid(
  members: Array<{ id: string; data: DocumentData }>,
  departingUid: string,
  memberIds: string[],
): string | null {
  const candidates = members
    .filter(({ data }) =>
      data.userId !== departingUid
      && data.isTombstone !== true
      && data.isDeleted !== true
      && data.isShadow !== true
      && typeof data.userId === 'string'
      && memberIds.includes(data.userId))
    .sort((a, b) => timestampMillis(a.data.joinedAt) - timestampMillis(b.data.joinedAt));
  const first = candidates[0]?.data.userId;
  return typeof first === 'string' && first.length > 0 ? first : null;
}
```

`deleteAccount.ts`: delete the local `timestampMillis`, `deletedUserSentinel`, and `oldestRealMemberUid`; import **only `oldestRealMemberUid` and `deletedUserSentinel`** from `./shared/membership` — `timestampMillis` has zero remaining uses in `deleteAccount.ts` (its only caller was the moved helper), and an unused import fails `npm run build` under `tsconfig.json` `noUnusedLocals` (Gate R1 adversary catch). Phase C call becomes `oldestRealMemberUid(members, uid, currentMemberIds)`.

Note on the memberIds argument: both callers pass the **pre-departure** roster (`currentMemberIds` / `freshMemberIds`) — the departing uid is excluded by conjunct (a), shadow uuids in that roster are excluded by conjunct (d) (NOT by (e) — they are legitimate roster entries), and `deleteAccount`'s tombstone-id swap into memberIds is harmless (tombstone docs are excluded by conjunct (b)).

### 2. `functions/src/callables/leaveGroup.ts` — succession branch in the existing tx

Inside the final transaction, after the `freshIsMember`/`freshMemberDocsSnap` reads and the `alreadyLeft` early-return (:167-170), **before any write**:

```ts
        // #1138: creator succession. leaveGroup never reassigned createdBy, so
        // a creator leave produced an admin-less group (#1132 closed the
        // security half and deliberately opened this availability half).
        // Mirror deleteAccount Phase C: hand createdBy to the oldest real
        // remaining member; when none survives, tombstone createdBy and
        // soft-delete the group (a creator leaving an otherwise-empty group).
        // Succession is a PERMANENT handoff — a rejoining ex-creator comes
        // back as a plain MEMBER.
        const isCreatorLeave = freshGroup.createdBy === uid;
        let successorUid: string | null = null;
        let successorDocIds: string[] = [];
        if (isCreatorLeave) {
          const membersSnap = await tx.get(groupRef.collection('members'));
          const members = membersSnap.docs.map((d) => ({ id: d.id, data: d.data() }));
          successorUid = oldestRealMemberUid(members, uid, freshMemberIds);
          successorDocIds = members
            .filter((m) => m.data.userId === successorUid)
            .map((m) => m.id);
        }
```

The group update (:178-183) folds in the succession fields, and the successor's member doc(s) — matched by `userId` FIELD, all legacy duplicates — get the role flip:

```ts
        const now = Timestamp.now();
        const groupUpdate: DocumentData = {
          memberIds: FieldValue.arrayRemove(uid),
          updatedAt: now,
          // #1144: release the lock atomically with the mutation.
          ...departureLockClearFields(),
        };
        if (isCreatorLeave) {
          if (successorUid != null) {
            groupUpdate.createdBy = successorUid;
          } else {
            groupUpdate.createdBy = deletedUserSentinel;
            groupUpdate.isDeleted = true;
            groupUpdate.deletedAt = now;
          }
        }
        tx.update(groupRef, groupUpdate);
        // #1138: the roster badge reads member.role (a derived display surface,
        // group_members_section.dart) — keep it truthful in the same tx.
        for (const docId of successorDocIds) {
          tx.update(groupRef.collection('members').doc(docId), { role: 'CREATOR' });
        }
```

Imports: add `oldestRealMemberUid, deletedUserSentinel` from `./shared/membership`; add `DocumentData` type import from `firebase-admin/firestore`.

Everything else in the tx (leaver doc deletes, activity row, lock assert/clear) is untouched. The full-members read happens ONLY on a creator leave (no extra reads for the common member leave), and Firestore tx ordering (reads before writes) is respected.

### 3. `deleteAccount.ts` Phase C — successor role flip (parity)

In the Phase C tx, after `tx.update(groupRef, groupUpdate)` (:763) — same read-path argument, same one-liner:

```ts
    if (gData.createdBy === uid && hasRealSurvivor) {
      for (const m of members.filter((mm) => mm.data.userId === remainingRealCreator)) {
        tx.update(groupRef.collection('members').doc(m.id), { role: 'CREATOR' });
      }
    }
```

(`members` is already in scope from :719; writes may follow the earlier tombstone `tx.set` since all reads are done.)

## Consequences (deliberate, spell them out)

- **Permanent handoff:** an ex-creator who leaves and rejoins is a plain member forever (successor keeps `createdBy`). Intended succession semantics; the reverse (rejoin restores authority) was the #1132 interim behavior, not a contract.
- **Shadow-only / empty group on creator leave → soft-delete.** Shadows may hold non-zero balances *among themselves* (creator-recorded expenses between placeholders); soft-deleting destroys that ledger view. Acceptable: no real user remains to see it, and this exactly mirrors `deleteAccount`'s no-real-survivor branch. The leaver themself is net-zero by the existing balance gate.
- **The new filter conjuncts change `deleteAccount` behavior in two cases:** (1) "only shadows survive" — previously appointed a shadow uuid (admin-less: it never authenticates), now soft-deletes the group (`orphaned: true` in the cascade result); (2) "only a torn doc survives" (real-member doc whose `userId` fell out of `memberIds`) — previously appointed that non-member (admin-less under the #1132 `createdBy ∈ memberIds` rules conjunct), now soft-deletes. Both strictly better; no test pins the old behavior; D1/D3 pin the new.
- **No backfill.** Groups whose creator left pre-#1138 keep their dangling `createdBy` (permanently admin-less if the creator's account is gone). Pre-launch, no real users; a backfill script is not worth building. The `alreadyLeft` idempotent path deliberately does NOT heal them (it returns before the tx).
- **`isDeleted` on the group is the standard soft-delete** every reader already honors (`leaveGroup`/`joinGroupByInviteCode`/`addShadowMember` treat it as not-found; client streams filter it). The `member_left` activity row is still written in the soft-delete branch — harmless, append-only, invisible once the group is gone.
- **Succession does not touch event `participantIds`, expenses, or the balance oracle** — `createdBy` is authz metadata, not a balance input (`recomputeNet` never reads it). No money math changes; no `ledgerRevisionProvider` bump needed (no expense/settlement write).
- Offline-queued interplay unchanged: the whole succession rides inside the existing #1144-locked transaction; contention still surfaces as `aborted`.

## Verification principles report

1. **Callsite classification** — `createdBy` write is OUTBOUND authz metadata; its read-paths are rules gates (`isCreator`, `requesterIsEventAdmin` group branch, `validMemberDelete` creator branch — all #1132-conjuncted, successor passes by construction since successor ∈ memberIds) and client affordance gating (`group.createdBy == uid`, live-watched). `role` write is OUTBOUND to a display-only read (`group_members_section.dart`). No display-formatted string is persisted.
2. **Concrete claims** — every file:line in Verified declarations re-read this session at `58479e4a`, not taken from the issue (the issue's line numbers were stale: helper is at :310, skip at :714, succession at :742).
3. **Read-path per write-path** — `createdBy`: rules gates (`isCreator` :324, `requesterIsEventAdmin` group branch, `validMemberDelete` creator branch), server callable guards (`deleteGroup`/`removeMember`/`addShadowMember`/`decideClaimRequest`/`listGroupClaimRequests`, plus `correctLogicalSettleUp.ts:181` `assertCorrectionActor`), and client derivations (`group_settings_screen.dart:45`, `group_detail_screen.dart:261,1176`, `event_permissions.dart:22`, `settle_up_screen.dart:387`, `group_settle_up_screen.dart:226`) — ALL compare `createdBy` to the CURRENT session/actor uid and are live-watched or per-request, so every one follows the reassignment: authority moves to the successor and away from the departed creator, nowhere does a stale copy persist. `role`: roster badge `group_members_section.dart:163,169`. `isDeleted`/`deletedAt`: quiesce checks in all three membership callables + client stream filters.
4. **Fields from type** — group doc fields touched: `createdBy`, `memberIds`, `updatedAt`, `isDeleted`, `deletedAt`, + lock-clear fields (exactly `deleteAccount` Phase C's set minus the accountDeletion markers). Member doc field touched: `role` (enum `'CREATOR' | 'MEMBER'`, `group_member_model.dart:15`).
5. **Data contracts** — helper signature spelled exactly; both callers pass `(members, departingUid, preDepartureMemberIds)`; sentinel value `'deleted-user'` unchanged (client already renders it as a dead uid — same as post-deleteAccount groups today).
6. **Arithmetic decomposition** — N/A; no money math. The balance gate and `recomputeNet` are untouched.
7. **Orthogonal axes:**
   - **Identity/anon (D6-R):** anon creators are current members; succession works identically for them. A successor may be anon — fine, anon users hold full creator authority today by design.
   - **Shadows:** excluded as successors (the core fix); a CLAIMED shadow (`isShadow: false`, uid-keyed, in memberIds) IS a valid successor — deliberate.
   - **Time:** `joinedAt` ordering with `MAX_SAFE_INTEGER` for garbage — a missing `joinedAt` sorts LAST (not first), matching existing `timestampMillis` semantics.
   - **Race:** succession rides the #1144 departure lock + tx re-reads; leave racing removeMember/decideClaimRequest serializes on the lock and tx conflicts.
   - **Settlements/money:** creator leave still requires leaver net-zero; succession adds no money writes.
   - **#1135 adjacency:** the departed ex-creator still in `participantIds` keeps the LIGHT event edit path — that membership-blind hole is all-participants-shaped, tracked separately, untouched here.

## Out of scope

- Creator-picks-successor / explicit transfer UI (future feature; nothing here blocks it).
- Backfill of pre-#1138 dangling-`createdBy` groups.
- A `creator_changed` activity type (new client rendering surface; `member_left` stays the only row).
- #1135 (departed participants' light event-edit path).
- Client changes of any kind (verified none needed).

---

## Tasks

### Task 1: RED — leaveGroup succession tests

**Files:**
- Modify: `functions/test/callables/leaveGroup.test.ts` (new `describe('#1138 creator succession')` using the existing seed helpers)

**Step 1: Write the failing tests**

Six tests (S1-S6). Seeds use the existing `seedGroup`/`seedMember`; shadow docs seed with `docId: uuid, userId: uuid, isShadow: true` **and the uuid IN `memberIds`** — that is what `addShadowMember` actually writes (`arrayUnion(newId)`, :137-139); seeding the uuid outside `memberIds` would let conjunct (e) mask conjunct (d) and the test would stay green even with the `isShadow` filter deleted (Gate R1 rubric catch — the RED must fail for the right reason).

- **S1 — hand-off:** group `[OWNER, MEMBER]`, both docs seeded. OWNER leaves → `createdBy == MEMBER`, `isDeleted` falsy, MEMBER's member doc `role == 'CREATOR'`, memberIds `[MEMBER]`, `member_left` activity row still written, lock fields absent.
- **S2 — oldest wins:** three members: MEMBER joined `2026-01-02`, `third` joined `2026-01-03`. OWNER leaves → `createdBy == MEMBER` (earlier joinedAt), `third`'s doc role untouched (`'MEMBER'`).
- **S3 — shadow never appointed:** memberIds `[OWNER, MEMBER, shadowUuid]`; shadow joined `2026-01-01` (OLDER than real MEMBER `2026-01-02`), `isShadow: true`. OWNER leaves → `createdBy == MEMBER`, shadow doc role untouched. Pins conjunct (d): the shadow is in memberIds and oldest, so ONLY the `isShadow` filter excludes it.
- **S4 — no real survivor → soft-delete:** memberIds `[OWNER, shadowUuid]` + the unclaimed shadow doc. OWNER leaves → group `isDeleted == true`, `deletedAt` set, `createdBy == 'deleted-user'`, shadow doc still present (mirror deleteAccount: no doc cleanup).
- **S5 — non-creator leave unchanged:** MEMBER leaves → `createdBy == OWNER`, no role flips, no soft-delete.
- **S6 — non-member doc never appointed (defense-in-depth):** survivors = a NON-shadow doc with `userId: 'ghost'` NOT in memberIds (torn state) + MEMBER (in memberIds, later joinedAt). OWNER leaves → `createdBy == MEMBER`. Pins conjunct (e) — the only test that does; keep `isShadow: false` on the ghost doc so (d) can't mask it.

**Step 2: Run to verify they fail**

Run: `cd functions && npm run test:emulator -- leaveGroup.test.ts -t "#1138"`
Expected: S1-S4, S6 FAIL on `createdBy`/`isDeleted` assertions (current code never touches them); S5 PASSES by construction (keep it — it pins the non-creator no-op).

**Step 3: Commit RED**

`test(#1138): RED — creator leave leaves the group admin-less (no succession)` — include the failing output in the commit body per the RED-evidence rule.

### Task 2: RED — deleteAccount shadow-successor tests

**Files:**
- Modify: `functions/test/callables/deleteAccount.test.ts` (alongside the `#294` succession tests at :1148-1244)

**Step 1: Write the failing tests**

- **D1 — shadow-only survivor soft-deletes:** creator-owned group, memberIds `[deletedUid, shadowUuid]` (the shadow uuid IN memberIds, as addShadowMember writes it), one unclaimed shadow member doc. `deleteAccount` → group `isDeleted == true`, `createdBy == 'deleted-user'`, result `groupOrphanedAndSoftDeleted == true`. (Currently RED: shadow uuid gets appointed, group stays live.)
- **D2 — older shadow loses to newer real member:** shadow joinedAt `2026-01-01`, real `otherUid` joinedAt `2026-01-05`, both docs present, memberIds `[deletedUid, otherUid, shadowUuid]`. → `createdBy == otherUid` AND `otherUid`'s doc `role == 'CREATOR'` (role-flip parity; currently RED on both — shadow is oldest AND in memberIds, so only conjunct (d) saves it).
- **D3 — torn real-member doc never appointed:** survivors = a NON-shadow doc `userId: 'ghost'` NOT in memberIds (isShadow: false) and nothing else; memberIds `[deletedUid]`. → group soft-deleted (`isDeleted == true`, `createdBy == 'deleted-user'`). Pins conjunct (e) on the deleteAccount side (Gate R1 adversary P3: only leaveGroup S6 covered the torn case; the behavior change — previously appointed, now soft-deletes — deserves its own pin). Currently RED: ghost gets appointed.

**Step 2: Run to verify they fail**

Run: `cd functions && npm run test:emulator -- deleteAccount.test.ts -t "#1138"`
Expected: D1 FAILS (`isDeleted` false, `createdBy` = shadow uuid), D2 FAILS (`createdBy` = shadow uuid), D3 FAILS (`createdBy` = 'ghost', group stays live).

**Step 3: Commit RED** with failing output in body.

### Task 3: GREEN — shared helper + both succession sites

**Files:**
- Modify: `functions/src/callables/shared/membership.ts` (add sentinel + `timestampMillis` + `oldestRealMemberUid` per Fix shape §1)
- Modify: `functions/src/callables/deleteAccount.ts` (delete locals, import from shared, pass `currentMemberIds`, add role flip per §3)
- Modify: `functions/src/callables/leaveGroup.ts` (succession branch per §2)

**Step 1:** Implement exactly the Fix shape code. **Step 2:** `npm run test:emulator -- leaveGroup.test.ts` then `-- deleteAccount.test.ts` — all green including pre-existing tests (test 9 and `:1190` verified tolerant). **Step 3:** `cd functions && npm run lint && npm run build` clean. **Step 4:** Full emulator suite `npm run test:emulator` (no args). **Step 5:** Commit `fix(#1138): creator succession on leave — reassign createdBy to the oldest real member, never a shadow/non-member`.

### Task 4: Docs truth sweep

**Files:**
- Modify: `docs/CLOUD-FUNCTIONS.md:18` — leaveGroup row gains: "Creator leave hands `createdBy` to the oldest real remaining member and flips their member-doc `role` (none → soft-delete the group) — #1138; succession is a permanent handoff."
- Modify: `CLAUDE.md` Key Invariants #1132 bullet — append: "#1138: `leaveGroup` now does creator succession (oldest real current member, never a shadow/non-member; none → soft-delete), mirroring `deleteAccount` — the handoff is permanent, rejoin does not restore authority."
- Check-and-update-if-stale: `docs/SECURITY-RULES.md` mentions of admin-less/creator authority (grep at execution time).

Commit `docs(#1138): record creator succession semantics`.

### Task 5: Ship

- PR: full-branch diff review (`git diff main...HEAD`), body = summary + test plan + RED evidence + `Spec: docs/plans/2026-07-11-1138-creator-succession-on-leave.md` + `Closes #1138` (in the squash-inherited commit body too).
- Backend deploy: this is a Functions change — after merge it joins the pending-deploy delta (`tool/pending_deploy.sh` / deploy-ceremony); note it in the PR body.
- `/automerge` (Gate-category: `functions/**` → fresh review + refuter).

## Gate record

- **Round 1** (rubric + adversary, fresh Opus contexts): rubric **1 P1 / 0 P2 / 2 P3**, adversary **0 P1 / 1 P2 / 2 P3**.
  - [P1, rubric — CONFIRMED against `addShadowMember.ts:137-139`] The spec claimed shadow uuids are "never in memberIds"; live code `arrayUnion`s them in. The exclusion rationale was inverted (real mechanism: shadows never authenticate) and S3/D1/D2 seeded the shadow OUTSIDE memberIds, so they'd stay green without the `isShadow` conjunct. → Spec rewritten: corrected rationale in Verified declarations + helper doc comment; S3/S4/D1/D2 re-seeded with the shadow uuid IN memberIds. (The adversary's identity-axis trace independently repeated the spec's false claim — the union of two reviewers is what caught it.)
  - [P2, adversary] `timestampMillis` would be an unused import in `deleteAccount.ts` → `noUnusedLocals` build failure. → Import list corrected; `timestampMillis` made module-private in `shared/membership.ts` (also resolves the adversary P3 name-collision with `groupNetBalance.ts`'s different-semantics export).
  - [P3s applied] Verification principle #3 read-path list widened (rubric); deleteAccount torn-member behavior change named in Consequences + new D3 test (adversary).
- **Round 2** (new fresh pair): _pending_
