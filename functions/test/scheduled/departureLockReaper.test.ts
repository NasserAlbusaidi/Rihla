import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';
// #1144: clears lingering departureInProgress locks (leaveGroup/removeMember
// killed after acquire). Nothing to resume — the membership mutation releases
// the lock atomically in its own transaction, so a lingering lock proves the
// mutation never committed and clearing is always safe.
import { departureLockReaper } from '../../src/scheduled/departureLockReaper';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
// onSchedule (v2) matches neither testEnv.wrap overload under strict ts-jest.
const wrapped = testEnv.wrap(departureLockReaper as any);

const OWNER = 'owner';
const MEMBER = 'member';
// Months in the past → comfortably older than the default 1h grace → "stale".
const STALE_LOCKED_AT = new Date('2026-02-01T00:00:00.000Z');

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

const groupData = async (groupId: string) =>
  (await getFirestore().doc(`groups/${groupId}`).get()).data() ?? {};

beforeEach(async () => {
  delete process.env.DEPARTURE_LOCK_REAPER_GRACE_MS;
  delete process.env.DEPARTURE_LOCK_REAPER_BATCH;
  await clearFirestore();
  jest.restoreAllMocks();
  jest.spyOn(logger, 'info').mockImplementation(() => undefined);
  jest.spyOn(logger, 'warn').mockImplementation(() => undefined);
  jest.spyOn(logger, 'error').mockImplementation(() => undefined);
});

afterAll(async () => {
  await clearFirestore();
  testEnv.cleanup();
});

describe('departureLockReaper (#1144)', () => {
  test('clears a stale departure lock; memberIds untouched', async () => {
    await seedGroup('g', {
      departureInProgress: true,
      departureLockedAt: STALE_LOCKED_AT,
      departureLockedBy: MEMBER,
    });

    await wrapped({} as any);

    const g = await groupData('g');
    expect(g.departureInProgress).toBe(false);
    expect(g.departureLockedAt ?? null).toBeNull();
    expect(g.departureLockedBy ?? null).toBeNull();
    expect(g.memberIds).toEqual([OWNER, MEMBER]);
  });

  test('leaves a fresh lock alone (a live invocation may hold it)', async () => {
    const freshLockedAt = new Date();
    await seedGroup('g', {
      departureInProgress: true,
      departureLockedAt: freshLockedAt,
      departureLockedBy: MEMBER,
    });

    await wrapped({} as any);

    const g = await groupData('g');
    expect(g.departureInProgress).toBe(true);
    expect(g.departureLockedBy).toBe(MEMBER);
  });

  test('clears a malformed lock (no timestamp) immediately — unreapable by age otherwise', async () => {
    await seedGroup('g', {
      departureInProgress: true,
      departureLockedBy: MEMBER,
    });

    await wrapped({} as any);

    const g = await groupData('g');
    expect(g.departureInProgress).toBe(false);
    expect(g.departureLockedBy ?? null).toBeNull();
  });

  test('freeze-respect: leaves the lock alone while another cascade holds the group', async () => {
    await seedGroup('g', {
      departureInProgress: true,
      departureLockedAt: STALE_LOCKED_AT,
      departureLockedBy: MEMBER,
      claimingInProgress: true,
    });

    await wrapped({} as any);

    const g = await groupData('g');
    expect(g.departureInProgress).toBe(true);
    expect(g.departureLockedBy).toBe(MEMBER);
  });

  test('untouched groups without the flag are not scanned into mutation', async () => {
    await seedGroup('g', {});

    await wrapped({} as any);

    const g = await groupData('g');
    expect(g.departureInProgress ?? null).toBeNull();
    expect(g.memberIds).toEqual([OWNER, MEMBER]);
  });
});
