// RED → GREEN: #1129 recordSettlement callable — GROUP + GROUPSETTLEUP modes.
// Group solo caps against the aggregate oracle nets; groupSettleUp validates
// the client-staged decomposition (Σ legs + residual == total, each leg ≤ the
// participantIds-only per-event drill-down overlap) and writes N legs +
// residual + ONE group_settlement activity row in one transaction — the
// rules-budget 8-leg carve-out is gone.
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/recordSettlement.group.test.ts" npm run test:emulator`

import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import { clearFirestore } from '../fixtures';
import { recordSettlement } from '../../src/callables/recordSettlement';
import {
  decomposeLegSettlementId,
  decomposeResidualSettlementId,
  deterministicSettlementId,
} from '../../src/callables/shared/settlementIds';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(recordSettlement);

const OWNER = 'owner';
const MEMBER = 'member';
const CAROL = 'carol';
const OUTSIDER = 'outsider';
const GROUP = 'g';

async function seedGroup(): Promise<void> {
  const db = getFirestore();
  await db.doc(`groups/${GROUP}`).set({
    id: GROUP,
    name: 'Desert Crew',
    inviteCode: 'ABC123',
    createdBy: OWNER,
    memberIds: [OWNER, MEMBER, CAROL],
    currency: 'OMR',
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    updatedAt: new Date('2026-01-02T00:00:00.000Z'),
    isDeleted: false,
    deletedAt: null,
  });
  for (const [uid, name] of [[OWNER, 'Owner'], [MEMBER, 'Member'], [CAROL, 'Carol']]) {
    await db.doc(`groups/${GROUP}/members/${uid}`).set({
      id: uid,
      userId: uid,
      displayName: name,
      role: uid === OWNER ? 'CREATOR' : 'MEMBER',
      joinedAt: new Date('2026-01-01T00:00:00.000Z'),
      isShadow: false,
    });
  }
}

async function seedEvent(eventId: string, participantIds: string[], data: Record<string, unknown> = {}): Promise<void> {
  await getFirestore().doc(`groups/${GROUP}/events/${eventId}`).set({
    id: eventId,
    groupId: GROUP,
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

async function seedExpense(
  eventId: string,
  id: string,
  payer: string,
  amountFils: number,
): Promise<void> {
  await getFirestore().doc(`groups/${GROUP}/events/${eventId}/expenses/${id}`).set({
    id,
    eventId,
    description: id,
    amountFils,
    currency: 'OMR',
    payerParticipantId: payer,
    scope: 'global',
    isDeleted: false,
    deletedAt: null,
    createdAt: '2026-01-05T00:00:00.000Z',
    createdBy: payer,
    lastEditedBy: payer,
  });
}

// Scenario A — the gsu-with-residual fixture:
//   e1 [owner, member]: owner paid 10.000 → member owes owner 5000
//   e2 [member, carol]: carol paid 4.000 → member owes carol 2000
//   e3 [owner, carol]: owner paid 4.000 → carol owes owner 2000
// Aggregate: member −7000, owner +7000, carol 0 → pair member→owner
// outstanding 7000. Per-event overlap member→owner: e1 5000, e2 0, e3 0 —
// so decompose(7000) = legs [e1:5000] + residual 2000 (cross-event debt).
async function seedScenarioA(): Promise<void> {
  await seedEvent('e1', [OWNER, MEMBER]);
  await seedEvent('e2', [MEMBER, CAROL]);
  await seedEvent('e3', [OWNER, CAROL]);
  await seedExpense('e1', 'x1', OWNER, 10000);
  await seedExpense('e2', 'x2', CAROL, 4000);
  await seedExpense('e3', 'x3', OWNER, 4000);
}

function input(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    groupId: GROUP,
    mode: 'group',
    payerParticipantId: MEMBER,
    recipientParticipantId: OWNER,
    amountFils: 7000,
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

function groupScopeId(amountFils: number, epoch: number): string {
  return deterministicSettlementId({
    scopeKey: `group:${GROUP}`,
    payerParticipantId: MEMBER,
    recipientParticipantId: OWNER,
    currency: 'OMR',
    amountFils,
    pairEpoch: epoch,
  });
}

function gsuId(amountFils: number, epoch: number): string {
  return deterministicSettlementId({
    scopeKey: `gsu:${GROUP}`,
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

describe('recordSettlement — group mode', () => {
  beforeEach(async () => {
    await clearFirestore();
    await seedGroup();
    await seedScenarioA();
  });

  afterAll(async () => {
    await clearFirestore();
    testEnv.cleanup();
  });

  test('group solo happy: aggregate cap, sentinel doc shape, group_settlement activity with STRING amount metadata', async () => {
    const result = (await call(input())) as Record<string, unknown>;

    expect(result).toMatchObject({
      alreadyRecorded: false,
      eventScopeWrites: 0,
      groupScopeWrites: 1,
      shouldBumpLedgerRevision: false, // pure group write: home once-provider watches live
    });

    const id = groupScopeId(7000, 0);
    const docs = await docsIn(`groups/${GROUP}/settlements`);
    expect(docs.size).toBe(1);
    const doc = docs.get(id)!;
    expect(doc).toBeDefined();
    expect(Object.keys(doc).sort()).toEqual([
      'amountFils', 'createdBy', 'currency', 'deletedAt', 'eventId', 'groupId',
      'id', 'isDeleted', 'note', 'payerName', 'recipientName',
      'payerParticipantId', 'recipientParticipantId', 'scope', 'settledAt',
    ].sort());
    expect(doc).toMatchObject({
      id,
      groupId: GROUP,
      eventId: GROUP, // sentinel — group settlements have no event
      scope: 'group',
      payerParticipantId: MEMBER,
      recipientParticipantId: OWNER,
      amountFils: 7000,
      currency: 'OMR',
      createdBy: MEMBER,
      isDeleted: false,
      deletedAt: null,
    });
    expect(typeof doc.settledAt).toBe('string');

    const activity = await docsIn(`groups/${GROUP}/activity`);
    expect(activity.size).toBe(1);
    const act = activity.get(`stl_${id}`)!;
    expect(act).toBeDefined();
    expect(act.type).toBe('group_settlement');
    expect(act.actorId).toBe(MEMBER);
    expect(typeof act.timestamp).toBe('string');
    // #808 metadata contract — group shape: STRING amount (Dart
    // Decimal.toString(): trailing zeros stripped), recipientId, NO
    // amountFils, NO eventId. Never homogenize with the event shape.
    expect(act.metadata).toEqual({
      amount: '7',
      recipientId: OWNER,
      currency: 'OMR',
      fromUserId: MEMBER,
      toUserId: OWNER,
      fromName: 'Member',
      toName: 'Owner',
    });
    expect(act.description).toBe('settled OMR 7.000 with Owner');
  });

  test('cross-event pair (empty-perEvent class) lands as a plain group settle — the invariant-11 fallback route', async () => {
    // Rebuild WITHOUT e1: member owes carol (e2), carol owes owner (e3) —
    // no single event has payer-owes ∧ recipient-owed for member→owner, yet
    // the aggregate pair outstanding is 2000.
    await clearFirestore();
    await seedGroup();
    await seedEvent('e2', [MEMBER, CAROL]);
    await seedEvent('e3', [OWNER, CAROL]);
    await seedExpense('e2', 'x2', CAROL, 4000);
    await seedExpense('e3', 'x3', OWNER, 4000);

    const result = (await call(input({ amountFils: 2000 }))) as Record<string, unknown>;
    expect(result).toMatchObject({ alreadyRecorded: false, groupScopeWrites: 1 });
  });

  test('the #1129 headline: different-amount racers from one observed state — the second is capped, never over-settles', async () => {
    // Racer A records a partial 3.000 from the epoch-0 view — lands.
    await call(input({ amountFils: 3000 }));

    // Racer B recorded the FULL 7.000 from the SAME pre-A view (epoch still
    // 0). Under #1093 both landed → over-settle by 3.000. Now the transaction
    // recomputes: outstanding is 4000, so B is rejected with the live number.
    await expect(call(input({ amountFils: 7000 }))).rejects.toMatchObject({
      code: 'failed-precondition',
      details: { kind: 'over-outstanding', outstandingFils: 4000, currency: 'OMR' },
    });

    expect((await docsIn(`groups/${GROUP}/settlements`)).size).toBe(1);
  });

  test('counterparty outside memberIds → party-not-member', async () => {
    await expect(
      call(input({ recipientParticipantId: 'stranger' })),
    ).rejects.toMatchObject({
      code: 'failed-precondition',
      details: { kind: 'party-not-member' },
    });
  });

  test('non-member caller → permission-denied', async () => {
    await expect(call(input(), OUTSIDER)).rejects.toMatchObject({ code: 'permission-denied' });
  });

  test('group-mode idempotent replay → alreadyRecorded, one doc, one activity row', async () => {
    await call(input());
    const second = (await call(input())) as Record<string, unknown>;

    expect(second).toMatchObject({ alreadyRecorded: true, groupScopeWrites: 1 });
    expect((await docsIn(`groups/${GROUP}/settlements`)).size).toBe(1);
    expect((await docsIn(`groups/${GROUP}/activity`)).size).toBe(1);
  });
});

describe('recordSettlement — groupSettleUp mode', () => {
  beforeEach(async () => {
    await clearFirestore();
    await seedGroup();
    await seedScenarioA();
  });

  afterAll(async () => {
    await clearFirestore();
    testEnv.cleanup();
  });

  function gsuInput(overrides: Record<string, unknown> = {}): Record<string, unknown> {
    return input({
      mode: 'groupSettleUp',
      amountFils: 7000,
      legs: [{ eventId: 'e1', amountFils: 5000 }],
      ...overrides,
    });
  }

  test('gsu happy: leg + residual + ONE activity row, conservation server-verified, atomic ids from the gsu parent', async () => {
    const result = (await call(gsuInput())) as Record<string, unknown>;

    expect(result).toMatchObject({
      alreadyRecorded: false,
      eventScopeWrites: 1,
      groupScopeWrites: 1,
      shouldBumpLedgerRevision: true,
    });

    const parent = gsuId(7000, 0);
    const legId = decomposeLegSettlementId(parent, 'e1');
    const residualId = decomposeResidualSettlementId(parent);

    const e1Docs = await docsIn(`groups/${GROUP}/events/e1/settlements`);
    expect(e1Docs.size).toBe(1);
    const leg = e1Docs.get(legId)!;
    expect(leg).toMatchObject({
      id: legId,
      eventId: 'e1',
      amountFils: 5000,
      groupSettleUpId: parent,
      payerParticipantId: MEMBER,
      recipientParticipantId: OWNER,
    });
    expect(typeof leg.settledAt).toBe('string');

    const groupDocs = await docsIn(`groups/${GROUP}/settlements`);
    expect(groupDocs.size).toBe(1);
    const residual = groupDocs.get(residualId)!;
    expect(residual).toMatchObject({
      id: residualId,
      scope: 'group',
      eventId: GROUP,
      amountFils: 2000,
      groupSettleUpId: parent,
    });
    // Conservation: Σ legs + residual == total, one shared timestamp.
    expect((leg.amountFils as number) + (residual.amountFils as number)).toBe(7000);
    expect(residual.settledAt).toBe(leg.settledAt);

    const activity = await docsIn(`groups/${GROUP}/activity`);
    expect(activity.size).toBe(1);
    const act = activity.get(`gstl_${parent}`)!;
    expect(act).toBeDefined();
    expect(act.type).toBe('group_settlement');
    expect(act.metadata).toEqual({
      amount: '7',
      recipientId: OWNER,
      currency: 'OMR',
      fromUserId: MEMBER,
      toUserId: OWNER,
      fromName: 'Member',
      toName: 'Owner',
    });
  });

  test('residual == 0 → no residual doc; idempotency probes the first leg', async () => {
    // Rebuild with ONLY e1 debt: full decompose covers the total.
    await clearFirestore();
    await seedGroup();
    await seedEvent('e1', [OWNER, MEMBER]);
    await seedExpense('e1', 'x1', OWNER, 10000);

    const data = gsuInput({ amountFils: 5000, legs: [{ eventId: 'e1', amountFils: 5000 }] });
    const result = (await call(data)) as Record<string, unknown>;
    expect(result).toMatchObject({ eventScopeWrites: 1, groupScopeWrites: 0 });
    expect((await docsIn(`groups/${GROUP}/settlements`)).size).toBe(0);

    const second = (await call(data)) as Record<string, unknown>;
    expect(second.alreadyRecorded).toBe(true);
    expect((await docsIn(`groups/${GROUP}/events/e1/settlements`)).size).toBe(1);
  });

  test('gsu idempotent replay → alreadyRecorded, counts unchanged', async () => {
    await call(gsuInput());
    const second = (await call(gsuInput())) as Record<string, unknown>;

    expect(second).toMatchObject({
      alreadyRecorded: true,
      eventScopeWrites: 1,
      groupScopeWrites: 1,
      shouldBumpLedgerRevision: true,
    });
    expect((await docsIn(`groups/${GROUP}/events/e1/settlements`)).size).toBe(1);
    expect((await docsIn(`groups/${GROUP}/settlements`)).size).toBe(1);
    expect((await docsIn(`groups/${GROUP}/activity`)).size).toBe(1);
  });

  test('stale leg (> per-event drill-down overlap) → stale-decomposition, NOTHING persisted', async () => {
    await expect(
      call(gsuInput({ legs: [{ eventId: 'e1', amountFils: 5001 }] })),
    ).rejects.toMatchObject({
      code: 'failed-precondition',
      details: { kind: 'stale-decomposition' },
    });

    expect((await docsIn(`groups/${GROUP}/events/e1/settlements`)).size).toBe(0);
    expect((await docsIn(`groups/${GROUP}/settlements`)).size).toBe(0);
    expect((await docsIn(`groups/${GROUP}/activity`)).size).toBe(0);
  });

  test('Σ legs > total (negative residual) → stale-decomposition', async () => {
    await expect(
      call(gsuInput({ amountFils: 4000, legs: [{ eventId: 'e1', amountFils: 5000 }] })),
    ).rejects.toMatchObject({
      code: 'failed-precondition',
      details: { kind: 'stale-decomposition' },
    });
  });

  test('leg for an unknown event → stale-decomposition', async () => {
    await expect(
      call(gsuInput({ legs: [{ eventId: 'e9', amountFils: 1000 }] })),
    ).rejects.toMatchObject({
      code: 'failed-precondition',
      details: { kind: 'stale-decomposition' },
    });
  });

  test('leg for a soft-deleted event → stale-decomposition', async () => {
    await seedEvent('e_dead', [OWNER, MEMBER], { isDeleted: true, deletedAt: '2026-01-06T00:00:00.000Z' });
    await expect(
      call(gsuInput({ legs: [{ eventId: 'e_dead', amountFils: 1000 }] })),
    ).rejects.toMatchObject({
      code: 'failed-precondition',
      details: { kind: 'stale-decomposition' },
    });
  });

  test('gsu total is ALSO capped by the aggregate outstanding', async () => {
    await expect(
      call(gsuInput({ amountFils: 7001 })),
    ).rejects.toMatchObject({
      code: 'failed-precondition',
      details: { kind: 'over-outstanding', outstandingFils: 7000 },
    });
  });

  describe('legs validation (invalid-argument)', () => {
    test.each([
      ['empty legs', { legs: [] }],
      ['missing legs', { legs: undefined }],
      ['duplicate leg eventIds', { legs: [{ eventId: 'e1', amountFils: 100 }, { eventId: 'e1', amountFils: 100 }] }],
      ['zero-amount leg', { legs: [{ eventId: 'e1', amountFils: 0 }] }],
      ['fractional leg', { legs: [{ eventId: 'e1', amountFils: 10.5 }] }],
    ])('%s', async (_name, overrides) => {
      await expect(call(gsuInput(overrides as Record<string, unknown>))).rejects.toMatchObject({
        code: 'invalid-argument',
      });
    });

    test('legs.length > 400 → failed-precondition (500-write tx headroom)', async () => {
      const legs = Array.from({ length: 401 }, (_, i) => ({ eventId: `e${i}`, amountFils: 1 }));
      await expect(call(gsuInput({ legs, amountFils: 7000 }))).rejects.toMatchObject({
        code: 'failed-precondition',
      });
    });
  });
});
