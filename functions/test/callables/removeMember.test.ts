import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';

// RED → GREEN: #318 server-authoritative creator-remove. Mirrors #290 leaveGroup
// but gates the TARGET member's net (not the caller's), verifies the caller is
// the group creator (permission-denied otherwise), and rejects self-removal
// (invalid-argument — the creator must use leaveGroup, the only path a creator's
// own debt could leak past the target-keyed gate). The callable recomputes the
// TARGET's net via the shared groupNetBalance oracle (exactly as the client
// BalanceCalculator), refuses with failed-precondition on a non-zero net, then
// atomically removes targetUserId from memberIds + deletes EVERY member doc
// matching `userId == targetUserId` (creator docs are uuid-keyed, #294) + writes
// a `member_left` activity doc with metadata{memberAction:removed,memberName}
// (NOT `member_removed` — the client renders/filters/icons all key on
// `member_left`, activity_display.dart:37-42). The direct client creator-remove
// path is locked in firestore.rules (validCreatorRemoveMember dropped).
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && npm run test:emulator -- removeMember.test.ts`

import { removeMember } from '../../src/callables/removeMember';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(removeMember);

const OWNER = 'owner';
const MEMBER = 'member';
const THIRD = 'third';

async function seedGroup(
  groupId: string,
  data: Record<string, unknown> = {},
): Promise<void> {
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
    ...data,
  });
}

async function seedMember(
  groupId: string,
  uid: string,
  data: Record<string, unknown> = {},
  docId?: string,
): Promise<void> {
  const displayName =
    uid === OWNER ? 'Owner' : uid === MEMBER ? 'Member' : 'Third';
  await getFirestore().doc(`groups/${groupId}/members/${docId ?? uid}`).set({
    id: docId ?? uid,
    userId: uid,
    displayName,
    role: uid === OWNER ? 'CREATOR' : 'MEMBER',
    joinedAt: new Date('2026-01-01T00:00:00.000Z'),
    isShadow: false,
    isTombstone: false,
    ...data,
  });
}

async function seedEvent(
  groupId: string,
  eventId: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore().doc(`groups/${groupId}/events/${eventId}`).set({
    id: eventId,
    groupId,
    name: eventId,
    type: 'trip',
    createdBy: OWNER,
    participantIds: [OWNER, MEMBER],
    participantNames: { [OWNER]: 'Owner', [MEMBER]: 'Member' },
    modules: { ledger: true },
    isDeleted: false,
    deletedAt: null,
    createdAt: new Date('2026-01-04T00:00:00.000Z'),
    ...data,
  });
}

async function seedExpense(
  path: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore().doc(path).set({
    id: path.split('/').pop(),
    eventId: path.split('/')[3],
    createdBy: OWNER,
    payerParticipantId: OWNER,
    amountFils: 12000,
    currency: 'OMR',
    description: 'expense',
    scope: 'global',
    customSplitParticipants: [],
    splitMode: 'equally',
    splitDistribution: {},
    isDeleted: false,
    deletedAt: null,
    createdAt: '2026-01-06T00:00:00.000Z',
    ...data,
  });
}

async function seedEventSettlement(
  path: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore().doc(path).set({
    id: path.split('/').pop(),
    eventId: path.split('/')[3],
    createdBy: MEMBER,
    payerParticipantId: MEMBER,
    recipientParticipantId: OWNER,
    payerName: 'Member',
    recipientName: 'Owner',
    amountFils: 6000,
    currency: 'OMR',
    note: null,
    isDeleted: false,
    deletedAt: null,
    settledAt: '2026-01-08T00:00:00.000Z',
    scope: 'event',
    ...data,
  });
}

const groupData = async (groupId: string) =>
  (await getFirestore().doc(`groups/${groupId}`).get()).data() ?? {};

const docExists = async (path: string): Promise<boolean> =>
  (await getFirestore().doc(path).get()).exists;

async function membersWithUserId(groupId: string, uid: string): Promise<number> {
  const snap = await getFirestore()
    .collection(`groups/${groupId}/members`)
    .where('userId', '==', uid)
    .get();
  return snap.size;
}

async function activityDocs(
  groupId: string,
): Promise<Array<Record<string, unknown>>> {
  const snap = await getFirestore().collection(`groups/${groupId}/activity`).get();
  return snap.docs.map((d) => d.data());
}

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

describe('removeMember callable — server-authoritative creator-remove + balance gate (#318)', () => {
  test('1. missing auth is rejected (unauthenticated)', async () => {
    await expect(
      wrapped({
        data: { groupId: 'g', targetUserId: MEMBER },
        auth: undefined,
      } as any),
    ).rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('2. invalid groupId ("" and "a/b") is rejected with invalid-argument', async () => {
    await expect(
      wrapped({
        data: { groupId: '', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(
      wrapped({
        data: { groupId: 'a/b', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('3. invalid targetUserId ("" and "a/b") is rejected with invalid-argument', async () => {
    await expect(
      wrapped({
        data: { groupId: 'g', targetUserId: '' },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(
      wrapped({
        data: { groupId: 'g', targetUserId: 'a/b' },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('4. self-removal (targetUserId === caller) is rejected with invalid-argument', async () => {
    // The creator cannot self-remove — they must use leaveGroup (the only path
    // a creator's own debt could leak past the target-keyed gate). Asserted even
    // before the group lookup (it is an input-shape error).
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);

    await expect(
      wrapped({
        data: { groupId: 'g', targetUserId: OWNER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'invalid-argument' });

    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await activityDocs('g')).toHaveLength(0);
  });

  test('5. missing group is rejected with not-found', async () => {
    await expect(
      wrapped({
        data: { groupId: 'ghost', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'not-found' });
  });

  test('6. non-creator caller is rejected with permission-denied; no writes', async () => {
    // Axis leaveGroup never tests: only the group creator may remove others.
    await seedGroup('g', { memberIds: [OWNER, MEMBER, THIRD] });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedMember('g', THIRD);

    await expect(
      wrapped({
        data: { groupId: 'g', targetUserId: THIRD },
        auth: { uid: MEMBER },
      } as any),
    ).rejects.toMatchObject({ code: 'permission-denied' });

    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER, THIRD]);
    expect(await docExists('groups/g/members/third')).toBe(true);
    expect(await activityDocs('g')).toHaveLength(0);
  });

  test('7. square target leaves: memberIds loses target, member doc deleted, member_left logged with removed metadata + creator actorName', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);

    const res = await wrapped({
      data: { groupId: 'g', targetUserId: MEMBER },
      auth: { uid: OWNER },
    } as any);

    expect(res).toMatchObject({
      groupId: 'g',
      mode: 'removed',
      alreadyRemoved: false,
    });
    expect((await groupData('g')).memberIds).toEqual([OWNER]);
    expect(await docExists('groups/g/members/member')).toBe(false);

    const activity = await activityDocs('g');
    expect(activity).toHaveLength(1);
    // P1: type MUST be member_left (NOT member_removed) — activity_display.dart,
    // the Members filter, and the user_minus icon all key on member_left and
    // disambiguate the "removed" case via metadata.memberAction.
    expect(activity[0]).toMatchObject({
      type: 'member_left',
      actorId: OWNER,
      actorName: 'Owner',
    });
    expect(activity[0].type).not.toBe('member_removed');
    expect(activity[0].metadata).toEqual({
      memberAction: 'removed',
      memberName: 'Member',
    });
    expect(typeof activity[0].timestamp).toBe('string');
    expect(typeof activity[0].description).toBe('string');
  });

  test('8. non-member target (absent from memberIds, no member doc) → alreadyRemoved, no writes', async () => {
    await seedGroup('g', { memberIds: [OWNER] });
    await seedMember('g', OWNER);

    const res = await wrapped({
      data: { groupId: 'g', targetUserId: MEMBER },
      auth: { uid: OWNER },
    } as any);

    expect(res).toMatchObject({
      groupId: 'g',
      mode: 'removed',
      alreadyRemoved: true,
    });
    expect((await groupData('g')).memberIds).toEqual([OWNER]);
    expect(await activityDocs('g')).toHaveLength(0);
  });

  test('9. settled target (event settlement zeroes the owed) may be removed', async () => {
    // OWNER pays 12.000 OMR equally between OWNER+MEMBER → MEMBER owes 6.000;
    // MEMBER settles 6.000 to OWNER → net[MEMBER] == 0.
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1');
    await seedEventSettlement('groups/g/events/e1/settlements/s1');

    const res = await wrapped({
      data: { groupId: 'g', targetUserId: MEMBER },
      auth: { uid: OWNER },
    } as any);

    expect(res).toMatchObject({ mode: 'removed', alreadyRemoved: false });
    expect((await groupData('g')).memberIds).toEqual([OWNER]);
    expect(await docExists('groups/g/members/member')).toBe(false);
  });

  test('10. target debtor (non-zero net) is rejected with failed-precondition; no writes', async () => {
    // OWNER pays 12.000 equally → MEMBER owes 6.000, never settled.
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1');

    await expect(
      wrapped({
        data: { groupId: 'g', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
    expect(await activityDocs('g')).toHaveLength(0);
  });

  test('10b. mixed-currency group blocks removal even when the target nets to a fake zero (#261)', async () => {
    // OWNER pays 10.000 OMR (equal → each owes 5.000); MEMBER pays 10.00 USD
    // (equal → each owes 5.00). MEMBER net = 10(USD) − 5(OMR) − 5(USD) = a FAKE
    // zero, so isZero() would WRONGLY allow removal. currencies {OMR,USD} → refuse.
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 10000,
      currency: 'OMR',
      payerParticipantId: OWNER,
      createdBy: OWNER,
    });
    await seedExpense('groups/g/events/e1/expenses/x2', {
      amountFils: 1000,
      currency: 'USD',
      payerParticipantId: MEMBER,
      createdBy: MEMBER,
    });

    await expect(
      wrapped({
        data: { groupId: 'g', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
    expect(await activityDocs('g')).toHaveLength(0);
  });

  test('11. target creditor (positive net) is also blocked', async () => {
    // MEMBER pays 12.000 equally → MEMBER paid 12, owed 6 → net +6.000.
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      payerParticipantId: MEMBER,
      createdBy: MEMBER,
    });

    await expect(
      wrapped({
        data: { groupId: 'g', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER]);
  });

  test('12. gate keys on the TARGET, not the caller: caller (OWNER) has a non-zero net but a SQUARE target is removable', async () => {
    // OWNER pays 12.000 equally → OWNER net +6.000 (creditor), MEMBER net -6.000.
    // THIRD is square (never in any event). Removing THIRD must succeed even
    // though the CALLER (OWNER) is not square — the gate is on net.get(TARGET).
    await seedGroup('g', { memberIds: [OWNER, MEMBER, THIRD] });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedMember('g', THIRD);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1');

    const res = await wrapped({
      data: { groupId: 'g', targetUserId: THIRD },
      auth: { uid: OWNER },
    } as any);

    expect(res).toMatchObject({ mode: 'removed', alreadyRemoved: false });
    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/third')).toBe(false);
  });

  test('13. uuid-keyed target member doc (userId field ≠ doc id, #294): found & deleted on remove', async () => {
    const targetDocId = 'b1a2c3-uuid-doc';
    await seedGroup('g');
    await seedMember('g', OWNER);
    // Target doc keyed by a random uuid with userId:MEMBER (a .doc(uid) lookup
    // would MISS it — match by the userId FIELD).
    await seedMember('g', MEMBER, {}, targetDocId);

    const res = await wrapped({
      data: { groupId: 'g', targetUserId: MEMBER },
      auth: { uid: OWNER },
    } as any);

    expect(res).toMatchObject({ mode: 'removed', alreadyRemoved: false });
    expect((await groupData('g')).memberIds).toEqual([OWNER]);
    expect(await docExists(`groups/g/members/${targetDocId}`)).toBe(false);
    expect(await membersWithUserId('g', MEMBER)).toBe(0);
  });

  test('14. ORTHOGONAL money-flow axis: target net zero ONLY because a DEPARTED THIRD settled their debt to the target; recomputeNet still nets target to zero → removal ALLOWED', async () => {
    // MONEY-FLOW / former-actor axis (not the creator-authz axis under test):
    // MEMBER pays 12.000 split equally over the 3-person event universe
    // {OWNER,MEMBER,THIRD} → each owes 4.000, so MEMBER is a +8.000 CREDITOR.
    // A departed THIRD (no longer a member, no member doc) settled 8.000 TO
    // MEMBER, and THIRD is still in the event participantIds. recomputeNet's
    // universe is participantIds ∪ (payers+settlement-parties \ live), so THIRD
    // stays in the universe; MEMBER's +8.000 credit is cancelled by the 8.000
    // settlement received → net[MEMBER] == 0 → removable, even though the
    // offsetting counterparty has DEPARTED (append-only settlement row persists).
    await seedGroup('g', { memberIds: [OWNER, MEMBER] });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    // THIRD departed: in participantIds + a settlement party, but NOT a member.
    await seedEvent('g', 'e1', {
      participantIds: [OWNER, MEMBER, THIRD],
      participantNames: { [OWNER]: 'Owner', [MEMBER]: 'Member', [THIRD]: 'Third' },
    });
    await seedExpense('groups/g/events/e1/expenses/x1', {
      payerParticipantId: MEMBER,
      createdBy: MEMBER,
    });
    // THIRD settles 8.000 to MEMBER → cancels MEMBER's +8.000 credit.
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: THIRD,
      recipientParticipantId: MEMBER,
      payerName: 'Third',
      recipientName: 'Member',
      amountFils: 8000,
      createdBy: THIRD,
    });

    const res = await wrapped({
      data: { groupId: 'g', targetUserId: MEMBER },
      auth: { uid: OWNER },
    } as any);

    expect(res).toMatchObject({ mode: 'removed', alreadyRemoved: false });
    expect((await groupData('g')).memberIds).toEqual([OWNER]);
    expect(await docExists('groups/g/members/member')).toBe(false);
  });
});
