import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { clearFirestore } from '../fixtures';

// RED → GREEN (#366 Tasks 2-3): the balance-aggregate writer. The handler
// recomputes via the shared groupNetBalance oracle (parity by construction —
// there is NO balance math in this module) and writes
// groups/{gid}/aggregates/balance behind a sourceTimeMs ordering guard inside
// a transaction. Trigger wrappers gate on balance-relevant key diffs (the
// expenseAuditLogger classify precedent) so description-only edits never
// recompute. Spec: docs/plans/2026-06-10-366-balance-aggregate.md §0.3-0.5.
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && npm run test:emulator -- balanceAggregator.test.ts`

import functionsTest from 'firebase-functions-test';
import { Money } from '../../src/callables/groupNetBalance';
import {
  eventBalanceAggregator,
  eventModuleBalanceAggregator,
  groupSettlementBalanceAggregator,
  memberBalanceAggregator,
  refreshGroupBalanceAggregate,
  shouldRecompute,
  toMilli,
} from '../../src/triggers/balanceAggregator';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });

const ALICE = 'alice';
const BOB = 'bob';
const CAROL = 'carol';

const GROUP = 'g-agg-366';
const EVENT = 'e1';
const AGG_PATH = `groups/${GROUP}/aggregates/balance`;

// Same fixture as groupNetBalance.test.ts (cross-referenced — parity case P1):
// tombstoned former-member payer + both settlement scopes.
async function seedFixture(groupData: Record<string, unknown> = {}): Promise<void> {
  const db = getFirestore();
  await db.doc(`groups/${GROUP}`).set({
    id: GROUP,
    name: GROUP,
    inviteCode: 'ABC123',
    createdBy: ALICE,
    memberIds: [ALICE, BOB],
    currency: 'OMR',
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    updatedAt: new Date('2026-01-01T00:00:00.000Z'),
    isDeleted: false,
    deletedAt: null,
    ...groupData,
  });
  const members: Array<[string, boolean]> = [
    [ALICE, false],
    [BOB, false],
    [CAROL, true],
  ];
  for (const [uid, isTombstone] of members) {
    await db.doc(`groups/${GROUP}/members/${uid}`).set({
      id: uid,
      userId: uid,
      displayName: uid,
      role: uid === ALICE ? 'CREATOR' : 'MEMBER',
      joinedAt: new Date('2026-01-01T00:00:00.000Z'),
      isShadow: false,
      isTombstone,
    });
  }
  await db.doc(`groups/${GROUP}/events/${EVENT}`).set({
    id: EVENT,
    groupId: GROUP,
    name: EVENT,
    type: 'trip',
    createdBy: ALICE,
    participantIds: [ALICE, BOB],
    participantNames: { [ALICE]: 'Alice', [BOB]: 'Bob' },
    modules: { ledger: true },
    isDeleted: false,
    deletedAt: null,
    createdAt: new Date('2026-01-02T00:00:00.000Z'),
  });
  await db.doc(`groups/${GROUP}/events/${EVENT}/expenses/x1`).set({
    id: 'x1',
    eventId: EVENT,
    description: 'Fuel',
    amountFils: 9000,
    currency: 'OMR',
    payerParticipantId: CAROL,
    scope: 'global',
    isDeleted: false,
    deletedAt: null,
    createdAt: '2026-01-03T00:00:00.000Z',
    createdBy: CAROL,
    lastEditedBy: CAROL,
  });
  await db.doc(`groups/${GROUP}/events/${EVENT}/settlements/s1`).set({
    id: 's1',
    eventId: EVENT,
    payerParticipantId: ALICE,
    recipientParticipantId: BOB,
    payerName: 'Alice',
    recipientName: 'Bob',
    amountFils: 1000,
    currency: 'OMR',
    note: null,
    isDeleted: false,
    deletedAt: null,
    settledAt: '2026-01-04T00:00:00.000Z',
    createdBy: ALICE,
  });
  await db.doc(`groups/${GROUP}/settlements/gs1`).set({
    id: 'gs1',
    groupId: GROUP,
    eventId: GROUP,
    scope: 'group',
    payerParticipantId: BOB,
    recipientParticipantId: ALICE,
    payerName: 'Bob',
    recipientName: 'Alice',
    amountFils: 2000,
    currency: 'OMR',
    note: null,
    isDeleted: false,
    deletedAt: null,
    settledAt: '2026-01-05T00:00:00.000Z',
    createdBy: BOB,
  });
}

describe('toMilli', () => {
  it('encodes subunit-exact Decimals as integer milli', () => {
    expect(toMilli(new Money('1.234'))).toBe(1234);
    expect(toMilli(new Money('-0.001'))).toBe(-1);
    expect(toMilli(new Money('7'))).toBe(7000); // JPY-style integer amount
    expect(toMilli(new Money('0'))).toBe(0);
  });

  it('defensively truncates a non-integral milli toward zero (unreachable for oracle output)', () => {
    expect(toMilli(new Money('0.0005'))).toBe(0);
    expect(toMilli(new Money('-0.0015'))).toBe(-1);
  });
});

describe('refreshGroupBalanceAggregate (#366)', () => {
  beforeEach(async () => {
    delete process.env.BALANCE_AGGREGATE_MAX_BYTES;
    await clearFirestore();
    await seedFixture();
  });

  afterAll(async () => {
    delete process.env.BALANCE_AGGREGATE_MAX_BYTES;
    await clearFirestore();
  });

  it('writes the aggregate doc with exact milli maps (parity case P1)', async () => {
    const db = getFirestore();
    await refreshGroupBalanceAggregate(db, GROUP, 1000);

    const snap = await db.doc(AGG_PATH).get();
    expect(snap.exists).toBe(true);
    const data = snap.data()!;
    expect(data.schemaVersion).toBe(1);
    expect(data.currency).toBe('OMR');
    expect(data.currencies).toEqual(['OMR']);
    expect(data.netMilli).toEqual({
      [ALICE]: -4000,
      [BOB]: -2000,
      [CAROL]: 6000,
    });
    expect(data.perEventNetMilli).toEqual({
      [EVENT]: { [ALICE]: -3500, [BOB]: -5500 },
    });
    expect(data.eventCount).toBe(1);
    expect(data.degraded).toBe(false);
    expect(data.sourceTimeMs).toBe(1000);
    expect(data.computedAt).toBeInstanceOf(Timestamp);
  });

  it('skips a stale recompute (guard: existing sourceTimeMs is newer)', async () => {
    const db = getFirestore();
    await db.doc(AGG_PATH).set({ sourceTimeMs: 2000, sentinel: 'keep' });

    await refreshGroupBalanceAggregate(db, GROUP, 1000);

    const data = (await db.doc(AGG_PATH).get()).data()!;
    expect(data.sentinel).toBe('keep');
    expect(data.sourceTimeMs).toBe(2000);
    expect(data.netMilli).toBeUndefined();
  });

  it('overwrites idempotently on an equal sourceTimeMs (at-least-once redelivery / batch fan-out)', async () => {
    const db = getFirestore();
    await refreshGroupBalanceAggregate(db, GROUP, 2000);
    const first = (await db.doc(AGG_PATH).get()).data()!;

    await refreshGroupBalanceAggregate(db, GROUP, 2000);
    const second = (await db.doc(AGG_PATH).get()).data()!;

    expect(second.netMilli).toEqual(first.netMilli);
    expect(second.perEventNetMilli).toEqual(first.perEventNetMilli);
    expect(second.sourceTimeMs).toBe(2000);
  });

  it('skips a group with deletingInProgress (the deleteGroup cascade owns that window)', async () => {
    const db = getFirestore();
    await db.doc(`groups/${GROUP}`).update({ deletingInProgress: true });

    await refreshGroupBalanceAggregate(db, GROUP, 1000);

    expect((await db.doc(AGG_PATH).get()).exists).toBe(false);
  });

  it('skips a soft-deleted group', async () => {
    const db = getFirestore();
    await db.doc(`groups/${GROUP}`).update({ isDeleted: true });

    await refreshGroupBalanceAggregate(db, GROUP, 1000);

    expect((await db.doc(AGG_PATH).get()).exists).toBe(false);
  });

  it('skips a missing group', async () => {
    const db = getFirestore();
    await refreshGroupBalanceAggregate(db, 'no-such-group', 1000);
    expect((await db.doc('groups/no-such-group/aggregates/balance').get()).exists).toBe(false);
  });

  it('writes a degraded doc (no maps) when the encoded maps would approach the 1MiB limit', async () => {
    process.env.BALANCE_AGGREGATE_MAX_BYTES = '10';
    const db = getFirestore();

    await refreshGroupBalanceAggregate(db, GROUP, 3000);

    const data = (await db.doc(AGG_PATH).get()).data()!;
    expect(data.degraded).toBe(true);
    expect(data.netMilli).toBeUndefined();
    expect(data.perEventNetMilli).toBeUndefined();
    expect(data.sourceTimeMs).toBe(3000);
    expect(data.schemaVersion).toBe(1);
  });
});

describe('shouldRecompute (pure)', () => {
  const KEYS = ['amountFils', 'splitDistribution', 'isDeleted'] as const;

  test('creates and hard deletes always recompute', () => {
    expect(shouldRecompute(undefined, { amountFils: 1 }, KEYS)).toBe(true);
    expect(shouldRecompute({ amountFils: 1 }, undefined, KEYS)).toBe(true);
  });

  test('updates recompute only when a balance key changes (deep compare on maps)', () => {
    expect(
      shouldRecompute(
        { amountFils: 1, description: 'a' },
        { amountFils: 1, description: 'b' },
        KEYS,
      ),
    ).toBe(false);
    expect(shouldRecompute({ amountFils: 1 }, { amountFils: 2 }, KEYS)).toBe(true);
    expect(
      shouldRecompute(
        { splitDistribution: { a: 1, b: 2 } },
        { splitDistribution: { a: 1, b: 2 } },
        KEYS,
      ),
    ).toBe(false);
    expect(
      shouldRecompute(
        { splitDistribution: { a: 1, b: 2 } },
        { splitDistribution: { a: 1, b: 3 } },
        KEYS,
      ),
    ).toBe(true);
    expect(shouldRecompute({ isDeleted: false }, { isDeleted: true }, KEYS)).toBe(true);
  });
});

describe('trigger wrappers (#366)', () => {
  const wrapExpense = testEnv.wrap(eventModuleBalanceAggregator);
  const wrapGroupSettlement = testEnv.wrap(groupSettlementBalanceAggregator);
  const wrapEvent = testEnv.wrap(eventBalanceAggregator);
  const wrapMember = testEnv.wrap(memberBalanceAggregator);

  function expenseSnap(data: Record<string, unknown> | null, docId = 'x1') {
    return testEnv.firestore.makeDocumentSnapshot(
      data ?? {},
      `groups/${GROUP}/events/${EVENT}/expenses/${docId}`,
    );
  }

  async function aggDoc() {
    return getFirestore().doc(AGG_PATH).get();
  }

  beforeEach(async () => {
    delete process.env.BALANCE_AGGREGATE_MAX_BYTES;
    await clearFirestore();
    await seedFixture();
  });

  afterAll(async () => {
    await clearFirestore();
    testEnv.cleanup();
  });

  it('recomputes on an expense create and stamps sourceTimeMs = Date.parse(event.time)', async () => {
    const time = '2026-06-10T00:00:01.000Z';
    await wrapExpense({
      data: testEnv.makeChange(expenseSnap(null), expenseSnap({ amountFils: 9000 })),
      params: { gid: GROUP, eid: EVENT, module: 'expenses', docId: 'x1' },
      id: 'ev-1',
      time,
    });

    const snap = await aggDoc();
    expect(snap.exists).toBe(true);
    expect(snap.data()!.sourceTimeMs).toBe(Date.parse(time));
    // The doc reflects the SEEDED Firestore state (parity case P1) — the
    // handler recomputes from the database, not from the trigger payload.
    expect(snap.data()!.netMilli).toEqual({
      [ALICE]: -4000,
      [BOB]: -2000,
      [CAROL]: 6000,
    });
  });

  it('skips activity_logs writes (the audit logger must not recompute balances)', async () => {
    await wrapExpense({
      data: testEnv.makeChange(expenseSnap(null), expenseSnap({ logText: 'x' })),
      params: { gid: GROUP, eid: EVENT, module: 'activity_logs', docId: 'a1' },
      id: 'ev-2',
      time: '2026-06-10T00:00:02.000Z',
    });
    expect((await aggDoc()).exists).toBe(false);
  });

  it('skips a description-only expense edit', async () => {
    await wrapExpense({
      data: testEnv.makeChange(
        expenseSnap({ amountFils: 9000, description: 'Fuel' }),
        expenseSnap({ amountFils: 9000, description: 'Petrol' }),
      ),
      params: { gid: GROUP, eid: EVENT, module: 'expenses', docId: 'x1' },
      id: 'ev-3',
      time: '2026-06-10T00:00:03.000Z',
    });
    expect((await aggDoc()).exists).toBe(false);
  });

  it('skips a participantNames-only event update but recomputes on a participantIds change', async () => {
    const eventPath = `groups/${GROUP}/events/${EVENT}`;
    const base = { participantIds: [ALICE, BOB], participantNames: { [ALICE]: 'Alice' } };
    await wrapEvent({
      data: testEnv.makeChange(
        testEnv.firestore.makeDocumentSnapshot(base, eventPath),
        testEnv.firestore.makeDocumentSnapshot(
          { ...base, participantNames: { [ALICE]: 'Alicia' } },
          eventPath,
        ),
      ),
      params: { gid: GROUP, eid: EVENT },
      id: 'ev-4',
      time: '2026-06-10T00:00:04.000Z',
    });
    expect((await aggDoc()).exists).toBe(false);

    await wrapEvent({
      data: testEnv.makeChange(
        testEnv.firestore.makeDocumentSnapshot(base, eventPath),
        testEnv.firestore.makeDocumentSnapshot(
          { ...base, participantIds: [ALICE] },
          eventPath,
        ),
      ),
      params: { gid: GROUP, eid: EVENT },
      id: 'ev-5',
      time: '2026-06-10T00:00:05.000Z',
    });
    expect((await aggDoc()).exists).toBe(true);
  });

  it('skips a displayName-only member update but recomputes on a tombstone flip', async () => {
    const memberPath = `groups/${GROUP}/members/${BOB}`;
    const base = { userId: BOB, displayName: 'Bob', isTombstone: false };
    await wrapMember({
      data: testEnv.makeChange(
        testEnv.firestore.makeDocumentSnapshot(base, memberPath),
        testEnv.firestore.makeDocumentSnapshot({ ...base, displayName: 'Bobby' }, memberPath),
      ),
      params: { gid: GROUP, memberId: BOB },
      id: 'ev-6',
      time: '2026-06-10T00:00:06.000Z',
    });
    expect((await aggDoc()).exists).toBe(false);

    await wrapMember({
      data: testEnv.makeChange(
        testEnv.firestore.makeDocumentSnapshot(base, memberPath),
        testEnv.firestore.makeDocumentSnapshot({ ...base, isTombstone: true }, memberPath),
      ),
      params: { gid: GROUP, memberId: BOB },
      id: 'ev-7',
      time: '2026-06-10T00:00:07.000Z',
    });
    expect((await aggDoc()).exists).toBe(true);
  });

  it('recomputes on a group-settlement create', async () => {
    const path = `groups/${GROUP}/settlements/gs2`;
    await wrapGroupSettlement({
      data: testEnv.makeChange(
        testEnv.firestore.makeDocumentSnapshot({}, path),
        testEnv.firestore.makeDocumentSnapshot(
          { amountFils: 500, payerParticipantId: ALICE, recipientParticipantId: BOB },
          path,
        ),
      ),
      params: { gid: GROUP, settlementId: 'gs2' },
      id: 'ev-8',
      time: '2026-06-10T00:00:08.000Z',
    });
    expect((await aggDoc()).exists).toBe(true);
  });

  it('converges under out-of-order delivery: a late event with an earlier time is skipped', async () => {
    const t1 = '2026-06-10T00:00:01.000Z';
    const t2 = '2026-06-10T00:00:09.000Z';
    // Fresh delivery (t2) lands first…
    await wrapExpense({
      data: testEnv.makeChange(expenseSnap(null), expenseSnap({ amountFils: 9000 })),
      params: { gid: GROUP, eid: EVENT, module: 'expenses', docId: 'x1' },
      id: 'ev-9',
      time: t2,
    });
    // …then the older write's event (t1) is delivered late.
    await wrapExpense({
      data: testEnv.makeChange(expenseSnap(null), expenseSnap({ amountFils: 1 })),
      params: { gid: GROUP, eid: EVENT, module: 'expenses', docId: 'x0' },
      id: 'ev-10',
      time: t1,
    });

    const data = (await aggDoc()).data()!;
    expect(data.sourceTimeMs).toBe(Date.parse(t2)); // t1's recompute was skipped
  });
});
