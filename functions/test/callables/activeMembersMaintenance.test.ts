import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';
import { nextActiveMemberIds } from '../../src/callables/shared/activeMembers';
import { leaveGroup } from '../../src/callables/leaveGroup';
import { removeMember } from '../../src/callables/removeMember';
import { addShadowMember } from '../../src/callables/addShadowMember';
import { joinGroupByInviteCode } from '../../src/callables/joinGroupByInviteCode';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });

const OWNER = 'owner';
const MEMBER = 'member';
const TOMBSTONE = 'deleted-t1';

// #1144 R5: every roster writer maintains `activeMemberIds` (= memberIds minus
// tombstones; shadows in) through the shared nextActiveMemberIds helper —
// present field: apply the op; absent field (legacy group): SEED from
// memberIds − tombstone member-doc userIds, then apply. claimShadow and
// deleteAccount coverage lives in their own suites (claimShadow.test.ts
// test 8, deleteAccount.test.ts main-cascade test).

async function seedGroup(
  groupId: string,
  memberIds: string[],
  extra: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore().doc(`groups/${groupId}`).set({
    id: groupId,
    name: groupId,
    inviteCode: 'ABC123',
    createdBy: OWNER,
    memberIds,
    currency: 'OMR',
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    updatedAt: new Date('2026-01-02T00:00:00.000Z'),
    isDeleted: false,
    deletedAt: null,
    ...extra,
  });
}

async function seedMember(
  groupId: string,
  uid: string,
  extra: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore().doc(`groups/${groupId}/members/${uid}`).set({
    id: uid,
    userId: uid,
    displayName: uid,
    role: uid === OWNER ? 'CREATOR' : 'MEMBER',
    joinedAt: new Date('2026-01-01T00:00:00.000Z'),
    isShadow: false,
    isTombstone: false,
    ...extra,
  });
}

const groupData = async (groupId: string) =>
  (await getFirestore().doc(`groups/${groupId}`).get()).data() ?? {};

beforeEach(async () => {
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

describe('nextActiveMemberIds helper', () => {
  test('present field: add / remove / replace apply to it directly', async () => {
    await seedGroup('g', [OWNER, MEMBER], { activeMemberIds: [OWNER, MEMBER] });
    const db = getFirestore();
    const groupRef = db.doc('groups/g');
    const results = await db.runTransaction(async (tx) => {
      const gData = (await tx.get(groupRef)).data() ?? {};
      return Promise.all([
        nextActiveMemberIds(tx, groupRef, gData, { add: 'new-uid' }),
        nextActiveMemberIds(tx, groupRef, gData, { add: MEMBER }), // dedup
        nextActiveMemberIds(tx, groupRef, gData, { remove: MEMBER }),
        nextActiveMemberIds(tx, groupRef, gData, {
          replace: { from: MEMBER, to: 'claimer' },
        }),
      ]);
    });
    expect(results[0]).toEqual([OWNER, MEMBER, 'new-uid']);
    expect(results[1]).toEqual([OWNER, MEMBER]);
    expect(results[2]).toEqual([OWNER]);
    expect(results[3]).toEqual([OWNER, 'claimer']);
  });

  test('absent field: seeds memberIds MINUS tombstone member docs, then applies', async () => {
    await seedGroup('g', [OWNER, MEMBER, TOMBSTONE]); // no activeMemberIds
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedMember('g', TOMBSTONE, {
      displayName: 'Deleted member',
      isTombstone: true,
    });
    const db = getFirestore();
    const groupRef = db.doc('groups/g');
    const next = await db.runTransaction(async (tx) => {
      const gData = (await tx.get(groupRef)).data() ?? {};
      return nextActiveMemberIds(tx, groupRef, gData, { add: 'joiner' });
    });
    expect(next).toEqual([OWNER, MEMBER, 'joiner']); // tombstone excluded
  });
});

describe('roster writers maintain activeMemberIds', () => {
  test('leaveGroup: present field → leaver removed from both sets', async () => {
    await seedGroup('g', [OWNER, MEMBER], { activeMemberIds: [OWNER, MEMBER] });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);

    await testEnv.wrap(leaveGroup)({
      data: { groupId: 'g' },
      auth: { uid: MEMBER },
    } as any);

    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER]);
    expect(group.activeMemberIds).toEqual([OWNER]);
  });

  test('leaveGroup: legacy group (absent field) → self-heals, tombstone excluded', async () => {
    await seedGroup('g', [OWNER, MEMBER, TOMBSTONE]);
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedMember('g', TOMBSTONE, {
      displayName: 'Deleted member',
      isTombstone: true,
    });

    await testEnv.wrap(leaveGroup)({
      data: { groupId: 'g' },
      auth: { uid: MEMBER },
    } as any);

    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER, TOMBSTONE]);
    expect(group.activeMemberIds).toEqual([OWNER]);
  });

  test('removeMember: present field → target removed from both sets', async () => {
    await seedGroup('g', [OWNER, MEMBER], { activeMemberIds: [OWNER, MEMBER] });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);

    await testEnv.wrap(removeMember)({
      data: { groupId: 'g', targetUserId: MEMBER },
      auth: { uid: OWNER },
    } as any);

    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER]);
    expect(group.activeMemberIds).toEqual([OWNER]);
  });

  test('addShadowMember: shadow uuid joins BOTH sets (shadows are active)', async () => {
    await seedGroup('g', [OWNER], { activeMemberIds: [OWNER] });
    await seedMember('g', OWNER);

    const res = (await testEnv.wrap(addShadowMember)({
      data: { groupId: 'g', displayName: 'Ali' },
      auth: { uid: OWNER },
    } as any)) as { memberId: string };

    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER, res.memberId]);
    expect(group.activeMemberIds).toEqual([OWNER, res.memberId]);
  });

  test('joinGroupByInviteCode: joiner added to both sets; legacy group self-heals around a tombstone', async () => {
    await seedGroup('g', [OWNER, TOMBSTONE]); // legacy: no activeMemberIds
    await seedMember('g', OWNER);
    await seedMember('g', TOMBSTONE, {
      displayName: 'Deleted member',
      isTombstone: true,
    });
    await getFirestore().doc('inviteCodes/ABC123').set({
      groupId: 'g',
      createdAt: new Date('2026-01-01T00:00:00.000Z'),
    });

    await testEnv.wrap(joinGroupByInviteCode)({
      data: { inviteCode: 'ABC123', displayName: 'Joiner' },
      auth: { uid: 'joiner-uid' },
    } as any);

    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER, TOMBSTONE, 'joiner-uid']);
    expect(group.activeMemberIds).toEqual([OWNER, 'joiner-uid']);
  });
});
