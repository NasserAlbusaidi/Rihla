import functionsTest from 'firebase-functions-test';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';
import { cleanupAnonUidArtifacts } from '../../src/callables/cleanupAnonUidArtifacts';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(cleanupAnonUidArtifacts);

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
      data: { oldUid: 'old-anon-uid' },
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
      data: { oldUid: 'same-uid' },
      auth: { uid: 'same-uid' },
    } as any)).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('when both UIDs are members, oldUid is removed and survivor retained', async () => {
    await seedAuthUsers();
    await seedGroup('g1', ['old-anon-uid', 'new-uid', 'owner']);
    await seedMember('g1', 'old-anon-uid', { displayName: 'Old Name' });
    await seedMember('g1', 'new-uid', { displayName: 'New Name', role: 'CREATOR' });

    await expect(wrapped({
      data: { oldUid: 'old-anon-uid' },
      auth: { uid: 'new-uid' },
    } as any)).resolves.toMatchObject({
      groupsProcessed: 1,
      groupsFailed: [],
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
    await seedGroup('g1', ['old-anon-uid'], { createdBy: 'owner' });
    await seedMember('g1', 'old-anon-uid', {
      displayName: 'Recovered Name',
      role: 'CREATOR',
      isShadow: true,
    });

    await wrapped({
      data: { oldUid: 'old-anon-uid' },
      auth: { uid: 'new-uid' },
    } as any);

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

    await wrapped({
      data: { oldUid: 'old-anon-uid' },
      auth: { uid: 'new-uid' },
    } as any);

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
    await seedGroup('g1', ['old-anon-uid']);
    await seedMember('g1', 'old-anon-uid');
    await seedEvent('g1', 'e1', {
      participantIds: ['old-anon-uid', 'owner'],
      participantNames: {
        'old-anon-uid': 'Old Name',
        owner: 'Owner',
      },
    });

    await wrapped({
      data: { oldUid: 'old-anon-uid' },
      auth: { uid: 'new-uid' },
    } as any);

    const event = await getFirestore().doc('groups/g1/events/e1').get();
    expect(event.data()?.participantIds).toEqual(['new-uid', 'owner']);
    expect(event.data()?.participantNames).toEqual({
      'new-uid': 'Old Name',
      owner: 'Owner',
    });
  });

  test('deleted anon auth user returns authUserDeleted true', async () => {
    await seedAuthUsers();

    const result = await wrapped({
      data: { oldUid: 'old-anon-uid' },
      auth: { uid: 'new-uid' },
    } as any);

    expect(result.authUserDeleted).toBe(true);
    await expect(getAuth().getUser('old-anon-uid'))
      .rejects.toMatchObject({ code: 'auth/user-not-found' });
  });

  test('auth/user-not-found during auth delete returns false without throwing', async () => {
    await seedAuthUsers();
    await getAuth().deleteUser('old-anon-uid');

    await expect(wrapped({
      data: { oldUid: 'old-anon-uid' },
      auth: { uid: 'new-uid' },
    } as any)).resolves.toMatchObject({
      authUserDeleted: false,
    });
  });

  test('per-group failure is returned while other groups still process', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedGroup('good', ['old-anon-uid']);
    await seedMember('good', 'old-anon-uid');
    await seedGroup('bad', ['old-anon-uid']);
    await seedMember('bad', 'old-anon-uid');
    await seedEvent('bad', 'bad-event', { participantIds: 'old-anon-uid' });

    const result = await wrapped({
      data: { oldUid: 'old-anon-uid' },
      auth: { uid: 'new-uid' },
    } as any);

    const good = await db.doc('groups/good').get();
    const bad = await db.doc('groups/bad').get();
    expect(result.groupsProcessed).toBe(1);
    expect(result.groupsFailed).toEqual(['bad']);
    expect(good.data()?.memberIds).toEqual(['new-uid']);
    expect(bad.data()?.memberIds).toEqual(['old-anon-uid']);
  });

  test('fcm token for oldUid is deleted when present', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await db.doc('fcm_tokens/old-anon-uid').set({ token: 'stale-token' });

    const result = await wrapped({
      data: { oldUid: 'old-anon-uid' },
      auth: { uid: 'new-uid' },
    } as any);

    const fcmToken = await db.doc('fcm_tokens/old-anon-uid').get();
    expect(result.fcmTokenDeleted).toBe(true);
    expect(fcmToken.exists).toBe(false);
  });

  test('absent fcm token returns false without error', async () => {
    await seedAuthUsers();

    await expect(wrapped({
      data: { oldUid: 'old-anon-uid' },
      auth: { uid: 'new-uid' },
    } as any)).resolves.toMatchObject({
      fcmTokenDeleted: false,
    });
  });
});
