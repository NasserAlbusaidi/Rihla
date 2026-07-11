import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';
import { leaveGroup } from '../../src/callables/leaveGroup';
import { removeMember } from '../../src/callables/removeMember';
import { recomputeNet } from '../../src/callables/groupNetBalance';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });

const OWNER = 'owner';
const MEMBER = 'member';

// #1144 R1: a member with UNIVERSE-ONLY history (payer or settlement party in
// an event that no longer rosters them) is invisible to the zero-gate while
// live — the fold drops non-universe rows — but folds INTO the universe the
// instant their member doc is hard-deleted (payers/settlement parties are the
// NON-member-gated universe inputs, groupNetBalance.ts:684-686). Departing
// them "at zero" therefore mints a non-zero departed balance with no
// post-departure write at all. leaveGroup/removeMember must refuse instead.
// Split keys / customSplitParticipants are member-gated (:687-689) and DROP
// after the hard-delete — a split-key-only leaver stays free to depart, and
// the tests below pin BOTH sides of that boundary.

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

async function seedEvent(
  groupId: string,
  eventId: string,
  participantIds: string[],
): Promise<void> {
  await getFirestore().doc(`groups/${groupId}/events/${eventId}`).set({
    id: eventId,
    groupId,
    name: eventId,
    type: 'trip',
    createdBy: OWNER,
    participantIds,
    participantNames: Object.fromEntries(participantIds.map((id) => [id, id])),
    modules: { ledger: true },
    isDeleted: false,
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
  });
}

async function seedExpense(
  groupId: string,
  eventId: string,
  expenseId: string,
  payer: string,
  amountFils: number,
  extra: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore()
    .doc(`groups/${groupId}/events/${eventId}/expenses/${expenseId}`)
    .set({
      id: expenseId,
      eventId,
      createdBy: payer,
      payerParticipantId: payer,
      amountFils,
      currency: 'OMR',
      scope: 'global',
      splitMode: 'equally',
      isDeleted: false,
      createdAt: new Date('2026-01-01T00:00:00.000Z').toISOString(),
      ...extra,
    });
}

async function seedEventSettlement(
  groupId: string,
  eventId: string,
  settlementId: string,
  payer: string,
  recipient: string,
  amountFils: number,
): Promise<void> {
  await getFirestore()
    .doc(`groups/${groupId}/events/${eventId}/settlements/${settlementId}`)
    .set({
      id: settlementId,
      eventId,
      createdBy: payer,
      payerParticipantId: payer,
      recipientParticipantId: recipient,
      amountFils,
      currency: 'OMR',
      isDeleted: false,
      settledAt: new Date('2026-01-01T00:00:00.000Z').toISOString(),
    });
}

const groupData = async (groupId: string) =>
  (await getFirestore().doc(`groups/${groupId}`).get()).data() ?? {};

const docExists = async (path: string): Promise<boolean> =>
  (await getFirestore().doc(path).get()).exists;

function expectLockCleared(group: Record<string, unknown>): void {
  expect(group.departureInProgress).not.toBe(true);
  expect(group.departureLockedAt ?? null).toBeNull();
  expect(group.departureLockedBy ?? null).toBeNull();
}

async function memberNetAbsentEverywhere(groupId: string, uid: string): Promise<boolean> {
  const { net } = await recomputeNet(
    getFirestore(),
    getFirestore().doc(`groups/${groupId}`),
  );
  return [...net.values()].every((bucket) => {
    const v = bucket.get(uid);
    return v == null || v.isZero();
  });
}

const wrappedLeave = () => testEnv.wrap(leaveGroup);
const wrappedRemove = () => testEnv.wrap(removeMember);

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

// Fixture shape shared by the refusal cases: member is PAYER on e1 but NOT on
// its roster (the D9 roster-removal aftermath / a forged create). The live
// fold drops member's rows entirely, so the zero-gate alone sees zero.
async function seedUniverseOnlyPayer(): Promise<void> {
  await seedGroup('g');
  await seedMember('g', OWNER);
  await seedMember('g', MEMBER);
  await seedEvent('g', 'e1', [OWNER]); // member NOT rostered
  await seedExpense('g', 'e1', 'x1', MEMBER, 10000); // member paid 10.000 OMR
}

describe('#1144 R1 — departure refused when the leaver holds universe-only history', () => {
  test('1. leaveGroup: universe-only PAYER (live net zero) → failed-precondition, no mutation, lock cleared', async () => {
    await seedUniverseOnlyPayer();
    // Prove the premise: the live fold sees member as square — the zero-gate
    // alone cannot catch this departure.
    expect(await memberNetAbsentEverywhere('g', MEMBER)).toBe(true);

    await expect(
      wrappedLeave()({ data: { groupId: 'g' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
    expectLockCleared(group);
  });

  test('2. removeMember: universe-only payer target → failed-precondition, no mutation, lock cleared', async () => {
    await seedUniverseOnlyPayer();

    await expect(
      wrappedRemove()({
        data: { groupId: 'g', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
    expectLockCleared(group);
  });

  test('3. leaveGroup: universe-only SETTLEMENT PARTY → failed-precondition', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1', [OWNER]); // member NOT rostered
    // member is a settlement recipient on an event that doesn't roster them.
    await seedEventSettlement('g', 'e1', 's1', OWNER, MEMBER, 5000);

    await expect(
      wrappedLeave()({ data: { groupId: 'g' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER, MEMBER]);
    expectLockCleared(group);
  });
});

describe('#1144 R1 — boundary pins: what must STILL depart freely', () => {
  test('4. split-key-only leaver departs freely and does NOT resurrect (member-gated fold)', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1', [OWNER]); // member NOT rostered
    // owner paid; member appears ONLY as an exact split key. Member-gated
    // fold drops this while live AND after the hard-delete departure.
    await seedExpense('g', 'e1', 'x1', OWNER, 10000, {
      splitMode: 'exact',
      splitDistribution: { [OWNER]: 5000, [MEMBER]: 5000 },
    });

    const result = await wrappedLeave()({
      data: { groupId: 'g' },
      auth: { uid: MEMBER },
    } as any);
    expect(result).toMatchObject({ alreadyLeft: false });

    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER]);
    expect(await docExists('groups/g/members/member')).toBe(false);
    expectLockCleared(group);
    // No resurrection: post-departure the uid is in no member doc, so the
    // member-gated split-key fold still drops it.
    expect(await memberNetAbsentEverywhere('g', MEMBER)).toBe(true);
  });

  test('5. regression: rostered-everywhere leaver at zero departs normally', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1', [OWNER, MEMBER]);
    await seedExpense('g', 'e1', 'x1', MEMBER, 10000);
    // owner settles their 5.000 share → member square.
    await seedEventSettlement('g', 'e1', 's1', OWNER, MEMBER, 5000);

    const result = await wrappedLeave()({
      data: { groupId: 'g' },
      auth: { uid: MEMBER },
    } as any);
    expect(result).toMatchObject({ alreadyLeft: false });

    const group = await groupData('g');
    expect(group.memberIds).toEqual([OWNER]);
    expectLockCleared(group);
  });

  test('6. soft-deleted-docs-only history is invisible to the guard (fold parity)', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1', [OWNER]); // member NOT rostered
    await seedExpense('g', 'e1', 'x1', MEMBER, 10000, {
      isDeleted: true,
      deletedAt: new Date('2026-01-05T00:00:00.000Z').toISOString(),
    });

    const result = await wrappedLeave()({
      data: { groupId: 'g' },
      auth: { uid: MEMBER },
    } as any);
    expect(result).toMatchObject({ alreadyLeft: false });
    expectLockCleared(await groupData('g'));
  });
});

describe('#1144 R1 — positive control: the resurrection is real', () => {
  test('7. Admin force-departure of the universe-only payer mints a non-zero departed balance', async () => {
    await seedUniverseOnlyPayer();
    expect(await memberNetAbsentEverywhere('g', MEMBER)).toBe(true);

    // Bypass the callable entirely (what a pre-guard departure did): delete
    // the member doc + arrayRemove — the state the guard exists to prevent.
    await getFirestore().doc('groups/g/members/member').delete();
    await getFirestore().doc('groups/g').update({
      memberIds: [OWNER],
    });

    // The fold now folds the ex-payer in: paid 10.000, equal share 5.000 →
    // net +5.000. Non-zero out of thin air — no post-departure write.
    expect(await memberNetAbsentEverywhere('g', MEMBER)).toBe(false);
  });
});
