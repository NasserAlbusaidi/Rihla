import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import { clearFirestore } from '../fixtures';
import { joinGroupByInviteCode } from '../../src/callables/joinGroupByInviteCode';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(joinGroupByInviteCode);

async function seedInviteGroup(): Promise<void> {
  const db = getFirestore();
  await db.doc('groups/g1').set({
    id: 'g1',
    name: 'Desert Crew',
    inviteCode: 'ABC123',
    createdBy: 'owner',
    memberIds: ['owner'],
    currency: 'OMR',
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  await db.doc('groups/g1/members/owner').set({
    id: 'owner',
    userId: 'owner',
    displayName: 'Owner',
    role: 'CREATOR',
    joinedAt: new Date(),
    isShadow: false,
  });
  await db.doc('inviteCodes/ABC123').set({
    groupId: 'g1',
    createdAt: new Date(),
  });
}

beforeEach(async () => {
  await clearFirestore();
  await seedInviteGroup();
});

afterAll(async () => {
  await clearFirestore();
  testEnv.cleanup();
});

describe('joinGroupByInviteCode', () => {
  test('unauthenticated request rejected', async () => {
    await expect(wrapped({ data: { inviteCode: 'ABC123' }, auth: undefined } as any))
      .rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('invalid invite code rejected without revealing groups', async () => {
    await expect(wrapped({
      data: { inviteCode: 'NOPE99', displayName: 'Eve' },
      auth: { uid: 'eve' },
    } as any)).rejects.toMatchObject({ code: 'not-found' });
  });

  test('join adds uid to group and creates member document', async () => {
    const res = await wrapped({
      data: { inviteCode: 'abc123', displayName: 'Alice' },
      auth: { uid: 'alice' },
    } as any);

    expect(res).toEqual({ groupId: 'g1' });
    const db = getFirestore();
    const groupSnap = await db.doc('groups/g1').get();
    expect(groupSnap.data()?.memberIds).toContain('alice');

    const memberSnap = await db.doc('groups/g1/members/alice').get();
    expect(memberSnap.exists).toBe(true);
    expect(memberSnap.data()).toMatchObject({
      id: 'alice',
      userId: 'alice',
      displayName: 'Alice',
      role: 'MEMBER',
      isShadow: false,
    });
  });

  test('already-member join is idempotent', async () => {
    const first = await wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Alice' },
      auth: { uid: 'alice' },
    } as any);
    const second = await wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Alice Again' },
      auth: { uid: 'alice' },
    } as any);

    expect(first).toEqual({ groupId: 'g1' });
    expect(second).toEqual({ groupId: 'g1' });
    const members = await getFirestore().collection('groups/g1/members').listDocuments();
    expect(members.map((doc) => doc.id).sort()).toEqual(['alice', 'owner']);
  });
});
