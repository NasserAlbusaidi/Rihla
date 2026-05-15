import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
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

afterEach(() => {
  jest.restoreAllMocks();
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

  test('bad invite attempts lock the caller after five failures', async () => {
    for (let i = 0; i < 5; i += 1) {
      await expect(wrapped({
        data: { inviteCode: 'NOPE99', displayName: 'Eve' },
        auth: { uid: 'eve' },
      } as any)).rejects.toMatchObject({ code: 'not-found' });
    }

    await expect(wrapped({
      data: { inviteCode: 'NOPE99', displayName: 'Eve' },
      auth: { uid: 'eve' },
    } as any)).rejects.toMatchObject({ code: 'resource-exhausted' });
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

  test('missing display name falls back to Anonymous', async () => {
    await expect(wrapped({
      data: { inviteCode: 'ABC123' },
      auth: { uid: 'anon' },
    } as any)).resolves.toEqual({ groupId: 'g1' });

    const memberSnap = await getFirestore().doc('groups/g1/members/anon').get();
    expect(memberSnap.data()?.displayName).toBe('Anonymous');
  });

  test('display name length mirrors Firestore rules limit', async () => {
    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'A'.repeat(33) },
      auth: { uid: 'long-name' },
    } as any)).rejects.toMatchObject({ code: 'invalid-argument' });

    const memberSnap = await getFirestore()
      .doc('groups/g1/members/long-name')
      .get();
    expect(memberSnap.exists).toBe(false);
  });

  test('display name rejects control characters before Admin SDK writes', async () => {
    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Eve\nMallory' },
      auth: { uid: 'bad-name' },
    } as any)).rejects.toMatchObject({ code: 'invalid-argument' });

    const memberSnap = await getFirestore()
      .doc('groups/g1/members/bad-name')
      .get();
    expect(memberSnap.exists).toBe(false);
  });

  test('successful join clears previous failed attempt counter', async () => {
    for (let i = 0; i < 4; i += 1) {
      await expect(wrapped({
        data: { inviteCode: 'NOPE99', displayName: 'Bob' },
        auth: { uid: 'bob' },
      } as any)).rejects.toMatchObject({ code: 'not-found' });
    }

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Bob' },
      auth: { uid: 'bob' },
    } as any)).resolves.toEqual({ groupId: 'g1' });

    const counterSnap = await getFirestore().doc('joinAttempts/bob').get();
    expect(counterSnap.exists).toBe(false);

    await expect(wrapped({
      data: { inviteCode: 'NOPE99', displayName: 'Bob' },
      auth: { uid: 'bob' },
    } as any)).rejects.toMatchObject({ code: 'not-found' });
  });

  test('success log omits raw invite code', async () => {
    const infoSpy = jest
      .spyOn(logger, 'info')
      .mockImplementation(() => undefined);

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Carol' },
      auth: { uid: 'carol' },
    } as any)).resolves.toEqual({ groupId: 'g1' });

    expect(infoSpy).toHaveBeenCalledWith('group-join succeeded', {
      uid: 'carol',
      groupId: 'g1',
    });
    expect(JSON.stringify(infoSpy.mock.calls)).not.toContain('ABC123');
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

  test('already-member join heals a missing member document', async () => {
    const db = getFirestore();
    await db.doc('groups/g1').update({ memberIds: ['owner', 'orphan'] });

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Orphan' },
      auth: { uid: 'orphan' },
    } as any)).resolves.toEqual({ groupId: 'g1' });

    const memberSnap = await db.doc('groups/g1/members/orphan').get();
    expect(memberSnap.exists).toBe(true);
    expect(memberSnap.data()).toMatchObject({
      id: 'orphan',
      userId: 'orphan',
      displayName: 'Orphan',
      role: 'MEMBER',
      isShadow: false,
    });
  });

  test('malformed memberIds is rejected before writing membership', async () => {
    const db = getFirestore();
    await db.doc('groups/g1').update({ memberIds: 'owner' });

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Mallory' },
      auth: { uid: 'mallory' },
    } as any)).rejects.toMatchObject({ code: 'failed-precondition' });

    const memberSnap = await db.doc('groups/g1/members/mallory').get();
    expect(memberSnap.exists).toBe(false);
  });
});
