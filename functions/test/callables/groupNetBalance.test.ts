import { getFirestore } from 'firebase-admin/firestore';
import { clearFirestore } from '../fixtures';

// RED → GREEN (#366 Task 1): recomputeNet grows two outputs feeding the
// balance-aggregate doc — `perEventNet` (the participantIds-only drill-down
// slice mirroring the client _buildPerEventBreakdown in
// lib/features/groups/providers/group_balance_provider.dart:432-471) and
// `eventCount` (live events, mirroring GroupBalances.eventCount). The fixture
// exercises the IDENTITY axis (a tombstoned former-member payer: included in
// `net` via the former-financial-actor universe, EXCLUDED from the drill-down)
// and the SETTLEMENT axis (an event settlement moves both maps; a group-scope
// settlement moves `net` only). netMilli ≠ Σ perEventNet by design — this test
// pins the three documented gaps (universe, group settlements, drops).
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && npm run test:emulator -- groupNetBalance.test.ts`

import { recomputeNet } from '../../src/callables/groupNetBalance';

const ALICE = 'alice';
const BOB = 'bob';
const CAROL = 'carol'; // tombstoned former member; payer of the only expense

const GROUP = 'g-oracle-366';
const EVENT = 'e1';

async function seedFixture(): Promise<void> {
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
  // 9.000 OMR paid by the FORMER member, equal split, global scope. Mirrors the
  // client service write-map: an equal-split expense persists NO
  // splitMode/splitDistribution keys (expense_service.dart skips both).
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
  // Event settlement: alice paid bob 1.000 OMR.
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
  // Group-scope settlement: bob paid alice 2.000 OMR (folds into net ONLY).
  await db.doc(`groups/${GROUP}/settlements/gs1`).set({
    id: 'gs1',
    groupId: GROUP,
    eventId: GROUP, // sentinel: group settlements write eventId = groupId
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

describe('recomputeNet drill-down extension (#366)', () => {
  beforeEach(async () => {
    await clearFirestore();
    await seedFixture();
  });

  afterAll(async () => {
    await clearFirestore();
  });

  it('keeps the existing net contract (former-actor universe + both settlement scopes), now per-currency bucketed', async () => {
    const db = getFirestore();
    const result = await recomputeNet(db, db.doc(`groups/${GROUP}`));

    // #382 PR-2: net is per-currency. This all-OMR fixture has a single 'OMR'
    // bucket whose per-uid values are byte-for-byte the pre-PR-2 flat net.
    expect([...result.net.keys()]).toEqual(['OMR']);
    const omr = result.net.get('OMR')!;
    // Universe {alice, bob, carol}: equal split 9.000 / 3 = 3.000 owed each.
    // alice: −3.000 + 1.000 (event settlement paid) − 2.000 (group settlement
    // received) = −4.000; bob: −3.000 − 1.000 + 2.000 = −2.000;
    // carol: 9.000 paid − 3.000 owed = +6.000. Conservation: sum = 0.
    expect(omr.get(ALICE)!.toFixed(3)).toBe('-4.000');
    expect(omr.get(BOB)!.toFixed(3)).toBe('-2.000');
    expect(omr.get(CAROL)!.toFixed(3)).toBe('6.000');
    expect(result.liveEventRefs).toHaveLength(1);
  });

  it('emits the participantIds-only drill-down slice (perEventNet), per-currency bucketed', async () => {
    const db = getFirestore();
    const result = await recomputeNet(db, db.doc(`groups/${GROUP}`));

    const slice = result.perEventNet.get(EVENT);
    expect(slice).toBeDefined();
    // #382 PR-2: the slice is per-currency; this all-OMR event has one 'OMR' bucket.
    expect([...slice!.keys()]).toEqual(['OMR']);
    const omr = slice!.get('OMR')!;
    // Drill-down universe {alice, bob}: equal split 9.000 / 2 = 4.500 each;
    // carol's payment is DROPPED (payer outside universe); the event settlement
    // folds; the GROUP settlement does NOT.
    expect(omr.get(ALICE)!.toFixed(3)).toBe('-3.500');
    expect(omr.get(BOB)!.toFixed(3)).toBe('-5.500');
    // The former actor never appears in the drill-down — the client contract
    // (_buildPerEventBreakdown is participantIds-only, pinned by
    // group_balance_provider_test.dart).
    expect(omr.has(CAROL)).toBe(false);
    expect(result.perEventNet.size).toBe(1);
  });

  it('emits eventCount = live events and omits empty-participant events from the drill-down', async () => {
    const db = getFirestore();
    // A second live event with NO participants: counted in eventCount (the
    // client counts events.length), but skipped by the drill-down (the client
    // skips participants.isEmpty events).
    await db.doc(`groups/${GROUP}/events/e2`).set({
      id: 'e2',
      groupId: GROUP,
      name: 'e2',
      type: 'trip',
      createdBy: ALICE,
      participantIds: [],
      participantNames: {},
      modules: { ledger: true },
      isDeleted: false,
      deletedAt: null,
      createdAt: new Date('2026-01-06T00:00:00.000Z'),
    });
    // A soft-deleted event: excluded from BOTH.
    await db.doc(`groups/${GROUP}/events/e3`).set({
      id: 'e3',
      groupId: GROUP,
      name: 'e3',
      type: 'trip',
      createdBy: ALICE,
      participantIds: [ALICE],
      participantNames: { [ALICE]: 'Alice' },
      modules: { ledger: true },
      isDeleted: true,
      deletedAt: new Date('2026-01-07T00:00:00.000Z'),
      createdAt: new Date('2026-01-06T00:00:00.000Z'),
    });

    const result = await recomputeNet(db, db.doc(`groups/${GROUP}`));
    expect(result.eventCount).toBe(2); // e1 + e2, never e3
    expect(result.perEventNet.has('e2')).toBe(false);
    expect(result.perEventNet.has('e3')).toBe(false);
  });
});

// #872: the weighted allocator's rounding remainder must land on the
// alphabetically-last POSITIVE-weight recipient — never a declared-0-share
// key that happens to sort last. Client mirror:
// balance_calculations_test.dart "(#872)" cases.
describe('#872 weighted remainder vs 0-share key sorting last', () => {
  const PAYER = 'alice';
  const POSITIVE = 'bob';
  const ZERO = 'zed'; // sorts last with a declared 0 weight
  const GROUP872 = 'g-872';
  const EVENT872 = 'e-872';

  async function seed872(
    splitMode: 'shares' | 'percent',
    splitDistribution: Record<string, number>,
  ): Promise<void> {
    const db = getFirestore();
    await db.doc(`groups/${GROUP872}`).set({
      id: GROUP872,
      name: GROUP872,
      inviteCode: 'ABC872',
      createdBy: PAYER,
      memberIds: [PAYER, POSITIVE, ZERO],
      currency: 'OMR',
      createdAt: new Date('2026-01-01T00:00:00.000Z'),
      updatedAt: new Date('2026-01-01T00:00:00.000Z'),
      isDeleted: false,
      deletedAt: null,
    });
    for (const uid of [PAYER, POSITIVE, ZERO]) {
      await db.doc(`groups/${GROUP872}/members/${uid}`).set({
        id: uid,
        userId: uid,
        displayName: uid,
        role: uid === PAYER ? 'CREATOR' : 'MEMBER',
        joinedAt: new Date('2026-01-01T00:00:00.000Z'),
        isShadow: false,
        isTombstone: false,
      });
    }
    await db.doc(`groups/${GROUP872}/events/${EVENT872}`).set({
      id: EVENT872,
      groupId: GROUP872,
      name: EVENT872,
      type: 'trip',
      createdBy: PAYER,
      participantIds: [PAYER, POSITIVE, ZERO],
      participantNames: { [PAYER]: 'Alice', [POSITIVE]: 'Bob', [ZERO]: 'Zed' },
      modules: { ledger: true },
      isDeleted: false,
      deletedAt: null,
      createdAt: new Date('2026-01-02T00:00:00.000Z'),
    });
    // 1.000 OMR: 1/3-ish weights force a truncation residual of 0.001.
    await db.doc(`groups/${GROUP872}/events/${EVENT872}/expenses/x1`).set({
      id: 'x1',
      eventId: EVENT872,
      description: 'Dinner',
      amountFils: 1000,
      currency: 'OMR',
      payerParticipantId: PAYER,
      scope: 'global',
      splitMode,
      splitDistribution,
      isDeleted: false,
      deletedAt: null,
      createdAt: '2026-01-03T00:00:00.000Z',
      createdBy: PAYER,
      lastEditedBy: PAYER,
    });
  }

  beforeEach(async () => {
    await clearFirestore();
  });

  afterAll(async () => {
    await clearFirestore();
  });

  it('shares: residual goes to the last positive-share key, 0-share owes nothing', async () => {
    await seed872('shares', { [PAYER]: 1, [POSITIVE]: 2, [ZERO]: 0 });
    const db = getFirestore();
    const result = await recomputeNet(db, db.doc(`groups/${GROUP872}`));

    const omr = result.net.get('OMR')!;
    // owed: alice 0.333, bob 0.667 (0.666 + 0.001 residual), zed 0.000.
    // net: alice 1.000 paid − 0.333 owed = +0.667; bob −0.667; zed 0.
    expect(omr.get(PAYER)!.toFixed(3)).toBe('0.667');
    expect(omr.get(POSITIVE)!.toFixed(3)).toBe('-0.667');
    expect(omr.get(ZERO)!.toFixed(3)).toBe('0.000');
  });

  it('percent: residual goes to the last positive-percent key, 0-percent owes nothing', async () => {
    // percent persists humanPercent x 1000: 33.33% / 66.67% / 0%.
    await seed872('percent', { [PAYER]: 33330, [POSITIVE]: 66670, [ZERO]: 0 });
    const db = getFirestore();
    const result = await recomputeNet(db, db.doc(`groups/${GROUP872}`));

    const omr = result.net.get('OMR')!;
    expect(omr.get(PAYER)!.toFixed(3)).toBe('0.667');
    expect(omr.get(POSITIVE)!.toFixed(3)).toBe('-0.667');
    expect(omr.get(ZERO)!.toFixed(3)).toBe('0.000');
  });
});

// #928 — client↔oracle parity pin (mirrored fixture). The Dart side is
// test/unit/malformed_doc_fencing_test.dart test 4: identical inputs, identical
// hand-computed nets. A non-string expense payer is a total-parse-salvage case
// on BOTH sides — the Dart factory salvages it to '' then guards it out of the
// eventBalanceUniverse; the oracle already gates it with `typeof === 'string'`
// before the paid credit AND the universe fold (groupNetBalance.ts:406/651). So
// NEITHER counts the payer and NEITHER seeds a phantom row. No oracle change:
// this fixture pins that the server stays put while the client is brought into
// line — the shared contract (kind: functions-jest, Firestore emulator, Java 21;
// run: `cd functions && npm run test:emulator -- callables/groupNetBalance.test.ts`).
describe('recomputeNet — non-string payer parity (#928)', () => {
  const GROUP928 = 'g-oracle-928';
  const ALICE928 = 'alice';
  const BOB928 = 'bob';

  beforeEach(async () => {
    await clearFirestore();
    const db = getFirestore();
    await db.doc(`groups/${GROUP928}`).set({
      id: GROUP928,
      name: GROUP928,
      inviteCode: 'ABC928',
      createdBy: ALICE928,
      memberIds: [ALICE928, BOB928],
      currency: 'OMR',
      createdAt: new Date('2026-01-01T00:00:00.000Z'),
      updatedAt: new Date('2026-01-01T00:00:00.000Z'),
      isDeleted: false,
      deletedAt: null,
    });
    for (const uid of [ALICE928, BOB928]) {
      await db.doc(`groups/${GROUP928}/members/${uid}`).set({
        id: uid,
        userId: uid,
        displayName: uid,
        role: uid === ALICE928 ? 'CREATOR' : 'MEMBER',
        joinedAt: new Date('2026-01-01T00:00:00.000Z'),
        isShadow: false,
        isTombstone: false,
      });
    }
    await db.doc(`groups/${GROUP928}/events/e1`).set({
      id: 'e1',
      groupId: GROUP928,
      name: 'e1',
      type: 'trip',
      createdBy: ALICE928,
      participantIds: [ALICE928, BOB928],
      participantNames: { [ALICE928]: 'Alice', [BOB928]: 'Bob' },
      modules: { ledger: true },
      isDeleted: false,
      deletedAt: null,
      createdAt: new Date('2026-01-02T00:00:00.000Z'),
    });
    // One global OMR 10.000 expense whose payerParticipantId is the NUMBER 42
    // (a forged/legacy doc). Equal-split → no splitMode/splitDistribution keys.
    await db.doc(`groups/${GROUP928}/events/e1/expenses/x1`).set({
      id: 'x1',
      eventId: 'e1',
      description: 'Dinner',
      amountFils: 10000,
      currency: 'OMR',
      payerParticipantId: 42,
      scope: 'global',
      isDeleted: false,
      deletedAt: null,
      createdAt: '2026-01-03T00:00:00.000Z',
      createdBy: ALICE928,
      lastEditedBy: ALICE928,
    });
  });

  afterAll(async () => {
    await clearFirestore();
  });

  it('non-string payer is not credited and seeds no phantom row: alice/bob -5.000 each', async () => {
    const db = getFirestore();
    const result = await recomputeNet(db, db.doc(`groups/${GROUP928}`));

    const omr = result.net.get('OMR')!;
    // Universe {alice, bob}: equal split 10.000 / 2 = 5.000 owed each. The
    // non-string payer is dropped by `typeof payerId === 'string'` (paid credit
    // + universe fold), so no phantom '' row and the divisor stays 2 — identical
    // to the Dart client after salvage + guard.
    expect([...omr.keys()].sort()).toEqual([ALICE928, BOB928]);
    expect(omr.get(ALICE928)!.toFixed(3)).toBe('-5.000');
    expect(omr.get(BOB928)!.toFixed(3)).toBe('-5.000');
  });
});
