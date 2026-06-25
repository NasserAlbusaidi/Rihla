# Issue 663 Delete-Quiesce Lock Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `leaveGroup` and `removeMember` Admin-SDK callables reject soft-deleted or delete-quiesced groups before they mutate membership.

**Architecture:** Mirror the existing `joinGroupByInviteCode`, `addShadowMember`, request-claim, and claim-decision write-lock contract: treat `isDeleted === true` or `deletingInProgress === true` exactly like a missing group and throw `HttpsError('not-found', 'Group not found.')`. The first check runs after the initial group read, but the final `memberIds` / member-doc / activity writes must also run inside a Firestore transaction that re-reads the group immediately before writing; otherwise `deleteGroup` can set `deletingInProgress:true` between the initial read and the final batch commit.

**Tech Stack:** Firebase Cloud Functions v2, TypeScript, Firebase Admin SDK, Firestore/Auth emulator tests, Jest.

---

## Live Code Verification

Commands run while writing this spec:

- `gh issue view 663 --json number,title,state,labels,milestone,body,url,comments`
- `rg -n "leaveGroup|removeMember|deleteGroup|deletingInProgress|isDeleted|deleteLockedAt|addShadowMember|joinGroupByInviteCode" functions/src functions/test security/firestore.rules docs/CLOUD-FUNCTIONS.md docs/SECURITY-RULES.md`
- `nl -ba functions/src/callables/leaveGroup.ts | sed -n '1,220p'`
- `nl -ba functions/src/callables/removeMember.ts | sed -n '1,240p'`
- `nl -ba functions/src/callables/addShadowMember.ts | sed -n '1,140p'`
- `nl -ba functions/src/callables/joinGroupByInviteCode.ts | sed -n '250,300p'`
- `nl -ba security/firestore.rules | sed -n '120,150p'`
- `nl -ba functions/src/callables/groupNetBalance.ts | sed -n '300,350p;720,780p'`
- `RIHLA_AUTH_EMULATOR_PORT=19191 RIHLA_FIRESTORE_EMULATOR_PORT=18181 RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/leaveGroup.test.ts test/callables/removeMember.test.ts" bash tool/run_firebase_emulator_tests.sh`

Findings:

- `functions/src/callables/leaveGroup.ts:56-64` checks only that the group exists, then derives membership from `memberIds`; there is no `isDeleted` or `deletingInProgress` guard before `memberIds` mutation at `leaveGroup.ts:111-130`.
- `functions/src/callables/removeMember.ts:83-95` checks only that the group exists and that `createdBy === request.auth.uid`; there is no `isDeleted` or `deletingInProgress` guard before `memberIds` mutation at `removeMember.ts:160-179`.
- `functions/src/callables/joinGroupByInviteCode.ts:269-278` and `functions/src/callables/addShadowMember.ts:71-76` already reject `isDeleted === true || deletingInProgress === true` with `not-found`, explicitly because Admin SDK writes bypass Firestore rules.
- `functions/src/callables/requestClaimShadow.ts:72-77` and `functions/src/callables/decideClaimRequest.ts:63-65` use the same write-lock pattern for claim-related group writes.
- `security/firestore.rules:134-139` blocks client group writes when `groups/{gid}.isDeleted == true` or `groups/{gid}.deletingInProgress == true`.
- `deleteGroup` sets `deletingInProgress: true`, `deleteLockedAt`, and `deleteLockedBy` before finalize, then leaves `memberIds` intact during final soft-delete (`functions/src/callables/deleteGroup.ts:120-172`, `232-274`).
- `RecomputeResult` has exact fields `net`, `liveEventRefs`, `perEventNet`, and `eventCount` (`functions/src/callables/groupNetBalance.ts:319-347`). The race regression may mock only this boundary because the database is a system boundary and both changed callables read only `net`.
- Existing focused callable suites pass before this change on alternate emulator ports: 2 suites, 27 tests passing. The default Firestore emulator port `18080` was occupied, so baseline used `RIHLA_AUTH_EMULATOR_PORT=19191` and `RIHLA_FIRESTORE_EMULATOR_PORT=18181`.

## Gate Classification

This is a mandatory Gate-category change before implementation because it touches Cloud Functions auth/validation/write authorization. It does not change Firestore rules, money math, routing, or schema, but it changes server-side write eligibility for membership mutation callables that bypass rules.

Run `rihla-run-the-gate` against this file before writing tests or production code. Stop until a fresh-context reviewer returns no [P1] findings.

## Callsite Classification

- OUTBOUND: `functions/src/callables/leaveGroup.ts` callable entry. It writes `groups/{groupId}.memberIds`, deletes `groups/{groupId}/members/*` docs matching `userId == request.auth.uid`, and writes a `groups/{groupId}/activity/*` `member_left` doc.
- OUTBOUND: `functions/src/callables/removeMember.ts` callable entry. It writes `groups/{groupId}.memberIds`, deletes `groups/{groupId}/members/*` docs matching `userId == targetUserId`, and writes a `groups/{groupId}/activity/*` `member_left` doc with removal metadata.
- OUTBOUND but unchanged: `functions/src/callables/deleteGroup.ts` creates and finalizes the delete quiesce state. This plan reads its contract and does not modify it.
- OUTBOUND siblings for parity only: `joinGroupByInviteCode`, `addShadowMember`, `requestClaimShadow`, and `decideClaimRequest` already reject soft-deleted/quiesced groups. This plan does not modify them.
- OUTBOUND but out of scope for #663: `claimShadow` writes `memberIds` and member docs as the approved-claim re-key engine; its callable entry path is guarded by the request/decision callables covered above. This plan does not modify it.
- OUTBOUND but out of scope for #663: `deleteAccount` writes `memberIds`, member docs, and sometimes `createdBy`/soft-delete fields while deleting the caller's own account. This plan reads it only to prove `removeMember` must re-check creator authority at the final write boundary.
- INBOUND: `GroupService.watchUserGroups`, `GroupService.watchGroup`, group settings/member UI, balance aggregator triggers, and activity feed read the group/member/activity docs after these writes. This plan reduces writes during delete windows and does not change data shape.

## Data Contracts

`leaveGroup` output remains:

```ts
export interface LeaveGroupOutput {
  groupId: string;
  mode: 'left';
  alreadyLeft: boolean;
}
```

`removeMember` output remains:

```ts
export interface RemoveMemberOutput {
  groupId: string;
  mode: 'removed';
  alreadyRemoved: boolean;
}
```

Shared validation contract:

```ts
if (group.isDeleted === true || group.deletingInProgress === true) {
  throw new HttpsError('not-found', 'Group not found.');
}
```

Placement is load-bearing:

- In `leaveGroup`, run the first guard immediately after `const group = groupSnap.data() ?? {};` and before deriving `memberIds` or querying member docs.
- In `removeMember`, run the first guard immediately after `const group = groupSnap.data() ?? {};` and before `createdBy` authorization.
- In both callables, replace the final non-transactional `db.batch()` mutation with `db.runTransaction(...)`. Inside that transaction, re-read `groupRef`, re-run the same guard, re-query the relevant member docs, then write `memberIds`, delete member docs, and write activity only if the actor/target is still present.
- In `removeMember`, also re-check `freshGroup.createdBy === uid` inside the final transaction before target/member/activity writes. The initial creator check is stale once `recomputeNet` has awaited; `deleteAccount` can rewrite `createdBy` while the callable is in flight.

Reasons:

- `not-found` matches sibling Admin-SDK membership writers and avoids leaking deleted/quiesced group state.
- The first guard avoids unnecessary member-doc queries and `recomputeNet` work for groups already known to be unavailable.
- The final transaction guard closes the race where `deleteGroup` acquires `deletingInProgress:true` after the first read but before leave/remove commits writes.
- The final `removeMember` creator check closes the race where creator authority changes after the first read but before remove commits writes.
- The guard must run before the idempotent `alreadyLeft` / `alreadyRemoved` short-circuit. Even a fully absent actor must not receive a successful membership-write response for a soft-deleted or quiesced group.
- The final transaction may return `alreadyLeft: true` / `alreadyRemoved: true` if a concurrent leave/remove completed between the first idempotency check and the final transaction. It must not write activity in that case.

No persisted map changes:

- `leaveGroup` still writes only `memberIds: FieldValue.arrayRemove(uid)` and `updatedAt`, deletes matching member docs, and writes the existing `member_left` activity shape on successful live-group leave.
- `removeMember` still writes only `memberIds: FieldValue.arrayRemove(targetUserId)` and `updatedAt`, deletes matching target member docs, and writes the existing `member_left` removal activity shape on successful live-group remove.
- No Cloud Functions exports are added or removed.
- No Firestore rules or indexes are changed.
- No client code is changed.

## Files

- Modify: `functions/test/callables/leaveGroup.test.ts`
  - Add a RED regression proving `leaveGroup` rejects `isDeleted` and `deletingInProgress` groups with `not-found` and performs no membership/activity writes.
- Modify: `functions/src/callables/leaveGroup.ts`
  - Add the first write-lock guard, then move final writes into a transaction with a fresh group re-read and guard.
- Create: `functions/test/callables/memberRemovalDeleteLockRace.test.ts`
  - Add deterministic race regressions by mocking the `recomputeNet` database boundary to flip `deletingInProgress` or `createdBy` after initial validation but before final membership writes.
- Modify: `functions/test/callables/removeMember.test.ts`
  - Add a RED regression proving `removeMember` rejects `isDeleted` and `deletingInProgress` groups with `not-found` and performs no membership/activity writes.
- Modify: `functions/src/callables/removeMember.ts`
  - Add the first write-lock guard, then move final writes into a transaction with a fresh group re-read and guard.

No external docs update is required. `docs/CLOUD-FUNCTIONS.md` already states Admin SDK callables carry their own authorization checks, and this is a parity fix inside existing callable behavior.

## Task 1: RED/GREEN Initial Guard For `leaveGroup`

**Files:**
- Modify: `functions/test/callables/leaveGroup.test.ts`
- Modify: `functions/src/callables/leaveGroup.ts`

- [ ] **Step 1: Add the failing regression**

Add this test after the existing missing-group test:

```ts
  test('3b. soft-deleted OR deletingInProgress group -> not-found; no membership/activity writes', async () => {
    await seedGroup('g1', { isDeleted: true });
    await seedMember('g1', OWNER);
    await seedMember('g1', MEMBER);

    await expect(
      wrapped({ data: { groupId: 'g1' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'not-found' });

    expect((await groupData('g1')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g1/members/member')).toBe(true);
    expect(await activityDocs('g1')).toHaveLength(0);

    await seedGroup('g2', {
      deletingInProgress: true,
      deleteLockedAt: new Date('2026-06-25T00:00:00.000Z'),
      deleteLockedBy: OWNER,
    });
    await seedMember('g2', OWNER);
    await seedMember('g2', MEMBER);

    await expect(
      wrapped({ data: { groupId: 'g2' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'not-found' });

    expect((await groupData('g2')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g2/members/member')).toBe(true);
    expect(await activityDocs('g2')).toHaveLength(0);
  });
```

- [ ] **Step 2: Run RED**

Run:

```bash
RIHLA_AUTH_EMULATOR_PORT=19191 RIHLA_FIRESTORE_EMULATOR_PORT=18181 RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/leaveGroup.test.ts" bash tool/run_firebase_emulator_tests.sh
```

Expected: FAIL. The new test should report a resolved value instead of rejecting with `not-found`.

- [ ] **Step 3: Update the comment and add the first guard**

Replace the top "No lock and no rate-limit" paragraph with:

```ts
// No separate mutation lock and no rate-limit (unlike deleteGroup): leave is a
// single small atomic mutation touching only the leaver's own membership;
// re-entry is bounded upstream by joinGroupByInviteCode's 5/hr throttle. It
// still honors deleteGroup's quiesce marker like every Admin-SDK membership
// writer, because Admin SDK writes bypass firestore.rules. enforceAppCheck is
// the per-actor control (#197).
```

Immediately after `const group = groupSnap.data() ?? {};`, add:

```ts
    // Honor the same write-lock as firestore.rules (Admin SDK bypasses rules),
    // mirroring joinGroupByInviteCode/addShadowMember: soft-deleted or
    // delete-quiesced groups are indistinguishable from missing groups.
    if (group.isDeleted === true || group.deletingInProgress === true) {
      throw new HttpsError('not-found', 'Group not found.');
    }
```

- [ ] **Step 4: Run GREEN**

Run the Step 2 command again.

Expected: PASS.

## Task 2: RED/GREEN Write-Boundary Race For `leaveGroup`

**Files:**
- Create: `functions/test/callables/memberRemovalDeleteLockRace.test.ts`
- Modify: `functions/src/callables/leaveGroup.ts`

- [ ] **Step 1: Create the race test file with the `leaveGroup` regression**

Create `functions/test/callables/memberRemovalDeleteLockRace.test.ts`:

```ts
import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import type { DocumentReference } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';
import { leaveGroup } from '../../src/callables/leaveGroup';
import { removeMember } from '../../src/callables/removeMember';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });

const OWNER = 'owner';
const MEMBER = 'member';

let mockMutateGroup: (groupRef: DocumentReference) => Promise<unknown> =
  async () => undefined;

jest.mock('../../src/callables/groupNetBalance', () => ({
  recomputeNet: jest.fn(async (_db: unknown, groupRef: DocumentReference) => {
    await mockMutateGroup(groupRef);
    return {
      net: new Map(),
      liveEventRefs: [],
      perEventNet: new Map(),
      eventCount: 0,
    };
  }),
}));

async function seedGroup(groupId: string): Promise<void> {
  await getFirestore().doc(`groups/${groupId}`).set({
    id: groupId,
    name: groupId,
    inviteCode: 'ABC123',
    createdBy: OWNER,
    memberIds: [OWNER, MEMBER],
    currency: 'OMR',
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    updatedAt: new Date('2026-01-02T00:00:00.000Z'),
    isDeleted: false,
    deletedAt: null,
  });
}

async function seedMember(groupId: string, uid: string): Promise<void> {
  await getFirestore().doc(`groups/${groupId}/members/${uid}`).set({
    id: uid,
    userId: uid,
    displayName: uid === OWNER ? 'Owner' : 'Member',
    role: uid === OWNER ? 'CREATOR' : 'MEMBER',
    joinedAt: new Date('2026-01-01T00:00:00.000Z'),
    isShadow: false,
    isTombstone: false,
  });
}

const groupData = async (groupId: string) =>
  (await getFirestore().doc(`groups/${groupId}`).get()).data() ?? {};

const docExists = async (path: string): Promise<boolean> =>
  (await getFirestore().doc(path).get()).exists;

async function activityCount(groupId: string): Promise<number> {
  return (await getFirestore().collection(`groups/${groupId}/activity`).get()).size;
}

function callablesWithRecomputeRace(
  mutateGroup: (groupRef: DocumentReference) => Promise<unknown>,
) {
  mockMutateGroup = mutateGroup;
  return {
    leave: testEnv.wrap(leaveGroup),
    remove: testEnv.wrap(removeMember),
  };
}

const flipDeleteLock = (groupRef: DocumentReference) =>
  groupRef.update({
    deletingInProgress: true,
    deleteLockedAt: new Date('2026-06-25T00:00:00.000Z'),
    deleteLockedBy: OWNER,
  });

const flipSoftDeleted = (groupRef: DocumentReference) =>
  groupRef.update({
    isDeleted: true,
    deletedAt: new Date('2026-06-25T00:00:00.000Z'),
  });

const transferCreator = (groupRef: DocumentReference) =>
  groupRef.update({ createdBy: MEMBER });

beforeEach(async () => {
  await clearFirestore();
  mockMutateGroup = async () => undefined;
  jest.restoreAllMocks();
  jest.spyOn(logger, 'info').mockImplementation(() => undefined);
  jest.spyOn(logger, 'warn').mockImplementation(() => undefined);
  jest.spyOn(logger, 'error').mockImplementation(() => undefined);
});

afterAll(async () => {
  await clearFirestore();
  testEnv.cleanup();
});

describe('member removal callables honor delete lock at the final write boundary (#663)', () => {
  test('leaveGroup blocks if deleteGroup quiesces after initial validation but before membership writes', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    const { leave } = await callablesWithRecomputeRace(flipDeleteLock);

    await expect(
      leave({ data: { groupId: 'g' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'not-found' });

    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
    expect(await activityCount('g')).toBe(0);
  });

  test('leaveGroup blocks if group is finalized deleted after initial validation but before membership writes', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    const { leave } = await callablesWithRecomputeRace(flipSoftDeleted);

    await expect(
      leave({ data: { groupId: 'g' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'not-found' });

    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
    expect(await activityCount('g')).toBe(0);
  });
});
```

- [ ] **Step 2: Run RED**

Run:

```bash
RIHLA_AUTH_EMULATOR_PORT=19191 RIHLA_FIRESTORE_EMULATOR_PORT=18181 RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/memberRemovalDeleteLockRace.test.ts" bash tool/run_firebase_emulator_tests.sh
```

Expected: FAIL. The old `leaveGroup` commits the stale batch after mocked `recomputeNet` flips `deletingInProgress:true` or `isDeleted:true`, so the promise resolves and/or membership/activity changes.

- [ ] **Step 3: Move final leave writes into a transaction**

Replace the final `now` / `db.batch()` block in `leaveGroup` with a transaction that re-reads the group and member docs:

```ts
    const mutation = await db.runTransaction(async (tx) => {
      const freshGroupSnap = await tx.get(groupRef);
      if (!freshGroupSnap.exists) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      const freshGroup = freshGroupSnap.data() ?? {};
      if (freshGroup.isDeleted === true || freshGroup.deletingInProgress === true) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      const freshMemberIds: string[] = Array.isArray(freshGroup.memberIds)
        ? freshGroup.memberIds.filter((v): v is string => typeof v === 'string')
        : [];
      const freshMemberDocsSnap = await tx.get(
        groupRef.collection('members').where('userId', '==', uid),
      );
      const freshIsMember = freshMemberIds.includes(uid);
      if (!freshIsMember && freshMemberDocsSnap.empty) {
        return { alreadyLeft: true };
      }
      const freshActorName =
        freshMemberDocsSnap.docs
          .map((d) => d.data().displayName)
          .find((name): name is string => typeof name === 'string' && name.length > 0)
        ?? actorName;

      const now = Timestamp.now();
      tx.update(groupRef, {
        memberIds: FieldValue.arrayRemove(uid),
        updatedAt: now,
      });
      for (const memberDoc of freshMemberDocsSnap.docs) {
        tx.delete(memberDoc.ref);
      }
      const activityRef = groupRef.collection('activity').doc();
      tx.set(activityRef, {
        id: activityRef.id,
        type: 'member_left',
        actorId: uid,
        actorName: freshActorName,
        description: 'left the group',
        metadata: {},
        timestamp: new Date().toISOString(),
      });
      return { alreadyLeft: false };
    });

    if (mutation.alreadyLeft) {
      return { groupId, mode: 'left', alreadyLeft: true };
    }
```

Keep the existing logger and final return for the `alreadyLeft:false` path.

- [ ] **Step 4: Run GREEN**

Run the Step 2 command and then the Task 1 command.

Expected: PASS for both.

## Task 3: RED/GREEN Initial Guard For `removeMember`

**Files:**
- Modify: `functions/test/callables/removeMember.test.ts`
- Modify: `functions/src/callables/removeMember.ts`

- [ ] **Step 1: Add the failing regression**

Add this test after the existing missing-group test:

```ts
  test('5b. soft-deleted OR deletingInProgress group -> not-found; no membership/activity writes', async () => {
    await seedGroup('g1', { isDeleted: true });
    await seedMember('g1', OWNER);
    await seedMember('g1', MEMBER);

    await expect(
      wrapped({
        data: { groupId: 'g1', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'not-found' });

    expect((await groupData('g1')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g1/members/member')).toBe(true);
    expect(await activityDocs('g1')).toHaveLength(0);

    await seedGroup('g2', {
      deletingInProgress: true,
      deleteLockedAt: new Date('2026-06-25T00:00:00.000Z'),
      deleteLockedBy: OWNER,
    });
    await seedMember('g2', OWNER);
    await seedMember('g2', MEMBER);

    await expect(
      wrapped({
        data: { groupId: 'g2', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'not-found' });

    expect((await groupData('g2')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g2/members/member')).toBe(true);
    expect(await activityDocs('g2')).toHaveLength(0);
  });
```

- [ ] **Step 2: Run RED**

Run:

```bash
RIHLA_AUTH_EMULATOR_PORT=19191 RIHLA_FIRESTORE_EMULATOR_PORT=18181 RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/removeMember.test.ts" bash tool/run_firebase_emulator_tests.sh
```

Expected: FAIL. The new test should report a resolved value instead of rejecting with `not-found`.

- [ ] **Step 3: Update the comment and add the first guard**

Replace the top "No lock and no rate-limit" paragraph with:

```ts
// No separate mutation lock and no rate-limit (unlike deleteGroup): remove is a
// single small atomic mutation. It still honors deleteGroup's quiesce marker
// like every Admin-SDK membership writer, because Admin SDK writes bypass
// firestore.rules. enforceAppCheck is the per-actor control (#197).
```

Immediately after `const group = groupSnap.data() ?? {};`, add:

```ts
    // Honor the same write-lock as firestore.rules (Admin SDK bypasses rules),
    // mirroring joinGroupByInviteCode/addShadowMember: soft-deleted or
    // delete-quiesced groups are indistinguishable from missing groups.
    if (group.isDeleted === true || group.deletingInProgress === true) {
      throw new HttpsError('not-found', 'Group not found.');
    }
```

- [ ] **Step 4: Run GREEN**

Run the Step 2 command again.

Expected: PASS.

## Task 4: RED/GREEN Write-Boundary Race For `removeMember`

**Files:**
- Modify: `functions/test/callables/memberRemovalDeleteLockRace.test.ts`
- Modify: `functions/src/callables/removeMember.ts`

- [ ] **Step 1: Add the `removeMember` delete-lock race regression**

Add this test inside the existing `describe`:

```ts
  test('removeMember blocks if deleteGroup quiesces after initial validation but before membership writes', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    const { remove } = await callablesWithRecomputeRace(flipDeleteLock);

    await expect(
      remove({
        data: { groupId: 'g', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'not-found' });

    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
    expect(await activityCount('g')).toBe(0);
  });
```

Then add the finalized-delete variant:

```ts
  test('removeMember blocks if group is finalized deleted after initial validation but before membership writes', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    const { remove } = await callablesWithRecomputeRace(flipSoftDeleted);

    await expect(
      remove({
        data: { groupId: 'g', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'not-found' });

    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
    expect(await activityCount('g')).toBe(0);
  });
```

Then add this second `removeMember` write-boundary regression for stale creator authority:

```ts
  test('removeMember blocks if creator authority changes after initial validation but before membership writes', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    const { remove } = await callablesWithRecomputeRace(transferCreator);

    await expect(
      remove({
        data: { groupId: 'g', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'permission-denied' });

    expect((await groupData('g')).createdBy).toBe(MEMBER);
    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
    expect(await activityCount('g')).toBe(0);
  });
```

- [ ] **Step 2: Run RED**

Run:

```bash
RIHLA_AUTH_EMULATOR_PORT=19191 RIHLA_FIRESTORE_EMULATOR_PORT=18181 RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/memberRemovalDeleteLockRace.test.ts" bash tool/run_firebase_emulator_tests.sh
```

Expected: FAIL for the new remove tests. `leaveGroup` races should already pass from Task 2; old `removeMember` commits the stale batch after mocked `recomputeNet` flips `deletingInProgress:true`, flips `isDeleted:true`, or rewrites `createdBy`.

- [ ] **Step 3: Move final remove writes into a transaction**

Replace the final actor-doc / `now` / `db.batch()` block in `removeMember` with a transaction that re-reads the group, re-checks creator authority, target docs, and actor docs:

```ts
    const mutation = await db.runTransaction(async (tx) => {
      const freshGroupSnap = await tx.get(groupRef);
      if (!freshGroupSnap.exists) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      const freshGroup = freshGroupSnap.data() ?? {};
      if (freshGroup.isDeleted === true || freshGroup.deletingInProgress === true) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      if (freshGroup.createdBy !== uid) {
        throw new HttpsError(
          'permission-denied',
          'Only the group creator can remove a member.',
        );
      }
      const freshMemberIds: string[] = Array.isArray(freshGroup.memberIds)
        ? freshGroup.memberIds.filter((v): v is string => typeof v === 'string')
        : [];
      const freshTargetDocsSnap = await tx.get(
        groupRef.collection('members').where('userId', '==', targetUserId),
      );
      const freshActorDocsSnap = await tx.get(
        groupRef.collection('members').where('userId', '==', uid),
      );
      const freshTargetIsMember = freshMemberIds.includes(targetUserId);
      if (!freshTargetIsMember && freshTargetDocsSnap.empty) {
        return { alreadyRemoved: true };
      }
      const freshTargetName =
        freshTargetDocsSnap.docs
          .map((d) => d.data().displayName)
          .find((name): name is string => typeof name === 'string' && name.length > 0)
        ?? targetName;
      const freshActorName =
        freshActorDocsSnap.docs
          .map((d) => d.data().displayName)
          .find((name): name is string => typeof name === 'string' && name.length > 0)
        ?? 'Someone';

      const now = Timestamp.now();
      tx.update(groupRef, {
        memberIds: FieldValue.arrayRemove(targetUserId),
        updatedAt: now,
      });
      for (const memberDoc of freshTargetDocsSnap.docs) {
        tx.delete(memberDoc.ref);
      }
      const activityRef = groupRef.collection('activity').doc();
      tx.set(activityRef, {
        id: activityRef.id,
        type: 'member_left',
        actorId: uid,
        actorName: freshActorName,
        description: `${freshTargetName} was removed from the group`,
        metadata: { memberAction: 'removed', memberName: freshTargetName },
        timestamp: new Date().toISOString(),
      });
      return { alreadyRemoved: false };
    });

    if (mutation.alreadyRemoved) {
      return { groupId, mode: 'removed', alreadyRemoved: true };
    }
```

Keep the existing logger and final return for the `alreadyRemoved:false` path.

- [ ] **Step 4: Run GREEN**

Run the Step 2 command and then the Task 3 command.

Expected: PASS for both.

## Task 5: Verification And Branch Handoff

**Files:**
- No additional edits.

- [ ] **Step 1: Run the combined callable regression suites**

Run:

```bash
RIHLA_AUTH_EMULATOR_PORT=19191 RIHLA_FIRESTORE_EMULATOR_PORT=18181 RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/leaveGroup.test.ts test/callables/removeMember.test.ts test/callables/memberRemovalDeleteLockRace.test.ts" bash tool/run_firebase_emulator_tests.sh
```

Expected: PASS.

- [ ] **Step 2: Run sibling write-lock suites**

Run:

```bash
RIHLA_AUTH_EMULATOR_PORT=19191 RIHLA_FIRESTORE_EMULATOR_PORT=18181 RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/joinGroupByInviteCode.test.ts test/callables/addShadowMember.test.ts test/callables/claimRequest.test.ts test/callables/claimShadow.test.ts" bash tool/run_firebase_emulator_tests.sh
```

Expected: PASS.

- [ ] **Step 3: Build and lint Functions**

Run:

```bash
npm --prefix functions run build
npm --prefix functions run lint
```

Expected: PASS.

- [ ] **Step 4: Check patch hygiene**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only the planned five files plus this plan doc are modified.

- [ ] **Step 5: Commit**

Run:

```bash
git add docs/plans/2026-06-25-issue-663-delete-quiesce-lock.md \
  functions/src/callables/leaveGroup.ts \
  functions/src/callables/removeMember.ts \
  functions/test/callables/leaveGroup.test.ts \
  functions/test/callables/removeMember.test.ts \
  functions/test/callables/memberRemovalDeleteLockRace.test.ts
git commit -m "fix(functions): honor delete quiesce lock in member removal" -m "Refs #663"
```

Expected: commit succeeds. Use `Refs #663`, not `Closes #663`, unless the PR is intended to close the issue on merge.

## Seven-Point Verification Pass

1. **Callsites classified:** see "Callsite Classification." Both changed callsites are OUTBOUND Admin-SDK writes.
2. **Concrete claims verified against code:** paths and line claims above were checked with `rg` and `nl`; baseline callable tests were run before editing.
3. **Read-path per write-path:** membership writes are read by group/member providers, settings/member UI, balance aggregator triggers, and activity feed. The change blocks writes during delete windows and does not add or change persisted fields.
4. **Fields from type:** no TypeScript interface, Firestore model, or client model fields are added, removed, renamed, or migrated.
5. **Data contracts spelled out:** exact throw code/message, first-check placement, transaction write-boundary placement, and unchanged write maps are defined.
6. **Arithmetic decomposition:** no money arithmetic is changed. Existing `recomputeNet` calls remain untouched and are skipped only when the group is already deleted or delete-quiesced at either validation boundary.
7. **Orthogonal adversarial pass:** the tests are not another non-zero balance case. They exercise the time/lifecycle axis: a zero-net member/target who would otherwise be removable during a concurrent delete lock. Expected behavior is fail-safe `not-found` and no membership/activity writes.
