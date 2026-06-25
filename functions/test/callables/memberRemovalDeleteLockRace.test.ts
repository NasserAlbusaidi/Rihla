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

let mockMutateGroup: (groupRef: DocumentReference) => Promise<unknown> =
  async () => undefined;

jest.mock('../../src/callables/groupNetBalance', () => ({
  recomputeNet: jest.fn(async (_db: unknown, groupRef: DocumentReference) => {
    await mockMutateGroup(groupRef);
    return {
      net: new Map(),
      liveEventRefs: [],
      perEventNet: new Map(),
      eventCount: 0,
    };
  }),
}));

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

const groupData = async (groupId: string) =>
  (await getFirestore().doc(`groups/${groupId}`).get()).data() ?? {};

const docExists = async (path: string): Promise<boolean> =>
  (await getFirestore().doc(path).get()).exists;

async function activityCount(groupId: string): Promise<number> {
  return (await getFirestore().collection(`groups/${groupId}/activity`).get()).size;
}

function callablesWithRecomputeRace(
  mutateGroup: (groupRef: DocumentReference) => Promise<unknown>,
) {
  mockMutateGroup = mutateGroup;
  return {
    leave: testEnv.wrap(leaveGroup),
    remove: testEnv.wrap(removeMember),
  };
}

const flipDeleteLock = (groupRef: DocumentReference) =>
  groupRef.update({
    deletingInProgress: true,
    deleteLockedAt: new Date('2026-06-25T00:00:00.000Z'),
    deleteLockedBy: OWNER,
  });

const flipSoftDeleted = (groupRef: DocumentReference) =>
  groupRef.update({
    isDeleted: true,
    deletedAt: new Date('2026-06-25T00:00:00.000Z'),
  });

const transferCreator = (groupRef: DocumentReference) =>
  groupRef.update({ createdBy: MEMBER });

beforeEach(async () => {
  await clearFirestore();
  mockMutateGroup = async () => undefined;
  jest.restoreAllMocks();
  jest.spyOn(logger, 'info').mockImplementation(() => undefined);
  jest.spyOn(logger, 'warn').mockImplementation(() => undefined);
  jest.spyOn(logger, 'error').mockImplementation(() => undefined);
});

afterAll(async () => {
  await clearFirestore();
  testEnv.cleanup();
});

describe('member removal callables honor delete lock at the final write boundary (#663)', () => {
  test('leaveGroup blocks if deleteGroup quiesces after initial validation but before membership writes', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    const { leave } = callablesWithRecomputeRace(flipDeleteLock);

    await expect(
      leave({ data: { groupId: 'g' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'not-found' });

    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
    expect(await activityCount('g')).toBe(0);
  });

  test('leaveGroup blocks if group is finalized deleted after initial validation but before membership writes', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    const { leave } = callablesWithRecomputeRace(flipSoftDeleted);

    await expect(
      leave({ data: { groupId: 'g' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'not-found' });

    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
    expect(await activityCount('g')).toBe(0);
  });

  test('removeMember blocks if deleteGroup quiesces after initial validation but before membership writes', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    const { remove } = callablesWithRecomputeRace(flipDeleteLock);

    await expect(
      remove({
        data: { groupId: 'g', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'not-found' });

    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
    expect(await activityCount('g')).toBe(0);
  });

  test('removeMember blocks if group is finalized deleted after initial validation but before membership writes', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    const { remove } = callablesWithRecomputeRace(flipSoftDeleted);

    await expect(
      remove({
        data: { groupId: 'g', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'not-found' });

    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
    expect(await activityCount('g')).toBe(0);
  });

  test('removeMember blocks if creator authority changes after initial validation but before membership writes', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    const { remove } = callablesWithRecomputeRace(transferCreator);

    await expect(
      remove({
        data: { groupId: 'g', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'permission-denied' });

    expect((await groupData('g')).createdBy).toBe(MEMBER);
    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
    expect(await activityCount('g')).toBe(0);
  });
});
