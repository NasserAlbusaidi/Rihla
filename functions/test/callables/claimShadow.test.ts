import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';

// RED → GREEN: #278 claim/merge PR7. claimShadow re-keys a placeholder
// ("shadow") member's uuid identity to a real joiner's auth uid across every
// money doc (splitDistribution / payer / customSplit / settlements + member doc
// + memberIds), so the joiner INHERITS the shadow's balance. The mirror image of
// deleteAccount.ts's uid→tombstone re-key (here uuid→uid). Two-phase, idempotent:
// Phase B batched child scrubs, Phase C transactional identity retirement
// (memberIds LAST). D2: when the claimer already holds a slice, splitDistribution
// SUMS (mergeUidMapKey, PR6) — never overwrites. D7: KEY-ONLY (no name-value
// rewrite — the claimed doc keeps the creator-typed shadow name). D9: a
// POST-commit recomputeNet parity assert (priorShadow + priorClaimer per
// currency) catches a forged-doc divergence and REFUSES to finalize (loud
// internal error), rather than silently corrupting the net.
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/claimShadow.test.ts" npm run test:emulator`

import { claimShadow } from '../../src/callables/claimShadow';
import { recomputeNet } from '../../src/callables/groupNetBalance';
import { refreshGroupBalanceAggregate } from '../../src/triggers/balanceAggregator';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(claimShadow);

const OWNER = 'owner';
const CLAIMER = 'claimer';
const OUTSIDER = 'outsider';
const MEMBER2 = 'member2';
const SHADOW = 'shadow-7f3a9c';

type Auth = { uid: string; token: { firebase: { sign_in_provider: string } } };
function authOf(uid: string, provider = 'password'): Auth {
  return { uid, token: { firebase: { sign_in_provider: provider } } };
}
// Caller is the AUTHORIZER (PR7 = group creator); claimerUid is the target
// identity that inherits the shadow. PR8 routes this through creator-approval.
function call(
  data: { groupId?: string; shadowMemberId?: string; claimerUid?: string },
  auth: Auth | undefined = authOf(OWNER),
): Promise<unknown> {
  return wrapped({ data, auth } as never);
}

async function seedGroup(
  groupId: string,
  memberIds: string[],
  data: Record<string, unknown> = {},
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
  // Mirrors addShadowMember's write: doc id === userId === uuid, isShadow:true.
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
    createdBy: OWNER,
    payerParticipantId: OWNER,
    recipientParticipantId: OWNER,
    payerName: 'Owner',
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

async function seedGroupSettlement(
  groupId: string,
  sid: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore().doc(`groups/${groupId}/settlements/${sid}`).set({
    id: sid,
    createdBy: OWNER,
    payerParticipantId: OWNER,
    recipientParticipantId: OWNER,
    payerName: 'Owner',
    recipientName: 'Owner',
    amountFils: 5000,
    currency: 'OMR',
    note: null,
    isDeleted: false,
    deletedAt: null,
    settledAt: '2026-01-09T00:00:00.000Z',
    scope: 'group',
    groupId,
    ...data,
  });
}

const groupDoc = async (groupId: string) =>
  (await getFirestore().doc(`groups/${groupId}`).get()).data() ?? {};
const memberDoc = async (groupId: string, docId: string) =>
  (await getFirestore().doc(`groups/${groupId}/members/${docId}`).get()).data();
async function memberDocCount(groupId: string): Promise<number> {
  return (await getFirestore().collection(`groups/${groupId}/members`).get()).size;
}
async function expenseDoc(path: string) {
  return (await getFirestore().doc(path).get()).data() ?? {};
}

// Per-currency net readers. recomputeNet → Map<ccy, Map<uid, Decimal>>; absent
// key ⇒ no position in that currency. Returns a fixed-dp string (or 'absent').
async function nets(groupId: string) {
  const { net } = await recomputeNet(getFirestore(), getFirestore().doc(`groups/${groupId}`));
  return net;
}
function at(net: Map<string, Map<string, unknown>>, ccy: string, uid: string, dp: number): string {
  const v = net.get(ccy)?.get(uid) as { toFixed: (d: number) => string } | undefined;
  return v ? v.toFixed(dp) : 'absent';
}
const omr = (net: Map<string, Map<string, unknown>>, uid: string) => at(net, 'OMR', uid, 3);
const usd = (net: Map<string, Map<string, unknown>>, uid: string) => at(net, 'USD', uid, 2);

beforeEach(async () => {
  await clearFirestore();
  delete process.env.DELETE_ACCOUNT_BATCH_LIMIT;
  jest.restoreAllMocks();
  jest.spyOn(logger, 'info').mockImplementation(() => undefined);
  jest.spyOn(logger, 'warn').mockImplementation(() => undefined);
  jest.spyOn(logger, 'error').mockImplementation(() => undefined);
});

afterAll(async () => {
  await clearFirestore();
  testEnv.cleanup();
});

describe('claimShadow callable — uuid→uid re-key engine (#278 PR7)', () => {
  test('1. missing auth → unauthenticated', async () => {
    // Call wrapped directly: passing explicit `undefined` to call()'s defaulted
    // auth param would use the default (the JS default-parameter trap).
    await expect(
      wrapped({
        data: { groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER },
        auth: undefined,
      } as never),
    ).rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('2. anonymous caller → permission-denied; no writes', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW);
    await expect(
      call(
        { groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER },
        authOf(OWNER, 'anonymous'),
      ),
    ).rejects.toMatchObject({ code: 'permission-denied' });
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, SHADOW]);
  });

  test('3. invalid groupId / shadowMemberId / claimerUid → invalid-argument', async () => {
    await expect(call({ groupId: '', shadowMemberId: SHADOW, claimerUid: CLAIMER })).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(call({ groupId: 'a/b', shadowMemberId: SHADOW, claimerUid: CLAIMER })).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(call({ groupId: 'g', shadowMemberId: '', claimerUid: CLAIMER })).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: '' })).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: 'a/b' })).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('4. missing / soft-deleted / deletingInProgress group → not-found', async () => {
    await expect(call({ groupId: 'nope', shadowMemberId: SHADOW, claimerUid: CLAIMER })).rejects.toMatchObject({ code: 'not-found' });
    await seedGroup('g1', [OWNER, SHADOW], { isDeleted: true });
    await seedMember('g1', OWNER);
    await seedShadow('g1', SHADOW);
    await expect(call({ groupId: 'g1', shadowMemberId: SHADOW, claimerUid: CLAIMER })).rejects.toMatchObject({ code: 'not-found' });
    await seedGroup('g2', [OWNER, SHADOW], { deletingInProgress: true });
    await seedMember('g2', OWNER);
    await seedShadow('g2', SHADOW);
    await expect(call({ groupId: 'g2', shadowMemberId: SHADOW, claimerUid: CLAIMER })).rejects.toMatchObject({ code: 'not-found' });
  });

  test('5. target is a REAL member (isShadow:false) → failed-precondition; no writes', async () => {
    await seedGroup('g', [OWNER, MEMBER2]);
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER2); // isShadow:false
    await expect(
      call({ groupId: 'g', shadowMemberId: MEMBER2, claimerUid: CLAIMER }),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, MEMBER2]);
    expect(await memberDocCount('g')).toBe(2);
  });

  test('6. shadow already gone (prior claim / never existed) → idempotent alreadyClaimed, no writes', async () => {
    await seedGroup('g', [OWNER, CLAIMER]);
    await seedMember('g', OWNER);
    await seedMember('g', CLAIMER);
    const res = (await call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER })) as {
      alreadyClaimed: boolean;
    };
    expect(res.alreadyClaimed).toBe(true);
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, CLAIMER]);
    expect(await memberDocCount('g')).toBe(2);
  });

  test('7. caller is not the group creator (non-creator member or outsider) → permission-denied', async () => {
    await seedGroup('g', [OWNER, MEMBER2, SHADOW]);
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER2);
    await seedShadow('g', SHADOW);
    await expect(
      call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER }, authOf(MEMBER2)),
    ).rejects.toMatchObject({ code: 'permission-denied' });
    await expect(
      call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER }, authOf(OUTSIDER)),
    ).rejects.toMatchObject({ code: 'permission-denied' });
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, MEMBER2, SHADOW]);
  });

  test('8. HAPPY zero-balance shadow → memberIds swap, member doc copy+delete, net all zero', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW, 'Ali');
    await seedEvent('g', 'e1', [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });

    const res = (await call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER })) as {
      alreadyClaimed: boolean;
    };
    expect(res.alreadyClaimed).toBe(false);

    expect((await groupDoc('g')).memberIds).toEqual([OWNER, CLAIMER]);
    const claimerDoc = await memberDoc('g', CLAIMER);
    expect(claimerDoc).toMatchObject({
      id: CLAIMER,
      userId: CLAIMER,
      displayName: 'Ali', // D7 — keeps the shadow's name
      isShadow: false,
    });
    expect(claimerDoc?.isTombstone).toBeUndefined();
    expect(await memberDoc('g', SHADOW)).toBeUndefined(); // shadow doc deleted
    expect(await memberDocCount('g')).toBe(2);
    // event participantIds + participantNames re-keyed (KEY-ONLY, value kept)
    const ev = (await getFirestore().doc('groups/g/events/e1').get()).data()!;
    expect(ev.participantIds).toEqual([OWNER, CLAIMER]);
    expect(ev.participantNames).toEqual({ [OWNER]: 'Owner', [CLAIMER]: 'Ali' });

    const net = await nets('g');
    expect(omr(net, OWNER)).toBe('0.000');
    expect(omr(net, CLAIMER)).toBe('0.000');
    expect(omr(net, SHADOW)).toBe('absent');
  });

  test('9. HAPPY shadow as DEBTOR (equal split, D8 claimer brand-new) → CLAIMER inherits −6.000', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW, 'Ali');
    await seedEvent('g', 'e1', [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });
    await seedExpense('groups/g/events/e1/expenses/x1', { payerParticipantId: OWNER, amountFils: 12000 });

    const before = await nets('g');
    expect(omr(before, SHADOW)).toBe('-6.000');
    expect(omr(before, OWNER)).toBe('6.000');

    await call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER });

    const net = await nets('g');
    expect(omr(net, CLAIMER)).toBe('-6.000'); // B4 parity: 0 + (−6.000)
    expect(omr(net, OWNER)).toBe('6.000');
    expect(omr(net, SHADOW)).toBe('absent');
  });

  test('10. HAPPY shadow as PAYER → CLAIMER inherits +6.000 (payer scalar re-keyed)', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW);
    await seedEvent('g', 'e1', [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });
    await seedExpense('groups/g/events/e1/expenses/x1', { payerParticipantId: SHADOW, amountFils: 12000 });

    await call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER });

    const net = await nets('g');
    expect(omr(net, CLAIMER)).toBe('6.000');
    expect(omr(net, OWNER)).toBe('-6.000');
    expect(omr(net, SHADOW)).toBe('absent');
    const ex = await expenseDoc('groups/g/events/e1/expenses/x1');
    expect(ex.payerParticipantId).toBe(CLAIMER);
    expect(ex.claimRekeyAt).toBeDefined(); // re-keyed expense carries the audit-skip sentinel ([P2])
  });

  test('11. claimer already a live member (exact split, forged/Admin collision seed) → reject up-front (failed-precondition), no SUM, nothing mutated', async () => {
    // D8 (enforced in the engine, #557): a claim adopts a placeholder for a NEW
    // identity, so the claimer must NOT already be a member. The honest CREATE
    // rule forbids a split key outside participants + non-membership, so a shared
    // slice is unreachable on the happy path; this seeds the colliding state via
    // the Admin SDK to model the ONLY same-group collision path (a legacy/forged
    // doc). SUM-on-collision is now a `mergeUidMapKey` helper concern only
    // (mapReKey.test.ts) — at the CLAIM level a claimer-already-member collision
    // is refused loudly, never auto-merged (an equal split would silently move
    // the divisor; see test 20).
    await seedGroup('g', [OWNER, CLAIMER, SHADOW]);
    await seedMember('g', OWNER);
    await seedMember('g', CLAIMER, { displayName: 'Khalid' });
    await seedShadow('g', SHADOW, 'Ali');
    await seedEvent('g', 'e1', [OWNER, CLAIMER, SHADOW], {
      [OWNER]: 'Owner',
      [CLAIMER]: 'Khalid',
      [SHADOW]: 'Ali',
    });
    await seedExpense('groups/g/events/e1/expenses/x1', {
      payerParticipantId: OWNER,
      amountFils: 12000,
      splitMode: 'exact',
      splitDistribution: { [OWNER]: 4000, [CLAIMER]: 4000, [SHADOW]: 4000 },
    });

    await expect(
      call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER }),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    // No writes: split untouched, shadow doc + memberIds intact.
    expect((await expenseDoc('groups/g/events/e1/expenses/x1')).splitDistribution).toEqual({
      [OWNER]: 4000,
      [CLAIMER]: 4000,
      [SHADOW]: 4000,
    });
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, CLAIMER, SHADOW]);
    expect(await memberDoc('g', SHADOW)).toBeDefined();
    expect(await memberDocCount('g')).toBe(3);
  });

  test('12. claimer already a live member (shadow is a payer AND claimer has a slice, forged seed) → reject up-front, payer NOT swapped', async () => {
    await seedGroup('g', [OWNER, CLAIMER, SHADOW]);
    await seedMember('g', OWNER);
    await seedMember('g', CLAIMER, { displayName: 'Khalid' });
    await seedShadow('g', SHADOW, 'Ali');
    await seedEvent('g', 'e1', [OWNER, CLAIMER, SHADOW], {
      [OWNER]: 'Owner',
      [CLAIMER]: 'Khalid',
      [SHADOW]: 'Ali',
    });
    // A: SHADOW pays 9.000 exact {owner:3,claimer:3,shadow:3}
    await seedExpense('groups/g/events/e1/expenses/a', {
      payerParticipantId: SHADOW,
      amountFils: 9000,
      splitMode: 'exact',
      splitDistribution: { [OWNER]: 3000, [CLAIMER]: 3000, [SHADOW]: 3000 },
    });
    // B: OWNER pays 12.000 exact {owner:4,claimer:4,shadow:4}
    await seedExpense('groups/g/events/e1/expenses/b', {
      payerParticipantId: OWNER,
      amountFils: 12000,
      splitMode: 'exact',
      splitDistribution: { [OWNER]: 4000, [CLAIMER]: 4000, [SHADOW]: 4000 },
    });

    await expect(
      call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER }),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    // No writes: payer scalar + memberIds intact.
    expect((await expenseDoc('groups/g/events/e1/expenses/a')).payerParticipantId).toBe(SHADOW);
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, CLAIMER, SHADOW]);
    expect(await memberDocCount('g')).toBe(3);
  });

  test('13. shadow CASH-SETTLED (debt + offsetting event settlement) → CLAIMER nets 0', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW);
    await seedEvent('g', 'e1', [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });
    await seedExpense('groups/g/events/e1/expenses/x1', { payerParticipantId: OWNER, amountFils: 12000 });
    // shadow pays owner 6.000 → settles the debt
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: SHADOW,
      recipientParticipantId: OWNER,
      payerName: 'Ali',
      recipientName: 'Owner',
      amountFils: 6000,
    });

    expect(omr(await nets('g'), SHADOW)).toBe('0.000');

    await call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER });

    const net = await nets('g');
    expect(omr(net, CLAIMER)).toBe('0.000');
    expect(omr(net, OWNER)).toBe('0.000');
    expect(omr(net, SHADOW)).toBe('absent');
    expect((await getFirestore().doc('groups/g/events/e1/settlements/s1').get()).data()!.payerParticipantId).toBe(CLAIMER);
  });

  test('14. high-debt shadow across 3 events (D3 worst-case) → CLAIMER inherits −100.000', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW);
    for (const [eid, fils] of [['e1', 60000], ['e2', 60000], ['e3', 80000]] as const) {
      await seedEvent('g', eid, [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });
      await seedExpense(`groups/g/events/${eid}/expenses/x`, { payerParticipantId: OWNER, amountFils: fils });
    }
    expect(omr(await nets('g'), SHADOW)).toBe('-100.000');

    await call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER });

    const net = await nets('g');
    expect(omr(net, CLAIMER)).toBe('-100.000');
    expect(omr(net, OWNER)).toBe('100.000');
    expect(omr(net, SHADOW)).toBe('absent');
  });

  test('15. multi-currency shadow → CLAIMER inherits −6.000 OMR AND −5.00 USD (per-currency, never summed)', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW);
    await seedEvent('g', 'omr', [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });
    await seedExpense('groups/g/events/omr/expenses/x', { payerParticipantId: OWNER, amountFils: 12000, currency: 'OMR' });
    await seedEvent('g', 'usd', [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });
    await seedExpense('groups/g/events/usd/expenses/x', { payerParticipantId: OWNER, amountFils: 1000, currency: 'USD' });

    await call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER });

    const net = await nets('g');
    expect(omr(net, CLAIMER)).toBe('-6.000');
    expect(usd(net, CLAIMER)).toBe('-5.00');
    expect(omr(net, SHADOW)).toBe('absent');
    expect(usd(net, SHADOW)).toBe('absent');
  });

  test('16. idempotency / double-claim → second call no-ops (money not doubled)', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW);
    await seedEvent('g', 'e1', [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });
    await seedExpense('groups/g/events/e1/expenses/x1', { payerParticipantId: OWNER, amountFils: 12000 });

    await call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER });
    const second = (await call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER })) as {
      alreadyClaimed: boolean;
    };
    expect(second.alreadyClaimed).toBe(true);

    const net = await nets('g');
    expect(omr(net, CLAIMER)).toBe('-6.000'); // NOT −12.000
    expect(await memberDocCount('g')).toBe(2);
  });

  test('17. batched-cascade boundary (limit lowered) → multi-flush, final state correct + parity', async () => {
    process.env.DELETE_ACCOUNT_BATCH_LIMIT = '2';
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW);
    await seedEvent('g', 'e1', [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });
    for (let i = 0; i < 5; i += 1) {
      await seedExpense(`groups/g/events/e1/expenses/x${i}`, { payerParticipantId: OWNER, amountFils: 4000 });
    }
    expect(omr(await nets('g'), SHADOW)).toBe('-10.000');

    await call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER });

    const net = await nets('g');
    expect(omr(net, CLAIMER)).toBe('-10.000');
    expect(omr(net, SHADOW)).toBe('absent');
  });

  test('18. activity-log re-key is best-effort: a malformed activity doc does NOT fail the claim', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW);
    await seedEvent('g', 'e1', [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });
    await getFirestore().doc('groups/g/events/e1/activity_logs/a1').set({
      actorId: SHADOW,
      actorName: 'Ali',
      logText: 'Ali added expense',
    });
    await getFirestore().doc('groups/g/events/e1/activity_logs/a2').set({
      // malformed: missing actorId, odd metadata — must not crash the re-key
      metadata: 'not-a-map',
      targetParticipantId: SHADOW,
    });

    await expect(
      call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER }),
    ).resolves.toBeDefined();
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, CLAIMER]);
    expect((await getFirestore().doc('groups/g/events/e1/activity_logs/a1').get()).data()!.actorId).toBe(CLAIMER);
  });

  test('19. claimer already a live member (forged: shadow ∈ splitDistribution but ∉ participantIds) → reject up-front (failed-precondition), not a post-commit detect', async () => {
    // Was a [P1] post-commit parity DETECT (threw `internal` AFTER the merge was
    // irreversibly committed). With the claimer-already-member guard (#557) the
    // forged divergence is refused BEFORE any write — no finalize-then-throw, and
    // the idempotent retry can no longer bless it un-verified. (A forged
    // shadow∈split/∉participants paired with a NEW, non-member claimer would still
    // be caught post-commit by verifyParity; that narrow residual is a follow-up.)
    await seedGroup('g', [OWNER, CLAIMER, SHADOW]);
    await seedMember('g', OWNER);
    await seedMember('g', CLAIMER, { displayName: 'Khalid' });
    await seedShadow('g', SHADOW, 'Ali');
    await seedEvent('g', 'e1', [OWNER, CLAIMER], { [OWNER]: 'Owner', [CLAIMER]: 'Khalid' });
    await seedExpense('groups/g/events/e1/expenses/x1', {
      payerParticipantId: OWNER,
      amountFils: 12000,
      splitMode: 'exact',
      splitDistribution: { [OWNER]: 4000, [CLAIMER]: 4000, [SHADOW]: 4000 },
    });

    await expect(
      call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER }),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, CLAIMER, SHADOW]);
    expect(await memberDocCount('g')).toBe(3);
  });

  test('20. ★[P1] claimer already a live member + EQUAL split → reject up-front (failed-precondition), nothing mutated (no finalize-then-throw)', async () => {
    // The reported P1. Under an EQUAL split the owed amount is universe-derived,
    // so re-keying a shadow onto an EXISTING member dedups participantIds (3→2)
    // and moves the divisor (12/3 → 12/2). The post-commit parity assert then
    // false-fails (expected −8 = priorShadow −4 + priorClaimer −4; actual −6)
    // AFTER the merge is irreversibly committed, and the idempotent retry
    // (shadow already gone) returns alreadyClaimed without re-verifying — the
    // system reports `internal` for a finalized operation. D8 guarantees the
    // claimer is a NEW non-member; the engine enforces that precondition itself,
    // so the divisor never moves and nothing is committed.
    await seedGroup('g', [OWNER, CLAIMER, SHADOW]);
    await seedMember('g', OWNER);
    await seedMember('g', CLAIMER, { displayName: 'Khalid' });
    await seedShadow('g', SHADOW, 'Ali');
    await seedEvent('g', 'e1', [OWNER, CLAIMER, SHADOW], {
      [OWNER]: 'Owner',
      [CLAIMER]: 'Khalid',
      [SHADOW]: 'Ali',
    });
    // default seedExpense = equally, splitDistribution {} (universe-derived)
    await seedExpense('groups/g/events/e1/expenses/x1', {
      payerParticipantId: OWNER,
      amountFils: 12000,
    });

    const before = await nets('g');
    expect(omr(before, CLAIMER)).toBe('-4.000');
    expect(omr(before, SHADOW)).toBe('-4.000');

    await expect(
      call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER }),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    // Nothing finalized: memberIds, member docs, event + nets all untouched.
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, CLAIMER, SHADOW]);
    expect(await memberDoc('g', SHADOW)).toBeDefined();
    expect(await memberDocCount('g')).toBe(3);
    const ev = (await getFirestore().doc('groups/g/events/e1').get()).data()!;
    expect(ev.participantIds).toEqual([OWNER, CLAIMER, SHADOW]);
    const after = await nets('g');
    expect(omr(after, CLAIMER)).toBe('-4.000');
    expect(omr(after, SHADOW)).toBe('-4.000');
  });

  test('21. ★[P2] balance aggregate converges: post-claim aggregate doc shows CLAIMER net, shadow absent', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW);
    await seedEvent('g', 'e1', [OWNER, SHADOW], { [OWNER]: 'Owner', [SHADOW]: 'Ali' });
    await seedExpense('groups/g/events/e1/expenses/x1', { payerParticipantId: OWNER, amountFils: 12000 });

    await call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER });
    // The #366 display-cache aggregator recomputes via the same recomputeNet
    // (sourceTimeMs-guarded); fire its recompute directly (the emulator harness
    // does not auto-run onDocumentWritten triggers).
    await refreshGroupBalanceAggregate(getFirestore(), 'g', 1000);

    const agg = (await getFirestore().doc('groups/g/aggregates/balance').get()).data()!;
    expect(agg.netMilliByCurrency.OMR[CLAIMER]).toBe(-6000);
    expect(agg.netMilliByCurrency.OMR[SHADOW]).toBeUndefined();
  });

  test('22. GROUP-scope settlement re-key → CLAIMER inherits it (parity reads FULL recomputeNet, not per-event)', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW);
    // No event — only a group-scope settlement where shadow is the payer (+5.000)
    await seedGroupSettlement('g', 's1', {
      payerParticipantId: SHADOW,
      recipientParticipantId: OWNER,
      payerName: 'Ali',
      recipientName: 'Owner',
      amountFils: 5000,
    });
    expect(omr(await nets('g'), SHADOW)).toBe('5.000');

    await call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER });

    const net = await nets('g');
    expect(omr(net, CLAIMER)).toBe('5.000');
    expect(omr(net, OWNER)).toBe('-5.000');
    expect(omr(net, SHADOW)).toBe('absent');
    expect((await getFirestore().doc('groups/g/settlements/s1').get()).data()!.payerParticipantId).toBe(CLAIMER);
  });

  test('23. ★[P1 round-2] claimer is a DEPARTED member (∉ memberIds) but still ∈ event participantIds + EQUAL split → reject up-front (failed-precondition), nothing mutated', async () => {
    // The refute-found gap in a memberIds-only guard: the equal-split divisor is
    // derived from the per-event participantIds UNIVERSE (groupNetBalance.ts:613
    // `new Set(participantIds)` → :419/:421 `allocateEqual([...universe])`), NOT
    // memberIds. leaveGroup.ts:19 / removeMember.ts:30 drop a uid from memberIds
    // but NEVER prune event participantIds, so a departed member is ∉ memberIds
    // yet ∈ participantIds — re-keying the shadow onto them still dedups
    // participantIds (3→2) and moves the divisor (12/3→12/2), re-triggering the
    // post-commit `internal` throw a memberIds guard would miss. The guard must
    // reject on the financial UNIVERSE (priorNet key-set), not memberIds.
    await seedGroup('g', [OWNER, SHADOW]); // CLAIMER has LEFT — not in memberIds
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW, 'Ali');
    // CLAIMER still a participant of the event (leave doesn't prune participantIds).
    await seedEvent('g', 'e1', [OWNER, CLAIMER, SHADOW], {
      [OWNER]: 'Owner',
      [CLAIMER]: 'Khalid',
      [SHADOW]: 'Ali',
    });
    await seedExpense('groups/g/events/e1/expenses/x1', {
      payerParticipantId: OWNER,
      amountFils: 12000, // equally (universe-derived divisor)
    });

    const before = await nets('g');
    expect(omr(before, CLAIMER)).toBe('-4.000'); // counted in the divisor despite ∉ memberIds
    expect(omr(before, SHADOW)).toBe('-4.000');

    await expect(
      call({ groupId: 'g', shadowMemberId: SHADOW, claimerUid: CLAIMER }),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    // Nothing finalized — no divisor shift, no finalize-then-throw.
    expect((await groupDoc('g')).memberIds).toEqual([OWNER, SHADOW]);
    expect(await memberDoc('g', SHADOW)).toBeDefined();
    const ev = (await getFirestore().doc('groups/g/events/e1').get()).data()!;
    expect(ev.participantIds).toEqual([OWNER, CLAIMER, SHADOW]);
    const after = await nets('g');
    expect(omr(after, CLAIMER)).toBe('-4.000');
    expect(omr(after, SHADOW)).toBe('-4.000');
  });
});
