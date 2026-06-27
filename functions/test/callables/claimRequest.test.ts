import functionsTest from 'firebase-functions-test';
import { getFirestore, FieldValue, Timestamp, WriteBatch } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';

// RED → GREEN: #278 claim/merge PR8 — creator-approval request/approve flow.
// A real (durable) person REQUESTS to claim a placeholder ("shadow") member
// (pre-join, D8); the group CREATOR APPROVES; only an approved decideClaimRequest
// invokes the PR7 re-key engine (claimShadowEngine), which is otherwise
// unreachable (the raw onCall was de-exported). This is the impersonation gate.
// listMyClaimRequests (requester poll) + listGroupClaimRequests (creator poll)
// surface the read-gated claimRequests collection via callables.
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/claimRequest.test.ts" npm run test:emulator`

import { requestClaimShadow } from '../../src/callables/requestClaimShadow';
import { decideClaimRequest } from '../../src/callables/decideClaimRequest';
import { listMyClaimRequests } from '../../src/callables/listMyClaimRequests';
import { listGroupClaimRequests } from '../../src/callables/listGroupClaimRequests';
import { claimShadowEngine } from '../../src/callables/claimShadow';
import { recomputeNet } from '../../src/callables/groupNetBalance';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrappedRequest = testEnv.wrap(requestClaimShadow);
const wrappedDecide = testEnv.wrap(decideClaimRequest);
const wrappedListMy = testEnv.wrap(listMyClaimRequests);
const wrappedListGroup = testEnv.wrap(listGroupClaimRequests);

const OWNER = 'owner';
const CLAIMER = 'claimer'; // a durable real uid (the requester)
const MEMBER2 = 'member2';
const OUTSIDER = 'outsider';
const SHADOW = 'shadow-7f3a9c';
const CODE = 'ABC123';

type Auth = { uid: string; token: { firebase: { sign_in_provider: string } } };
function authOf(uid: string, provider = 'password'): Auth {
  return { uid, token: { firebase: { sign_in_provider: provider } } };
}
// requestClaimShadow / listMyClaimRequests default to the durable requester;
// decideClaimRequest / listGroupClaimRequests default to the creator.
const reqClaim = (data: Record<string, unknown>, auth: Auth | undefined = authOf(CLAIMER)) =>
  wrappedRequest({ data, auth } as never);
const decide = (data: Record<string, unknown>, auth: Auth | undefined = authOf(OWNER)) =>
  wrappedDecide({ data, auth } as never);
const listMy = (data: Record<string, unknown>, auth: Auth | undefined = authOf(CLAIMER)) =>
  wrappedListMy({ data, auth } as never);
const listGroup = (data: Record<string, unknown>, auth: Auth | undefined = authOf(OWNER)) =>
  wrappedListGroup({ data, auth } as never);

const reqId = (requester: string, shadow: string) => `${requester}__${shadow}`;

async function seedGroup(
  groupId: string,
  memberIds: string[],
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore().doc(`groups/${groupId}`).set({
    id: groupId,
    name: groupId,
    inviteCode: CODE,
    createdBy: OWNER,
    memberIds,
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
): Promise<void> {
  await getFirestore().doc(`groups/${groupId}/members/${uid}`).set({
    id: uid,
    userId: uid,
    displayName: uid === OWNER ? 'Owner' : uid,
    role: uid === OWNER ? 'CREATOR' : 'MEMBER',
    joinedAt: new Date('2026-01-01T00:00:00.000Z'),
    isShadow: false,
    ...data,
  });
}

async function seedShadow(
  groupId: string,
  shadowId: string,
  displayName = 'Ali',
  data: Record<string, unknown> = {},
): Promise<void> {
  await seedMember(groupId, shadowId, {
    displayName,
    role: 'MEMBER',
    isShadow: true,
    joinedAt: new Date('2026-01-03T00:00:00.000Z'),
    ...data,
  });
}

async function seedEvent(
  groupId: string,
  eventId: string,
  participantIds: string[],
  participantNames: Record<string, string>,
): Promise<void> {
  await getFirestore().doc(`groups/${groupId}/events/${eventId}`).set({
    id: eventId,
    groupId,
    name: eventId,
    type: 'trip',
    createdBy: OWNER,
    participantIds,
    participantNames,
    modules: { ledger: true },
    isDeleted: false,
    deletedAt: null,
    createdAt: new Date('2026-01-04T00:00:00.000Z'),
  });
}

async function seedExpense(path: string, data: Record<string, unknown> = {}): Promise<void> {
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

async function seedInviteCode(code: string, groupId: string): Promise<void> {
  await getFirestore().doc(`inviteCodes/${code}`).set({
    code,
    groupId,
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
  });
}

// Directly seed a pending claimRequests doc (decide tests should not depend on
// requestClaimShadow's correctness).
async function seedPendingRequest(
  groupId: string,
  requester: string,
  shadow: string,
  shadowName = 'Ali',
  status = 'pending',
): Promise<string> {
  const rid = reqId(requester, shadow);
  await getFirestore().doc(`groups/${groupId}/claimRequests/${rid}`).set({
    requesterUid: requester,
    requesterDisplayName: 'Khalid',
    shadowMemberId: shadow,
    shadowDisplayName: shadowName,
    status,
    createdAt: FieldValue.serverTimestamp(),
    decidedBy: null,
    decidedAt: null,
  });
  return rid;
}

const groupDoc = async (groupId: string) =>
  (await getFirestore().doc(`groups/${groupId}`).get()).data() ?? {};
const memberDoc = async (groupId: string, docId: string) =>
  (await getFirestore().doc(`groups/${groupId}/members/${docId}`).get()).data();
const expenseDoc = async (path: string) =>
  (await getFirestore().doc(path).get()).data() ?? {};
const memberDocCount = async (groupId: string) =>
  (await getFirestore().collection(`groups/${groupId}/members`).get()).size;
const reqDoc = async (groupId: string, rid: string) =>
  (await getFirestore().doc(`groups/${groupId}/claimRequests/${rid}`).get()).data();
const reqCount = async (groupId: string) =>
  (await getFirestore().collection(`groups/${groupId}/claimRequests`).get()).size;

async function nets(groupId: string) {
  const { net } = await recomputeNet(getFirestore(), getFirestore().doc(`groups/${groupId}`));
  return net;
}
function omr(net: Map<string, Map<string, unknown>>, uid: string): string {
  const v = net.get('OMR')?.get(uid) as { toFixed: (d: number) => string } | undefined;
  return v ? v.toFixed(3) : 'absent';
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

describe('requestClaimShadow (#278 PR8)', () => {
  test('R1. missing auth → unauthenticated; anonymous → permission-denied; no request', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW);
    await seedInviteCode(CODE, 'g');
    await expect(
      wrappedRequest({ data: { inviteCode: CODE, shadowMemberId: SHADOW }, auth: undefined } as never),
    ).rejects.toMatchObject({ code: 'unauthenticated' });
    await expect(
      reqClaim({ inviteCode: CODE, shadowMemberId: SHADOW }, authOf(CLAIMER, 'anonymous')),
    ).rejects.toMatchObject({ code: 'permission-denied' });
    expect(await reqCount('g')).toBe(0);
  });

  test('R2. malformed invite code → invalid-argument; unknown code → not-found', async () => {
    await expect(reqClaim({ inviteCode: 'bad', shadowMemberId: SHADOW })).rejects.toMatchObject({
      code: 'invalid-argument',
    });
    await expect(reqClaim({ inviteCode: 'ZZ9999', shadowMemberId: SHADOW })).rejects.toMatchObject({
      code: 'not-found',
    });
  });

  test('R3. durable non-member + valid code + claimable shadow → pending request written', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW, 'Ali');
    await seedInviteCode(CODE, 'g');

    const res = (await reqClaim({
      inviteCode: CODE,
      shadowMemberId: SHADOW,
      displayName: 'Khalid',
    })) as { requestId: string; status: string; groupId: string };

    expect(res).toMatchObject({ requestId: reqId(CLAIMER, SHADOW), status: 'pending', groupId: 'g' });
    expect(await reqDoc('g', reqId(CLAIMER, SHADOW))).toMatchObject({
      requesterUid: CLAIMER,
      requesterDisplayName: 'Khalid',
      shadowMemberId: SHADOW,
      shadowDisplayName: 'Ali',
      status: 'pending',
    });
    expect(await reqCount('g')).toBe(1);
  });

  test('R4. target not a claimable shadow (real member / tombstoned) → failed-precondition; no request', async () => {
    await seedGroup('g', [OWNER, MEMBER2]);
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER2);
    await seedInviteCode(CODE, 'g');
    await expect(reqClaim({ inviteCode: CODE, shadowMemberId: MEMBER2 })).rejects.toMatchObject({
      code: 'failed-precondition',
    });
    await seedShadow('g', SHADOW, 'Ali', { isTombstone: true });
    await getFirestore().doc('groups/g').update({ memberIds: [OWNER, MEMBER2, SHADOW] });
    await expect(reqClaim({ inviteCode: CODE, shadowMemberId: SHADOW })).rejects.toMatchObject({
      code: 'failed-precondition',
    });
    expect(await reqCount('g')).toBe(0);
  });

  test('R5. requester already a member of the group → failed-precondition; no request', async () => {
    await seedGroup('g', [OWNER, CLAIMER, SHADOW]);
    await seedMember('g', OWNER);
    await seedMember('g', CLAIMER);
    await seedShadow('g', SHADOW);
    await seedInviteCode(CODE, 'g');
    await expect(reqClaim({ inviteCode: CODE, shadowMemberId: SHADOW })).rejects.toMatchObject({
      code: 'failed-precondition',
    });
    expect(await reqCount('g')).toBe(0);
  });

  test('R6. idempotent re-request → one single pending doc', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW);
    await seedInviteCode(CODE, 'g');
    await reqClaim({ inviteCode: CODE, shadowMemberId: SHADOW });
    await reqClaim({ inviteCode: CODE, shadowMemberId: SHADOW });
    expect(await reqCount('g')).toBe(1);
    expect((await reqDoc('g', reqId(CLAIMER, SHADOW)))?.status).toBe('pending');
  });

  test('R7. re-request after a decline → re-opens the same doc to pending', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW);
    await seedInviteCode(CODE, 'g');
    await reqClaim({ inviteCode: CODE, shadowMemberId: SHADOW });
    await decide({ groupId: 'g', requestId: reqId(CLAIMER, SHADOW), approve: false });
    expect((await reqDoc('g', reqId(CLAIMER, SHADOW)))?.status).toBe('declined');
    const res = (await reqClaim({ inviteCode: CODE, shadowMemberId: SHADOW })) as { status: string };
    expect(res.status).toBe('pending');
    expect(await reqCount('g')).toBe(1);
    expect((await reqDoc('g', reqId(CLAIMER, SHADOW)))?.status).toBe('pending');
  });

  test('#710 R8. re-request while existing request is claiming rejects and preserves lock fields', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW);
    await seedInviteCode(CODE, 'g');
    const rid = await seedPendingRequest('g', CLAIMER, SHADOW);
    const claimingAt = Timestamp.fromMillis(1234);
    const mutationStartedAt = Timestamp.fromMillis(5678);
    await getFirestore().doc(`groups/g/claimRequests/${rid}`).update({
      status: 'claiming',
      requesterDisplayName: 'Original requester',
      claimingBy: OWNER,
      claimingAt,
      claimMutationStartedAt: mutationStartedAt,
    });

    await expect(
      reqClaim({ inviteCode: CODE, shadowMemberId: SHADOW, displayName: 'New Name' }),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    expect(await reqDoc('g', rid)).toMatchObject({
      requesterUid: CLAIMER,
      requesterDisplayName: 'Original requester',
      shadowMemberId: SHADOW,
      status: 'claiming',
      claimingBy: OWNER,
      claimingAt,
      claimMutationStartedAt: mutationStartedAt,
    });
  });
});

describe('decideClaimRequest (#278 PR8)', () => {
  test('D1. missing auth → unauthenticated; anonymous → permission-denied; request unchanged', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW);
    const rid = await seedPendingRequest('g', CLAIMER, SHADOW);
    await expect(
      wrappedDecide({ data: { groupId: 'g', requestId: rid, approve: true }, auth: undefined } as never),
    ).rejects.toMatchObject({ code: 'unauthenticated' });
    await expect(
      decide({ groupId: 'g', requestId: rid, approve: true }, authOf(OWNER, 'anonymous')),
    ).rejects.toMatchObject({ code: 'permission-denied' });
    expect((await reqDoc('g', rid))?.status).toBe('pending');
  });

  test('D2. NON-creator (member or outsider) → permission-denied; request unchanged [CORE D1 GATE]', async () => {
    await seedGroup('g', [OWNER, MEMBER2, SHADOW]);
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER2);
    await seedShadow('g', SHADOW);
    const rid = await seedPendingRequest('g', CLAIMER, SHADOW);
    await expect(
      decide({ groupId: 'g', requestId: rid, approve: true }, authOf(MEMBER2)),
    ).rejects.toMatchObject({ code: 'permission-denied' });
    await expect(
      decide({ groupId: 'g', requestId: rid, approve: true }, authOf(OUTSIDER)),
    ).rejects.toMatchObject({ code: 'permission-denied' });
    expect((await reqDoc('g', rid))?.status).toBe('pending');
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, MEMBER2, SHADOW]);
  });

  test('D3. invalid groupId / requestId / non-boolean approve → invalid-argument', async () => {
    await expect(decide({ groupId: 'a/b', requestId: 'x', approve: true })).rejects.toMatchObject({
      code: 'invalid-argument',
    });
    await expect(decide({ groupId: 'g', requestId: '', approve: true })).rejects.toMatchObject({
      code: 'invalid-argument',
    });
    await expect(decide({ groupId: 'g', requestId: 'x', approve: 'yes' })).rejects.toMatchObject({
      code: 'invalid-argument',
    });
  });

  test('D4. missing / soft-deleted / deletingInProgress group → not-found', async () => {
    await expect(
      decide({ groupId: 'nope', requestId: reqId(CLAIMER, SHADOW), approve: true }),
    ).rejects.toMatchObject({ code: 'not-found' });
    await seedGroup('g1', [OWNER, SHADOW], { isDeleted: true });
    await expect(
      decide({ groupId: 'g1', requestId: reqId(CLAIMER, SHADOW), approve: true }),
    ).rejects.toMatchObject({ code: 'not-found' });
    await seedGroup('g2', [OWNER, SHADOW], { deletingInProgress: true });
    await expect(
      decide({ groupId: 'g2', requestId: reqId(CLAIMER, SHADOW), approve: true }),
    ).rejects.toMatchObject({ code: 'not-found' });
  });

  test('D5. requestId not found → not-found', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW);
    await expect(
      decide({ groupId: 'g', requestId: 'claimer__missing', approve: true }),
    ).rejects.toMatchObject({ code: 'not-found' });
  });

  test('D6. decline (approve:false) → status declined, no engine call, shadow + memberIds untouched', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW, 'Ali');
    const rid = await seedPendingRequest('g', CLAIMER, SHADOW);
    const res = (await decide({ groupId: 'g', requestId: rid, approve: false })) as { status: string };
    expect(res.status).toBe('declined');
    const doc = await reqDoc('g', rid);
    expect(doc?.status).toBe('declined');
    expect(doc?.decidedBy).toBe(OWNER);
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, SHADOW]);
    expect(await memberDoc('g', SHADOW)).toBeDefined();
    expect(await memberDoc('g', CLAIMER)).toBeUndefined();
  });

  test('D7. already-decided request (claimed OR declined) → failed-precondition (idempotent)', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW);
    const ridDeclined = await seedPendingRequest('g', CLAIMER, SHADOW, 'Ali', 'declined');
    await expect(
      decide({ groupId: 'g', requestId: ridDeclined, approve: true }),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    const ridClaimed = await seedPendingRequest('g', MEMBER2, SHADOW, 'Ali', 'claimed');
    await expect(
      decide({ groupId: 'g', requestId: ridClaimed, approve: false }),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('D8. approve a DEBTOR shadow → engine runs: memberIds swap, member doc copy (D7 name), claimer inherits −6.000, status claimed', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW, 'Ali');
    await seedEvent('g', 'e1', [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });
    await seedExpense('groups/g/events/e1/expenses/x1', { payerParticipantId: OWNER, amountFils: 12000 });
    const rid = await seedPendingRequest('g', CLAIMER, SHADOW, 'Ali');

    const res = (await decide({ groupId: 'g', requestId: rid, approve: true })) as {
      status: string;
      alreadyClaimed: boolean;
    };

    expect(res.status).toBe('claimed');
    expect(res.alreadyClaimed).toBe(false);
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, CLAIMER]);
    expect(await memberDoc('g', CLAIMER)).toMatchObject({
      userId: CLAIMER,
      displayName: 'Ali', // D7 — keeps the shadow's name, NOT the requester's "Khalid"
      isShadow: false,
    });
    expect(await memberDoc('g', SHADOW)).toBeUndefined();
    const net = await nets('g');
    expect(omr(net, CLAIMER)).toBe('-6.000');
    expect(omr(net, OWNER)).toBe('6.000');
    expect(omr(net, SHADOW)).toBe('absent');
    const request = await reqDoc('g', rid);
    expect(request?.status).toBe('claimed');
    expect(request?.claimMutationStartedAt).toBeInstanceOf(Timestamp);
    expect((await getFirestore().doc(`groups/g/claimShadowLocks/${SHADOW}`).get()).exists).toBe(false);
    expect(await groupDoc('g')).not.toMatchObject({ claimingInProgress: true });
  });

  test('D9. approve when the requester is ALREADY a member → engine failed-precondition; request stays pending; nothing mutated', async () => {
    await seedGroup('g', [OWNER, CLAIMER, SHADOW]);
    await seedMember('g', OWNER);
    await seedMember('g', CLAIMER, { displayName: 'Khalid' });
    await seedShadow('g', SHADOW, 'Ali');
    await seedEvent('g', 'e1', [OWNER, CLAIMER, SHADOW], {
      [OWNER]: 'Owner',
      [CLAIMER]: 'Khalid',
      [SHADOW]: 'Ali',
    });
    await seedExpense('groups/g/events/e1/expenses/x1', { payerParticipantId: OWNER, amountFils: 12000 });
    const rid = await seedPendingRequest('g', CLAIMER, SHADOW);

    await expect(decide({ groupId: 'g', requestId: rid, approve: true })).rejects.toMatchObject({
      code: 'failed-precondition',
    });
    expect((await reqDoc('g', rid))?.status).toBe('pending'); // NOT claimed
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, CLAIMER, SHADOW]);
    expect(await memberDoc('g', SHADOW)).toBeDefined();
    expect(await memberDocCount('g')).toBe(3);
    // #714 P1-B (Gate): a pre-mutation reject must also tear down the CAS-created lock
    // and the group freeze (resetPreMutationClaimReservation), else the group stays
    // write-frozen on a rejected approval.
    expect((await getFirestore().doc(`groups/g/claimShadowLocks/${SHADOW}`).get()).exists).toBe(false);
    expect((await groupDoc('g')).claimingInProgress).toBeUndefined();
  });

  test('D10. double-approve → second sees status != pending → failed-precondition (engine idempotency = no double-merge)', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW, 'Ali');
    await seedEvent('g', 'e1', [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });
    await seedExpense('groups/g/events/e1/expenses/x1', { payerParticipantId: OWNER, amountFils: 12000 });
    const rid = await seedPendingRequest('g', CLAIMER, SHADOW, 'Ali');

    await decide({ groupId: 'g', requestId: rid, approve: true });
    await expect(decide({ groupId: 'g', requestId: rid, approve: true })).rejects.toMatchObject({
      code: 'failed-precondition',
    });
    expect(omr(await nets('g'), CLAIMER)).toBe('-6.000'); // NOT doubled
  });

  test('D11. impersonation seal: an injected claimerUid in the payload is IGNORED — re-key target is the doc requesterUid', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW, 'Ali');
    await seedEvent('g', 'e1', [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });
    await seedExpense('groups/g/events/e1/expenses/x1', { payerParticipantId: OWNER, amountFils: 12000 });
    const rid = await seedPendingRequest('g', CLAIMER, SHADOW, 'Ali');

    // A creator (or MITM) tries to redirect the claim onto OUTSIDER by injecting
    // a claimerUid the input type does not carry. It MUST be ignored.
    await decide({ groupId: 'g', requestId: rid, approve: true, claimerUid: OUTSIDER, shadowMemberId: OUTSIDER });

    expect((await groupDoc('g')).memberIds).toEqual([OWNER, CLAIMER]); // NOT OUTSIDER
    expect(await memberDoc('g', OUTSIDER)).toBeUndefined();
    expect(await memberDoc('g', CLAIMER)).toMatchObject({ isShadow: false });
    expect(omr(await nets('g'), CLAIMER)).toBe('-6.000');
  });

  test('D12. crash-retry: engine already re-keyed but status stuck pending → re-approve DECLINES (membership + balance intact, money never doubled)', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW, 'Ali');
    await seedEvent('g', 'e1', [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });
    await seedExpense('groups/g/events/e1/expenses/x1', { payerParticipantId: OWNER, amountFils: 12000 });
    const rid = await seedPendingRequest('g', CLAIMER, SHADOW, 'Ali');

    // Simulate a first decide whose engine COMMITTED the re-key, then crashed
    // before the status write — request stuck 'pending', shadow already retired.
    await claimShadowEngine(getFirestore(), getFirestore().doc('groups/g'), SHADOW, CLAIMER);
    expect((await reqDoc('g', rid))?.status).toBe('pending');
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, CLAIMER]);

    // Re-approve: the shadow is GONE → alreadyClaimed:true → DECLINE (this approval
    // claimed nothing THIS time; status:'claimed' is reserved for a fresh re-key).
    // CLAIMER stays a correct member with the balance from the crashed run — only
    // the advisory label lags (a self-correcting false-negative; money is correct).
    await expect(decide({ groupId: 'g', requestId: rid, approve: true })).rejects.toMatchObject({
      code: 'failed-precondition',
    });
    expect((await reqDoc('g', rid))?.status).toBe('declined');
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, CLAIMER]); // membership intact
    expect(omr(await nets('g'), CLAIMER)).toBe('-6.000'); // balance intact, NOT doubled
    expect(await memberDocCount('g')).toBe(2);
  });

  test('D13. two requesters for ONE shadow: approving the LOSER after the winner claimed → failed-precondition, loser declined, NO phantom claim', async () => {
    // Refute-found gap: two distinct durable users can each hold a pending request
    // for the same shadow (requestClaimShadow keys by requesterUid__shadowMemberId,
    // no one-pending-per-shadow guard — a duplicate-name group is legitimate). The
    // engine returns alreadyClaimed:true whenever the shadow is GONE, identity-blind
    // to who retired it — so approving the loser must NOT be flipped to 'claimed'
    // (that requester inherited nothing). It must lose the race gracefully.
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW, 'Ali');
    await seedEvent('g', 'e1', [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });
    await seedExpense('groups/g/events/e1/expenses/x1', { payerParticipantId: OWNER, amountFils: 12000 });
    const ridWinner = await seedPendingRequest('g', CLAIMER, SHADOW, 'Ali');
    const ridLoser = await seedPendingRequest('g', OUTSIDER, SHADOW, 'Ali');

    // Creator approves the winner → CLAIMER inherits the shadow.
    await decide({ groupId: 'g', requestId: ridWinner, approve: true });
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, CLAIMER]);

    // Creator then approves the loser → shadow gone → must reject, not phantom-claim.
    await expect(decide({ groupId: 'g', requestId: ridLoser, approve: true })).rejects.toMatchObject({
      code: 'failed-precondition',
    });
    expect((await reqDoc('g', ridLoser))?.status).toBe('declined'); // NOT 'claimed'
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, CLAIMER]); // OUTSIDER not added
    expect(await memberDoc('g', OUTSIDER)).toBeUndefined();
    expect(omr(await nets('g'), CLAIMER)).toBe('-6.000'); // winner's balance intact, not doubled
  });

  test('D14. multi-shadow sibling (automerge-refute R2): claiming a DIFFERENT shadow must NOT let a stale request phantom-claim one a third party took', async () => {
    // The refute repro on the identity axis: requester CLAIMER holds pending
    // requests for two shadows (s1, s2). OUTSIDER claims s1; CLAIMER claims s2 and
    // becomes a member. Approving CLAIMER's stale s1 request finds s1 GONE →
    // alreadyClaimed:true. CLAIMER ∈ memberIds (via s2), so a memberIds-only guard
    // would phantom-mark s1 'claimed'. The fix (status:'claimed' only on a fresh
    // re-key) DECLINES it — CLAIMER inherited nothing from s1.
    await seedGroup('g', [OWNER, 's1', 's2']);
    await seedMember('g', OWNER);
    await seedShadow('g', 's1', 'Ali');
    await seedShadow('g', 's2', 'Sara');
    const ridClaimerS1 = await seedPendingRequest('g', CLAIMER, 's1', 'Ali');
    const ridClaimerS2 = await seedPendingRequest('g', CLAIMER, 's2', 'Sara');
    const ridOutsiderS1 = await seedPendingRequest('g', OUTSIDER, 's1', 'Ali');

    await decide({ groupId: 'g', requestId: ridOutsiderS1, approve: true }); // OUTSIDER claims s1
    await decide({ groupId: 'g', requestId: ridClaimerS2, approve: true }); // CLAIMER claims s2 → member
    expect([...((await groupDoc('g')).memberIds as string[])].sort()).toEqual(
      [CLAIMER, OUTSIDER, OWNER].sort(),
    );

    // CLAIMER's stale s1 request: s1 was taken by OUTSIDER → DECLINE, not claim.
    await expect(decide({ groupId: 'g', requestId: ridClaimerS1, approve: true })).rejects.toMatchObject({
      code: 'failed-precondition',
    });
    expect((await reqDoc('g', ridClaimerS1))?.status).toBe('declined'); // NOT 'claimed'
  });

  test('#710 D15. active claim freeze rejects a second approval for the same shadow before money mutation', async () => {
    await seedGroup('g', [OWNER, SHADOW], {
      claimingInProgress: true,
      claimLockedAt: Timestamp.fromMillis(1000),
    });
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW, 'Ali');
    await seedEvent('g', 'e1', [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });
    await seedExpense('groups/g/events/e1/expenses/x1', {
      payerParticipantId: OWNER,
      amountFils: 12000,
    });
    const rid = await seedPendingRequest('g', OUTSIDER, SHADOW, 'Ali');

    await expect(decide({ groupId: 'g', requestId: rid, approve: true })).rejects.toMatchObject({
      code: expect.stringMatching(/^(aborted|failed-precondition)$/),
    });

    expect((await reqDoc('g', rid))?.status).toBe('pending');
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, SHADOW]);
    expect(await memberDoc('g', OUTSIDER)).toBeUndefined();
    expect((await expenseDoc('groups/g/events/e1/expenses/x1')).payerParticipantId).toBe(OWNER);
  });

  test('#710 D16. existing per-shadow lock rejects approval even if the group mirror is missing', async () => {
    const lockedAt = Timestamp.fromMillis(2222);
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW, 'Ali');
    await seedEvent('g', 'e1', [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });
    await seedExpense('groups/g/events/e1/expenses/x1', {
      payerParticipantId: OWNER,
      amountFils: 12000,
    });
    const rid = await seedPendingRequest('g', OUTSIDER, SHADOW, 'Ali');
    await getFirestore().doc(`groups/g/claimShadowLocks/${SHADOW}`).set({
      groupId: 'g',
      shadowMemberId: SHADOW,
      claimerUid: CLAIMER,
      requestId: reqId(CLAIMER, SHADOW),
      lockedBy: OWNER,
      lockedAt,
      updatedAt: lockedAt,
    });

    await expect(decide({ groupId: 'g', requestId: rid, approve: true })).rejects.toMatchObject({
      code: expect.stringMatching(/^(aborted|failed-precondition)$/),
    });

    expect((await reqDoc('g', rid))?.status).toBe('pending');
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, SHADOW]);
    expect(await memberDoc('g', OUTSIDER)).toBeUndefined();
    expect((await expenseDoc('groups/g/events/e1/expenses/x1')).payerParticipantId).toBe(OWNER);
  });

  test('#710 D17. post-marker engine failure leaves claiming request and lock for recovery', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW, 'Ali');
    await seedEvent('g', 'e1', [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });
    await seedExpense('groups/g/events/e1/expenses/x1', {
      payerParticipantId: OWNER,
      amountFils: 12000,
    });
    const rid = await seedPendingRequest('g', CLAIMER, SHADOW, 'Ali');
    const realCommit = WriteBatch.prototype.commit;
    jest.spyOn(WriteBatch.prototype, 'commit').mockImplementation(function (this: WriteBatch) {
      return Promise.reject(new Error('forced post-marker phase-B failure'));
    });

    await expect(decide({ groupId: 'g', requestId: rid, approve: true })).rejects.toBeDefined();

    const request = await reqDoc('g', rid);
    const group = await groupDoc('g');
    const lock = (await getFirestore().doc(`groups/g/claimShadowLocks/${SHADOW}`).get()).data();
    expect(request).toMatchObject({
      status: 'claiming',
      requesterUid: CLAIMER,
      shadowMemberId: SHADOW,
      claimingBy: OWNER,
    });
    expect(request?.claimingAt).toBeInstanceOf(Timestamp);
    expect(request?.claimMutationStartedAt).toBeInstanceOf(Timestamp);
    expect(lock).toMatchObject({
      groupId: 'g',
      shadowMemberId: SHADOW,
      claimerUid: CLAIMER,
      requestId: rid,
      lockedBy: OWNER,
    });
    expect(lock?.mutationStartedAt).toBeInstanceOf(Timestamp);
    expect(group.claimingInProgress).toBe(true);
    expect(group.claimLockedAt).toBeInstanceOf(Timestamp);
    expect(group.claimMutationStartedAt).toBeInstanceOf(Timestamp);
    expect((await expenseDoc('groups/g/events/e1/expenses/x1')).payerParticipantId).toBe(OWNER);

    jest.spyOn(WriteBatch.prototype, 'commit').mockImplementation(function (this: WriteBatch) {
      return realCommit.apply(this);
    });
  });
});

describe('list claim requests (#278 PR8)', () => {
  test('L1. listMyClaimRequests: anon → permission-denied; durable non-member → only OWN requests', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW);
    await seedInviteCode(CODE, 'g');
    await seedPendingRequest('g', CLAIMER, SHADOW, 'Ali');
    await seedPendingRequest('g', OUTSIDER, SHADOW, 'Ali'); // someone else's

    await expect(listMy({ inviteCode: CODE }, authOf(CLAIMER, 'anonymous'))).rejects.toMatchObject({
      code: 'permission-denied',
    });
    const res = (await listMy({ inviteCode: CODE })) as { requests: Array<{ shadowMemberId: string; status: string }> };
    expect(res.requests).toHaveLength(1);
    expect(res.requests[0]).toMatchObject({ shadowMemberId: SHADOW, status: 'pending' });
  });

  test('L2. listGroupClaimRequests: non-creator → permission-denied; creator → pending requests', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW);
    await seedPendingRequest('g', CLAIMER, SHADOW, 'Ali');

    await expect(listGroup({ groupId: 'g' }, authOf(MEMBER2))).rejects.toMatchObject({
      code: 'permission-denied',
    });
    await expect(listGroup({ groupId: 'g' }, authOf(OUTSIDER))).rejects.toMatchObject({
      code: 'permission-denied',
    });
    const res = (await listGroup({ groupId: 'g' })) as {
      requests: Array<{ requesterUid: string; shadowMemberId: string; status: string }>;
    };
    expect(res.requests).toHaveLength(1);
    expect(res.requests[0]).toMatchObject({
      requesterUid: CLAIMER,
      shadowMemberId: SHADOW,
      status: 'pending',
    });
  });
});

describe('end-to-end claim (#278 PR8)', () => {
  test('E1. request → approve → requester nets the shadow prior balance across events (D1+D8 happy path)', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW, 'Ali');
    await seedInviteCode(CODE, 'g');
    for (const [eid, fils] of [['e1', 12000], ['e2', 6000]] as const) {
      await seedEvent('g', eid, [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });
      await seedExpense(`groups/g/events/${eid}/expenses/x`, { payerParticipantId: OWNER, amountFils: fils });
    }
    expect(omr(await nets('g'), SHADOW)).toBe('-9.000'); // 6.000 + 3.000

    const r = (await reqClaim({ inviteCode: CODE, shadowMemberId: SHADOW, displayName: 'Khalid' })) as {
      requestId: string;
      status: string;
    };
    expect(r.status).toBe('pending');
    await decide({ groupId: 'g', requestId: r.requestId, approve: true });

    const net = await nets('g');
    expect(omr(net, CLAIMER)).toBe('-9.000');
    expect(omr(net, SHADOW)).toBe('absent');
    expect(await memberDoc('g', CLAIMER)).toMatchObject({ displayName: 'Ali', isShadow: false });
  });
});
