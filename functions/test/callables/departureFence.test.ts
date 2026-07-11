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

// #1144: unlike memberRemovalDeleteLockRace (which stubs recomputeNet to an
// empty net), these tests run the REAL oracle — the injection hook fires at
// the recompute call site and then delegates, modelling a balance-input write
// that commits in the gap between the callable's validation and its
// recompute. With the departure fence, the recompute runs UNDER the lock, so
// the injected write is either seen by the recompute (→ zero-gate refusal) or
// could not have been accepted at all (rules/Admin honor checks).
let injectAtRecompute: (groupRef: DocumentReference) => Promise<unknown> =
  async () => undefined;

jest.mock('../../src/callables/groupNetBalance', () => {
  const actual = jest.requireActual('../../src/callables/groupNetBalance');
  return {
    ...actual,
    recomputeNet: jest.fn(async (db: unknown, groupRef: DocumentReference) => {
      await injectAtRecompute(groupRef);
      return actual.recomputeNet(db, groupRef);
    }),
  };
});

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

async function seedEvent(
  groupId: string,
  eventId: string,
  participantIds: string[],
): Promise<void> {
  await getFirestore().doc(`groups/${groupId}/events/${eventId}`).set({
    id: eventId,
    groupId,
    name: eventId,
    type: 'trip',
    createdBy: OWNER,
    participantIds,
    participantNames: Object.fromEntries(participantIds.map((id) => [id, id])),
    modules: { ledger: true },
    isDeleted: false,
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
  });
}

// Equal global split over the event roster: payer +amount, each roster member
// -amount/N — the roster IS the divisor, which is what the roster-add ordering
// test exploits.
async function seedExpense(
  groupId: string,
  eventId: string,
  expenseId: string,
  payer: string,
  amountFils: number,
): Promise<void> {
  await getFirestore()
    .doc(`groups/${groupId}/events/${eventId}/expenses/${expenseId}`)
    .set({
      id: expenseId,
      eventId,
      createdBy: payer,
      payerParticipantId: payer,
      amountFils,
      currency: 'OMR',
      scope: 'global',
      splitMode: 'equally',
      isDeleted: false,
      createdAt: new Date('2026-01-01T00:00:00.000Z').toISOString(),
    });
}

async function seedEventSettlement(
  groupId: string,
  eventId: string,
  settlementId: string,
  payer: string,
  recipient: string,
  amountFils: number,
): Promise<void> {
  await getFirestore()
    .doc(`groups/${groupId}/events/${eventId}/settlements/${settlementId}`)
    .set({
      id: settlementId,
      eventId,
      createdBy: payer,
      payerParticipantId: payer,
      recipientParticipantId: recipient,
      amountFils,
      currency: 'OMR',
      isDeleted: false,
      settledAt: new Date('2026-01-01T00:00:00.000Z').toISOString(),
    });
}

const groupData = async (groupId: string) =>
  (await getFirestore().doc(`groups/${groupId}`).get()).data() ?? {};

const docExists = async (path: string): Promise<boolean> =>
  (await getFirestore().doc(path).get()).exists;

function expectLockCleared(group: Record<string, unknown>): void {
  expect(group.departureInProgress).not.toBe(true);
  expect(group.departureLockedAt ?? null).toBeNull();
  expect(group.departureLockedBy ?? null).toBeNull();
}

const wrappedLeave = () => testEnv.wrap(leaveGroup);
const wrappedRemove = () => testEnv.wrap(removeMember);

beforeEach(async () => {
  await clearFirestore();
  injectAtRecompute = async () => undefined;
  jest.restoreAllMocks();
  jest.spyOn(logger, 'info').mockImplementation(() => undefined);
  jest.spyOn(logger, 'warn').mockImplementation(() => undefined);
  jest.spyOn(logger, 'error').mockImplementation(() => undefined);
});

afterAll(async () => {
  await clearFirestore();
  testEnv.cleanup();
});

describe('#1144 departure fence — zero-check and membership mutation are atomic', () => {
  test('ordering 1: balance write committed BEFORE the call → refused, no mutation, no lingering lock', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1', [OWNER, MEMBER]);
    // owner paid 10.000 OMR equal-global over {owner, member} → member -5.000.
    await seedExpense('g', 'e1', 'x1', OWNER, 10000);

    await expect(
      wrappedLeave()({ data: { groupId: 'g' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
    expectLockCleared(group);
  });

  test('ordering 2 (the #1144-B race): settlement lands in the gap → leave must NOT depart a non-zero member, and the lock must already be engaged at recompute time', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1', [OWNER, MEMBER]);

    let lockSeenAtRecompute: unknown = null;
    injectAtRecompute = async (groupRef) => {
      lockSeenAtRecompute = ((await groupRef.get()).data() ?? {}).departureInProgress;
      // owner→member settlement: member net -5.000 — the leaver is no longer square.
      await seedEventSettlement('g', 'e1', 'raceSet', OWNER, MEMBER, 5000);
    };

    await expect(
      wrappedLeave()({ data: { groupId: 'g' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    expect(lockSeenAtRecompute).toBe(true);
    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
    expectLockCleared(group);
  });

  test('ordering 2, roster-add variant (the issue\'s worked example): adding the leaver to an event roster in the gap redistributes an equal split → refused', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    // member NOT on the roster: owner-only event, owner paid → everyone square.
    await seedEvent('g', 'e1', [OWNER]);
    await seedExpense('g', 'e1', 'x1', OWNER, 10000);

    injectAtRecompute = async () => {
      await getFirestore().doc('groups/g/events/e1').update({
        participantIds: [OWNER, MEMBER],
        participantNames: { owner: 'owner', member: 'member' },
      });
    };

    await expect(
      wrappedLeave()({ data: { groupId: 'g' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER, MEMBER]);
    expectLockCleared(group);
  });

  test('ordering 2, event-undelete variant: restoring a soft-deleted event in the gap re-adds its debt → refused', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1', [OWNER, MEMBER]);
    await seedExpense('g', 'e1', 'x1', OWNER, 10000);
    // e1 starts soft-deleted → its member -5.000 is OUT of the basis.
    await getFirestore().doc('groups/g/events/e1').update({
      isDeleted: true,
      deletedAt: new Date('2026-01-03T00:00:00.000Z'),
    });

    injectAtRecompute = async () => {
      await getFirestore().doc('groups/g/events/e1').update({
        isDeleted: false,
        deletedAt: null,
      });
    };

    await expect(
      wrappedLeave()({ data: { groupId: 'g' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER, MEMBER]);
    expectLockCleared(group);
  });

  test('removeMember, ordering 2: settlement lands in the gap → target must NOT be removed non-zero; lock engaged at recompute time', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1', [OWNER, MEMBER]);

    let lockSeenAtRecompute: unknown = null;
    injectAtRecompute = async (groupRef) => {
      lockSeenAtRecompute = ((await groupRef.get()).data() ?? {}).departureInProgress;
      await seedEventSettlement('g', 'e1', 'raceSet', OWNER, MEMBER, 5000);
    };

    await expect(
      wrappedRemove()({
        data: { groupId: 'g', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    expect(lockSeenAtRecompute).toBe(true);
    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
    expectLockCleared(group);
  });
});

describe('#1144 departure lock lifecycle', () => {
  test('successful leave clears the lock atomically with the mutation', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);

    const result = await wrappedLeave()({
      data: { groupId: 'g' },
      auth: { uid: MEMBER },
    } as any);
    expect(result).toMatchObject({ alreadyLeft: false });

    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER]);
    expect(await docExists('groups/g/members/member')).toBe(false);
    expectLockCleared(group);
  });

  test('recompute throwing still clears the lock', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    injectAtRecompute = async () => {
      throw new Error('synthetic oracle failure');
    };

    await expect(
      wrappedLeave()({ data: { groupId: 'g' }, auth: { uid: MEMBER } } as any),
    ).rejects.toBeTruthy();

    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER, MEMBER]);
    expectLockCleared(group);
  });

  test('mutual exclusion: leaveGroup while a departure lock is held → aborted (NOT failed-precondition — the client maps that to the settle-up snackbar), no mutation, peer lock untouched', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    const peerLockedAt = new Date('2026-06-25T00:00:00.000Z');
    await getFirestore().doc('groups/g').update({
      departureInProgress: true,
      departureLockedAt: peerLockedAt,
      departureLockedBy: OWNER,
    });

    await expect(
      wrappedLeave()({ data: { groupId: 'g' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'aborted' });

    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER, MEMBER]);
    expect(group.departureInProgress).toBe(true);
    expect((group.departureLockedAt as { toMillis(): number }).toMillis())
      .toBe(peerLockedAt.getTime());
    expect(group.departureLockedBy).toBe(OWNER);
  });

  test('mutual exclusion: removeMember while a departure lock is held → aborted, no mutation', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await getFirestore().doc('groups/g').update({
      departureInProgress: true,
      departureLockedAt: new Date('2026-06-25T00:00:00.000Z'),
      departureLockedBy: MEMBER,
    });

    await expect(
      wrappedRemove()({
        data: { groupId: 'g', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'aborted' });

    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
  });

  test('lock reaped mid-flight: final transaction aborts rather than departing on a stale basis', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    // Simulate the reaper (or a peer reclaim) clearing OUR lock between
    // recompute and the mutation transaction.
    injectAtRecompute = async (groupRef) => {
      await groupRef.update({
        departureInProgress: false,
        departureLockedAt: null,
        departureLockedBy: null,
      });
    };

    await expect(
      wrappedLeave()({ data: { groupId: 'g' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'aborted' });

    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
  });
});
