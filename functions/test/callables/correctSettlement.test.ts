// RED → GREEN: #889 correction marker foundation — correctSettlement callable
// (direct event/group correction). Server-authoritative replacement for the
// client-direct reverse write on the solo `onCorrect` sites, so the reverse
// row carries an un-forgeable `correctionOfSettlementId` marker (rules deny
// the key on client creates via hasOnly-omission).
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/correctSettlement.test.ts" npm run test:emulator`

import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';
import { correctSettlement } from '../../src/callables/correctSettlement';
import { directReverseId } from '../../src/callables/shared/settlementCorrection';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(correctSettlement);

const OWNER = 'owner';
const MEMBER = 'member';
const OUTSIDER = 'outsider';

async function seedGroup(groupId: string, data: Record<string, unknown> = {}): Promise<void> {
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
    amountFils: 5000,
    currency: 'OMR',
    note: 'dinner',
    isDeleted: false,
    deletedAt: null,
    settledAt: '2026-01-08T00:00:00.000Z',
    ...data,
  });
}

async function seedGroupSettlement(
  path: string,
  data: Record<string, unknown> = {},
): Promise<void> {
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
    amountFils: 5000,
    currency: 'OMR',
    note: 'dinner',
    isDeleted: false,
    deletedAt: null,
    settledAt: '2026-01-08T00:00:00.000Z',
    ...data,
  });
}

async function getDoc(path: string) {
  return (await getFirestore().doc(path).get()).data();
}

async function collectionDocs(path: string) {
  return (await getFirestore().collection(path).get()).docs;
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

const CORRECTION_NOTE = 'Correction of a recorded payment';

describe('correctSettlement — scope: event', () => {
  test('1. missing auth → unauthenticated', async () => {
    await expect(
      wrapped({
        data: { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE },
        auth: undefined,
      } as any),
    ).rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('2. non-member caller → permission-denied', async () => {
    await seedGroup('g');
    await expect(
      wrapped({
        data: { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE },
        auth: { uid: OUTSIDER },
      } as any),
    ).rejects.toMatchObject({ code: 'permission-denied' });
  });

  test('3. locked/deleted group (all four flags) → not-found', async () => {
    for (const flag of ['isDeleted', 'deletingInProgress', 'claimingInProgress', 'accountDeletionInProgress', 'departureInProgress']) {
      const gid = `locked-${flag}`;
      await seedGroup(gid, { [flag]: true });
      await expect(
        wrapped({
          data: { groupId: gid, scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE },
          auth: { uid: OWNER },
        } as any),
      ).rejects.toMatchObject({ code: 'not-found' });
    }
  });

  test('4. deleted event → not-found', async () => {
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER], { isDeleted: true });
    await expect(
      wrapped({
        data: { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'not-found' });
  });

  test('5. missing settlement → not-found', async () => {
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER]);
    await expect(
      wrapped({
        data: { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 'ghost', correctionNote: CORRECTION_NOTE },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'not-found' });
  });

  test('6. deleted settlement → failed-precondition', async () => {
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1', { isDeleted: true });
    await expect(
      wrapped({
        data: { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('7. non-participant parties → failed-precondition', async () => {
    await seedGroup('g', { memberIds: [OWNER, MEMBER, OUTSIDER] });
    await seedEvent('g', 'e1', [OWNER, MEMBER]); // OUTSIDER not a participant
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: OUTSIDER,
      recipientParticipantId: OWNER,
    });
    await expect(
      wrapped({
        data: { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('8. already-marked original → failed-precondition', async () => {
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      correctionOfSettlementId: 'someOtherOrig',
    });
    await expect(
      wrapped({
        data: { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('9. tagged groupSettleUpId original → failed-precondition (correct via correctLogicalSettleUp instead)', async () => {
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1', { groupSettleUpId: 'su-1' });
    await expect(
      wrapped({
        data: { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('10. unsupported scope → invalid-argument', async () => {
    await seedGroup('g');
    await expect(
      wrapped({
        data: { groupId: 'g', scope: 'trip', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('11. missing eventId for event scope → invalid-argument', async () => {
    await seedGroup('g');
    await expect(
      wrapped({
        data: { groupId: 'g', scope: 'event', settlementId: 's1', correctionNote: CORRECTION_NOTE },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('12. empty / over-length / control-char correctionNote → invalid-argument; a NON-sentinel note is ACCEPTED verbatim', async () => {
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1');

    for (const note of ['', '   ', 'x'.repeat(281), 'bad\x01note']) {
      await expect(
        wrapped({
          data: { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: note },
          auth: { uid: OWNER },
        } as any),
      ).rejects.toMatchObject({ code: 'invalid-argument' });
    }

    // A non-sentinel note is accepted and written VERBATIM — proving no
    // locale-sentinel input validation on the incoming note.
    const res = await wrapped({
      data: { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: 'paid you back' },
      auth: { uid: OWNER },
    } as any);
    expect(res).toMatchObject({ noop: false });
    const reverseId = directReverseId('groups/g/events/e1/settlements/s1');
    const reverse = await getDoc(`groups/g/events/e1/settlements/${reverseId}`);
    expect(reverse?.note).toBe('paid you back');
  });

  test('13. HAPPY: writes the exact event reverse map with deterministic id, marker set', async () => {
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1');

    const res = await wrapped({
      data: { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE },
      auth: { uid: OWNER },
    } as any);

    expect(res).toEqual({
      eventScopeWrites: 1,
      groupScopeWrites: 0,
      repaired: false,
      noop: false,
      shouldBumpLedgerRevision: true,
    });

    const reverseId = directReverseId('groups/g/events/e1/settlements/s1');
    const reverse = await getDoc(`groups/g/events/e1/settlements/${reverseId}`);
    expect(reverse).toMatchObject({
      id: reverseId,
      eventId: 'e1',
      payerParticipantId: OWNER,
      recipientParticipantId: MEMBER,
      payerName: 'Owner',
      recipientName: 'Member',
      amountFils: 5000,
      currency: 'OMR',
      note: CORRECTION_NOTE,
      isDeleted: false,
      deletedAt: null,
      createdBy: OWNER,
      correctionOfSettlementId: 's1',
    });
    expect(reverse?.settledAt).toEqual(expect.any(String));
    expect('groupSettleUpId' in (reverse ?? {})).toBe(false);

    // Original is untouched (append-only, B3).
    const original = await getDoc('groups/g/events/e1/settlements/s1');
    expect(original?.isDeleted).toBe(false);
    expect(original?.correctionOfSettlementId).toBeUndefined();
  });

  test('14. retry is idempotent — no duplicate reverse; returns noop:true, shouldBumpLedgerRevision:true', async () => {
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1');

    await wrapped({
      data: { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE },
      auth: { uid: OWNER },
    } as any);
    // Retry by a DIFFERENT member with a DIFFERENT locale note — idempotency
    // does not require createdBy == callerUid or note == correctionNote.
    const retry = await wrapped({
      data: { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: 'تصحيح لدفعة مُسجَّلة' },
      auth: { uid: MEMBER },
    } as any);

    expect(retry).toEqual({
      eventScopeWrites: 1,
      groupScopeWrites: 0,
      repaired: false,
      noop: true,
      shouldBumpLedgerRevision: true,
    });
    const docs = await collectionDocs('groups/g/events/e1/settlements');
    expect(docs).toHaveLength(2); // original + the ONE reverse, never a second
  });

  test('15. bounded-legacy already-corrected source → no-op success, no new write', async () => {
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1'); // MEMBER -> OWNER, note "dinner"
    await seedEventSettlement('groups/g/events/e1/settlements/legacyFix', {
      payerParticipantId: OWNER,
      recipientParticipantId: MEMBER,
      payerName: 'Owner',
      recipientName: 'Member',
      note: CORRECTION_NOTE, // sentinel, exact inverse of s1, uuid id (pre-marker)
    });

    const res = await wrapped({
      data: { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE },
      auth: { uid: OWNER },
    } as any);

    expect(res).toEqual({
      eventScopeWrites: 0,
      groupScopeWrites: 0,
      repaired: false,
      noop: true,
      shouldBumpLedgerRevision: false,
    });
    const docs = await collectionDocs('groups/g/events/e1/settlements');
    expect(docs).toHaveLength(2); // s1 + legacyFix — nothing new
  });

  test('16. original IS itself a legacy correction row → failed-precondition (no correction-of-correction)', async () => {
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER]);
    await seedEventSettlement('groups/g/events/e1/settlements/source1'); // MEMBER -> OWNER, "dinner"
    await seedEventSettlement('groups/g/events/e1/settlements/legacyFix', {
      payerParticipantId: OWNER,
      recipientParticipantId: MEMBER,
      payerName: 'Owner',
      recipientName: 'Member',
      note: CORRECTION_NOTE,
    });

    await expect(
      wrapped({
        data: { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 'legacyFix', correctionNote: CORRECTION_NOTE },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('17. deterministic reverse id collision that does NOT validate → already-exists; no other write', async () => {
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1');
    const reverseId = directReverseId('groups/g/events/e1/settlements/s1');
    // A doc already lives at the deterministic id but with the WRONG amount —
    // it does not validate as the expected reverse.
    await seedEventSettlement(`groups/g/events/e1/settlements/${reverseId}`, {
      payerParticipantId: OWNER,
      recipientParticipantId: MEMBER,
      amountFils: 1,
      correctionOfSettlementId: 's1',
    });

    await expect(
      wrapped({
        data: { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'already-exists' });

    const docs = await collectionDocs('groups/g/events/e1/settlements');
    expect(docs).toHaveLength(2); // s1 + the pre-seeded conflicting doc only
  });

  test('18. correction of a settlement AFTER event close still succeeds (settlements stay live)', async () => {
    await seedGroup('g');
    await seedEvent('g', 'e1', [OWNER, MEMBER], { isClosed: true, closedAt: '2026-02-01T00:00:00.000Z', closedBy: OWNER });
    await seedEventSettlement('groups/g/events/e1/settlements/s1');

    const res = await wrapped({
      data: { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE },
      auth: { uid: OWNER },
    } as any);
    expect(res.noop).toBe(false);
  });
});

describe('correctSettlement — scope: group', () => {
  test('rejection matrix mirrors event scope (group-member parties)', async () => {
    await seedGroup('g', { memberIds: [OWNER, MEMBER, OUTSIDER] });
    await seedGroupSettlement('groups/g/settlements/gs1', {
      payerParticipantId: OUTSIDER,
      recipientParticipantId: OWNER,
    });
    // OUTSIDER removed from live membership — parties must be CURRENT members.
    await getFirestore().doc('groups/g').update({ memberIds: [OWNER, MEMBER] });

    await expect(
      wrapped({
        data: { groupId: 'g', scope: 'group', settlementId: 'gs1', correctionNote: CORRECTION_NOTE },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('HAPPY: writes the exact group reverse map, shouldBumpLedgerRevision:false', async () => {
    await seedGroup('g');
    await seedGroupSettlement('groups/g/settlements/gs1');

    const res = await wrapped({
      data: { groupId: 'g', scope: 'group', settlementId: 'gs1', correctionNote: CORRECTION_NOTE },
      auth: { uid: OWNER },
    } as any);

    expect(res).toEqual({
      eventScopeWrites: 0,
      groupScopeWrites: 1,
      repaired: false,
      noop: false,
      shouldBumpLedgerRevision: false,
    });

    const reverseId = directReverseId('groups/g/settlements/gs1');
    const reverse = await getDoc(`groups/g/settlements/${reverseId}`);
    expect(reverse).toMatchObject({
      id: reverseId,
      groupId: 'g',
      eventId: 'g',
      scope: 'group',
      payerParticipantId: OWNER,
      recipientParticipantId: MEMBER,
      amountFils: 5000,
      currency: 'OMR',
      note: CORRECTION_NOTE,
      correctionOfSettlementId: 'gs1',
    });
  });

  test('retry is idempotent (no duplicate group reverse)', async () => {
    await seedGroup('g');
    await seedGroupSettlement('groups/g/settlements/gs1');

    await wrapped({
      data: { groupId: 'g', scope: 'group', settlementId: 'gs1', correctionNote: CORRECTION_NOTE },
      auth: { uid: OWNER },
    } as any);
    const retry = await wrapped({
      data: { groupId: 'g', scope: 'group', settlementId: 'gs1', correctionNote: CORRECTION_NOTE },
      auth: { uid: OWNER },
    } as any);

    expect(retry.noop).toBe(true);
    const docs = await collectionDocs('groups/g/settlements');
    expect(docs).toHaveLength(2);
  });

  test('legacy no-op: a live bounded-legacy inverse correction already exists', async () => {
    await seedGroup('g');
    await seedGroupSettlement('groups/g/settlements/gs1');
    await seedGroupSettlement('groups/g/settlements/legacyFix', {
      payerParticipantId: OWNER,
      recipientParticipantId: MEMBER,
      payerName: 'Owner',
      recipientName: 'Member',
      note: CORRECTION_NOTE,
    });

    const res = await wrapped({
      data: { groupId: 'g', scope: 'group', settlementId: 'gs1', correctionNote: CORRECTION_NOTE },
      auth: { uid: OWNER },
    } as any);
    expect(res.noop).toBe(true);
    const docs = await collectionDocs('groups/g/settlements');
    expect(docs).toHaveLength(2);
  });

  test('invalid-collision: fails without writing when the deterministic reverse id exists but does not validate', async () => {
    await seedGroup('g');
    await seedGroupSettlement('groups/g/settlements/gs1');
    const reverseId = directReverseId('groups/g/settlements/gs1');
    await seedGroupSettlement(`groups/g/settlements/${reverseId}`, {
      payerParticipantId: OWNER,
      recipientParticipantId: MEMBER,
      amountFils: 1,
      correctionOfSettlementId: 'gs1',
    });

    await expect(
      wrapped({
        data: { groupId: 'g', scope: 'group', settlementId: 'gs1', correctionNote: CORRECTION_NOTE },
        auth: { uid: OWNER },
      } as any),
    ).rejects.toMatchObject({ code: 'already-exists' });
  });
});

// Actor policy: only the group creator or a party (payer/recipient) to the
// settlement may correct it. A member who is neither is denied; shadow
// participants (uuid ids, never auth uids) can never satisfy the party branch.
describe('correctSettlement — actor policy (creator-or-party)', () => {
  const THIRD = 'third';
  const SHADOW = '7f3b2a10-9c4d-4e8f-b1a2-3d5c6e7f8a9b';

  function callAs(uid: string, data: Record<string, unknown>) {
    return wrapped({ data, auth: { uid } } as any);
  }

  test('A1. DENY: event scope — member who is neither party nor creator → permission-denied, no write', async () => {
    await seedGroup('g', { memberIds: [OWNER, MEMBER, THIRD] });
    await seedEvent('g', 'e1', [OWNER, MEMBER, THIRD]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1'); // MEMBER -> OWNER

    await expect(
      callAs(THIRD, { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE }),
    ).rejects.toMatchObject({ code: 'permission-denied' });
    const docs = await collectionDocs('groups/g/events/e1/settlements');
    expect(docs).toHaveLength(1);
  });

  test('A2. ALLOW: payer corrects', async () => {
    await seedGroup('g', { memberIds: [OWNER, MEMBER, THIRD] });
    await seedEvent('g', 'e1', [OWNER, MEMBER, THIRD]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1'); // MEMBER -> OWNER

    const res = await callAs(MEMBER, { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE });
    expect(res.noop).toBe(false);
  });

  test('A3. ALLOW: recipient corrects', async () => {
    await seedGroup('g', { memberIds: [OWNER, MEMBER, THIRD] });
    await seedEvent('g', 'e1', [OWNER, MEMBER, THIRD]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: MEMBER,
      recipientParticipantId: THIRD,
      recipientName: 'Third',
    });

    const res = await callAs(THIRD, { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE });
    expect(res.noop).toBe(false);
  });

  test('A4. ALLOW: group creator who is not a party corrects', async () => {
    await seedGroup('g', { memberIds: [OWNER, MEMBER, THIRD] });
    await seedEvent('g', 'e1', [OWNER, MEMBER, THIRD]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: MEMBER,
      recipientParticipantId: THIRD,
      recipientName: 'Third',
    });

    const res = await callAs(OWNER, { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE });
    expect(res.noop).toBe(false);
  });

  test('A5. group scope: DENY non-party member; ALLOW payer', async () => {
    await seedGroup('g', { memberIds: [OWNER, MEMBER, THIRD] });
    await seedGroupSettlement('groups/g/settlements/gs1'); // MEMBER -> OWNER

    await expect(
      callAs(THIRD, { groupId: 'g', scope: 'group', settlementId: 'gs1', correctionNote: CORRECTION_NOTE }),
    ).rejects.toMatchObject({ code: 'permission-denied' });

    const res = await callAs(MEMBER, { groupId: 'g', scope: 'group', settlementId: 'gs1', correctionNote: CORRECTION_NOTE });
    expect(res.noop).toBe(false);
  });

  test('A6. shadow party never opens the door: non-party member denied, real counterparty allowed', async () => {
    // The shadow uuid must sit in memberIds AND participantIds so the earlier
    // party-validation loop passes and the ACTOR gate is the branch under test.
    await seedGroup('g', { memberIds: [OWNER, MEMBER, THIRD, SHADOW] });
    await seedEvent('g', 'e1', [OWNER, MEMBER, THIRD, SHADOW]);
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: SHADOW,
      recipientParticipantId: MEMBER,
      payerName: 'Shadow',
      recipientName: 'Member',
    });

    await expect(
      callAs(THIRD, { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE }),
    ).rejects.toMatchObject({ code: 'permission-denied' });

    const res = await callAs(MEMBER, { groupId: 'g', scope: 'event', eventId: 'e1', settlementId: 's1', correctionNote: CORRECTION_NOTE });
    expect(res.noop).toBe(false);
  });
});
