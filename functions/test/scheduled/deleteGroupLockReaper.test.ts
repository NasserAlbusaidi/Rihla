import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';
// RED until functions/src/scheduled/deleteGroupLockReaper.ts exists (#519). The
// reaper resumes the SHARED idempotent finalizeGroupDeletion for stale
// deleteGroup locks (deletingInProgress:true past the grace window): settled →
// completes the soft-delete; unsettled → clears the lock so the group is usable
// again. Money-safe: it never bumps deleteLockedAt, so recomputeNet's resume
// horizon (groupNetBalance.ts:518) still re-includes a partially flushed cascade.
import { deleteGroupLockReaper } from '../../src/scheduled/deleteGroupLockReaper';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
// onSchedule (v2) matches neither testEnv.wrap overload under strict ts-jest.
const wrapped = testEnv.wrap(deleteGroupLockReaper as any);

const OWNER = 'owner';
const MEMBER = 'member';
// Months in the past → comfortably older than the default 1h grace → "stale".
const STALE_LOCKED_AT = new Date('2026-02-01T00:00:00.000Z');

async function clearAll(): Promise<void> {
  await clearFirestore();
}

async function seedGroup(groupId: string, data: Record<string, unknown> = {}): Promise<void> {
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
    displayName: uid,
    role: uid === OWNER ? 'CREATOR' : 'MEMBER',
    joinedAt: new Date('2026-01-01T00:00:00.000Z'),
    isShadow: false,
    isTombstone: false,
  });
}

async function seedEvent(groupId: string, eventId: string, data: Record<string, unknown> = {}): Promise<void> {
  await getFirestore().doc(`groups/${groupId}/events/${eventId}`).set({
    id: eventId,
    groupId,
    name: eventId,
    type: 'trip',
    createdBy: OWNER,
    participantIds: [OWNER, MEMBER],
    participantNames: { [OWNER]: 'Owner', [MEMBER]: 'Member' },
    modules: { ledger: true },
    isDeleted: false,
    deletedAt: null,
    createdAt: new Date('2026-01-04T00:00:00.000Z'),
    ...data,
  });
}

async function seedExpense(path: string, data: Record<string, unknown> = {}): Promise<void> {
  await getFirestore().doc(path).set({
    id: path.split('/').pop(),
    eventId: path.split('/')[3],
    createdBy: OWNER,
    payerParticipantId: OWNER,
    amountFils: 12000,
    currency: 'OMR',
    description: 'expense',
    scope: 'global',
    customSplitParticipants: [],
    splitMode: 'equally',
    splitDistribution: {},
    isDeleted: false,
    deletedAt: null,
    createdAt: '2026-01-06T00:00:00.000Z',
    ...data,
  });
}

async function seedGroupSettlement(groupId: string, docId: string, data: Record<string, unknown> = {}): Promise<void> {
  await getFirestore().doc(`groups/${groupId}/settlements/${docId}`).set({
    id: docId,
    groupId,
    eventId: groupId, // group-scope sentinel
    scope: 'group',
    createdBy: MEMBER,
    payerParticipantId: MEMBER,
    recipientParticipantId: OWNER,
    payerName: 'Member',
    recipientName: 'Owner',
    amountFils: 6000,
    currency: 'OMR',
    note: null,
    isDeleted: false,
    deletedAt: null,
    settledAt: '2026-01-09T00:00:00.000Z',
    ...data,
  });
}

const groupData = async (groupId: string) => (await getFirestore().doc(`groups/${groupId}`).get()).data();

beforeEach(async () => {
  delete process.env.DELETE_GROUP_LOCK_REAPER_GRACE_MS;
  delete process.env.DELETE_GROUP_LOCK_REAPER_BATCH;
  delete process.env.DELETE_GROUP_BATCH_LIMIT;
  await clearAll();
  jest.restoreAllMocks();
  jest.spyOn(logger, 'info').mockImplementation(() => undefined);
  jest.spyOn(logger, 'warn').mockImplementation(() => undefined);
  jest.spyOn(logger, 'error').mockImplementation(() => undefined);
});

afterAll(async () => {
  await clearAll();
  testEnv.cleanup();
});

describe('deleteGroupLockReaper (#519)', () => {
  test('1. stale + settled lock → resumes and completes the soft-delete', async () => {
    await seedGroup('g', {
      deletingInProgress: true,
      deleteLockedAt: STALE_LOCKED_AT,
      deleteLockedBy: OWNER,
    });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    // personal expense paid by OWNER for himself → net zero → settled.
    await seedExpense('groups/g/events/e1/expenses/x1', {
      scope: 'personal',
      payerParticipantId: OWNER,
      amountFils: 1000,
    });

    await wrapped({});

    const group = await groupData('g');
    expect(group?.isDeleted).toBe(true);
    expect(group?.deletingInProgress).toBe(false);
    const event = (await getFirestore().doc('groups/g/events/e1').get()).data();
    expect(event?.isDeleted).toBe(true);
  });

  test('2. stale + settled + PARTIAL cascade → resumes idempotently via the lock horizon', async () => {
    // Mirrors callable test 20: the event was already soft-deleted AFTER the lock
    // (a flushed partial batch). The group is settled ONLY if recomputeNet's
    // resume horizon re-includes that event's debt (else the group settlement
    // makes it look unsettled and the reaper would WRONGLY clear instead of
    // complete — the obs-28986 money-unsafe path).
    const eventDeletedAt = new Date('2026-02-01T00:00:01.000Z'); // after the lock
    await seedGroup('g', {
      deletingInProgress: true,
      deleteLockedAt: STALE_LOCKED_AT,
      deleteLockedBy: OWNER,
    });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1', {
      isDeleted: true,
      deletedAt: eventDeletedAt,
      updatedAt: eventDeletedAt,
    });
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 12000,
      splitMode: 'exact',
      scope: 'custom',
      customSplitParticipants: [OWNER, MEMBER],
      splitDistribution: { [OWNER]: 6000, [MEMBER]: 6000 }, // MEMBER owes OWNER 6000
    });
    await seedGroupSettlement('g', 's1', {
      payerParticipantId: MEMBER,
      recipientParticipantId: OWNER,
      amountFils: 6000, // offsets the e1 debt → net zero WHEN e1 is in scope
    });

    await wrapped({});

    const group = await groupData('g');
    expect(group?.isDeleted).toBe(true);
    expect(group?.deletingInProgress).toBe(false);
  });

  test('3. stale + unsettled lock → clears the lock, group NOT deleted', async () => {
    await seedGroup('g', {
      deletingInProgress: true,
      deleteLockedAt: STALE_LOCKED_AT,
      deleteLockedBy: OWNER,
    });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 12000,
      splitMode: 'exact',
      scope: 'custom',
      customSplitParticipants: [OWNER, MEMBER],
      splitDistribution: { [OWNER]: 6000, [MEMBER]: 6000 }, // unsettled, no offset
    });

    await wrapped({});

    const group = await groupData('g');
    expect(group?.deletingInProgress).toBe(false);
    expect(group?.deleteLockedAt).toBeUndefined();
    expect(group?.deleteLockedBy).toBeUndefined();
    expect(group?.isDeleted).toBe(false); // usable again, not deleted
  });

  test('4. fresh lock (within grace) → untouched', async () => {
    const fresh = new Date();
    await seedGroup('g', {
      deletingInProgress: true,
      deleteLockedAt: fresh,
      deleteLockedBy: OWNER,
    });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);

    await wrapped({});

    const group = await groupData('g');
    expect(group?.deletingInProgress).toBe(true);
    expect(group?.deleteLockedBy).toBe(OWNER);
    expect(group?.isDeleted).toBe(false);
  });

  test('5. no lock → no-op', async () => {
    await seedGroup('g'); // no deletingInProgress
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);

    await wrapped({});

    const group = await groupData('g');
    expect(group?.isDeleted).toBe(false);
    expect(group?.deletingInProgress).toBeUndefined();
  });
});
