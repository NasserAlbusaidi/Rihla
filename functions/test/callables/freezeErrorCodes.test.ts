import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';

// RED → GREEN: #1209 + #1211 transient-freeze error-code contract.
//
// leaveGroup / removeMember / deleteGroup must surface a TRANSIENT freeze — a
// bounded concurrent operation (claim / account-deletion / another departure)
// after which the group lives on and the caller is still a member — as
// `aborted`, the code the client maps to the retry-inviting "membership change
// in progress" copy. A TERMINAL freeze (the group is GONE: isDeleted, or a
// delete in flight) stays `not-found`, which the client treats as "nothing to
// do, go home". Pre-fix the transient flags threw `not-found` on leave/remove
// (silent leave-success while still a member — #1211) and `failed-precondition`
// on deleteGroup (the settle-up snackbar on a possibly-settled group — #1209).
// See shared/departureLock.ts contract comment for the full split.
//
// Table-driven per the money/legal rule (this IS the error-code contract).
//
// Coverage note: these rows exercise the PRE-check sites (leaveGroup :86,
// removeMember :108, deleteGroup :161) and — for the departureInProgress rows on
// leave/remove — acquireDepartureLock's own contention branch. The in-tx
// re-check sites (leaveGroup :174, removeMember :207) and acquireDepartureLock's
// four-flag terminal/transient split (departureLock :49-56, shielded by the
// callers' pre-checks) apply the SAME one-line split in the SAME diff and are
// unreachable by a pre-seeded flag (they need a flag to appear mid-transaction);
// they are covered by code review, not a contrived mid-tx injection.
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && npm run test:emulator -- freezeErrorCodes.test.ts`

import { deleteGroup } from '../../src/callables/deleteGroup';
import { leaveGroup } from '../../src/callables/leaveGroup';
import { removeMember } from '../../src/callables/removeMember';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrappedLeave = testEnv.wrap(leaveGroup);
const wrappedRemove = testEnv.wrap(removeMember);
const wrappedDelete = testEnv.wrap(deleteGroup);

const OWNER = 'owner';
const MEMBER = 'member';

async function seedGroup(
  groupId: string,
  data: Record<string, unknown> = {},
): Promise<void> {
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
    ...data,
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

// deleteGroup's flag check sits behind the creator+current-member gate, so
// every callable is seeded with OWNER as creator+member and MEMBER as the
// second member (the leaver / removal target).
async function seedRoster(groupId: string, groupData: Record<string, unknown>): Promise<void> {
  await seedGroup(groupId, groupData);
  await seedMember(groupId, OWNER);
  await seedMember(groupId, MEMBER);
}

interface CallableUnderTest {
  name: string;
  // The uid seeded as creator+member (OWNER) invokes deleteGroup/removeMember;
  // the plain MEMBER invokes leaveGroup on themselves.
  invoke: (groupId: string) => Promise<unknown>;
}

const CALLABLES: CallableUnderTest[] = [
  {
    name: 'leaveGroup',
    invoke: (groupId) =>
      wrappedLeave({ data: { groupId }, auth: { uid: MEMBER } } as any),
  },
  {
    name: 'removeMember',
    invoke: (groupId) =>
      wrappedRemove({
        data: { groupId, targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
  },
  {
    name: 'deleteGroup',
    invoke: (groupId) =>
      wrappedDelete({ data: { groupId }, auth: { uid: OWNER } } as any),
  },
];

async function clearGlobalDocs(): Promise<void> {
  const db = getFirestore();
  for (const collection of ['deleteGroupAttempts', 'deletionAttempts']) {
    const docs = await db.collection(collection).listDocuments();
    await Promise.all(docs.map((doc) => doc.delete()));
  }
}

beforeEach(async () => {
  await clearFirestore();
  await clearGlobalDocs();
  jest.restoreAllMocks();
  jest.spyOn(logger, 'info').mockImplementation(() => undefined);
  jest.spyOn(logger, 'warn').mockImplementation(() => undefined);
  jest.spyOn(logger, 'error').mockImplementation(() => undefined);
});

afterAll(async () => {
  await clearFirestore();
  await clearGlobalDocs();
  testEnv.cleanup();
});

describe('transient-freeze error-code contract (#1209/#1211)', () => {
  // A concurrent claim or account-deletion is a bounded operation after which
  // the group survives and the caller stays a member ⇒ `aborted` (retry), NOT
  // `not-found` (silent leave, #1211) and NOT `failed-precondition` (settle-up
  // snackbar on a settled group, #1209).
  const TRANSIENT_FLAGS = [
    'claimingInProgress',
    'accountDeletionInProgress',
  ] as const;

  for (const callable of CALLABLES) {
    for (const flag of TRANSIENT_FLAGS) {
      test(`${callable.name} × ${flag} → aborted`, async () => {
        await seedRoster('g', { [flag]: true });
        await expect(callable.invoke('g')).rejects.toMatchObject({
          code: 'aborted',
        });
      });
    }
  }

  // departureInProgress: a peer leave/remove is in flight. deleteGroup's
  // pre-check throws it directly (RED pre-fix: failed-precondition). For
  // leave/remove the pre-check does NOT list departureInProgress; they fall
  // through to acquireDepartureLock, whose contention branch was ALREADY
  // `aborted` (GREEN pin, unchanged by this PR).
  for (const callable of CALLABLES) {
    test(`${callable.name} × departureInProgress → aborted`, async () => {
      await seedRoster('g', {
        departureInProgress: true,
        departureLockedAt: new Date('2026-06-25T00:00:00.000Z'),
        departureLockedBy: 'someone-else',
      });
      await expect(callable.invoke('g')).rejects.toMatchObject({
        code: 'aborted',
      });
    });
  }
});

describe('terminal-freeze error-code contract (leaveGroup/removeMember)', () => {
  // The group is GONE (soft-deleted) or being deleted (ends in gone) ⇒
  // `not-found`. Pins the KEEP side of the split. deleteGroup is EXCLUDED: its
  // isDeleted branch is a SUCCESS response (alreadyDeleted:true) and its
  // deletingInProgress branch is the #519/#529 concurrent-observer path — both
  // pinned by deleteGroup.test.ts (tests 16 / 20 / observer), untouched here.
  const TERMINAL_FLAGS = ['isDeleted', 'deletingInProgress'] as const;
  const LEAVE_REMOVE = CALLABLES.filter((c) => c.name !== 'deleteGroup');

  for (const callable of LEAVE_REMOVE) {
    for (const flag of TERMINAL_FLAGS) {
      test(`${callable.name} × ${flag} → not-found`, async () => {
        const groupData =
          flag === 'deletingInProgress'
            ? {
                deletingInProgress: true,
                deleteLockedAt: new Date('2026-06-25T00:00:00.000Z'),
                deleteLockedBy: OWNER,
              }
            : { isDeleted: true };
        await seedRoster('g', groupData);
        await expect(callable.invoke('g')).rejects.toMatchObject({
          code: 'not-found',
        });
      });
    }
  }
});

describe('deleteGroup malformed-lock error-code contract (#1209)', () => {
  // A delete lock with a missing timestamp is a transient malformed state the
  // owner clears and retries ⇒ `aborted` (RED pre-fix: failed-precondition,
  // rendered by the client as the settle-up snackbar). Mirrors deleteGroup.test
  // 20b, isolated here as the error-code assertion.
  test('deleteGroup observed lock missing its timestamp → aborted', async () => {
    await seedRoster('g', {
      deletingInProgress: true,
      deleteLockedBy: OWNER,
      // deleteLockedAt intentionally ABSENT → the malformed-observed-lock path.
    });
    await expect(
      wrappedDelete({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'aborted' });
  });
});
