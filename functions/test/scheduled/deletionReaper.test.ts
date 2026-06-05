import functionsTest from 'firebase-functions-test';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp, WriteBatch } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';
import { deletionReaper } from '../../src/scheduled/deletionReaper';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
// onSchedule (v2) matches neither testEnv.wrap overload under strict ts-jest;
// the cast is required and runtime-verified to execute the handler body.
const wrapped = testEnv.wrap(deletionReaper as any);

const HOUR = 60 * 60 * 1000;
const targetUid = 'reap-uid';
const otherUid = 'survivor-uid';

async function clearAll(): Promise<void> {
  const db = getFirestore();
  for (const collection of ['deletionAudit', 'fcm_tokens', 'joinAttempts', 'deletionAttempts']) {
    const docs = await db.collection(collection).listDocuments();
    await Promise.all(docs.map((doc) => doc.delete()));
  }
  const auth = getAuth();
  const users = await auth.listUsers(1000);
  await Promise.all(users.users.map((u) => auth.deleteUser(u.uid).catch(() => undefined)));
  await clearFirestore();
}

async function seedAuthUser(uid: string): Promise<void> {
  await getAuth().createUser({ uid, email: `${uid}@example.com`, password: 'Password123!' });
}

async function seedGroupWithMember(gid: string, uid: string): Promise<void> {
  const db = getFirestore();
  await db.doc(`groups/${gid}`).set({
    id: gid,
    name: gid,
    memberIds: [uid, otherUid],
    createdBy: otherUid,
    inviteCode: `${gid}123`.slice(0, 6).toUpperCase(),
    currency: 'OMR',
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    updatedAt: new Date('2026-01-02T00:00:00.000Z'),
    isDeleted: false,
    deletedAt: null,
  });
  await db.doc(`groups/${gid}/members/${uid}`).set({
    id: uid, userId: uid, displayName: 'Reaped Member', role: 'MEMBER',
    joinedAt: new Date('2026-01-01T00:00:00.000Z'), isShadow: false,
  });
  await db.doc(`groups/${gid}/members/${otherUid}`).set({
    id: otherUid, userId: otherUid, displayName: 'Survivor', role: 'CREATOR',
    joinedAt: new Date('2026-01-01T00:00:00.000Z'), isShadow: false,
  });
}

async function seedMarker(uid: string, lastAttemptAtMs: number, attemptCount = 1): Promise<void> {
  await getFirestore().doc(`deletionAudit/${uid}`).set({
    uid,
    status: 'failed',
    cascadeFailed: ['stale-group'],
    firstFailedAt: Timestamp.fromMillis(lastAttemptAtMs),
    lastAttemptAt: Timestamp.fromMillis(lastAttemptAtMs),
    attemptCount,
    expiresAt: Timestamp.fromMillis(lastAttemptAtMs + 30 * 24 * HOUR),
  });
}

beforeEach(async () => {
  delete process.env.DELETION_REAPER_GRACE_MS;
  delete process.env.DELETION_REAPER_BATCH;
  delete process.env.DELETE_ACCOUNT_BATCH_LIMIT;
  await clearAll();
  jest.restoreAllMocks();
  jest.spyOn(logger, 'info').mockImplementation(() => undefined);
  jest.spyOn(logger, 'error').mockImplementation(() => undefined);
  jest.spyOn(logger, 'warn').mockImplementation(() => undefined);
});

afterAll(async () => {
  await clearAll();
  testEnv.cleanup();
});

describe('deletionReaper (#76)', () => {
  test('finishes an abandoned deletion past the grace window', async () => {
    const db = getFirestore();
    await seedAuthUser(targetUid);
    await seedGroupWithMember('g1', targetUid);
    await seedMarker(targetUid, Date.now() - 25 * HOUR); // older than 24h grace

    await wrapped({});

    const memberIds = (await db.doc('groups/g1').get()).data()?.memberIds as string[];
    expect(memberIds).not.toContain(targetUid);
    await expect(getAuth().getUser(targetUid)).rejects.toMatchObject({ code: 'auth/user-not-found' });
    expect((await db.doc(`deletionAudit/${targetUid}`).get()).exists).toBe(false);
  });

  test('does not touch a marker still within the grace window', async () => {
    const db = getFirestore();
    await seedAuthUser(targetUid);
    await seedGroupWithMember('g1', targetUid);
    await seedMarker(targetUid, Date.now()); // fresh — client may still retry

    await wrapped({});

    const memberIds = (await db.doc('groups/g1').get()).data()?.memberIds as string[];
    expect(memberIds).toContain(targetUid);
    await expect(getAuth().getUser(targetUid)).resolves.toMatchObject({ uid: targetUid });
    expect((await db.doc(`deletionAudit/${targetUid}`).get()).exists).toBe(true);
  });

  test('self-heals an orphaned marker whose auth user is already gone', async () => {
    const db = getFirestore();
    // no auth user, no groups — deletion completed but the marker-delete tore.
    await seedMarker(targetUid, Date.now() - 25 * HOUR);

    await expect(wrapped({})).resolves.toBeUndefined();

    expect((await db.doc(`deletionAudit/${targetUid}`).get()).exists).toBe(false);
  });

  test('keeps the marker and increments attemptCount when the cascade re-fails', async () => {
    const db = getFirestore();
    await seedAuthUser(targetUid);
    await seedGroupWithMember('g1', targetUid);
    await db.doc('groups/g1/events/ev').set({
      id: 'ev', groupId: 'g1', name: 'ev', type: 'trip', createdBy: targetUid,
      participantIds: [targetUid, otherUid], participantNames: { [targetUid]: 'Reaped Member' },
      modules: { ledger: true }, isDeleted: false,
      createdAt: new Date('2026-01-04T00:00:00.000Z'), updatedAt: new Date('2026-01-05T00:00:00.000Z'),
    });
    await db.doc('groups/g1/events/ev/expenses/e1').set({
      id: 'e1', createdBy: targetUid, payerParticipantId: targetUid, amountFils: 1000,
      currency: 'OMR', scope: 'custom', splitMode: 'exact',
      customSplitParticipants: [targetUid, otherUid], splitDistribution: { [targetUid]: 500, [otherUid]: 500 },
      description: 'x', note: 'n', receiptUrl: 'r', isDeleted: false, deletedAt: null,
      createdAt: '2026-01-06T00:00:00.000Z',
    });
    await seedMarker(targetUid, Date.now() - 25 * HOUR, 1);

    const realCommit = WriteBatch.prototype.commit;
    let commits = 0;
    jest.spyOn(WriteBatch.prototype, 'commit').mockImplementation(function (this: WriteBatch) {
      commits += 1;
      if (commits === 1) return Promise.reject(new Error('forced phase-B failure'));
      return realCommit.apply(this);
    });

    await wrapped({});

    const marker = (await db.doc(`deletionAudit/${targetUid}`).get()).data();
    expect(marker?.attemptCount).toBe(2);
    await expect(getAuth().getUser(targetUid)).resolves.toMatchObject({ uid: targetUid });
  });

  test('bounds work to DELETION_REAPER_BATCH per run', async () => {
    const db = getFirestore();
    process.env.DELETION_REAPER_BATCH = '1';
    await seedAuthUser('reap-a');
    await seedAuthUser('reap-b');
    await seedMarker('reap-a', Date.now() - 25 * HOUR);
    await seedMarker('reap-b', Date.now() - 26 * HOUR);

    await wrapped({});

    const remaining = await db.collection('deletionAudit').listDocuments();
    expect(remaining).toHaveLength(1); // exactly one processed (deleted) per run
  });
});
