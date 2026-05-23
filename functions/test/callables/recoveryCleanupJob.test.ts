import functionsTest from 'firebase-functions-test';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';
import {
  advanceRecoveryCleanupJob,
  claimRecoveryCleanupJob,
} from '../../src/callables/recoveryCleanupJob';
import { AccountJobStatusOutput } from '../../src/accountJobs/types';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrappedClaim = testEnv.wrap(claimRecoveryCleanupJob);
const wrappedAdvance = testEnv.wrap(advanceRecoveryCleanupJob);

const oldUid = 'old-anon-uid';
const newUid = 'new-uid';
const cleanupSecret = 'test-cleanup-secret-with-enough-entropy-12345';

async function clearAuthUsers(): Promise<void> {
  const auth = getAuth();
  const users = await auth.listUsers(1000);
  await Promise.all(
    users.users.map((user) => auth.deleteUser(user.uid).catch(() => undefined)),
  );
}

async function clearGlobalDocs(): Promise<void> {
  const db = getFirestore();
  for (const collection of [
    'fcm_tokens',
    'joinAttempts',
    'recoveryCleanupJobs',
  ]) {
    const docs = await db.collection(collection).listDocuments();
    await Promise.all(docs.map((doc) => doc.delete()));
  }
}

async function seedAuthUsers(): Promise<void> {
  await getAuth().createUser({ uid: oldUid });
  await getAuth().createUser({
    uid: newUid,
    email: `${newUid}@example.com`,
    password: 'Password123!',
  });
}

async function seedCleanupIntent(): Promise<void> {
  await getFirestore().doc(`recoveryCleanupIntents/${oldUid}`).set({
    secret: cleanupSecret,
    createdAt: new Date(),
  });
}

async function seedGroup(
  groupId: string,
  memberIds: string[],
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore()
    .doc(`groups/${groupId}`)
    .set({
      id: groupId,
      name: groupId,
      memberIds,
      createdBy: memberIds[0],
      currency: 'OMR',
      createdAt: new Date('2026-01-01T00:00:00.000Z'),
      updatedAt: new Date('2026-01-02T00:00:00.000Z'),
      ...data,
    });
}

async function seedMember(
  groupId: string,
  uid: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore()
    .doc(`groups/${groupId}/members/${uid}`)
    .set({
      id: uid,
      userId: uid,
      displayName: uid,
      role: 'MEMBER',
      joinedAt: new Date('2026-01-01T00:00:00.000Z'),
      isShadow: false,
      ...data,
    });
}

async function seedEvent(
  groupId: string,
  eventId: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore()
    .doc(`groups/${groupId}/events/${eventId}`)
    .set({
      id: eventId,
      groupId,
      name: eventId,
      type: 'trip',
      createdBy: oldUid,
      participantIds: [oldUid],
      participantNames: { [oldUid]: 'Old Name' },
      modules: { ledger: true },
      isDeleted: false,
      createdAt: new Date('2026-01-03T00:00:00.000Z'),
      updatedAt: new Date('2026-01-04T00:00:00.000Z'),
      ...data,
    });
}

function emptyCounters(): Record<string, number> {
  return {
    groupsProcessed: 0,
    groupsFailed: 0,
    membersRewritten: 0,
    eventsRewritten: 0,
    expensesRewritten: 0,
    settlementsRewritten: 0,
    activityLogsRewritten: 0,
  };
}

function claim(): Promise<AccountJobStatusOutput> {
  return wrappedClaim({
    data: { oldUid, cleanupSecret },
    auth: { uid: newUid },
  } as any) as unknown as Promise<AccountJobStatusOutput>;
}

function advance(jobId = oldUid): Promise<AccountJobStatusOutput> {
  return wrappedAdvance({
    data: { jobId },
    auth: { uid: newUid },
  } as any) as unknown as Promise<AccountJobStatusOutput>;
}

beforeEach(async () => {
  await clearFirestore();
  await clearGlobalDocs();
  await clearAuthUsers();
  jest.restoreAllMocks();
  jest.spyOn(logger, 'info').mockImplementation(() => undefined);
  jest.spyOn(logger, 'error').mockImplementation(() => undefined);
});

afterAll(async () => {
  await clearFirestore();
  await clearGlobalDocs();
  await clearAuthUsers();
  testEnv.cleanup();
});

describe('recovery cleanup job', () => {
  test('failed group cleanup preserves membership and can retry after data is fixed', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', [oldUid], { createdBy: oldUid });
    await seedMember('g1', oldUid);
    await seedEvent('g1', 'e1');
    await db.doc('groups/g1/events/e1/activity_logs/bad').set({
      id: 'bad',
      actorId: oldUid,
      metadata: { actors: [oldUid, { uid: 'other' }] },
      createdAt: new Date('2026-01-05T00:00:00.000Z'),
    });

    await expect(claim()).resolves.toMatchObject({
      status: 'running',
      current: 0,
      total: 1,
    });
    await expect(advance()).resolves.toMatchObject({
      status: 'failed',
      retryable: true,
      current: 0,
      total: 1,
    });

    expect((await db.doc('groups/g1').get()).data()?.memberIds).toEqual([
      oldUid,
    ]);
    expect((await db.doc(`groups/g1/members/${oldUid}`).get()).exists).toBe(
      true,
    );
    expect((await db.doc(`groups/g1/members/${newUid}`).get()).exists).toBe(
      false,
    );
    await expect(getAuth().getUser(oldUid)).resolves.toMatchObject({
      uid: oldUid,
    });

    await db.doc('groups/g1/events/e1/activity_logs/bad').update({
      metadata: {
        actorId: oldUid,
        actors: [oldUid, 'owner'],
        requestId: oldUid,
      },
    });

    await expect(advance()).resolves.toMatchObject({
      status: 'running',
      current: 1,
      total: 1,
    });
    await expect(advance()).resolves.toMatchObject({
      status: 'complete',
      current: 1,
      total: 1,
    });

    const group = await db.doc('groups/g1').get();
    const activity = await db.doc('groups/g1/events/e1/activity_logs/bad').get();
    expect(group.data()?.memberIds).toEqual([newUid]);
    expect(activity.data()?.actorId).toBe(newUid);
    expect(activity.data()?.metadata).toMatchObject({
      actorId: newUid,
      actors: [newUid, 'owner'],
      requestId: oldUid,
    });
    await expect(getAuth().getUser(oldUid)).rejects.toMatchObject({
      code: 'auth/user-not-found',
    });
  });

  test('retry processes stranded rows after membership already points at newUid', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedGroup('g1', [newUid], { createdBy: newUid });
    await seedMember('g1', newUid);
    await seedEvent('g1', 'e1', {
      createdBy: newUid,
      participantIds: [newUid],
      participantNames: { [newUid]: 'New Name' },
    });
    await db.doc('groups/g1/events/e1/expenses/x1').set({
      id: 'x1',
      createdBy: oldUid,
      payerParticipantId: oldUid,
      customSplitParticipants: [oldUid, newUid],
      splitDistribution: { [oldUid]: 6000, [newUid]: 6000 },
      createdAt: new Date('2026-01-05T00:00:00.000Z'),
    });
    await db.doc(`recoveryCleanupJobs/${oldUid}`).set({
      kind: 'recoveryCleanup',
      oldUid,
      newUid,
      secretHash: 'not-used-after-claim',
      status: 'failed',
      phase: 'Group g1 failed',
      groupIds: ['g1'],
      cursorIndex: 0,
      retryable: true,
      errorCode: 'previous-failure',
      counters: emptyCounters(),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    await expect(advance()).resolves.toMatchObject({
      status: 'running',
      current: 1,
      total: 1,
      counters: expect.objectContaining({ expensesRewritten: 1 }),
    });

    const expense = await db.doc('groups/g1/events/e1/expenses/x1').get();
    expect(expense.data()).toMatchObject({
      createdBy: newUid,
      payerParticipantId: newUid,
      customSplitParticipants: [newUid],
      splitDistribution: { [newUid]: 6000 },
    });
  });

  test('large event expense collections are processed across multiple pages', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', [oldUid]);
    await seedMember('g1', oldUid);
    await seedEvent('g1', 'e1');

    let batch = db.batch();
    let writes = 0;
    for (let index = 0; index < 520; index += 1) {
      batch.set(db.doc(`groups/g1/events/e1/expenses/x${index}`), {
        id: `x${index}`,
        createdBy: oldUid,
        payerParticipantId: oldUid,
        amountFils: 1000,
        currency: 'OMR',
        createdAt: new Date('2026-01-05T00:00:00.000Z'),
      });
      writes += 1;
      if (writes === 400) {
        await batch.commit();
        batch = db.batch();
        writes = 0;
      }
    }
    if (writes > 0) {
      await batch.commit();
    }

    await claim();
    await expect(advance()).resolves.toMatchObject({
      status: 'running',
      current: 1,
      total: 1,
      counters: expect.objectContaining({ expensesRewritten: 520 }),
    });

    const first = await db.doc('groups/g1/events/e1/expenses/x0').get();
    const last = await db.doc('groups/g1/events/e1/expenses/x519').get();
    expect(first.data()).toMatchObject({
      createdBy: newUid,
      payerParticipantId: newUid,
    });
    expect(last.data()).toMatchObject({
      createdBy: newUid,
      payerParticipantId: newUid,
    });
  });
});
