import functionsTest from 'firebase-functions-test';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
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
import { decideClaimRequest } from '../../src/callables/decideClaimRequest';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(removeMember);
const wrappedDecide = testEnv.wrap(decideClaimRequest);

const OWNER = 'owner';
const MEMBER = 'member';
const THIRD = 'third';
const SHADOW = 'shadow-1210uuid';
const REQUESTER = 'requester';

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

// #1210 helpers: a placeholder shadow + a pending claim request against it.
async function seedShadow(
  groupId: string,
  shadowId: string,
  displayName = 'Ali',
): Promise<void> {
  await getFirestore().doc(`groups/${groupId}/members/${shadowId}`).set({
    id: shadowId,
    userId: shadowId,
    displayName,
    role: 'MEMBER',
    joinedAt: new Date('2026-01-03T00:00:00.000Z'),
    isShadow: true,
    isTombstone: false,
  });
}

async function seedClaimRequest(
  groupId: string,
  requester: string,
  shadowId: string,
  status = 'pending',
): Promise<string> {
  const rid = `${requester}__${shadowId}`;
  await getFirestore().doc(`groups/${groupId}/claimRequests/${rid}`).set({
    requesterUid: requester,
    requesterDisplayName: 'Khalid',
    shadowMemberId: shadowId,
    shadowDisplayName: 'Ali',
    status,
    createdAt: FieldValue.serverTimestamp(),
    decidedBy: null,
    decidedAt: null,
  });
  return rid;
}

const claimReqDoc = async (groupId: string, rid: string) =>
  (await getFirestore().doc(`groups/${groupId}/claimRequests/${rid}`).get()).data();

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

  test('5b. soft-deleted OR deletingInProgress group -> not-found; no membership/activity writes', async () => {
    await seedGroup('g1', { isDeleted: true });
    await seedMember('g1', OWNER);
    await seedMember('g1', MEMBER);

    await expect(
      wrapped({
        data: { groupId: 'g1', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
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
      wrapped({
        data: { groupId: 'g2', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'not-found' });

    expect((await groupData('g2')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g2/members/member')).toBe(true);
    expect(await activityDocs('g2')).toHaveLength(0);
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

  test('6b. #1132 departed creator (createdBy set, not in memberIds) is rejected with permission-denied; no writes', async () => {
    // Seed the net-zero removable state test 7 succeeds on, but drop OWNER from
    // memberIds (createdBy still OWNER) — so the isCurrentMember conjunct is the
    // SOLE failure cause (pre-fix this SUCCEEDS at removing THIRD).
    await seedGroup('g', { memberIds: [MEMBER, THIRD] });
    await seedMember('g', MEMBER);
    await seedMember('g', THIRD);

    await expect(
      wrapped({
        data: { groupId: 'g', targetUserId: THIRD },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'permission-denied' });

    expect((await groupData('g')).memberIds).toEqual([MEMBER, THIRD]);
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

  test('10b. mixed-currency group blocks removal when the target is non-zero in a bucket (#261/#382)', async () => {
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
      wrapped({
        data: { groupId: 'g', targetUserId: MEMBER },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    expect((await groupData('g')).memberIds).toEqual([OWNER, MEMBER]);
    expect(await docExists('groups/g/members/member')).toBe(true);
    expect(await activityDocs('g')).toHaveLength(0);
  });

  test('10c. mixed-currency group ALLOWS removal when the target is settled in EVERY bucket (#382 PR-2)', async () => {
    // Mirror of deleteGroup 9e for removeMember: a 2-currency group where the
    // target nets zero in each bucket. Pre-PR-2 the currencies.size>1 guard
    // refused unconditionally; the per-bucket gate now removes the square target.
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    // OMR: OWNER pays 10.000 global-equal → MEMBER owes 5.000; MEMBER→OWNER
    // 5.000 OMR clears MEMBER's OMR bucket.
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
    // USD clears MEMBER's USD bucket.
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
      data: { groupId: 'g', targetUserId: MEMBER },
      auth: { uid: OWNER },
    } as any);
    expect(res).toMatchObject({ mode: 'removed', alreadyRemoved: false });
    expect((await groupData('g')).memberIds).toEqual([OWNER]);
    expect(await docExists('groups/g/members/member')).toBe(false);
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

describe("removeMember retires a removed shadow's pending claim requests (#1210)", () => {
  test('1. RED→GREEN: removing a shadow declines its pending claim request atomically with the removal', async () => {
    await seedGroup('g', { memberIds: [OWNER, SHADOW] });
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW, 'Ali');
    const rid = await seedClaimRequest('g', REQUESTER, SHADOW);

    // Pre-state: the request is pending — this is what SURVIVES the removal on
    // UNFIXED code (the source of #1210: an Approve then hits the engine's
    // torn-cascade P0 instead of a clean short-circuit).
    expect((await claimReqDoc('g', rid))?.status).toBe('pending');

    const res = await wrapped({
      data: { groupId: 'g', targetUserId: SHADOW },
      auth: { uid: OWNER },
    } as any);

    expect(res).toMatchObject({ mode: 'removed', alreadyRemoved: false });
    expect((await groupData('g')).memberIds).toEqual([OWNER]);
    expect(await docExists(`groups/g/members/${SHADOW}`)).toBe(false);

    // The pending request was declined in the SAME commit as the removal, tagged
    // with the notifier-skip marker. On UNFIXED code this is still 'pending' → RED.
    const req = await claimReqDoc('g', rid);
    expect(req?.status).toBe('declined');
    expect(req?.autoDeclineReason).toBe('shadow-removed');
    expect(req?.decidedBy).toBe(OWNER);
  });

  test('2. E2E UX pin: an Approve on the swept request short-circuits (already-decided), never the engine torn-cascade internal + P0 log', async () => {
    await seedGroup('g', { memberIds: [OWNER, SHADOW] });
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW, 'Ali');
    const rid = await seedClaimRequest('g', REQUESTER, SHADOW);

    await wrapped({
      data: { groupId: 'g', targetUserId: SHADOW },
      auth: { uid: OWNER },
    } as any);
    expect((await claimReqDoc('g', rid))?.status).toBe('declined');

    // A creator with a stale Group Settings list taps Approve on the now-declined
    // request. The clean already-decided short-circuit fires — NOT the engine's
    // torn-cascade `internal` error.
    await expect(
      wrappedDecide({
        data: { groupId: 'g', requestId: rid, approve: true },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({
      code: 'failed-precondition',
      message: 'This claim request has already been decided.',
    });

    // …and the #558 Hole-2 torn-cascade P0 never fired (the engine was never reached).
    expect(logger.error).not.toHaveBeenCalledWith(
      expect.stringContaining('prior cascade torn'),
      expect.anything(),
    );
  });

  test('3. pre-tx heal: a pending request for an ALREADY-absent shadow is declined on the idempotent short-circuit (retry self-heals legacy/orphan rows)', async () => {
    // Shadow already fully gone (absent from memberIds, no member doc) but a
    // pending request lingers — a legacy row predating this fix, or a raced
    // orphan. removeMember hits the PRE-TX idempotent short-circuit and still
    // sweeps the row before returning alreadyRemoved.
    await seedGroup('g', { memberIds: [OWNER] });
    await seedMember('g', OWNER);
    const rid = await seedClaimRequest('g', REQUESTER, SHADOW);

    const res = await wrapped({
      data: { groupId: 'g', targetUserId: SHADOW },
      auth: { uid: OWNER },
    } as any);

    expect(res).toMatchObject({ mode: 'removed', alreadyRemoved: true });
    const req = await claimReqDoc('g', rid);
    expect(req?.status).toBe('declined');
    expect(req?.autoDeclineReason).toBe('shadow-removed');

    // The IN-TRANSACTION idempotent early-return branch (removeMember.ts,
    // `!freshTargetIsMember && freshTargetDocsSnap.empty`) is NOT deterministically
    // reachable in a single-threaded emulator — it needs a concurrent removal to
    // land between the pre-tx read and the tx re-read. It is covered by code
    // inspection: the claimRequests query read sits in the tx READS phase ABOVE
    // that branch (reads-before-writes), and the branch declines the swept rows
    // before its own `tx.update(groupRef, departureLockClearFields())`. A flaky
    // concurrency test is deliberately not written.
  });

  test('4. real-member removal with no claim requests: sweep is a no-op, removal behavior unchanged', async () => {
    await seedGroup('g'); // memberIds [OWNER, MEMBER]
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);

    const res = await wrapped({
      data: { groupId: 'g', targetUserId: MEMBER },
      auth: { uid: OWNER },
    } as any);

    expect(res).toMatchObject({ mode: 'removed', alreadyRemoved: false });
    expect((await groupData('g')).memberIds).toEqual([OWNER]);
    expect(await docExists('groups/g/members/member')).toBe(false);
    const snap = await getFirestore().collection('groups/g/claimRequests').get();
    expect(snap.size).toBe(0);
    expect(await activityDocs('g')).toHaveLength(1);
  });
});
