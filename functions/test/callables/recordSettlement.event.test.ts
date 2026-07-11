// RED → GREEN: #1129 recordSettlement callable — EVENT mode. The transactional
// replacement for the client-direct event settlement create: recomputes the
// single-event pair outstanding (#249 universe, one-event snapshot) inside the
// transaction, caps amountFils, derives the #1093 sd1 id from the client's
// observed pair-epoch (retry-idempotent), and writes the settlement doc + the
// ONE #1140 event_settlement activity row atomically.
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/recordSettlement.event.test.ts" npm run test:emulator`

import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import { clearFirestore } from '../fixtures';
import { recordSettlement } from '../../src/callables/recordSettlement';
import { deterministicSettlementId } from '../../src/callables/shared/settlementIds';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(recordSettlement);

const OWNER = 'owner';
const MEMBER = 'member';
const OUTSIDER = 'outsider';
const DEPARTED = 'departed';

const GROUP = 'g';
const EVENT = 'e1';

async function seedGroup(data: Record<string, unknown> = {}): Promise<void> {
  const db = getFirestore();
  await db.doc(`groups/${GROUP}`).set({
    id: GROUP,
    name: 'Desert Crew',
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
  await db.doc(`groups/${GROUP}/members/${OWNER}`).set({
    id: OWNER,
    userId: OWNER,
    displayName: 'Owner',
    role: 'CREATOR',
    joinedAt: new Date('2026-01-01T00:00:00.000Z'),
    isShadow: false,
  });
  await db.doc(`groups/${GROUP}/members/${MEMBER}`).set({
    id: MEMBER,
    userId: MEMBER,
    displayName: 'Member',
    role: 'MEMBER',
    joinedAt: new Date('2026-01-01T00:00:00.000Z'),
    isShadow: false,
  });
}

async function seedEvent(
  eventId: string,
  participantIds: string[],
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore().doc(`groups/${GROUP}/events/${eventId}`).set({
    id: eventId,
    groupId: GROUP,
    name: 'Weekend Camp',
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

// Owner pays 10.000 OMR, equal split with member → member owes owner 5000
// fils. Mirrors the client service write-map (equal split persists NO
// splitMode/splitDistribution keys).
async function seedDebt(): Promise<void> {
  await getFirestore().doc(`groups/${GROUP}/events/${EVENT}/expenses/x1`).set({
    id: 'x1',
    eventId: EVENT,
    description: 'Fuel',
    amountFils: 10000,
    currency: 'OMR',
    payerParticipantId: OWNER,
    scope: 'global',
    isDeleted: false,
    deletedAt: null,
    createdAt: '2026-01-05T00:00:00.000Z',
    createdBy: OWNER,
    lastEditedBy: OWNER,
  });
}

function input(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    groupId: GROUP,
    mode: 'event',
    eventId: EVENT,
    payerParticipantId: MEMBER,
    recipientParticipantId: OWNER,
    amountFils: 3000,
    currency: 'OMR',
    note: null,
    payerName: 'Member',
    recipientName: 'Owner',
    observedPairEpoch: 0,
    ...overrides,
  };
}

function call(data: Record<string, unknown>, uid: string | null = MEMBER): Promise<unknown> {
  return wrapped({ data, auth: uid == null ? undefined : { uid } } as never) as Promise<unknown>;
}

function expectedId(amountFils: number, epoch: number): string {
  return deterministicSettlementId({
    scopeKey: `event:${GROUP}:${EVENT}`,
    payerParticipantId: MEMBER,
    recipientParticipantId: OWNER,
    currency: 'OMR',
    amountFils,
    pairEpoch: epoch,
  });
}

async function docsIn(path: string): Promise<Map<string, Record<string, unknown>>> {
  const snap = await getFirestore().collection(path).get();
  return new Map(snap.docs.map((d) => [d.id, d.data() as Record<string, unknown>]));
}

describe('recordSettlement — event mode', () => {
  beforeEach(async () => {
    await clearFirestore();
    await seedGroup();
    await seedEvent(EVENT, [OWNER, MEMBER]);
    await seedDebt();
  });

  afterAll(async () => {
    await clearFirestore();
    testEnv.cleanup();
  });

  test('happy path: doc at the derived id, byte-shape, ISO-string times, activity row, output', async () => {
    const result = (await call(input())) as Record<string, unknown>;

    expect(result).toMatchObject({
      alreadyRecorded: false,
      eventScopeWrites: 1,
      groupScopeWrites: 0,
      shouldBumpLedgerRevision: true,
    });
    expect(typeof result.settledAt).toBe('string');

    const id = expectedId(3000, 0);
    const settlements = await docsIn(`groups/${GROUP}/events/${EVENT}/settlements`);
    expect(settlements.size).toBe(1);
    const doc = settlements.get(id)!;
    expect(doc).toBeDefined();
    // Exact write-map of the retired client buildSettlementDoc — key set AND
    // values. groupSettleUpId is OMITTED (solo settle), null name/note keys
    // are PRESENT with null values.
    expect(Object.keys(doc).sort()).toEqual([
      'amountFils', 'createdBy', 'currency', 'deletedAt', 'eventId', 'id',
      'isDeleted', 'note', 'payerName', 'recipientName', 'payerParticipantId',
      'recipientParticipantId', 'settledAt',
    ].sort());
    expect(doc).toMatchObject({
      id,
      eventId: EVENT,
      payerParticipantId: MEMBER,
      recipientParticipantId: OWNER,
      payerName: 'Member',
      recipientName: 'Owner',
      amountFils: 3000,
      currency: 'OMR',
      note: null,
      isDeleted: false,
      deletedAt: null,
      createdBy: MEMBER,
    });
    // Gate R2 P1: a Firestore Timestamp here type-buckets apart from every
    // legacy String doc (ordering) and epoch-0s in Settlement.fromFirestore.
    expect(typeof doc.settledAt).toBe('string');
    expect(doc.settledAt).toBe(result.settledAt);

    const activity = await docsIn(`groups/${GROUP}/activity`);
    expect(activity.size).toBe(1);
    const act = activity.get(`stl_${id}`)!;
    expect(act).toBeDefined();
    expect(act.type).toBe('event_settlement');
    expect(act.actorId).toBe(MEMBER);
    expect(act.actorName).toBe('Member'); // recorder's member-doc displayName
    expect(typeof act.timestamp).toBe('string');
    // #808 metadata contract — event shape: amountFils INT + eventId
    // (+ eventName when non-empty), never the group-shape string `amount`.
    expect(act.metadata).toEqual({
      amountFils: 3000,
      currency: 'OMR',
      fromUserId: MEMBER,
      toUserId: OWNER,
      fromName: 'Member',
      toName: 'Owner',
      eventId: EVENT,
      eventName: 'Weekend Camp',
    });
    // Description golden — TS formatCurrency mirror of AppFormatters
    // ('OMR 3.000'); counterparty is the OTHER party relative to the caller.
    expect(act.description).toBe('settled OMR 3.000 with Owner');
  });

  test('cap boundary: exactly the outstanding is allowed; the next fils is rejected with fresh outstanding', async () => {
    await call(input({ amountFils: 5000 }));

    await expect(
      call(input({ amountFils: 1, observedPairEpoch: 1 })),
    ).rejects.toMatchObject({
      code: 'failed-precondition',
      details: { kind: 'over-outstanding', outstandingFils: 0, currency: 'OMR' },
    });
  });

  test('over-settle rejected atomically: nothing persists, details carry the live outstanding', async () => {
    await expect(call(input({ amountFils: 5001 }))).rejects.toMatchObject({
      code: 'failed-precondition',
      details: { kind: 'over-outstanding', outstandingFils: 5000, currency: 'OMR' },
    });

    expect((await docsIn(`groups/${GROUP}/events/${EVENT}/settlements`)).size).toBe(0);
    expect((await docsIn(`groups/${GROUP}/activity`)).size).toBe(0);
  });

  test('sequential settles with fresh epochs both land; the drained pair then rejects', async () => {
    await call(input({ amountFils: 3000, observedPairEpoch: 0 }));
    await call(input({ amountFils: 2000, observedPairEpoch: 1 }));

    const settlements = await docsIn(`groups/${GROUP}/events/${EVENT}/settlements`);
    expect(settlements.size).toBe(2);

    await expect(
      call(input({ amountFils: 500, observedPairEpoch: 2 })),
    ).rejects.toMatchObject({
      code: 'failed-precondition',
      details: { kind: 'over-outstanding', outstandingFils: 0 },
    });
  });

  test('idempotent replay: identical call → alreadyRecorded, ONE doc, ONE activity row', async () => {
    const first = (await call(input())) as Record<string, unknown>;
    const second = (await call(input())) as Record<string, unknown>;

    expect(second).toMatchObject({
      alreadyRecorded: true,
      eventScopeWrites: 1,
      shouldBumpLedgerRevision: true,
    });
    expect(second.settledAt).toBe(first.settledAt); // replay reports the recorded time

    expect((await docsIn(`groups/${GROUP}/events/${EVENT}/settlements`)).size).toBe(1);
    expect((await docsIn(`groups/${GROUP}/activity`)).size).toBe(1);
  });

  test('the #1093 same-observed-state racer: on-behalf recorder replays the same intent → alreadyRecorded, one doc', async () => {
    await call(input(), MEMBER);
    // Owner records the SAME payment from the same observed state (epoch 0) —
    // createdBy is deliberately NOT an id input (#595).
    const result = (await call(input(), OWNER)) as Record<string, unknown>;

    expect(result.alreadyRecorded).toBe(true);
    expect((await docsIn(`groups/${GROUP}/events/${EVENT}/settlements`)).size).toBe(1);
  });

  test('conflicting payload at the derived id → already-exists', async () => {
    const id = expectedId(3000, 0);
    await getFirestore().doc(`groups/${GROUP}/events/${EVENT}/settlements/${id}`).set({
      id,
      eventId: EVENT,
      payerParticipantId: MEMBER,
      recipientParticipantId: 'somebody-else',
      payerName: null,
      recipientName: null,
      amountFils: 3000,
      currency: 'OMR',
      note: null,
      isDeleted: false,
      deletedAt: null,
      settledAt: '2026-01-06T00:00:00.000Z',
      createdBy: MEMBER,
    });

    await expect(call(input())).rejects.toMatchObject({ code: 'already-exists' });
  });

  describe('authz gates', () => {
    test('unauthenticated → unauthenticated', async () => {
      await expect(call(input(), null)).rejects.toMatchObject({ code: 'unauthenticated' });
    });

    test('non-member caller → permission-denied', async () => {
      await expect(call(input(), OUTSIDER)).rejects.toMatchObject({ code: 'permission-denied' });
    });

    test('counterparty outside event participantIds → party-not-participant', async () => {
      await seedGroup({ memberIds: [OWNER, MEMBER, 'third'] });
      await expect(
        call(input({ recipientParticipantId: 'third' })),
      ).rejects.toMatchObject({
        code: 'failed-precondition',
        details: { kind: 'party-not-participant' },
      });
    });

    test('#1144: participant no longer in memberIds → party-not-member', async () => {
      await seedEvent(EVENT, [OWNER, MEMBER, DEPARTED]);
      await expect(
        call(input({ recipientParticipantId: DEPARTED })),
      ).rejects.toMatchObject({
        code: 'failed-precondition',
        details: { kind: 'party-not-member' },
      });
    });

    test('deleteAccount tombstone ghost (in participantIds AND memberIds) stays settleable', async () => {
      const GHOST = 'tomb_ghost';
      // Clean reseed: the beforeEach x1 expense would re-split across the
      // widened participant set and skew the pair nets — this case pins the
      // ghost gate, so give it exactly one ghost-owed expense.
      await clearFirestore();
      await seedGroup({ memberIds: [OWNER, MEMBER, GHOST] });
      await seedEvent(EVENT, [OWNER, MEMBER, GHOST]);
      // Ghost paid 2.000 OMR equal split with member → member owes ghost 1000.
      await getFirestore().doc(`groups/${GROUP}/events/${EVENT}/expenses/x2`).set({
        id: 'x2',
        eventId: EVENT,
        description: 'Ice',
        amountFils: 2000,
        currency: 'OMR',
        payerParticipantId: GHOST,
        scope: 'global',
        splitMode: 'exact',
        splitDistribution: { [GHOST]: 1000, [MEMBER]: 1000 },
        isDeleted: false,
        deletedAt: null,
        createdAt: '2026-01-05T00:00:00.000Z',
        createdBy: GHOST,
        lastEditedBy: GHOST,
      });

      const result = (await call(
        input({ recipientParticipantId: GHOST, recipientName: null, amountFils: 1000 }),
      )) as Record<string, unknown>;
      expect(result.alreadyRecorded).toBe(false);
    });
  });

  describe('lifecycle gates', () => {
    test('soft-deleted event → not-found', async () => {
      await seedEvent(EVENT, [OWNER, MEMBER], { isDeleted: true, deletedAt: '2026-01-06T00:00:00.000Z' });
      await expect(call(input())).rejects.toMatchObject({ code: 'not-found' });
    });

    test('missing event → not-found', async () => {
      await expect(call(input({ eventId: 'nope' }))).rejects.toMatchObject({ code: 'not-found' });
    });

    test.each([
      ['isDeleted', { isDeleted: true }],
      ['deletingInProgress', { deletingInProgress: true }],
      ['claimingInProgress', { claimingInProgress: true }],
      ['accountDeletionInProgress', { accountDeletionInProgress: true }],
      ['departureInProgress', { departureInProgress: true }],
    ])('group write-lock flag %s → not-found', async (_flag, patch) => {
      await seedGroup(patch as Record<string, unknown>);
      await expect(call(input())).rejects.toMatchObject({ code: 'not-found' });
    });

    test('CLOSED event still accepts settlements (close gates expenses only)', async () => {
      await seedEvent(EVENT, [OWNER, MEMBER], { isClosed: true, closedAt: '2026-01-06T00:00:00.000Z', closedBy: OWNER });
      await seedDebt();
      const result = (await call(input())) as Record<string, unknown>;
      expect(result.alreadyRecorded).toBe(false);
    });
  });

  describe('input validation (invalid-argument)', () => {
    test.each([
      ['payer == recipient', { recipientParticipantId: MEMBER }],
      ['zero amount', { amountFils: 0 }],
      ['negative amount', { amountFils: -5 }],
      ['fractional amount', { amountFils: 1.5 }],
      ['unsupported currency', { currency: 'XXX' }],
      ['non-canonical currency case', { currency: 'omr' }],
      ['over-long name', { payerName: 'x'.repeat(33) }],
      ['over-long note', { note: 'x'.repeat(281) }],
      ['control chars in note', { note: 'a\u0000b' }],
      ['negative epoch', { observedPairEpoch: -1 }],
      ['fractional epoch', { observedPairEpoch: 1.5 }],
      ['absurd epoch', { observedPairEpoch: 10_000_001 }],
      ['missing eventId', { eventId: undefined }],
      ['legs supplied in event mode', { legs: [{ eventId: EVENT, amountFils: 1000 }] }],
      ['unknown mode', { mode: 'sideways' }],
    ])('%s', async (_name, overrides) => {
      await expect(call(input(overrides as Record<string, unknown>))).rejects.toMatchObject({
        code: 'invalid-argument',
      });
    });
  });

  test('per-currency isolation: OMR debt never funds a JPY settle', async () => {
    await expect(
      call(input({ currency: 'JPY', amountFils: 100 })),
    ).rejects.toMatchObject({
      code: 'failed-precondition',
      details: { kind: 'over-outstanding', outstandingFils: 0, currency: 'JPY' },
    });
  });

  test('JPY description golden (scale 1, zero decimals)', async () => {
    // Owner paid 500 JPY equal split → member owes 250 JPY.
    await getFirestore().doc(`groups/${GROUP}/events/${EVENT}/expenses/x_jpy`).set({
      id: 'x_jpy',
      eventId: EVENT,
      description: 'Ramen',
      amountFils: 500,
      currency: 'JPY',
      payerParticipantId: OWNER,
      scope: 'global',
      isDeleted: false,
      deletedAt: null,
      createdAt: '2026-01-05T00:00:00.000Z',
      createdBy: OWNER,
      lastEditedBy: OWNER,
    });

    await call(input({ currency: 'JPY', amountFils: 250 }));
    const activity = await docsIn(`groups/${GROUP}/activity`);
    const act = [...activity.values()][0];
    expect(act.description).toBe('settled JPY 250 with Owner');
  });
});
