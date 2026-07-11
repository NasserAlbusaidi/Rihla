import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';

// RED → GREEN: #290 server-authoritative self-leave. The callable recomputes the
// LEAVER's net via the shared groupNetBalance oracle (exactly as the client
// BalanceCalculator), refuses with failed-precondition on a non-zero net, then
// atomically removes the uid from memberIds + deletes EVERY member doc matching
// `userId == uid` (creator docs are uuid-keyed, #294) + writes a `member_left`
// activity doc. Mirrors deleteGroup's authoritative pattern; the direct client
// self-leave path is locked in firestore.rules (validSelfLeave dropped).
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && npm run test:emulator -- leaveGroup.test.ts`

import { leaveGroup } from '../../src/callables/leaveGroup';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(leaveGroup);

const OWNER = 'owner';
const MEMBER = 'member';

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
  await getFirestore().doc(`groups/${groupId}/members/${docId ?? uid}`).set({
    id: docId ?? uid,
    userId: uid,
    displayName: uid === OWNER ? 'Owner' : 'Member',
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

describe('leaveGroup callable — server-authoritative self-leave + balance gate (#290)', () => {
  test('1. missing auth is rejected (unauthenticated)', async () => {
    await expect(
      wrapped({ data: { groupId: 'g' }, auth: undefined } as any),
    ).rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('2. invalid groupId ("" and "a/b") is rejected with invalid-argument', async () => {
    await expect(
      wrapped({ data: { groupId: '' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(
      wrapped({ data: { groupId: 'a/b' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('3. missing group is rejected with not-found', async () => {
    await expect(
      wrapped({ data: { groupId: 'ghost' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'not-found' });
  });

  test('3b. soft-deleted OR deletingInProgress group -> not-found; no membership/activity writes', async () => {
    await seedGroup('g1', { isDeleted: true });
    await seedMember('g1', OWNER);
    await seedMember('g1', MEMBER);

    await expect(
      wrapped({ data: { groupId: 'g1' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'not-found' });

    expect((await groupData('g1')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g1/members/member')).toBe(true);
    expect(await activityDocs('g1')).toHaveLength(0);

    await seedGroup('g2', {
      deletingInProgress: true,
      deleteLockedAt: new Date('2026-06-25T00:00:00.000Z'),
      deleteLockedBy: OWNER,
    });
    await seedMember('g2', OWNER);
    await seedMember('g2', MEMBER);

    await expect(
      wrapped({ data: { groupId: 'g2' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'not-found' });

    expect((await groupData('g2')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g2/members/member')).toBe(true);
    expect(await activityDocs('g2')).toHaveLength(0);
  });

  test('4. non-member (absent from memberIds, no member doc) → alreadyLeft, no writes', async () => {
    await seedGroup('g', { memberIds: [OWNER] });
    await seedMember('g', OWNER);

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: MEMBER },
    } as any);

    expect(res).toMatchObject({ groupId: 'g', mode: 'left', alreadyLeft: true });
    expect((await groupData('g')).memberIds).toEqual([OWNER]);
    expect(await activityDocs('g')).toHaveLength(0);
  });

  test('5. square member (no ledger activity) leaves: memberIds loses uid, member doc deleted, member_left logged', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: MEMBER },
    } as any);

    expect(res).toMatchObject({ groupId: 'g', mode: 'left', alreadyLeft: false });
    expect((await groupData('g')).memberIds).toEqual([OWNER]);
    expect(await docExists('groups/g/members/member')).toBe(false);

    const activity = await activityDocs('g');
    expect(activity).toHaveLength(1);
    expect(activity[0]).toMatchObject({
      type: 'member_left',
      actorId: MEMBER,
      actorName: 'Member',
      description: 'left the group',
    });
    expect(typeof activity[0].timestamp).toBe('string');
    expect(activity[0].metadata).toEqual({});
  });

  test('6. settled member (event settlement zeroes the owed) may leave', async () => {
    // OWNER pays 12.000 OMR equally between OWNER+MEMBER → MEMBER owes 6.000;
    // MEMBER settles 6.000 to OWNER → net[MEMBER] == 0.
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1');
    await seedEventSettlement('groups/g/events/e1/settlements/s1');

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: MEMBER },
    } as any);

    expect(res).toMatchObject({ mode: 'left', alreadyLeft: false });
    expect((await groupData('g')).memberIds).toEqual([OWNER]);
    expect(await docExists('groups/g/members/member')).toBe(false);
  });

  test('7. debtor (non-zero net) is rejected with failed-precondition; no writes', async () => {
    // OWNER pays 12.000 equally → MEMBER owes 6.000, never settled.
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1');

    await expect(
      wrapped({ data: { groupId: 'g' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
    expect(await activityDocs('g')).toHaveLength(0);
  });

  test('8. creditor (positive net) is also blocked', async () => {
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
      wrapped({ data: { groupId: 'g' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER]);
  });

  test('8b. mixed-currency group blocks leave when the leaver is non-zero in a bucket (#261/#382)', async () => {
    // OWNER pays 10.000 OMR (equal → each owes 5.000) → OMR bucket MEMBER −5;
    // MEMBER pays 10.00 USD (equal → each owes 5.00) → USD bucket MEMBER +5.
    // #382 PR-2: MEMBER is non-zero in BOTH buckets → the per-bucket gate
    // refuses. (Pre-PR-2 the flat scalar MEMBER net = 10 − 5 − 5 faked zero and
    // only currencies.size>1 caught the money-loss path.)
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
      wrapped({ data: { groupId: 'g' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
  });

  test('9. creator member doc is uuid-keyed (userId field ≠ doc id, #294): found & deleted on leave', async () => {
    const creatorDocId = 'b1a2c3-uuid-doc';
    await seedGroup('g');
    // Creator doc keyed by a random uuid with userId:OWNER (group_provider.dart).
    await seedMember('g', OWNER, {}, creatorDocId);
    await seedMember('g', MEMBER);

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);

    expect(res).toMatchObject({ mode: 'left', alreadyLeft: false });
    expect((await groupData('g')).memberIds).toEqual([MEMBER]);
    // The uuid-keyed creator doc (a .doc(uid) lookup would MISS it) is deleted.
    expect(await docExists(`groups/g/members/${creatorDocId}`)).toBe(false);
    expect(await membersWithUserId('g', OWNER)).toBe(0);
  });

  test('8c. mixed-currency group ALLOWS leave when the leaver is settled in EVERY bucket (#382 PR-2)', async () => {
    // Mirror of deleteGroup 9e for leave: a 2-currency group where the leaver
    // nets zero in each bucket. Pre-PR-2 the currencies.size>1 guard refused
    // unconditionally; the per-bucket gate now lets the square leaver out.
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    // OMR: OWNER pays 10.000 global-equal → MEMBER owes 5.000; MEMBER→OWNER
    // 5.000 OMR clears MEMBER's OMR bucket to zero.
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 10000,
      currency: 'OMR',
      payerParticipantId: OWNER,
      createdBy: OWNER,
    });
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: MEMBER,
      recipientParticipantId: OWNER,
      amountFils: 5000,
      currency: 'OMR',
    });
    // USD: OWNER pays 10.00 global-equal → MEMBER owes 5.00; MEMBER→OWNER 5.00
    // USD clears MEMBER's USD bucket to zero.
    await seedExpense('groups/g/events/e1/expenses/x2', {
      amountFils: 1000,
      currency: 'USD',
      payerParticipantId: OWNER,
      createdBy: OWNER,
    });
    await seedEventSettlement('groups/g/events/e1/settlements/s2', {
      payerParticipantId: MEMBER,
      recipientParticipantId: OWNER,
      amountFils: 500,
      currency: 'USD',
    });

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: MEMBER },
    } as any);
    expect(res).toMatchObject({ mode: 'left', alreadyLeft: false });
    expect((await groupData('g')).memberIds).toEqual([OWNER]);
  });
});

// #1138: creator succession. leaveGroup never reassigned createdBy, so a creator
// leave produced an admin-less group under the #1132 membership-conjunct rules
// (and a permanently admin-less one after leave-then-deleteAccount, which skips
// non-member groups). Succession mirrors deleteAccount Phase C: hand createdBy
// to the oldest real remaining member (never an unclaimed shadow — it's in
// memberIds via addShadowMember's arrayUnion but never AUTHENTICATES — and never
// a torn doc whose userId fell out of memberIds), flip that member's roster
// role, and soft-delete the group when no real survivor exists.
describe('#1138 creator succession on leave', () => {
  const memberDoc = async (groupId: string, docId: string) =>
    (await getFirestore().doc(`groups/${groupId}/members/${docId}`).get()).data() ?? {};

  test('S1. creator leave hands createdBy to the survivor and flips their roster role', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);

    const res = await wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any);

    expect(res).toMatchObject({ mode: 'left', alreadyLeft: false });
    const g = await groupData('g');
    expect(g.createdBy).toBe(MEMBER);
    expect(g.isDeleted).toBeFalsy();
    expect(g.memberIds).toEqual([MEMBER]);
    // #1144 lock released atomically with the succession write.
    expect(g.departureInProgress).toBe(false);
    expect(g.departureLockedBy).toBeUndefined();
    // The roster badge reads member.role, not group.createdBy — keep it truthful.
    expect((await memberDoc('g', MEMBER)).role).toBe('CREATOR');
    const activity = await activityDocs('g');
    expect(activity).toEqual([expect.objectContaining({ type: 'member_left', actorId: OWNER })]);
  });

  test('S2. oldest-joined real member wins succession', async () => {
    await seedGroup('g', { memberIds: [OWNER, MEMBER, 'third'] });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER, { joinedAt: new Date('2026-01-02T00:00:00.000Z') });
    await seedMember('g', 'third', { joinedAt: new Date('2026-01-03T00:00:00.000Z') });

    await wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any);

    expect((await groupData('g')).createdBy).toBe(MEMBER);
    expect((await memberDoc('g', MEMBER)).role).toBe('CREATOR');
    expect((await memberDoc('g', 'third')).role).toBe('MEMBER');
  });

  test('S3. an unclaimed shadow is never appointed, even when it joined first', async () => {
    // Production shape: addShadowMember arrayUnions the shadow uuid INTO
    // memberIds, so only the isShadow flag can exclude it. Seed it IN memberIds
    // and OLDER than the real member — the succession must skip it anyway.
    const shadowUuid = 'shadow-uuid-1111';
    await seedGroup('g', { memberIds: [OWNER, MEMBER, shadowUuid] });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER, { joinedAt: new Date('2026-01-02T00:00:00.000Z') });
    await seedMember(
      'g',
      shadowUuid,
      { isShadow: true, joinedAt: new Date('2026-01-01T00:00:00.000Z') },
      shadowUuid,
    );

    await wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any);

    expect((await groupData('g')).createdBy).toBe(MEMBER);
    expect((await memberDoc('g', MEMBER)).role).toBe('CREATOR');
    expect((await memberDoc('g', shadowUuid)).role).toBe('MEMBER');
  });

  test('S4. no real survivor -> the group is soft-deleted, createdBy tombstoned', async () => {
    const shadowUuid = 'shadow-uuid-2222';
    await seedGroup('g', { memberIds: [OWNER, shadowUuid] });
    await seedMember('g', OWNER);
    await seedMember('g', shadowUuid, { isShadow: true }, shadowUuid);

    const res = await wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any);

    expect(res).toMatchObject({ mode: 'left', alreadyLeft: false });
    const g = await groupData('g');
    expect(g.isDeleted).toBe(true);
    expect(g.deletedAt).toBeTruthy();
    expect(g.createdBy).toBe('deleted-user');
    // Mirror deleteAccount's no-survivor branch: no shadow-doc cleanup.
    expect(await docExists(`groups/g/members/${shadowUuid}`)).toBe(true);
  });

  test('S5. a non-creator leave never touches createdBy or roles', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);

    await wrapped({ data: { groupId: 'g' }, auth: { uid: MEMBER } } as any);

    const g = await groupData('g');
    expect(g.createdBy).toBe(OWNER);
    expect(g.isDeleted).toBeFalsy();
    expect((await memberDoc('g', OWNER)).role).toBe('CREATOR');
  });

  test('S6. a torn doc whose userId fell out of memberIds is never appointed', async () => {
    // Defense-in-depth: a non-shadow doc outside memberIds would be equally
    // admin-less as createdBy (#1132 rules require createdBy ∈ memberIds). The
    // ghost joins EARLIER than MEMBER so ordering alone cannot save the test.
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER, { joinedAt: new Date('2026-01-02T00:00:00.000Z') });
    await seedMember(
      'g',
      'ghost',
      { joinedAt: new Date('2026-01-01T00:00:00.000Z') },
      'ghost-doc',
    );

    await wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any);

    expect((await groupData('g')).createdBy).toBe(MEMBER);
    expect((await memberDoc('g', MEMBER)).role).toBe('CREATOR');
    expect((await memberDoc('g', 'ghost-doc')).role).toBe('MEMBER');
  });
});
