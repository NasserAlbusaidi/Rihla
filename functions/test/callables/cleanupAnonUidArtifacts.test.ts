import functionsTest from 'firebase-functions-test';
import { getAuth } from 'firebase-admin/auth';
import { DocumentReference, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';
import { cleanupAnonUidArtifacts } from '../../src/callables/cleanupAnonUidArtifacts';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(cleanupAnonUidArtifacts);
const cleanupSecret = 'test-cleanup-secret-with-enough-entropy-12345';

async function clearAuthUsers(): Promise<void> {
  const auth = getAuth();
  const users = await auth.listUsers(1000);
  await Promise.all(
    users.users.map((user) => auth.deleteUser(user.uid).catch(() => undefined)),
  );
}

async function clearFcmTokens(): Promise<void> {
  const db = getFirestore();
  const docs = await db.collection('fcm_tokens').listDocuments();
  await Promise.all(docs.map((doc) => doc.delete()));
}

async function seedAuthUsers(
  newUid = 'new-uid',
  oldUid = 'old-anon-uid',
): Promise<void> {
  const auth = getAuth();
  await auth.createUser({ uid: oldUid });
  await auth.createUser({
    uid: newUid,
    email: `${newUid}@example.com`,
    password: 'Password123!',
  });
}

async function seedCleanupIntent(
  oldUid = 'old-anon-uid',
  secret = cleanupSecret,
): Promise<void> {
  await getFirestore().doc(`recoveryCleanupIntents/${oldUid}`).set({
    secret,
    createdAt: new Date(),
  });
}

function cleanupCall(
  oldUid = 'old-anon-uid',
  newUid = 'new-uid',
  secret = cleanupSecret,
): Promise<unknown> {
  return wrapped({
    data: { oldUid, cleanupSecret: secret },
    auth: { uid: newUid },
  } as any);
}

async function seedGroup(
  groupId: string,
  memberIds: string[],
  data: Record<string, unknown> = {},
): Promise<void> {
  const db = getFirestore();
  await db.doc(`groups/${groupId}`).set({
    id: groupId,
    name: groupId,
    memberIds,
    createdBy: memberIds[0],
    currency: 'OMR',
    createdAt: new Date(),
    updatedAt: new Date(),
    ...data,
  });
}

async function seedMember(
  groupId: string,
  uid: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  const db = getFirestore();
  await db.doc(`groups/${groupId}/members/${uid}`).set({
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
  const db = getFirestore();
  await db.doc(`groups/${groupId}/events/${eventId}`).set({
    id: eventId,
    groupId,
    name: eventId,
    type: 'trip',
    createdBy: 'owner',
    participantIds: ['old-anon-uid'],
    participantNames: { 'old-anon-uid': 'Old Name' },
    modules: { ledger: true },
    isDeleted: false,
    createdAt: new Date(),
    updatedAt: new Date(),
    ...data,
  });
}

beforeEach(async () => {
  await clearFirestore();
  await clearFcmTokens();
  await clearAuthUsers();
  jest.restoreAllMocks();
  jest.spyOn(logger, 'info').mockImplementation(() => undefined);
  jest.spyOn(logger, 'error').mockImplementation(() => undefined);
});

afterAll(async () => {
  await clearFirestore();
  await clearFcmTokens();
  await clearAuthUsers();
  testEnv.cleanup();
});

describe('cleanupAnonUidArtifacts', () => {
  test('anonymous calling UID is rejected', async () => {
    await getAuth().createUser({ uid: 'still-anon' });

    await expect(wrapped({
      data: { oldUid: 'old-anon-uid', cleanupSecret },
      auth: { uid: 'still-anon' },
    } as any)).rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('calling UID equal to oldUid is rejected', async () => {
    await getAuth().createUser({
      uid: 'same-uid',
      email: 'same@example.com',
      password: 'Password123!',
    });

    await expect(wrapped({
      data: { oldUid: 'same-uid', cleanupSecret },
      auth: { uid: 'same-uid' },
    } as any)).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('missing cleanup intent cannot migrate another UID artifacts', async () => {
    await seedAuthUsers();
    await seedGroup('victim-group', ['old-anon-uid']);
    await seedMember('victim-group', 'old-anon-uid');

    await expect(cleanupCall()).rejects.toMatchObject({
      code: 'permission-denied',
    });

    const group = await getFirestore().doc('groups/victim-group').get();
    expect(group.data()?.memberIds).toEqual(['old-anon-uid']);
    await expect(getAuth().getUser('old-anon-uid')).resolves.toBeDefined();
  });

  test('when both UIDs are members, oldUid is removed and survivor retained', async () => {
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid', 'new-uid', 'owner']);
    await seedMember('g1', 'old-anon-uid', { displayName: 'Old Name' });
    await seedMember('g1', 'new-uid', { displayName: 'New Name', role: 'CREATOR' });

    await expect(cleanupCall()).resolves.toMatchObject({
      groupsProcessed: 1,
      cascadeFailed: [],
      authUserDeleted: true,
    });

    const db = getFirestore();
    const group = await db.doc('groups/g1').get();
    const oldMember = await db.doc('groups/g1/members/old-anon-uid').get();
    const newMember = await db.doc('groups/g1/members/new-uid').get();
    expect(group.data()?.memberIds).toEqual(['new-uid', 'owner']);
    expect(oldMember.exists).toBe(false);
    expect(newMember.data()).toMatchObject({
      id: 'new-uid',
      userId: 'new-uid',
      displayName: 'New Name',
      role: 'CREATOR',
    });
  });

  test('when only oldUid is a member, it is replaced and member doc copied', async () => {
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid'], { createdBy: 'owner' });
    await seedMember('g1', 'old-anon-uid', {
      displayName: 'Recovered Name',
      role: 'CREATOR',
      isShadow: true,
    });

    await cleanupCall();

    const db = getFirestore();
    const group = await db.doc('groups/g1').get();
    const oldMember = await db.doc('groups/g1/members/old-anon-uid').get();
    const newMember = await db.doc('groups/g1/members/new-uid').get();
    expect(group.data()?.memberIds).toEqual(['new-uid']);
    expect(oldMember.exists).toBe(false);
    expect(newMember.data()).toMatchObject({
      id: 'new-uid',
      userId: 'new-uid',
      displayName: 'Recovered Name',
      role: 'CREATOR',
      isShadow: true,
    });
    expect(newMember.data()?.joinedAt).toBeDefined();
  });

  test('createdBy is rewritten on group, active event, and active expense only', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid'], { createdBy: 'old-anon-uid' });
    await seedMember('g1', 'old-anon-uid');
    await seedEvent('g1', 'active', { createdBy: 'old-anon-uid' });
    await seedEvent('g1', 'deleted', {
      createdBy: 'old-anon-uid',
      isDeleted: true,
    });
    await db.doc('groups/g1/events/active/expenses/x1').set({
      id: 'x1',
      createdBy: 'old-anon-uid',
      isDeleted: false,
    });
    await db.doc('groups/g1/events/active/expenses/x2').set({
      id: 'x2',
      createdBy: 'old-anon-uid',
      isDeleted: true,
    });
    await db.doc('groups/g1/events/active/settlements/s1').set({
      id: 's1',
      createdBy: 'old-anon-uid',
    });

    await cleanupCall();

    const group = await db.doc('groups/g1').get();
    const activeEvent = await db.doc('groups/g1/events/active').get();
    const deletedEvent = await db.doc('groups/g1/events/deleted').get();
    const activeExpense = await db.doc('groups/g1/events/active/expenses/x1').get();
    const deletedExpense = await db.doc('groups/g1/events/active/expenses/x2').get();
    const settlement = await db.doc('groups/g1/events/active/settlements/s1').get();
    expect(group.data()?.createdBy).toBe('new-uid');
    expect(activeEvent.data()?.createdBy).toBe('new-uid');
    expect(deletedEvent.data()?.createdBy).toBe('old-anon-uid');
    expect(activeExpense.data()?.createdBy).toBe('new-uid');
    expect(deletedExpense.data()?.createdBy).toBe('old-anon-uid');
    expect(settlement.data()?.createdBy).toBe('old-anon-uid');
  });

  test('event participantIds and participantNames replace oldUid with calling UID', async () => {
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid']);
    await seedMember('g1', 'old-anon-uid');
    await seedEvent('g1', 'e1', {
      participantIds: ['old-anon-uid', 'owner'],
      participantNames: {
        'old-anon-uid': 'Old Name',
        owner: 'Owner',
      },
    });

    await cleanupCall();

    const event = await getFirestore().doc('groups/g1/events/e1').get();
    expect(event.data()?.participantIds).toEqual(['new-uid', 'owner']);
    expect(event.data()?.participantNames).toEqual({
      'new-uid': 'Old Name',
      owner: 'Owner',
    });
  });

  test('deleted anon auth user returns authUserDeleted true', async () => {
    await seedAuthUsers();
    await seedCleanupIntent();

    const result = await cleanupCall() as { authUserDeleted: boolean };

    expect(result.authUserDeleted).toBe(true);
    await expect(getAuth().getUser('old-anon-uid'))
      .rejects.toMatchObject({ code: 'auth/user-not-found' });
  });

  test('auth/user-not-found during auth delete returns false without throwing', async () => {
    await seedAuthUsers();
    await seedCleanupIntent();
    await getAuth().deleteUser('old-anon-uid');

    await expect(cleanupCall()).resolves.toMatchObject({
      authUserDeleted: false,
    });
  });

  // AC1 (#46 phase 1): per-group failure must NOT delete the old anon
  // auth user and must NOT consume the cleanup intent. fcm/joinAttempts
  // deletes run BEFORE the Auth-delete gate so that recoverable identity
  // residue is scrubbed even when groups partially fail.
  test('per-group failure preserves auth user and cleanup intent (#46 AC1)', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await db.doc('fcm_tokens/old-anon-uid').set({ token: 'stale' });
    await db.doc('joinAttempts/old-anon-uid').set({ failCount: 3 });
    await seedGroup('good', ['old-anon-uid']);
    await seedMember('good', 'old-anon-uid');
    await seedGroup('bad', ['old-anon-uid']);
    await seedMember('bad', 'old-anon-uid');
    await seedEvent('bad', 'bad-event', { participantIds: 'old-anon-uid' });

    const result = await cleanupCall() as {
      groupsProcessed: number;
      cascadeFailed: string[];
      authUserDeleted: boolean;
      fcmTokenDeleted: boolean;
      joinAttemptsDeleted: boolean;
    };

    expect(result.groupsProcessed).toBe(1);
    expect(result.cascadeFailed).toEqual(['bad']);

    // P0 zombie-auth bug fix: Auth.deleteUser is gated on cascadeFailed.length === 0
    expect(result.authUserDeleted).toBe(false);
    await expect(getAuth().getUser('old-anon-uid')).resolves.toBeDefined();

    // Reorder: fcm/joinAttempts ARE attempted even when groups fail,
    // so identity residue is scrubbed and a retry doesn't see it.
    expect(result.fcmTokenDeleted).toBe(true);
    expect(result.joinAttemptsDeleted).toBe(true);
    expect((await db.doc('fcm_tokens/old-anon-uid').get()).exists).toBe(false);
    expect((await db.doc('joinAttempts/old-anon-uid').get()).exists).toBe(false);

    // Intent is preserved so the client can retry within the 15-min window
    expect((await db.doc('recoveryCleanupIntents/old-anon-uid').get()).exists)
      .toBe(true);

    // Group state: good migrated, bad untouched
    const good = await db.doc('groups/good').get();
    const bad = await db.doc('groups/bad').get();
    expect(good.data()?.memberIds).toEqual(['new-uid']);
    expect(bad.data()?.memberIds).toEqual(['old-anon-uid']);
  });

  // AC1b: fcm delete failure must enter cascadeFailed and gate Auth-delete.
  test('fcm delete failure gates auth delete (#46 AC1b)', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await db.doc('fcm_tokens/old-anon-uid').set({ token: 'stale' });

    const originalDelete = DocumentReference.prototype.delete;
    const spy = jest
      .spyOn(DocumentReference.prototype, 'delete')
      .mockImplementation(function (this: DocumentReference) {
        if (this.path === 'fcm_tokens/old-anon-uid') {
          return Promise.reject(new Error('forced fcm delete failure'));
        }
        return originalDelete.call(this);
      });

    try {
      const result = await cleanupCall() as {
        cascadeFailed: string[];
        authUserDeleted: boolean;
        fcmTokenDeleted: boolean;
      };

      expect(result.cascadeFailed).toContain('fcm_tokens');
      expect(result.authUserDeleted).toBe(false);
      expect(result.fcmTokenDeleted).toBe(false);
      await expect(getAuth().getUser('old-anon-uid')).resolves.toBeDefined();
      expect((await db.doc('recoveryCleanupIntents/old-anon-uid').get()).exists)
        .toBe(true);
    } finally {
      spy.mockRestore();
    }
  });

  // AC1c: joinAttempts delete failure must enter cascadeFailed and gate.
  test('joinAttempts delete failure gates auth delete (#46 AC1c)', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await db.doc('joinAttempts/old-anon-uid').set({ failCount: 3 });

    const originalDelete = DocumentReference.prototype.delete;
    const spy = jest
      .spyOn(DocumentReference.prototype, 'delete')
      .mockImplementation(function (this: DocumentReference) {
        if (this.path === 'joinAttempts/old-anon-uid') {
          return Promise.reject(new Error('forced joinAttempts delete failure'));
        }
        return originalDelete.call(this);
      });

    try {
      const result = await cleanupCall() as {
        cascadeFailed: string[];
        authUserDeleted: boolean;
        joinAttemptsDeleted: boolean;
      };

      expect(result.cascadeFailed).toContain('joinAttempts');
      expect(result.authUserDeleted).toBe(false);
      expect(result.joinAttemptsDeleted).toBe(false);
      await expect(getAuth().getUser('old-anon-uid')).resolves.toBeDefined();
      expect((await db.doc('recoveryCleanupIntents/old-anon-uid').get()).exists)
        .toBe(true);
    } finally {
      spy.mockRestore();
    }
  });

  test('fcm token for oldUid is deleted when present', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await db.doc('fcm_tokens/old-anon-uid').set({ token: 'stale-token' });

    const result = await cleanupCall() as { fcmTokenDeleted: boolean };

    const fcmToken = await db.doc('fcm_tokens/old-anon-uid').get();
    expect(result.fcmTokenDeleted).toBe(true);
    expect(fcmToken.exists).toBe(false);
  });

  test('absent fcm token returns false without error', async () => {
    await seedAuthUsers();
    await seedCleanupIntent();

    await expect(cleanupCall()).resolves.toMatchObject({
      fcmTokenDeleted: false,
    });
  });

  test('join attempt and cleanup intent for oldUid are deleted after cleanup', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await db.doc('joinAttempts/old-anon-uid').set({ failCount: 3 });

    await expect(cleanupCall()).resolves.toMatchObject({
      joinAttemptsDeleted: true,
    });

    expect((await db.doc('joinAttempts/old-anon-uid').get()).exists).toBe(false);
    expect((await db.doc('recoveryCleanupIntents/old-anon-uid').get()).exists)
      .toBe(false);
  });
});
