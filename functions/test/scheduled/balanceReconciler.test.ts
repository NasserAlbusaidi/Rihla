import functionsTest from 'firebase-functions-test';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';

// RED → GREEN (#366 Task 4): the daily reconciler IS the backfill (first run
// materializes a doc for every live group) and the drift healer (a doc a
// trigger should have kept fresh but didn't gets rewritten + a logger.warn so
// lost events are visible, never silent). Reuses refreshGroupBalanceAggregate
// (the deletionReaper reuse-the-core precedent) — no second compute path.
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && npm run test:emulator -- balanceReconciler.test.ts`

import {
  balanceReconciler,
  runBalanceReconciliation,
} from '../../src/scheduled/balanceReconciler';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });

const ALICE = 'alice';
const BOB = 'bob';

async function seedGroup(
  groupId: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  const db = getFirestore();
  await db.doc(`groups/${groupId}`).set({
    id: groupId,
    name: groupId,
    inviteCode: 'ABC123',
    createdBy: ALICE,
    memberIds: [ALICE, BOB],
    currency: 'OMR',
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    updatedAt: new Date('2026-01-01T00:00:00.000Z'),
    isDeleted: false,
    deletedAt: null,
    ...data,
  });
  for (const uid of [ALICE, BOB]) {
    await db.doc(`groups/${groupId}/members/${uid}`).set({
      id: uid,
      userId: uid,
      displayName: uid,
      role: uid === ALICE ? 'CREATOR' : 'MEMBER',
      joinedAt: new Date('2026-01-01T00:00:00.000Z'),
      isShadow: false,
      isTombstone: false,
    });
  }
}

async function seedExpense(groupId: string, amountFils: number): Promise<void> {
  const db = getFirestore();
  await db.doc(`groups/${groupId}/events/e1`).set({
    id: 'e1',
    groupId,
    name: 'e1',
    type: 'trip',
    createdBy: ALICE,
    participantIds: [ALICE, BOB],
    participantNames: { [ALICE]: 'Alice', [BOB]: 'Bob' },
    modules: { ledger: true },
    isDeleted: false,
    deletedAt: null,
    createdAt: new Date('2026-01-02T00:00:00.000Z'),
  });
  await db.doc(`groups/${groupId}/events/e1/expenses/x1`).set({
    id: 'x1',
    eventId: 'e1',
    description: 'Fuel',
    amountFils,
    currency: 'OMR',
    payerParticipantId: ALICE,
    scope: 'global',
    isDeleted: false,
    deletedAt: null,
    createdAt: '2026-01-03T00:00:00.000Z',
    createdBy: ALICE,
    lastEditedBy: ALICE,
  });
}

describe('runBalanceReconciliation (#366)', () => {
  beforeEach(async () => {
    delete process.env.BALANCE_RECONCILER_BATCH;
    delete process.env.BALANCE_RECONCILER_MAX;
    await clearFirestore();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  afterAll(async () => {
    delete process.env.BALANCE_RECONCILER_BATCH;
    delete process.env.BALANCE_RECONCILER_MAX;
    await clearFirestore();
    testEnv.cleanup();
  });

  it('backfills missing docs and heals a stale v1 doc into v2 (with a drift warn)', async () => {
    const db = getFirestore();
    await seedGroup('g-a');
    await seedExpense('g-a', 10000); // alice +5.000, bob −5.000
    await seedGroup('g-b'); // no events — empty maps doc is still materialized
    // g-a carries a pre-rollout v1 doc: the first post-deploy sweep IS the
    // v1→v2 backfill (#382 PR-3) — tx.set full-replace strips the dead v1
    // fields, and the drift warn firing once per pre-existing v1 doc is
    // intentional.
    await db.doc('groups/g-a/aggregates/balance').set({
      schemaVersion: 1,
      currency: 'OMR',
      currencies: ['OMR'],
      netMilli: { [ALICE]: 999 },
      perEventNetMilli: {},
      eventCount: 0,
      degraded: false,
      sourceTimeMs: 1,
    });
    const warn = jest.spyOn(logger, 'warn');

    const summary = await runBalanceReconciliation(db);

    expect(summary.scanned).toBe(2);
    expect(summary.refreshed).toBe(2);
    expect(summary.drift).toBe(1);
    expect(summary.failures).toBe(0);

    const a = (await db.doc('groups/g-a/aggregates/balance').get()).data()!;
    expect(a.schemaVersion).toBe(2);
    expect(a.netMilliByCurrency).toEqual({
      OMR: { [ALICE]: 5000, [BOB]: -5000 },
    });
    expect(a.perEventNetMilliByCurrency).toEqual({
      e1: { OMR: { [ALICE]: 5000, [BOB]: -5000 } },
    });
    expect(a.eventCount).toBe(1);
    expect(a.netMilli).toBeUndefined();
    expect(a.perEventNetMilli).toBeUndefined();
    expect(a.currencies).toBeUndefined();

    const b = (await db.doc('groups/g-b/aggregates/balance').get()).data()!;
    expect(b.netMilliByCurrency).toEqual({});
    expect(b.eventCount).toBe(0);

    expect(warn).toHaveBeenCalledWith(
      'balanceReconciler: drift healed',
      expect.objectContaining({ groupId: 'g-a' }),
    );
  });

  it('detects drift in a tampered v2 map even when eventCount matches', async () => {
    const db = getFirestore();
    await seedGroup('g-t');
    await seedExpense('g-t', 10000);
    // Right eventCount, wrong net bucket — only a fingerprint reading the v2
    // map names can see this drift (D6: v1 names read null on both sides and
    // detection goes permanently silent).
    await db.doc('groups/g-t/aggregates/balance').set({
      schemaVersion: 2,
      currency: 'OMR',
      netMilliByCurrency: { OMR: { [ALICE]: 999, [BOB]: -999 } },
      perEventNetMilliByCurrency: { e1: { OMR: { [ALICE]: 999, [BOB]: -999 } } },
      eventCount: 1,
      degraded: false,
      sourceTimeMs: 1,
    });
    const warn = jest.spyOn(logger, 'warn');

    const summary = await runBalanceReconciliation(db);

    expect(summary.drift).toBe(1);
    const healed = (await db.doc('groups/g-t/aggregates/balance').get()).data()!;
    expect(healed.netMilliByCurrency).toEqual({
      OMR: { [ALICE]: 5000, [BOB]: -5000 },
    });
    expect(warn).toHaveBeenCalledWith(
      'balanceReconciler: drift healed',
      expect.objectContaining({ groupId: 'g-t' }),
    );
  });

  it('does not warn drift when the existing doc already matches', async () => {
    const db = getFirestore();
    await seedGroup('g-c');
    await seedExpense('g-c', 10000);
    await runBalanceReconciliation(db); // materialize
    const warn = jest.spyOn(logger, 'warn');

    const summary = await runBalanceReconciliation(db);

    expect(summary.drift).toBe(0);
    expect(warn).not.toHaveBeenCalledWith(
      'balanceReconciler: drift healed',
      expect.anything(),
    );
  });

  it('skips soft-deleted groups', async () => {
    const db = getFirestore();
    await seedGroup('g-dead', { isDeleted: true });

    const summary = await runBalanceReconciliation(db);

    expect(summary.scanned).toBe(0);
    expect((await db.doc('groups/g-dead/aggregates/balance').get()).exists).toBe(false);
  });

  it('backfills a legacy group that has no isDeleted field (#525)', async () => {
    const db = getFirestore();
    // A pre-#190 group predates the isDeleted field. A `where('isDeleted','==',
    // false)` equality query silently excludes it, so it would never be
    // backfilled/drift-healed. Field-absent must fall through and BE processed.
    await seedGroup('g-legacy');
    await seedExpense('g-legacy', 10000);
    await db.doc('groups/g-legacy').update({ isDeleted: FieldValue.delete() });

    const summary = await runBalanceReconciliation(db);

    expect(summary.scanned).toBe(1);
    expect((await db.doc('groups/g-legacy/aggregates/balance').get()).exists).toBe(true);
  });

  it('paginates across pages — a small page size still sweeps every live group (#525)', async () => {
    // Page size 1 forces multiple pages. Pagination (not a single .limit() page)
    // must reach BOTH groups, with no truncation warn — proving the sweep is no
    // longer capped at one fixed page.
    process.env.BALANCE_RECONCILER_BATCH = '1';
    const db = getFirestore();
    await seedGroup('g-1');
    await seedGroup('g-2');
    const warn = jest.spyOn(logger, 'warn');

    const summary = await runBalanceReconciliation(db);

    expect(summary.scanned).toBe(2);
    expect(warn).not.toHaveBeenCalledWith(
      'balanceReconciler: max-groups cap hit — some live groups were not reconciled this run',
      expect.anything(),
    );
  });

  it('a soft-deleted group does not starve a live group sorting behind it (#525)', async () => {
    // The regression the gate caught: with a single fixed `.limit(pageSize)` read,
    // a retained soft-deleted doc consumes a slot and permanently starves a live
    // group sorting behind it. Ids order as a-dead < b-live < c-live, so page
    // size 2 = [a-dead, b-live] and c-live would never be fetched. Pagination
    // reaches every live group regardless of how many dead docs precede them.
    process.env.BALANCE_RECONCILER_BATCH = '2';
    const db = getFirestore();
    await seedGroup('a-dead', { isDeleted: true });
    await seedGroup('b-live');
    await seedGroup('c-live');

    const summary = await runBalanceReconciliation(db);

    expect(summary.scanned).toBe(2); // both live groups; the dead one is skipped
    expect(
      (await db.doc('groups/c-live/aggregates/balance').get()).exists,
    ).toBe(true);
  });

  it('warns loudly when the max-groups safety cap is hit (#525)', async () => {
    process.env.BALANCE_RECONCILER_MAX = '1';
    const db = getFirestore();
    await seedGroup('g-1');
    await seedGroup('g-2');
    const warn = jest.spyOn(logger, 'warn');

    const summary = await runBalanceReconciliation(db);

    expect(summary.scanned).toBe(1);
    expect(warn).toHaveBeenCalledWith(
      'balanceReconciler: max-groups cap hit — some live groups were not reconciled this run',
      expect.objectContaining({ maxGroups: 1 }),
    );
  });

  it('the scheduled wrapper runs end-to-end', async () => {
    await seedGroup('g-sched');
    // v2 onSchedule needs the `as any` cast through testEnv.wrap
    // (firebase-functions-test 3.4.1 — the deletionReaper precedent).
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const wrapped = testEnv.wrap(balanceReconciler as any);
    await wrapped({});
    const doc = await getFirestore().doc('groups/g-sched/aggregates/balance').get();
    expect(doc.exists).toBe(true);
  });
});
