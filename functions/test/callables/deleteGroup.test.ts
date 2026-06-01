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

beforeEach(async () => {
  delete process.env.DELETE_GROUP_BATCH_LIMIT;
  delete process.env.DELETE_ACCOUNT_BATCH_LIMIT;
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
    // |sum-100|>0.001 and falls back to EQUAL 50/50 ($5/$5). The settlement
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
    // owner paid $10, owes $6 → +$4; member owes $4 → -$4. member→owner $4.
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: MEMBER,
      recipientParticipantId: OWNER,
      amountFils: 4000, // settlements are OMR scale (1000) → 4.000 == $4 numeric
      currency: 'OMR',
    });

    const res = await wrapped({
      data: { groupId: 'g' },
      auth: { uid: OWNER },
    } as any);
    expect(res).toMatchObject({ mode: 'softDelete' });
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
});
