import { getFirestore } from 'firebase-admin/firestore';
import '../../../src/admin';
import { clearFirestore } from '../../fixtures';

// RED → GREEN: #1059 stage 2. When a roster change (join / addShadowMember)
// fans a member into events whose balances actually re-split (read-time equal
// split over the participant universe), ONE server-authored `member_resplit`
// activity row discloses it. These tests pin the shared helper:
//
//  - expenseSplitsOverUniverse: the SINGLE classification shared with
//    foldEventNet (groupNetBalance.ts) — an expense re-splits iff it takes the
//    equal branch AND its scope resolves recipients from the universe.
//  - detectResplitEvents: per fanned-in event, ≥1 live universe-splitting
//    expense → affected.
//  - writeResplitActivity: exact doc shape, occasion-keyed deterministic id
//    (memberId + sorted-affected-event-set hash), duplicate-create swallowed.
//
// kind: functions-jest (Firestore emulator, Java 21)
// runCommand: `cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/shared/resplitDisclosure.test.ts" npm run test:emulator`

import { expenseSplitsOverUniverse } from '../../../src/callables/groupNetBalance';
import {
  FanInEventCapture,
  detectResplitEvents,
  writeResplitActivity,
} from '../../../src/callables/shared/resplitDisclosure';

const GROUP = 'g_resplit';

afterEach(async () => {
  await clearFirestore();
});

// ---------------------------------------------------------------------------
// expenseSplitsOverUniverse — pure truth table (mirror foldEventNet routing)
// ---------------------------------------------------------------------------

describe('expenseSplitsOverUniverse', () => {
  const base = { payerParticipantId: 'alice' };

  test('global equal split (no split keys persisted) re-splits', () => {
    expect(expenseSplitsOverUniverse({ ...base, scope: 'global' })).toBe(true);
  });

  test('absent scope defaults to global and re-splits', () => {
    expect(expenseSplitsOverUniverse({ ...base })).toBe(true);
  });

  test('legacy sub_group scope re-splits (back-compat global)', () => {
    expect(expenseSplitsOverUniverse({ ...base, scope: 'sub_group' })).toBe(true);
  });

  test('custom scope with EMPTY customSplitParticipants re-splits', () => {
    expect(
      expenseSplitsOverUniverse({ ...base, scope: 'custom', customSplitParticipants: [] }),
    ).toBe(true);
  });

  test('personal scope never re-splits', () => {
    expect(expenseSplitsOverUniverse({ ...base, scope: 'personal' })).toBe(false);
  });

  test('custom scope with a non-empty fixed list never re-splits', () => {
    expect(
      expenseSplitsOverUniverse({
        ...base,
        scope: 'custom',
        customSplitParticipants: ['alice', 'bob'],
      }),
    ).toBe(false);
  });

  test.each(['exact', 'shares', 'percent'] as const)(
    'stored %s distribution with keys never re-splits',
    (mode) => {
      expect(
        expenseSplitsOverUniverse({
          ...base,
          scope: 'global',
          splitMode: mode,
          splitDistribution: { alice: 100, bob: 200 },
        }),
      ).toBe(false);
    },
  );

  test('stored mode with EMPTY distribution falls through to equal and re-splits', () => {
    expect(
      expenseSplitsOverUniverse({
        ...base,
        scope: 'global',
        splitMode: 'exact',
        splitDistribution: {},
      }),
    ).toBe(true);
  });

  test('explicit equally mode (legacy persisted) re-splits', () => {
    expect(
      expenseSplitsOverUniverse({ ...base, scope: 'global', splitMode: 'equally' }),
    ).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// detectResplitEvents
// ---------------------------------------------------------------------------

async function seedEvent(
  eventId: string,
  data: Record<string, unknown> = {},
): Promise<FanInEventCapture> {
  const db = getFirestore();
  const ref = db.doc(`groups/${GROUP}/events/${eventId}`);
  await ref.set({
    id: eventId,
    groupId: GROUP,
    name: `Event ${eventId}`,
    participantIds: ['alice'],
    participantNames: { alice: 'Alice' },
    isDeleted: false,
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    ...data,
  });
  return { ref, eventId, eventName: `Event ${eventId}` };
}

async function seedExpense(
  eventId: string,
  expenseId: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore().doc(`groups/${GROUP}/events/${eventId}/expenses/${expenseId}`).set({
    id: expenseId,
    eventId,
    payerParticipantId: 'alice',
    amountFils: 12345,
    currency: 'OMR',
    description: 'x',
    scope: 'global',
    customSplitParticipants: [],
    isDeleted: false,
    deletedAt: null,
    createdAt: '2026-01-01T00:00:00.000Z',
    createdBy: 'alice',
    lastEditedBy: 'alice',
    ...data,
  });
}

describe('detectResplitEvents', () => {
  test('event with a live global equal expense is affected (single shape)', async () => {
    const cap = await seedEvent('e1');
    await seedExpense('e1', 'x1');
    const detection = await detectResplitEvents([cap]);
    expect(detection.count).toBe(1);
    expect(detection.affectedEventIds).toEqual(['e1']);
    expect(detection.single).toEqual({ eventId: 'e1', eventName: 'Event e1' });
  });

  test('CLOSED (non-deleted) event with a live equal expense is affected', async () => {
    const cap = await seedEvent('e_closed', { isClosed: true, closedAt: new Date() });
    await seedExpense('e_closed', 'x1');
    const detection = await detectResplitEvents([cap]);
    expect(detection.count).toBe(1);
  });

  test('soft-deleted-expense-only event is NOT affected', async () => {
    const cap = await seedEvent('e2');
    await seedExpense('e2', 'x1', { isDeleted: true, deletedAt: new Date() });
    const detection = await detectResplitEvents([cap]);
    expect(detection.count).toBe(0);
    expect(detection.single).toBeNull();
  });

  test('stored-distribution-only event is NOT affected', async () => {
    const cap = await seedEvent('e3');
    await seedExpense('e3', 'x1', {
      splitMode: 'exact',
      splitDistribution: { alice: 6000, bob: 6345 },
    });
    const detection = await detectResplitEvents([cap]);
    expect(detection.count).toBe(0);
  });

  test('personal-scope-only event is NOT affected', async () => {
    const cap = await seedEvent('e4');
    await seedExpense('e4', 'x1', { scope: 'personal' });
    const detection = await detectResplitEvents([cap]);
    expect(detection.count).toBe(0);
  });

  test('zero-expense event is NOT affected', async () => {
    const cap = await seedEvent('e5');
    const detection = await detectResplitEvents([cap]);
    expect(detection.count).toBe(0);
  });

  test('multi-event: two affected, one immune → count 2, single null, ids sorted', async () => {
    const capB = await seedEvent('eB');
    const capA = await seedEvent('eA');
    const capC = await seedEvent('eC');
    await seedExpense('eB', 'x1');
    await seedExpense('eA', 'x1');
    await seedExpense('eC', 'x1', { scope: 'personal' });
    const detection = await detectResplitEvents([capB, capA, capC]);
    expect(detection.count).toBe(2);
    expect(detection.affectedEventIds).toEqual(['eA', 'eB']);
    expect(detection.single).toBeNull();
  });

  test('single affected event with an EMPTY name → single null (count copy + no deep-link)', async () => {
    const cap = await seedEvent('e6');
    await seedExpense('e6', 'x1');
    const detection = await detectResplitEvents([{ ...cap, eventName: '' }]);
    expect(detection.count).toBe(1);
    expect(detection.single).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// writeResplitActivity
// ---------------------------------------------------------------------------

describe('writeResplitActivity', () => {
  const db = () => getFirestore();

  test('single-event added-variant doc shape', async () => {
    await writeResplitActivity(db(), GROUP, {
      memberId: 'shadow-uuid-1',
      memberName: 'Bob',
      actorId: 'creator-uid',
      actorName: 'Alice',
      memberAction: 'added',
      detection: {
        count: 1,
        affectedEventIds: ['e1'],
        single: { eventId: 'e1', eventName: 'Trip' },
      },
    });
    const rows = await db().collection(`groups/${GROUP}/activity`).get();
    expect(rows.size).toBe(1);
    const doc = rows.docs[0].data();
    expect(rows.docs[0].id).toMatch(/^resplit_shadow-uuid-1_[0-9a-f]{12}$/);
    expect(doc.id).toBe(rows.docs[0].id);
    expect(doc.type).toBe('member_resplit');
    expect(doc.actorId).toBe('creator-uid');
    expect(doc.actorName).toBe('Alice');
    // PREDICATE — the client row chrome prepends actorName (#1059 Gate r1).
    expect(doc.description).toBe('added Bob to Trip — equal splits recalculated');
    expect(doc.metadata).toEqual({
      memberAction: 'added',
      memberName: 'Bob',
      affectedEventCount: 1,
      eventId: 'e1',
      eventName: 'Trip',
    });
    // ISO STRING timestamp only (#1140) — a Timestamp type-buckets apart.
    expect(typeof doc.timestamp).toBe('string');
    expect(() => new Date(doc.timestamp as string).toISOString()).not.toThrow();
  });

  test('multi-event joined-variant doc shape (no eventId/eventName)', async () => {
    await writeResplitActivity(db(), GROUP, {
      memberId: 'joiner-uid',
      memberName: 'Bob',
      actorId: 'joiner-uid',
      actorName: 'Bob',
      memberAction: 'joined',
      detection: { count: 3, affectedEventIds: ['a', 'b', 'c'], single: null },
    });
    const rows = await db().collection(`groups/${GROUP}/activity`).get();
    expect(rows.size).toBe(1);
    const doc = rows.docs[0].data();
    expect(doc.description).toBe('joined 3 events — equal splits recalculated');
    expect(doc.metadata).toEqual({
      memberAction: 'joined',
      memberName: 'Bob',
      affectedEventCount: 3,
    });
  });

  test('count-1 with malformed name uses "1 event" grammar (Gate r2 P3)', async () => {
    await writeResplitActivity(db(), GROUP, {
      memberId: 'joiner-uid',
      memberName: 'Bob',
      actorId: 'joiner-uid',
      actorName: 'Bob',
      memberAction: 'joined',
      detection: { count: 1, affectedEventIds: ['a'], single: null },
    });
    const rows = await db().collection(`groups/${GROUP}/activity`).get();
    expect(rows.docs[0].data().description).toBe('joined 1 event — equal splits recalculated');
  });

  test('zero affected events writes nothing', async () => {
    await writeResplitActivity(db(), GROUP, {
      memberId: 'm',
      memberName: 'Bob',
      actorId: 'a',
      actorName: 'Alice',
      memberAction: 'added',
      detection: { count: 0, affectedEventIds: [], single: null },
    });
    const rows = await db().collection(`groups/${GROUP}/activity`).get();
    expect(rows.size).toBe(0);
  });

  test('same-occasion duplicate dedups without throwing; different set → second row', async () => {
    const args = {
      memberId: 'joiner-uid',
      memberName: 'Bob',
      actorId: 'joiner-uid',
      actorName: 'Bob',
      memberAction: 'joined' as const,
      detection: { count: 1, affectedEventIds: ['e1'], single: null },
    };
    await writeResplitActivity(db(), GROUP, args);
    await expect(writeResplitActivity(db(), GROUP, args)).resolves.toBeUndefined();
    expect((await db().collection(`groups/${GROUP}/activity`).get()).size).toBe(1);

    // The rejoin-after-departure-window class (#1059 Gate r1 rubric P1): a
    // DIFFERENT affected-event set must produce a DISTINCT row, not be
    // swallowed by the first occasion's id.
    await writeResplitActivity(db(), GROUP, {
      ...args,
      detection: { count: 1, affectedEventIds: ['e2-post-departure'], single: null },
    });
    expect((await db().collection(`groups/${GROUP}/activity`).get()).size).toBe(2);
  });
});
