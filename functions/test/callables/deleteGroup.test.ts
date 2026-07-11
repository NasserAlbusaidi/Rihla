import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';
// RED: cluster `server-deletegroup-callable` (#190), spec §8.1. This module does
// NOT exist yet — the callable is the deliverable of this cluster. Until
// `functions/src/callables/deleteGroup.ts` is created and exported, this import
// fails to resolve and the whole suite errors at load
// (failureKind=not-implemented). After GREEN it asserts the §2 contract.
//
// CONSOLIDATED owner of the deleteGroup callable suite. This file pins the
// RE-SCOPED soft-delete contract (spec §0.5/§2): the callable SOFT-deletes the
// group (`isDeleted:true`, `memberIds` UNTOUCHED) + its events, KEEPS the
// append-only expense/settlement records + invite code, recomputes per-actor
// net EXACTLY as the client BalanceCalculator (per-doc currency decode, the
// percent /1000 decode, the per-event former-actor universe, strict
// `isDeleted === false`), and refuses with failed-precondition on any non-zero
// net. Prior sibling suites that encoded the REVERSED designs (hard
// recursiveDelete; option-(a) empty-memberIds; a `src/lib/balance` module;
// currency-blind major-unit summing) were deleted — this is the one design.
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21).
// runCommand: `cd functions && npm run test:emulator -- deleteGroup.test.ts`
// NOT run here (parallel emulator port collision; module not implemented yet).

import { deleteGroup } from '../../src/callables/deleteGroup';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(deleteGroup);

const OWNER = 'owner';
const MEMBER = 'member';

async function clearGlobalDocs(): Promise<void> {
  const db = getFirestore();
  for (const collection of ['deleteGroupAttempts', 'deletionAttempts']) {
    const docs = await db.collection(collection).listDocuments();
    await Promise.all(docs.map((doc) => doc.delete()));
  }
}

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
  await getFirestore().doc(`inviteCodes/ABC123`).set({
    groupId,
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
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
    displayName: uid,
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

async function seedGroupSettlement(
  groupId: string,
  docId: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore().doc(`groups/${groupId}/settlements/${docId}`).set({
    id: docId,
    groupId,
    eventId: groupId, // group-scope sentinel (firestore.rules:712)
    scope: 'group',
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
    settledAt: '2026-01-09T00:00:00.000Z',
    ...data,
  });
}

const groupSnap = async (groupId: string) =>
  getFirestore().doc(`groups/${groupId}`).get();
const docExists = async (path: string): Promise<boolean> =>
  (await getFirestore().doc(path).get()).exists;

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

async function waitFor(
  predicate: () => Promise<boolean>,
  label: string,
  timeoutMs = 1000,
): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    await sleep(25);
  }
  throw new Error(`Timed out waiting for ${label}`);
}

beforeEach(async () => {
  delete process.env.DELETE_GROUP_BATCH_LIMIT;
  delete process.env.DELETE_ACCOUNT_BATCH_LIMIT;
  delete process.env.DELETE_GROUP_PAUSE_AFTER_LOCK_MS;
  await clearFirestore();
  await clearGlobalDocs();
  jest.restoreAllMocks();
  jest.spyOn(logger, 'info').mockImplementation(() => undefined);
  jest.spyOn(logger, 'warn').mockImplementation(() => undefined);
  jest.spyOn(logger, 'error').mockImplementation(() => undefined);
});

afterAll(async () => {
  await clearFirestore();
  await clearGlobalDocs();
  testEnv.cleanup();
});

describe('deleteGroup callable — soft-delete + balance gate (#190 §8.1)', () => {
  test('1. missing auth is rejected (unauthenticated)', async () => {
    await seedGroup('g');
    await expect(
      wrapped({ data: { groupId: 'g' }, auth: undefined } as any),
    ).rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('2. non-creator is rejected with permission-denied', async () => {
    await seedGroup('g', { createdBy: OWNER });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await expect(
      wrapped({ data: { groupId: 'g' }, auth: { uid: MEMBER } } as any),
    ).rejects.toMatchObject({ code: 'permission-denied' });
    expect((await groupSnap('g')).data()?.isDeleted).toBe(false);
  });

  // #1132: a DEPARTED creator (createdBy still == uid, but uid removed from
  // memberIds by leaveGroup) must lose delete authority. Seed the exact
  // net-zero state that test 5 soft-deletes successfully, but drop OWNER from
  // memberIds — so membership is the SOLE remaining failure cause (pre-fix this
  // SUCCEEDS; only the new isCurrentMember conjunct turns it into
  // permission-denied). Asserts the specific code, not a bare throw.
  test('2b. #1132 departed creator (createdBy set, not in memberIds) is rejected with permission-denied', async () => {
    await seedGroup('g', { memberIds: [MEMBER] }); // createdBy still OWNER
    await seedMember('g', MEMBER);
    await expect(
      wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'permission-denied' });
    expect((await groupSnap('g')).data()?.isDeleted).toBe(false);
  });

  test('3. missing group is rejected with not-found', async () => {
    await expect(
      wrapped({ data: { groupId: 'ghost' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'not-found' });
  });

  test('4. invalid groupId ("" and "a/b") is rejected with invalid-argument', async () => {
    await expect(
      wrapped({ data: { groupId: '' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(
      wrapped({ data: { groupId: 'a/b' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('5. clean soft-delete (zero balance, no events): group doc PRESERVED with isDeleted:true, memberIds UNCHANGED', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);

    expect(res).toMatchObject({
      groupId: 'g',
      mode: 'softDelete',
      eventsSoftDeleted: 0,
      alreadyDeleted: false,
    });
    const group = await groupSnap('g');
    expect(group.exists).toBe(true); // soft-delete: NOT hard-deleted
    expect(group.data()?.isDeleted).toBe(true);
    expect(group.data()?.deletedAt).toBeTruthy();
    expect(group.data()?.memberIds).toEqual([OWNER, MEMBER]); // UNTOUCHED (§2.5)
    // Invite code is KEPT (rejected at join by joinGroupByInviteCode.ts:255).
    expect(await docExists('inviteCodes/ABC123')).toBe(true);
  });

  test('5b. #366: the balance-aggregate doc is removed by the cascade', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await getFirestore().doc('groups/g/aggregates/balance').set({
      schemaVersion: 2,
      currency: 'OMR',
      netMilliByCurrency: {},
      perEventNetMilliByCurrency: {},
      eventCount: 0,
      degraded: false,
      sourceTimeMs: 1,
    });

    await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);

    expect(await docExists('groups/g/aggregates/balance')).toBe(false);
  });

  test('6. outstanding balance (exact split) is rejected with failed-precondition (no partial write)', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    // owner pays 12000, exact split 6000/6000 → member owes 6000, no settlement.
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 12000,
      splitMode: 'exact',
      scope: 'custom',
      customSplitParticipants: [OWNER, MEMBER],
      splitDistribution: { [OWNER]: 6000, [MEMBER]: 6000 },
    });

    await expect(
      wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    expect((await groupSnap('g')).data()?.isDeleted).toBe(false);
  });

  test('7. settled via event settlement → soft-deletes; group isDeleted:true', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 12000,
      splitMode: 'exact',
      scope: 'custom',
      customSplitParticipants: [OWNER, MEMBER],
      splitDistribution: { [OWNER]: 6000, [MEMBER]: 6000 },
    });
    // member pays owner 6000 → net zeroed.
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: MEMBER,
      recipientParticipantId: OWNER,
      amountFils: 6000,
    });

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);

    expect(res).toMatchObject({ mode: 'softDelete', eventsSoftDeleted: 1 });
    const group = await groupSnap('g');
    expect(group.data()?.isDeleted).toBe(true);
    // The event is soft-deleted; its child expense/settlement stay reachable.
    expect((await getFirestore().doc('groups/g/events/e1').get()).data()?.isDeleted).toBe(true);
    expect(await docExists('groups/g/events/e1/expenses/x1')).toBe(true);
    expect(await docExists('groups/g/events/e1/settlements/s1')).toBe(true);
  });

  test('7b. #223: in-tolerance exact residual — a client-settled group must be deletable (server closes the residual like the client)', async () => {
    // expense 10.000 OMR, exact {owner:5000, member:5001} (sum 10.001, drift +1
    // fils → IN-tolerance, not the out-of-tolerance equal fallback). The client
    // BalanceCalculator closes the -1 residual onto the alphabetically-last
    // absorbable recipient (owner: 5000 → 4999), so member owes exactly 5001.
    // Member settles 5001 → CLIENT net all-zero (the app shows the group
    // settled). Before the close-out port the server kept owner owed 5000
    // verbatim → owner net -1 → failed-precondition: the server refused to
    // delete a group the app shows as settled. After the port the server agrees.
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 10000,
      splitMode: 'exact',
      scope: 'custom',
      customSplitParticipants: [OWNER, MEMBER],
      splitDistribution: { [OWNER]: 5000, [MEMBER]: 5001 },
    });
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: MEMBER,
      recipientParticipantId: OWNER,
      amountFils: 5001,
    });

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);

    expect(res).toMatchObject({ mode: 'softDelete', eventsSoftDeleted: 1 });
    expect((await groupSnap('g')).data()?.isDeleted).toBe(true);
  });

  test('7c. #270: negative EXACT split value → server equal-split fallback like the client (client-settled group must be deletable)', async () => {
    // exact {owner:-1000, member:11000} (sum 10.000 == amount → IN-tolerance,
    // residual 0). A legacy/Admin doc could carry this; rules block new ones.
    // The client _allocateExact negative-value guard falls back to EQUAL split
    // (owner 5.000 / member 5.000), so member owes 5.000; member settles 5.000
    // → CLIENT net all-zero (the app shows the group settled). WITHOUT the server
    // guard, allocateExact keeps the distribution verbatim (owner owed -1.000,
    // member 11.000) → member net -6.000 after the 5.000 settlement → the server
    // REFUSES to delete a group the app shows settled (the #223 shape, sign axis).
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 10000,
      splitMode: 'exact',
      scope: 'custom',
      customSplitParticipants: [OWNER, MEMBER],
      splitDistribution: { [OWNER]: -1000, [MEMBER]: 11000 },
    });
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: MEMBER,
      recipientParticipantId: OWNER,
      amountFils: 5000,
    });

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);

    expect(res).toMatchObject({ mode: 'softDelete', eventsSoftDeleted: 1 });
    expect((await groupSnap('g')).data()?.isDeleted).toBe(true);
  });

  test('7d. #270: negative SHARES split value → server equal-split fallback like the client', async () => {
    // shares {owner:-1, member:5} (totalShares 4 > 0 → reaches allocateWeighted
    // without the guard). The client _allocateShares negative guard equal-splits
    // 8.000 → owner 4.000 / member 4.000; member settles 4.000 → CLIENT all-zero.
    // Server-without-guard weighted over [member,owner]: member 10.000, owner
    // (last) 8-10 = -2.000 → owner net (8-4)-(-2) = +6.000 → REFUSES.
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 8000,
      splitMode: 'shares',
      scope: 'global',
      splitDistribution: { [OWNER]: -1, [MEMBER]: 5 },
    });
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: MEMBER,
      recipientParticipantId: OWNER,
      amountFils: 4000,
    });

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);

    expect(res).toMatchObject({ mode: 'softDelete', eventsSoftDeleted: 1 });
    expect((await groupSnap('g')).data()?.isDeleted).toBe(true);
  });

  test('7e. #270: negative PERCENT split value → server equal-split fallback like the client', async () => {
    // percent {owner:-20, member:120} persisted x1000 = {-20000, 120000} (sum
    // 100 → IN-tolerance, reaches allocateWeighted without the guard). The client
    // _allocatePercent negative guard equal-splits 10.000 → 5.000 / 5.000; member
    // settles 5.000 → CLIENT all-zero. Server-without-guard weighted over
    // [member,owner]: member 12.000, owner (last) 10-12 = -2.000 → owner net
    // (10-5)-(-2) = +7.000 → REFUSES.
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 10000,
      splitMode: 'percent',
      scope: 'global',
      splitDistribution: { [OWNER]: -20000, [MEMBER]: 120000 },
    });
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: MEMBER,
      recipientParticipantId: OWNER,
      amountFils: 5000,
    });

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);

    expect(res).toMatchObject({ mode: 'softDelete', eventsSoftDeleted: 1 });
    expect((await groupSnap('g')).data()?.isDeleted).toBe(true);
  });

  test('8. group-scope settlement is counted in the balance fold (§:285-304)', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 12000,
      splitMode: 'exact',
      scope: 'custom',
      customSplitParticipants: [OWNER, MEMBER],
      splitDistribution: { [OWNER]: 6000, [MEMBER]: 6000 },
    });
    // settled at the GROUP scope, not the event scope.
    await seedGroupSettlement('g', 's1', {
      payerParticipantId: MEMBER,
      recipientParticipantId: OWNER,
      amountFils: 6000,
    });

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);
    expect(res).toMatchObject({ mode: 'softDelete' });
    expect((await groupSnap('g')).data()?.isDeleted).toBe(true);
  });

  test('9. non-OMR group: per-doc currency decode + percent /1000 (HARD REQ #2/#3)', async () => {
    await seedGroup('g', { currency: 'USD' });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    // USD scale 100. amountFils 1000 = $10.00. percent 60/40 persisted as
    // 60000/40000 (value x 1000). The /1000 decode gives 60.0/40.0 → owner owes
    // $6.00, member owes $4.00. A 0..100-raw read (60000/40000) hits
    // |sum-100|>0.001 and falls back to EQUAL 50/50 ($5/$5). The USD settlement
    // below zeroes the 60/40 net only; under the buggy raw read it does not, so
    // a raw-read server wrongly returns failed-precondition.
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 1000,
      currency: 'USD',
      payerParticipantId: OWNER,
      splitMode: 'percent',
      scope: 'global',
      splitDistribution: { [OWNER]: 60000, [MEMBER]: 40000 },
    });
    // owner paid $10, owes $6 → +$4; member owes $4 → -$4. member→owner $4 USD.
    // #382 PR-2: the settlement is in the expense's OWN currency (USD) so it
    // lands in the SAME bucket as the debt and zeroes it. A cross-currency (OMR)
    // settlement would land in a separate OMR bucket and NOT settle the USD debt
    // (no FX) — that case is test 9f. (Pre-PR-2 this test used an OMR settlement
    // that "settled" the USD debt only because the flat scalar net was
    // currency-blind; bucketing ends that, so the fixture is now currency-correct.)
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: MEMBER,
      recipientParticipantId: OWNER,
      amountFils: 400, // USD scale (100) → $4.00 == owner's +$4
      currency: 'USD',
    });

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);
    expect(res).toMatchObject({ mode: 'softDelete' });
  });

  test('9b. mixed-currency group with an unsettled bucket is REFUSED (#261/#382)', async () => {
    await seedGroup('g', { currency: 'OMR' });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    // Two global-equal expenses, each in its own currency bucket: OWNER pays
    // 10.000 OMR (each owes 5.000) → OMR bucket {OWNER +5, MEMBER −5}; MEMBER
    // pays 10.00 USD (each owes 5.00) → USD bucket {OWNER −5, MEMBER +5}.
    // #382 PR-2: the per-bucket gate finds BOTH buckets non-zero → refuse.
    // (Pre-PR-2 the flat scalar net cross-cancelled to a FAKE 0 — OWNER = 10 − 5
    // − 5 = 0 — and only the currencies.size>1 guard caught the money-loss path;
    // now the per-currency buckets catch it directly and the guard is gone.)
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 10000,
      currency: 'OMR',
      payerParticipantId: OWNER,
      scope: 'global',
      splitMode: 'equally',
      splitDistribution: {},
    });
    await seedExpense('groups/g/events/e1/expenses/x2', {
      amountFils: 1000,
      currency: 'USD',
      payerParticipantId: MEMBER,
      scope: 'global',
      splitMode: 'equally',
      splitDistribution: {},
    });

    await expect(
      wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    expect((await groupSnap('g')).data()?.isDeleted).toBe(false);
  });

  test('9c. cross-event mixed currency (OMR in e1, USD in e2) is REFUSED (#261/#382)', async () => {
    // Cross-event buckets: e1's OMR expense and e2's USD expense each leave a
    // non-zero bucket, so the #382 per-bucket gate refuses. (Also still pins the
    // function-scope currencies Set for the v1 doc: a per-event set would miss it.)
    await seedGroup('g', { currency: 'OMR' });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedEvent('g', 'e2');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 10000,
      currency: 'OMR',
      payerParticipantId: OWNER,
      scope: 'global',
      splitMode: 'equally',
      splitDistribution: {},
    });
    await seedExpense('groups/g/events/e2/expenses/x2', {
      amountFils: 1000,
      currency: 'USD',
      payerParticipantId: MEMBER,
      scope: 'global',
      splitMode: 'equally',
      splitDistribution: {},
    });

    await expect(
      wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    expect((await groupSnap('g')).data()?.isDeleted).toBe(false);
  });

  test('9d. legacy mixed-CASE single currency (omr + OMR) settled group still deletes (#261)', async () => {
    // currencyOf returns the raw code; the net math uppercases internally, so an
    // OMR group whose legacy/Admin docs mix 'omr' and 'OMR' is GENUINELY settled
    // (net 0) and must NOT be falsely flagged multi-currency. Each personal-scope
    // expense is paid AND owed by the same payer → net 0. Without case
    // normalization the set is {'omr','OMR'} (size 2) and bricks this delete.
    await seedGroup('g', { currency: 'OMR' });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 5000,
      currency: 'omr', // lowercase legacy doc
      payerParticipantId: OWNER,
      scope: 'personal',
      splitMode: 'equally',
      splitDistribution: {},
    });
    await seedExpense('groups/g/events/e1/expenses/x2', {
      amountFils: 5000,
      currency: 'OMR',
      payerParticipantId: MEMBER,
      createdBy: MEMBER,
      scope: 'personal',
      splitMode: 'equally',
      splitDistribution: {},
    });

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);
    expect(res).toMatchObject({ mode: 'softDelete' });
  });

  test('9e. mixed-currency group with EVERY bucket settled DELETES (#382 PR-2)', async () => {
    // The headline behavior #382 PR-2 enables: a group holding two currencies is
    // deletable when each clears independently (no cross-currency netting).
    // Pre-PR-2 the currencies.size>1 guard refused this unconditionally.
    await seedGroup('g', { currency: 'OMR' });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    // OMR bucket: OWNER pays 10.000 global-equal → OWNER +5, MEMBER −5;
    // MEMBER→OWNER 5.000 OMR clears it.
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 10000,
      currency: 'OMR',
      payerParticipantId: OWNER,
      scope: 'global',
      splitMode: 'equally',
      splitDistribution: {},
    });
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: MEMBER,
      recipientParticipantId: OWNER,
      amountFils: 5000,
      currency: 'OMR',
    });
    // USD bucket: MEMBER pays 10.00 global-equal → MEMBER +5, OWNER −5;
    // OWNER→MEMBER 5.00 USD clears it.
    await seedExpense('groups/g/events/e1/expenses/x2', {
      amountFils: 1000,
      currency: 'USD',
      payerParticipantId: MEMBER,
      createdBy: MEMBER,
      scope: 'global',
      splitMode: 'equally',
      splitDistribution: {},
    });
    await seedEventSettlement('groups/g/events/e1/settlements/s2', {
      payerParticipantId: OWNER,
      recipientParticipantId: MEMBER,
      createdBy: OWNER,
      amountFils: 500,
      currency: 'USD',
    });

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);
    expect(res).toMatchObject({ mode: 'softDelete' });
    expect((await groupSnap('g')).data()?.isDeleted).toBe(true);
  });

  test('9f. a DIFFERENT-currency settlement does NOT settle the debt (no FX) → REFUSED (#382 PR-2)', async () => {
    // Money-safety: a USD debt cannot be cleared by an OMR settlement — different
    // buckets, no FX. Pre-PR-2 the flat scalar net was currency-blind and
    // numerically zeroed, so the group WRONGLY deleted; the per-bucket gate now
    // refuses, protecting the still-unsettled USD debt.
    await seedGroup('g', { currency: 'USD' });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    // OWNER pays 10.00 USD, global-equal → OWNER +5 USD, MEMBER −5 USD.
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 1000,
      currency: 'USD',
      payerParticipantId: OWNER,
      scope: 'global',
      splitMode: 'equally',
      splitDistribution: {},
    });
    // MEMBER→OWNER 5.000 OMR — lands in the OMR bucket, NOT the USD bucket.
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: MEMBER,
      recipientParticipantId: OWNER,
      amountFils: 5000,
      currency: 'OMR',
    });

    await expect(
      wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    expect((await groupSnap('g')).data()?.isDeleted).toBe(false);
  });

  test('10. percent split happy path (70/30) settles to zero (HARD REQ #3)', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    // 70/30 percent of 10.000 OMR paid by owner. Persisted 70000/30000.
    // /1000 decode → 70.0/30.0 → owner owes 7.000, member owes 3.000.
    // owner net +3.000 (paid 10 - owed 7); member -3.000. member→owner 3.000.
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 10000,
      payerParticipantId: OWNER,
      splitMode: 'percent',
      scope: 'global',
      splitDistribution: { [OWNER]: 70000, [MEMBER]: 30000 },
    });
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: MEMBER,
      recipientParticipantId: OWNER,
      amountFils: 3000,
    });

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);
    expect(res).toMatchObject({ mode: 'softDelete' });
  });

  test('11. former-actor-in-universe, DISTRIBUTION branch (HARD REQ #4)', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    // `gone` is a tombstoned member (gone ∉ liveMemberIds) who is a payer/
    // settlement actor → re-injected into the per-event universe (:234).
    await seedMember('g', 'gone', { isTombstone: true });
    await seedEvent('g', 'e1', { participantIds: [OWNER] });
    // owner pays 6000, shares split {owner, gone} → 3000 each (gone in universe
    // because it appears as a payer/settlement actor). owner +3000, gone -3000.
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 6000,
      payerParticipantId: OWNER,
      splitMode: 'shares',
      scope: 'global',
      splitDistribution: { [OWNER]: 1, gone: 1 },
    });
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: 'gone',
      recipientParticipantId: OWNER,
      amountFils: 3000,
      payerName: 'Gone',
      recipientName: 'Owner',
    });

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);
    expect(res).toMatchObject({ mode: 'softDelete' });
  });

  test('11b. former-actor-in-universe, EQUAL-SPLIT branch (Gate R1 finding #2, HARD REQ #4)', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    // `gone` tombstoned (∉ liveMemberIds), a settlement actor in the event →
    // re-injected into the universe (:234).
    await seedMember('g', 'gone', { isTombstone: true });
    await seedEvent('g', 'e1', { participantIds: [OWNER] });
    // scope:global, NO splitDistribution → equal split over the universe
    // {owner, gone} = 3000 each. owner net 6000-3000=+3000; gone 0-3000=-3000.
    // A server splitting over participantIds=['owner'] alone owes owner the
    // full 6000 → the settlement no longer zeroes → wrongly failed-precondition.
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 6000,
      payerParticipantId: OWNER,
      splitMode: 'equally',
      scope: 'global',
      splitDistribution: {},
    });
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: 'gone',
      recipientParticipantId: OWNER,
      amountFils: 3000,
      payerName: 'Gone',
      recipientName: 'Owner',
    });

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);
    expect(res).toMatchObject({ mode: 'softDelete' });
    expect((await groupSnap('g')).data()?.isDeleted).toBe(true);
  });

  test('12. out-of-universe splitDistribution ghost → unsettled group is REFUSED (HARD REQ #4, dangerous direction)', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1', { participantIds: [OWNER, MEMBER] });
    // ghost ∉ participantIds and NOT a payer/settlement actor → out of universe.
    // Correct (per-event-drop): weighted over sorted keys ghost,member,owner =
    // 2000 each, but owed seeded only for {owner,member} → ghost's 2000 dropped
    // → owner net 6000-2000=+4000, member -2000 → NON-ZERO → must refuse. A
    // "single global map" server credits ghost -2000 (sum 0) → wrongly deletes.
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 6000,
      payerParticipantId: OWNER,
      splitMode: 'shares',
      scope: 'global',
      splitDistribution: { [OWNER]: 1, [MEMBER]: 1, ghost: 1 },
    });

    await expect(
      wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    expect((await groupSnap('g')).data()?.isDeleted).toBe(false);
  });

  test('12b. departed-member split-recipient is FOLDED (member-gated) → group settlement offsets → deletes (#249)', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    // `gone` is a tombstoned MEMBER who appears ONLY as a split recipient in the
    // event (never a payer/event-settlement actor). #249 member-gates the
    // recipient fold to allMemberIds, so gone IS re-injected into the event
    // universe (contrast test 12, where a NON-member ghost stays dropped).
    await seedMember('g', 'gone', { isTombstone: true });
    await seedEvent('g', 'e1', {
      participantIds: [OWNER],
      participantNames: { [OWNER]: 'Owner' },
    });
    // owner pays 3000, custom split {owner, gone} → 1500 each. Without the
    // fold gone's 1500 owed is dropped; with it gone owes 1500.
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 3000,
      payerParticipantId: OWNER,
      scope: 'custom',
      customSplitParticipants: [OWNER, 'gone'],
      splitMode: 'equally',
      splitDistribution: {},
    });
    // gone settles their 1500 via a GROUP-level settlement (folded globally,
    // not via any event universe). Pre-#249 the server credits gone +1500 from
    // this settlement while DROPPING their -1500 event owed → gone net +1500 →
    // wrongly REFUSED. With the fold: gone -1500 (owed) +1500 (settlement) = 0,
    // owner +1500 (paid-owed) -1500 (settlement recipient) = 0 → deletes.
    await seedGroupSettlement('g', 'gs1', {
      payerParticipantId: 'gone',
      recipientParticipantId: OWNER,
      payerName: 'Gone',
      recipientName: 'Owner',
      amountFils: 1500,
    });

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);
    expect(res).toMatchObject({ mode: 'softDelete' });
    expect((await groupSnap('g')).data()?.isDeleted).toBe(true);
  });

  test('13. soft-deleted event holding a LIVE unsettled expense → resolves; child kept (audit trail)', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    // Event itself soft-deleted → the client (event_provider.dart:42) drops it
    // wholesale, so its live child expense must NOT enter the balance pass.
    await seedEvent('g', 'eDead', { isDeleted: true });
    await seedExpense('groups/g/events/eDead/expenses/live', {
      amountFils: 9000,
      splitMode: 'exact',
      scope: 'custom',
      customSplitParticipants: [OWNER, MEMBER],
      splitDistribution: { [OWNER]: 0, [MEMBER]: 9000 }, // unsettled if counted
      isDeleted: false,
    });

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);
    expect(res).toMatchObject({ mode: 'softDelete' });
    // Soft-delete keeps the audit trail: the live child expense is NOT removed.
    expect(await docExists('groups/g/events/eDead/expenses/live')).toBe(true);
  });

  test('14. isDeleted-ABSENT expense is treated as deleted-for-balance (strict === false)', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    // Legacy/Admin-written shape: NO isDeleted field. The client query
    // where('isDeleted','==',false) EXCLUDES it → client shows settled. The
    // strict `=== false` server predicate must also exclude it (NOT `!== true`).
    await getFirestore().doc('groups/g/events/e1/expenses/legacy').set({
      id: 'legacy',
      eventId: 'e1',
      createdBy: OWNER,
      payerParticipantId: OWNER,
      amountFils: 9000,
      currency: 'OMR',
      scope: 'custom',
      customSplitParticipants: [OWNER, MEMBER],
      splitMode: 'exact',
      splitDistribution: { [OWNER]: 0, [MEMBER]: 9000 },
      createdAt: '2026-01-06T00:00:00.000Z',
      // intentionally NO isDeleted field
    });

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);
    expect(res).toMatchObject({ mode: 'softDelete' });
  });

  test('15. per-UID rate limit rejects once exceeded (resource-exhausted)', async () => {
    await getFirestore().doc(`deleteGroupAttempts/${OWNER}`).set({
      count: 5,
      windowStart: new Date(),
      expiresAt: new Date(Date.now() + 60 * 60 * 1000),
    });
    await seedGroup('g');
    await seedMember('g', OWNER);

    await expect(
      wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'resource-exhausted' });
    expect((await groupSnap('g')).data()?.isDeleted).toBe(false);
  });

  test('16. idempotent retry: second call on an already-soft-deleted group → alreadyDeleted:true no-op', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);

    const first = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);
    expect(first).toMatchObject({ alreadyDeleted: false });
    expect((await groupSnap('g')).data()?.isDeleted).toBe(true);

    const second = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);
    expect(second).toMatchObject({
      mode: 'softDelete',
      eventsSoftDeleted: 0,
      alreadyDeleted: true,
    });
    expect((await groupSnap('g')).data()?.isDeleted).toBe(true);
  });

  test('17. large settled group: ≤450-op chunking flushes mid-cascade (no batch throw)', async () => {
    // Force a small batch limit so the cascade auto-flushes mid-stream.
    process.env.DELETE_GROUP_BATCH_LIMIT = '50';
    await seedGroup('g');
    await seedMember('g', OWNER);
    const db = getFirestore();
    // 460 events, each settled (personal-scope expense paid by the sole
    // participant → self-owed → net zero). 460 event soft-delete updates + the
    // group update exceeds a single 500-op batch and the 50-op test limit.
    let batch = db.batch();
    let ops = 0;
    for (let i = 0; i < 460; i++) {
      batch.set(db.doc(`groups/g/events/e${i}`), {
        id: `e${i}`,
        groupId: 'g',
        name: `e${i}`,
        type: 'trip',
        createdBy: OWNER,
        participantIds: [OWNER],
        participantNames: { [OWNER]: 'Owner' },
        modules: { ledger: true },
        isDeleted: false,
        deletedAt: null,
        createdAt: new Date('2026-01-04T00:00:00.000Z'),
      });
      batch.set(db.doc(`groups/g/events/e${i}/expenses/x${i}`), {
        id: `x${i}`,
        eventId: `e${i}`,
        createdBy: OWNER,
        payerParticipantId: OWNER,
        amountFils: 1000,
        currency: 'OMR',
        scope: 'personal',
        splitMode: 'equally',
        splitDistribution: {},
        customSplitParticipants: [],
        isDeleted: false,
        deletedAt: null,
        createdAt: '2026-01-06T00:00:00.000Z',
      });
      ops += 2;
      if (ops >= 400) {
        await batch.commit();
        batch = db.batch();
        ops = 0;
      }
    }
    await batch.commit();

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);
    expect(res).toMatchObject({ mode: 'softDelete', eventsSoftDeleted: 460 });
    expect((await groupSnap('g')).data()?.isDeleted).toBe(true);
    // Every event soft-deleted; no child expense destroyed (audit trail).
    const evDeleted = await db.doc('groups/g/events/e459').get();
    expect(evDeleted.data()?.isDeleted).toBe(true);
    expect(await docExists('groups/g/events/e459/expenses/x459')).toBe(true);
  });

  test('18. #205 quiesces writes before recomputing and finalizing deleteGroup', async () => {
    process.env.DELETE_GROUP_PAUSE_AFTER_LOCK_MS = '300';
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      scope: 'personal',
      payerParticipantId: OWNER,
      amountFils: 1000,
    });

    const pending = wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);

    await waitFor(
      async () => (await groupSnap('g')).data()?.deletingInProgress === true,
      'deleteGroup quiesce lock',
    );

    const locked = (await groupSnap('g')).data();
    expect(locked?.isDeleted).toBe(false);
    expect(locked?.deletingInProgress).toBe(true);
    expect(locked?.deleteLockedAt).toBeTruthy();
    expect(locked?.deleteLockedBy).toBe(OWNER);

    const result = await pending;
    expect(result).toMatchObject({ mode: 'softDelete', alreadyDeleted: false });

    const finalized = (await groupSnap('g')).data();
    expect(finalized?.isDeleted).toBe(true);
    expect(finalized?.deletingInProgress).toBe(false);
    expect(finalized?.deleteFinalizedAt).toBeTruthy();
  });

  test('19. #205 failed balance gate clears the quiesce marker', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 12000,
      splitMode: 'exact',
      scope: 'custom',
      customSplitParticipants: [OWNER, MEMBER],
      splitDistribution: { [OWNER]: 6000, [MEMBER]: 6000 },
    });

    await expect(
      wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    const group = (await groupSnap('g')).data();
    expect(group?.isDeleted).toBe(false);
    expect(group?.deletingInProgress).toBe(false);
    expect(group?.deleteLockedAt).toBeUndefined();
    expect(group?.deleteLockedBy).toBeUndefined();
  });

  test('20. #205 owner retry resumes a quiesced partial finalize idempotently', async () => {
    const deleteLockedAt = new Date('2026-02-01T00:00:00.000Z');
    const eventDeletedAt = new Date('2026-02-01T00:00:01.000Z');
    await seedGroup('g', {
      deletingInProgress: true,
      deleteLockedAt,
      deleteLockedBy: OWNER,
    });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1', {
      isDeleted: true,
      deletedAt: eventDeletedAt,
      updatedAt: eventDeletedAt,
    });
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 12000,
      splitMode: 'exact',
      scope: 'custom',
      customSplitParticipants: [OWNER, MEMBER],
      splitDistribution: { [OWNER]: 6000, [MEMBER]: 6000 },
    });
    await seedGroupSettlement('g', 's1', {
      payerParticipantId: MEMBER,
      recipientParticipantId: OWNER,
      amountFils: 6000,
    });

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);

    expect(res).toMatchObject({ mode: 'softDelete', alreadyDeleted: false });
    const group = (await groupSnap('g')).data();
    expect(group?.isDeleted).toBe(true);
    expect(group?.deletingInProgress).toBe(false);
  });

  test('20b. #668 owner retry clears missing-timestamp observed lock and does NOT finalize', async () => {
    await seedGroup('g', {
      deletingInProgress: true,
      deleteLockedBy: OWNER,
    });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      scope: 'personal',
      payerParticipantId: OWNER,
      amountFils: 1000,
    });

    await expect(
      wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    const group = (await groupSnap('g')).data();
    expect(group?.isDeleted).toBe(false);
    expect(group?.deletingInProgress).toBe(false);
    expect(group?.deleteLockedAt).toBeUndefined();
    expect(group?.deleteLockedBy).toBeUndefined();
    expect(logger.warn).toHaveBeenCalledWith(
      'deleteGroup malformed lock cleared',
      { uid: OWNER, groupId: 'g' },
    );
  });

  test('20c. #668 owner retry clears string-timestamp observed lock and does NOT finalize', async () => {
    await seedGroup('g', {
      deletingInProgress: true,
      deleteLockedAt: 'not-a-timestamp',
      deleteLockedBy: OWNER,
    });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      scope: 'personal',
      payerParticipantId: OWNER,
      amountFils: 1000,
    });

    await expect(
      wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    const group = (await groupSnap('g')).data();
    expect(group?.isDeleted).toBe(false);
    expect(group?.deletingInProgress).toBe(false);
    expect(group?.deleteLockedAt).toBeUndefined();
    expect(group?.deleteLockedBy).toBeUndefined();
    expect(logger.warn).toHaveBeenCalledWith(
      'deleteGroup malformed lock cleared',
      { uid: OWNER, groupId: 'g' },
    );
  });

  test('21. #205 failed owner retry does not clear another invocation lock', async () => {
    process.env.DELETE_GROUP_PAUSE_AFTER_LOCK_MS = '3000';
    const db = getFirestore();
    await db.doc(`deleteGroupAttempts/${OWNER}`).set({
      count: 4,
      windowStart: new Date(),
      expiresAt: new Date(Date.now() + 60 * 60 * 1000),
    });
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      scope: 'personal',
      payerParticipantId: OWNER,
      amountFils: 1000,
    });

    const firstDelete = wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);

    await waitFor(
      async () => (await groupSnap('g')).data()?.deletingInProgress === true,
      'first deleteGroup quiesce lock',
    );

    try {
      await expect(wrapped({
        data: { groupId: 'g' },
        auth: { uid: OWNER },
      } as any)).rejects.toMatchObject({ code: 'resource-exhausted' });

      const duringFirstDelete = (await groupSnap('g')).data();
      expect(duringFirstDelete?.isDeleted).toBe(false);
      expect(duringFirstDelete?.deletingInProgress).toBe(true);
      expect(duringFirstDelete?.deleteLockedBy).toBe(OWNER);
    } finally {
      await expect(firstDelete).resolves.toMatchObject({
        mode: 'softDelete',
        alreadyDeleted: false,
      });
    }
  });

  test('22. #205/#529 owner retry no longer clears an observed lock in-band (reaper owns stale recovery)', async () => {
    // Old contract: an owner retry that observed a stale lock and failed the
    // balance gate cleared the lock in-band. That observed-clear is the #529
    // hole — dropped. Stale-lock recovery now belongs to deleteGroupLockReaper,
    // so an observer leaves the lock intact regardless of age.
    const deleteLockedAt = new Date('2026-02-01T00:00:00.000Z');
    await seedGroup('g', {
      deletingInProgress: true,
      deleteLockedAt,
      deleteLockedBy: OWNER,
    });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 12000,
      splitMode: 'exact',
      scope: 'custom',
      customSplitParticipants: [OWNER, MEMBER],
      splitDistribution: { [OWNER]: 6000, [MEMBER]: 6000 },
    });

    await expect(
      wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    const group = (await groupSnap('g')).data();
    expect(group?.isDeleted).toBe(false);
    expect(group?.deletingInProgress).toBe(true);
    expect(group?.deleteLockedBy).toBe(OWNER);
  });

  test('23. #529 an observer does NOT clear a live lock on failed-precondition', async () => {
    // Models call #2 of a creator double-tap: it OBSERVES call #1's fresh (live)
    // lock, hits the unsettled-balance gate, and must NOT clear the lock out from
    // under the still-running call #1 (pre-fix: canClearObservedLock cleared it,
    // briefly re-opening client writes against a quiesced group). A fresh
    // deleteLockedAt = a live invocation holds it.
    const deleteLockedAt = new Date();
    await seedGroup('g', { deletingInProgress: true, deleteLockedAt, deleteLockedBy: OWNER });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 12000,
      splitMode: 'exact',
      scope: 'custom',
      customSplitParticipants: [OWNER, MEMBER],
      splitDistribution: { [OWNER]: 6000, [MEMBER]: 6000 },
    });

    await expect(
      wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    // The observer left the live lock intact for call #1 / the reaper.
    const group = (await groupSnap('g')).data();
    expect(group?.deletingInProgress).toBe(true);
    expect(group?.deleteLockedBy).toBe(OWNER);
    expect(group?.deleteLockedAt).toBeTruthy();
  });

  test('#1144 acquire refuses while a departure lock is held — no delete lock taken, no mutation', async () => {
    await seedGroup('g', {
      departureInProgress: true,
      departureLockedAt: new Date(),
      departureLockedBy: MEMBER,
    });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);

    await expect(
      wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    const group = (await groupSnap('g')).data();
    expect(group?.deletingInProgress ?? false).toBe(false);
    expect(group?.isDeleted).toBe(false);
    // The departure lock stays untouched for its owner.
    expect(group?.departureInProgress).toBe(true);
    expect(group?.departureLockedBy).toBe(MEMBER);
  });
});
