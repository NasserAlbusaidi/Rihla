import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import { clearFirestore } from '../../fixtures';
import {
  acquireDepartureLock,
  quiesceFreezeError,
} from '../../../src/callables/shared/departureLock';

// RED → GREEN: #1209 + #1211 shared quiesce classifier + the departure lock's
// direct contract enforcement.
//
// `quiesceFreezeError` is the pure terminal-vs-transient decision extracted from
// leaveGroup / removeMember (pre-check + in-tx re-check) and acquireDepartureLock
// so it lives in ONE place. Exhaustive pure coverage here; the callers' thin
// `if (freeze) throw freeze` dispatch is exercised by the callable suites.
//
// `acquireDepartureLock` is directly tested against a seeded flag: the callers'
// pre-checks normally shield its own quiesce split, so a direct call is the only
// way to execute the throw with a live flag (no contrived mid-tx race).
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && npm run test:emulator -- test/callables/shared/departureLock.test.ts`

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });

const OWNER = 'owner';

async function seedGroup(
  groupId: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore().doc(`groups/${groupId}`).set({
    id: groupId,
    name: groupId,
    createdBy: OWNER,
    memberIds: [OWNER],
    currency: 'OMR',
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    updatedAt: new Date('2026-01-02T00:00:00.000Z'),
    isDeleted: false,
    deletedAt: null,
    ...data,
  });
}

beforeEach(async () => {
  await clearFirestore();
});

afterAll(async () => {
  await clearFirestore();
  testEnv.cleanup();
});

describe('quiesceFreezeError — terminal vs transient (#1209/#1211)', () => {
  test('isDeleted → not-found', () => {
    expect(quiesceFreezeError({ isDeleted: true })?.code).toBe('not-found');
  });

  test('deletingInProgress → not-found', () => {
    expect(quiesceFreezeError({ deletingInProgress: true })?.code).toBe('not-found');
  });

  test('claimingInProgress → aborted', () => {
    expect(quiesceFreezeError({ claimingInProgress: true })?.code).toBe('aborted');
  });

  test('accountDeletionInProgress → aborted', () => {
    expect(quiesceFreezeError({ accountDeletionInProgress: true })?.code).toBe('aborted');
  });

  test('departureInProgress is NOT classified here → null (contention handled by acquireDepartureLock)', () => {
    expect(quiesceFreezeError({ departureInProgress: true })).toBeNull();
  });

  test('a writable group → null', () => {
    expect(quiesceFreezeError({})).toBeNull();
    expect(
      quiesceFreezeError({ isDeleted: false, deletingInProgress: false }),
    ).toBeNull();
  });

  test('terminal wins over transient when both are set', () => {
    expect(
      quiesceFreezeError({ isDeleted: true, claimingInProgress: true })?.code,
    ).toBe('not-found');
  });

  test('messages are stable (not-found / aborted)', () => {
    expect(quiesceFreezeError({ isDeleted: true })?.message).toBe('Group not found.');
    expect(quiesceFreezeError({ claimingInProgress: true })?.message).toBe(
      'Another operation is in progress. Try again.',
    );
  });
});

describe('acquireDepartureLock — direct contract enforcement (#1209/#1211)', () => {
  test('claimingInProgress (transient) → throws aborted, no lock taken', async () => {
    await seedGroup('g', { claimingInProgress: true });
    const db = getFirestore();
    await expect(
      acquireDepartureLock(db, db.doc('groups/g'), OWNER),
    ).rejects.toMatchObject({ code: 'aborted' });
    expect((await db.doc('groups/g').get()).data()?.departureInProgress ?? false).toBe(false);
  });

  test('isDeleted (terminal) → throws not-found', async () => {
    await seedGroup('g', { isDeleted: true });
    const db = getFirestore();
    await expect(
      acquireDepartureLock(db, db.doc('groups/g'), OWNER),
    ).rejects.toMatchObject({ code: 'not-found' });
  });

  test('missing group → not-found', async () => {
    const db = getFirestore();
    await expect(
      acquireDepartureLock(db, db.doc('groups/ghost'), OWNER),
    ).rejects.toMatchObject({ code: 'not-found' });
  });

  test('departureInProgress (contention) → throws aborted with its own message', async () => {
    await seedGroup('g', {
      departureInProgress: true,
      departureLockedAt: new Date('2026-06-25T00:00:00.000Z'),
      departureLockedBy: 'peer',
    });
    const db = getFirestore();
    await expect(
      acquireDepartureLock(db, db.doc('groups/g'), OWNER),
    ).rejects.toMatchObject({
      code: 'aborted',
      message: 'Another membership change is in progress. Try again.',
    });
  });

  test('writable group → acquires the lock (departureInProgress set, lockedBy=caller)', async () => {
    await seedGroup('g');
    const db = getFirestore();
    const lock = await acquireDepartureLock(db, db.doc('groups/g'), OWNER);
    expect(lock.lockedBy).toBe(OWNER);
    const group = (await db.doc('groups/g').get()).data();
    expect(group?.departureInProgress).toBe(true);
    expect(group?.departureLockedBy).toBe(OWNER);
  });
});
