// RED → GREEN: #889 correction marker foundation — correctLogicalSettleUp
// callable (decomposed group settle-up correction). Server-authoritative
// replacement for the client WriteBatch
// (SettlementCorrectionService.reverseLogicalSettleUp), validating the FULL
// logical set server-side so every reverse — event-scope slices AND the
// group-scope residual — carries the un-forgeable `correctionOfSettlementId`
// marker.
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/correctLogicalSettleUp.test.ts" npm run test:emulator`

import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';
import { correctLogicalSettleUp } from '../../src/callables/correctLogicalSettleUp';
import { logicalReverseId } from '../../src/callables/shared/settlementCorrection';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(correctLogicalSettleUp);

const OWNER = 'owner';
const MEMBER = 'member';
const CORRECTION_NOTE = 'Correction of a recorded payment';
const SU = 'su-logical-1';

async function seedGroup(groupId: string, data: Record<string, unknown> = {}): Promise<void> {
  await getFirestore().doc(`groups/${groupId}`).set({
    id: groupId,
    name: groupId,
    inviteCode: `${groupId}-CODE`,
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

async function seedEvent(
  groupId: string,
  eventId: string,
  participantIds: string[],
  data: Record<string, unknown> = {},
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
    deletedAt: null,
    createdAt: new Date('2026-01-04T00:00:00.000Z'),
    ...data,
  });
}

async function seedEventSettlement(path: string, data: Record<string, unknown> = {}): Promise<void> {
  await getFirestore().doc(path).set({
    id: path.split('/').pop(),
    eventId: path.split('/')[3],
    createdBy: MEMBER,
    payerParticipantId: MEMBER,
    recipientParticipantId: OWNER,
    payerName: 'Member',
    recipientName: 'Owner',
    amountFils: 3000,
    currency: 'OMR',
    note: 'partial settle',
    isDeleted: false,
    deletedAt: null,
    settledAt: '2026-01-08T00:00:00.000Z',
    groupSettleUpId: SU,
    ...data,
  });
}

async function seedGroupSettlement(path: string, data: Record<string, unknown> = {}): Promise<void> {
  await getFirestore().doc(path).set({
    id: path.split('/').pop(),
    groupId: path.split('/')[1],
    eventId: path.split('/')[1],
    scope: 'group',
    createdBy: MEMBER,
    payerParticipantId: MEMBER,
    recipientParticipantId: OWNER,
    payerName: 'Member',
    recipientName: 'Owner',
    amountFils: 2000,
    currency: 'OMR',
    note: 'residual settle',
    isDeleted: false,
    deletedAt: null,
    settledAt: '2026-01-08T00:00:00.000Z',
    groupSettleUpId: SU,
    ...data,
  });
}

async function getDoc(path: string) {
  return (await getFirestore().doc(path).get()).data();
}

async function collectionDocs(path: string) {
  return (await getFirestore().collection(path).get()).docs;
}

function call(data: Record<string, unknown>, uid = OWNER) {
  return wrapped({ data, auth: { uid } } as any);
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

describe('correctLogicalSettleUp — validation', () => {
  test('1. missing auth → unauthenticated', async () => {
    await expect(
      wrapped({ data: { groupId: 'g', groupSettleUpId: SU, correctionNote: CORRECTION_NOTE }, auth: undefined } as any),
    ).rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('2. non-member caller → permission-denied', async () => {
    await seedGroup('g');
    await expect(
      call({ groupId: 'g', groupSettleUpId: SU, correctionNote: CORRECTION_NOTE }, 'outsider'),
    ).rejects.toMatchObject({ code: 'permission-denied' });
  });

  test('3. blank / whitespace-only groupSettleUpId → invalid-argument', async () => {
    await seedGroup('g');
    for (const bad of ['', '   ']) {
      await expect(
        call({ groupId: 'g', groupSettleUpId: bad, correctionNote: CORRECTION_NOTE }),
      ).rejects.toMatchObject({ code: 'invalid-argument' });
    }
  });

  test('4. path-unsafe groupSettleUpId ("a/b") → invalid-argument', async () => {
    await seedGroup('g');
    await expect(
      call({ groupId: 'g', groupSettleUpId: 'a/b', correctionNote: CORRECTION_NOTE }),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('5. locked/deleted group (all four flags) → not-found', async () => {
    for (const flag of ['isDeleted', 'deletingInProgress', 'claimingInProgress', 'accountDeletionInProgress']) {
      const gid = `locked-${flag}`;
      await seedGroup(gid, { [flag]: true });
      await expect(
        call({ groupId: gid, groupSettleUpId: SU, correctionNote: CORRECTION_NOTE }),
      ).rejects.toMatchObject({ code: 'not-found' });
    }
  });

  test('6. no originals for this groupSettleUpId → not-found', async () => {
    await seedGroup('g');
    await expect(
      call({ groupId: 'g', groupSettleUpId: 'su-nonexistent', correctionNote: CORRECTION_NOTE }),
    ).rejects.toMatchObject({ code: 'not-found' });
  });

  test('7. invalid parties: an event-scope slice with a non-participant party → failed-precondition', async () => {
    await seedGroup('g', { memberIds: [OWNER, MEMBER, 'outsider'] });
    await seedEvent('g', 'e1', [OWNER, MEMBER]); // outsider not a participant
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: 'outsider',
      recipientParticipantId: OWNER,
    });
    await expect(
      call({ groupId: 'g', groupSettleUpId: SU, correctionNote: CORRECTION_NOTE }),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('8. invalid correctionNote (empty/over-length/control-char) → invalid-argument', async () => {
    await seedGroup('g');
    await seedGroupSettlement('groups/g/settlements/gsResidual');
    for (const note of ['', 'x'.repeat(281), 'bad\x01note']) {
      await expect(
        call({ groupId: 'g', groupSettleUpId: SU, correctionNote: note }),
      ).rejects.toMatchObject({ code: 'invalid-argument' });
    }
  });
});

describe('correctLogicalSettleUp — happy paths + concurrency', () => {
  test('writes exact event + group reverse maps for a mixed logical set; shouldBumpLedgerRevision:true', async () => {
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER]);
    await seedEvent('g', 'e2', [OWNER, MEMBER]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1');
    await seedEventSettlement('groups/g/events/e2/settlements/s2');
    await seedGroupSettlement('groups/g/settlements/gsResidual');

    const res = await call({ groupId: 'g', groupSettleUpId: SU, correctionNote: CORRECTION_NOTE });

    expect(res).toEqual({
      eventScopeWrites: 2,
      groupScopeWrites: 1,
      repaired: false,
      noop: false,
      shouldBumpLedgerRevision: true,
    });

    const rev1 = logicalReverseId(SU, 'groups/g/events/e1/settlements/s1');
    const rev2 = logicalReverseId(SU, 'groups/g/events/e2/settlements/s2');
    const revG = logicalReverseId(SU, 'groups/g/settlements/gsResidual');

    const e1Reverse = await getDoc(`groups/g/events/e1/settlements/${rev1}`);
    expect(e1Reverse).toMatchObject({
      id: rev1,
      eventId: 'e1',
      payerParticipantId: OWNER,
      recipientParticipantId: MEMBER,
      amountFils: 3000,
      currency: 'OMR',
      note: CORRECTION_NOTE,
      isDeleted: false,
      deletedAt: null,
      groupSettleUpId: SU,
      correctionOfSettlementId: 's1',
    });

    const e2Reverse = await getDoc(`groups/g/events/e2/settlements/${rev2}`);
    expect(e2Reverse).toMatchObject({ correctionOfSettlementId: 's2', groupSettleUpId: SU });

    const gReverse = await getDoc(`groups/g/settlements/${revG}`);
    expect(gReverse).toMatchObject({
      id: revG,
      groupId: 'g',
      eventId: 'g',
      scope: 'group',
      payerParticipantId: OWNER,
      recipientParticipantId: MEMBER,
      amountFils: 2000,
      correctionOfSettlementId: 'gsResidual',
      groupSettleUpId: SU,
    });

    // Originals untouched (append-only).
    expect((await getDoc('groups/g/events/e1/settlements/s1'))?.isDeleted).toBe(false);
    expect((await getDoc('groups/g/settlements/gsResidual'))?.isDeleted).toBe(false);
  });

  test('group-only logical set (no event slices) → shouldBumpLedgerRevision:false', async () => {
    await seedGroup('g');
    await seedGroupSettlement('groups/g/settlements/gsResidual');

    const res = await call({ groupId: 'g', groupSettleUpId: SU, correctionNote: CORRECTION_NOTE });
    expect(res).toEqual({
      eventScopeWrites: 0,
      groupScopeWrites: 1,
      repaired: false,
      noop: false,
      shouldBumpLedgerRevision: false,
    });
  });

  test('a slice under a SOFT-DELETED event is ignored — live slices + residual reverse and SUCCEED', async () => {
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER]); // live
    await seedEvent('g', 'eDead', [OWNER, MEMBER], { isDeleted: true }); // soft-deleted
    await seedEventSettlement('groups/g/events/e1/settlements/s1');
    await seedEventSettlement('groups/g/events/eDead/settlements/sDead');
    await seedGroupSettlement('groups/g/settlements/gsResidual');

    const res = await call({ groupId: 'g', groupSettleUpId: SU, correctionNote: CORRECTION_NOTE });

    // Only e1's slice + the residual are reversed — eDead's slice is ignored,
    // never a failure reason.
    expect(res).toEqual({
      eventScopeWrites: 1,
      groupScopeWrites: 1,
      repaired: false,
      noop: false,
      shouldBumpLedgerRevision: true,
    });
    const deadRev = logicalReverseId(SU, 'groups/g/events/eDead/settlements/sDead');
    expect(await getDoc(`groups/g/events/eDead/settlements/${deadRev}`)).toBeUndefined();
  });

  test('succeeds for 21 event slices plus residual (no rules-read-limit dependence)', async () => {
    await seedGroup('g');
    for (let i = 0; i < 21; i += 1) {
      const eid = `e${i}`;
      await seedEvent('g', eid, [OWNER, MEMBER]);
      await seedEventSettlement(`groups/g/events/${eid}/settlements/s${i}`);
    }
    await seedGroupSettlement('groups/g/settlements/gsResidual');

    const res = await call({ groupId: 'g', groupSettleUpId: SU, correctionNote: CORRECTION_NOTE });
    expect(res).toEqual({
      eventScopeWrites: 21,
      groupScopeWrites: 1,
      repaired: false,
      noop: false,
      shouldBumpLedgerRevision: true,
    });
  }, 30000);

  test('idempotent retry: second call is a full no-op, no duplicate reverses', async () => {
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1');
    await seedGroupSettlement('groups/g/settlements/gsResidual');

    await call({ groupId: 'g', groupSettleUpId: SU, correctionNote: CORRECTION_NOTE });
    const retry = await call({ groupId: 'g', groupSettleUpId: SU, correctionNote: CORRECTION_NOTE }, MEMBER);

    expect(retry).toEqual({
      eventScopeWrites: 0,
      groupScopeWrites: 0,
      repaired: false,
      noop: true,
      shouldBumpLedgerRevision: true,
    });
    expect(await collectionDocs('groups/g/events/e1/settlements')).toHaveLength(2);
    expect(await collectionDocs('groups/g/settlements')).toHaveLength(2);
  });

  test('completes missing reverses for a partial marker set (repair), returns repaired:true', async () => {
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER]);
    await seedEvent('g', 'e2', [OWNER, MEMBER]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1');
    await seedEventSettlement('groups/g/events/e2/settlements/s2');

    // Simulate a prior partial invocation: e1's reverse already exists and
    // validates; e2's does not exist yet.
    const rev1 = logicalReverseId(SU, 'groups/g/events/e1/settlements/s1');
    await seedEventSettlement(`groups/g/events/e1/settlements/${rev1}`, {
      payerParticipantId: OWNER,
      recipientParticipantId: MEMBER,
      groupSettleUpId: SU,
      correctionOfSettlementId: 's1',
      note: CORRECTION_NOTE,
    });

    const res = await call({ groupId: 'g', groupSettleUpId: SU, correctionNote: CORRECTION_NOTE });
    expect(res).toEqual({
      eventScopeWrites: 1,
      groupScopeWrites: 0,
      repaired: true,
      noop: false,
      shouldBumpLedgerRevision: true,
    });
    const rev2 = logicalReverseId(SU, 'groups/g/events/e2/settlements/s2');
    expect(await getDoc(`groups/g/events/e2/settlements/${rev2}`)).toMatchObject({
      correctionOfSettlementId: 's2',
    });
  });

  test('all-or-nothing: an invalid deterministic-id collision aborts the WHOLE call, no partial writes', async () => {
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER]);
    await seedEvent('g', 'e2', [OWNER, MEMBER]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1');
    await seedEventSettlement('groups/g/events/e2/settlements/s2');

    // e1's deterministic reverse id is squatted by a doc with the WRONG amount.
    const rev1 = logicalReverseId(SU, 'groups/g/events/e1/settlements/s1');
    await seedEventSettlement(`groups/g/events/e1/settlements/${rev1}`, {
      payerParticipantId: OWNER,
      recipientParticipantId: MEMBER,
      amountFils: 1, // wrong — does not validate as the expected reverse
      correctionOfSettlementId: 's1',
    });

    await expect(
      call({ groupId: 'g', groupSettleUpId: SU, correctionNote: CORRECTION_NOTE }),
    ).rejects.toMatchObject({ code: 'already-exists' });

    // e2's reverse must NOT have been written — all-or-nothing.
    const rev2 = logicalReverseId(SU, 'groups/g/events/e2/settlements/s2');
    expect(await getDoc(`groups/g/events/e2/settlements/${rev2}`)).toBeUndefined();
  });

  test('event lookups are scoped to the target group only — a same-tagged settlement in ANOTHER group is untouched', async () => {
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1');

    await seedGroup('otherGroup', { memberIds: [OWNER, MEMBER] });
    await seedEvent('otherGroup', 'eOther', [OWNER, MEMBER]);
    await seedEventSettlement('groups/otherGroup/events/eOther/settlements/sOther'); // SAME SU tag

    await call({ groupId: 'g', groupSettleUpId: SU, correctionNote: CORRECTION_NOTE });

    // The other group's tagged settlement is untouched — no reverse written there.
    const otherDocs = await collectionDocs('groups/otherGroup/events/eOther/settlements');
    expect(otherDocs).toHaveLength(1); // sOther only, no reverse
  });

  test('correction after event close still succeeds (settlements stay live)', async () => {
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER], { isClosed: true, closedAt: '2026-02-01T00:00:00.000Z', closedBy: OWNER });
    await seedEventSettlement('groups/g/events/e1/settlements/s1');

    const res = await call({ groupId: 'g', groupSettleUpId: SU, correctionNote: CORRECTION_NOTE });
    expect(res.noop).toBe(false);
  });

  test('an overlong (but valid) groupSettleUpId still produces bounded path-safe reverse ids', async () => {
    const longSu = 'x'.repeat(190);
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1', { groupSettleUpId: longSu });

    const res = await call({ groupId: 'g', groupSettleUpId: longSu, correctionNote: CORRECTION_NOTE });
    expect(res.eventScopeWrites).toBe(1);
    const revId = logicalReverseId(longSu, 'groups/g/events/e1/settlements/s1');
    expect(revId.length).toBeLessThan(80);
    expect(revId).not.toContain('/');
  });
});

// Actor policy: only the group creator, or a caller who is a party (payer OR
// recipient) on EVERY live tagged original, may reverse a logical settle-up.
// Party-on-some-but-not-all is denied.
describe('correctLogicalSettleUp — actor policy (creator-or-party-on-every-original)', () => {
  const THIRD = 'third';

  test('A1. DENY: member who is neither party nor creator → permission-denied, no writes', async () => {
    await seedGroup('g', { memberIds: [OWNER, MEMBER, THIRD] });
    await seedEvent('g', 'e1', [OWNER, MEMBER, THIRD]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1'); // MEMBER -> OWNER
    await seedGroupSettlement('groups/g/settlements/gs1'); // MEMBER -> OWNER residual

    await expect(
      call({ groupId: 'g', groupSettleUpId: SU, correctionNote: CORRECTION_NOTE }, THIRD),
    ).rejects.toMatchObject({ code: 'permission-denied' });
    expect(await collectionDocs('groups/g/events/e1/settlements')).toHaveLength(1);
    expect(await collectionDocs('groups/g/settlements')).toHaveLength(1);
  });

  test('A2. DENY: party on some but not all originals → permission-denied', async () => {
    await seedGroup('g', { memberIds: [OWNER, MEMBER, THIRD] });
    await seedEvent('g', 'e1', [OWNER, MEMBER, THIRD]);
    await seedEvent('g', 'e2', [OWNER, MEMBER, THIRD]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1'); // MEMBER -> OWNER
    await seedEventSettlement('groups/g/events/e2/settlements/s2', {
      payerParticipantId: THIRD,
      payerName: 'Third',
    }); // THIRD -> OWNER

    // MEMBER is payer on s1 but a stranger to s2 — the set is not theirs.
    await expect(
      call({ groupId: 'g', groupSettleUpId: SU, correctionNote: CORRECTION_NOTE }, MEMBER),
    ).rejects.toMatchObject({ code: 'permission-denied' });
  });

  test('A3. ALLOW: caller who is a party on EVERY original', async () => {
    await seedGroup('g', { memberIds: [OWNER, MEMBER, THIRD] });
    await seedEvent('g', 'e1', [OWNER, MEMBER, THIRD]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1'); // MEMBER -> OWNER
    await seedGroupSettlement('groups/g/settlements/gs1'); // MEMBER -> OWNER residual

    const res = await call({ groupId: 'g', groupSettleUpId: SU, correctionNote: CORRECTION_NOTE }, MEMBER);
    expect(res).toMatchObject({ noop: false, eventScopeWrites: 1, groupScopeWrites: 1 });
  });

  test('A4. ALLOW: group creator who is a party on none', async () => {
    await seedGroup('g', { memberIds: [OWNER, MEMBER, THIRD] });
    await seedEvent('g', 'e1', [OWNER, MEMBER, THIRD]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: MEMBER,
      recipientParticipantId: THIRD,
      recipientName: 'Third',
    });
    await seedGroupSettlement('groups/g/settlements/gs1', {
      payerParticipantId: MEMBER,
      recipientParticipantId: THIRD,
      recipientName: 'Third',
    });

    const res = await call({ groupId: 'g', groupSettleUpId: SU, correctionNote: CORRECTION_NOTE }, OWNER);
    expect(res).toMatchObject({ noop: false, eventScopeWrites: 1, groupScopeWrites: 1 });
  });
});
