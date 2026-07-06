import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
// rules-unit-testing v5 hands back a COMPAT Firestore instance (namespaced
// `db.batch()` / `db.doc(...).set`), matching the readiness suite this reuses.
import 'firebase/compat/app';
import 'firebase/compat/firestore';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const PROJECT_ID = 'rihla-decomposed-settleup-batch-test';
const RULES_PATH = resolve(__dirname, '../../security/firestore.rules');
const [FIRESTORE_HOST, FIRESTORE_PORT] =
  (process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080').split(':');

// #929: pins the SHAPE + per-op rule LOGIC of the atomic decomposed settle-up
// WriteBatch, and its all-or-nothing atomicity (6b). It does NOT pin the 20-
// document-access-call BUDGET — the rules emulator does not reliably enforce
// the 10/20 access-call limits, so kMaxDecomposeLegsAtomic = 9 rests on the
// verified 2·N+1 arithmetic (§ceiling of the spec), not on an emulator assert.
describe('#929 decomposed settle-up atomic batch (rules shape + atomicity)', () => {
  let testEnv: RulesTestEnvironment;

  beforeAll(async () => {
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: readFileSync(RULES_PATH, 'utf8'),
        host: FIRESTORE_HOST,
        port: Number(FIRESTORE_PORT),
      },
    });
  });

  afterAll(async () => {
    await testEnv.cleanup();
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
    await seedBaseData();
  });

  // Nine events (e1..e9), a group g1 with members owner + member.
  async function seedBaseData(): Promise<void> {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('groups/g1').set({
        id: 'g1',
        name: 'Desert Crew',
        inviteCode: 'ABC123',
        createdBy: 'owner',
        memberIds: ['owner', 'member'],
        currency: 'OMR',
        createdAt: new Date(),
        updatedAt: new Date(),
      });
      await db.doc('groups/g1/members/owner').set({
        id: 'owner',
        userId: 'owner',
        displayName: 'Owner',
        role: 'CREATOR',
        joinedAt: new Date(),
        isShadow: false,
      });
      await db.doc('groups/g1/members/member').set({
        id: 'member',
        userId: 'member',
        displayName: 'Member',
        role: 'MEMBER',
        joinedAt: new Date(),
        isShadow: false,
      });
      await db.doc('inviteCodes/ABC123').set({
        groupId: 'g1',
        createdAt: new Date(),
      });
      for (let i = 1; i <= 9; i++) {
        await db.doc(`groups/g1/events/e${i}`).set(validEvent(`e${i}`));
      }
    });
  }

  function validEvent(id: string): Record<string, unknown> {
    return {
      name: `Event ${id}`,
      type: 'camping',
      groupId: 'g1',
      createdBy: 'owner',
      participantIds: ['owner', 'member'],
      participantNames: { owner: 'Owner', member: 'Member' },
      modules: { ledger: true },
      startDate: null,
      endDate: null,
      isDeleted: false,
      deletedAt: null,
      createdAt: new Date().toISOString(),
      serverCreatedAt: new Date(),
      updatedAt: null,
      description: null,
      isClosed: false,
      closedAt: null,
      closedBy: null,
    };
  }

  // Mirrors the client SettlementService.buildSettlementDoc output (event leg):
  // payer 'member' → recipient 'owner', createdBy 'member', groupSettleUpId set.
  function eventLeg(overrides: Record<string, unknown> = {}): Record<string, unknown> {
    return {
      id: 'set',
      eventId: 'e1',
      payerParticipantId: 'member',
      recipientParticipantId: 'owner',
      payerName: 'Member',
      recipientName: 'Owner',
      amountFils: 3000,
      currency: 'OMR',
      note: null,
      isDeleted: false,
      deletedAt: null,
      settledAt: new Date().toISOString(),
      createdBy: 'member',
      groupSettleUpId: 'su-1',
      ...overrides,
    };
  }

  // Mirrors GroupSettlementService.buildGroupSettlementDoc (residual leg).
  function residualLeg(overrides: Record<string, unknown> = {}): Record<string, unknown> {
    return {
      id: 'gres',
      groupId: 'g1',
      eventId: 'g1', // sentinel — group settlements have no eventId
      scope: 'group',
      payerParticipantId: 'member',
      recipientParticipantId: 'owner',
      amountFils: 4000,
      currency: 'OMR',
      note: null,
      payerName: 'Member',
      recipientName: 'Owner',
      isDeleted: false,
      deletedAt: null,
      settledAt: new Date().toISOString(),
      createdBy: 'member',
      groupSettleUpId: 'su-1',
      ...overrides,
    };
  }

  async function docExists(path: string): Promise<boolean> {
    let exists = false;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      exists = (await ctx.firestore().doc(path).get()).exists;
    });
    return exists;
  }

  // 6a: an all-valid decompose (2 event legs + 1 residual) commits.
  test('all-valid batch of 2 event legs + 1 residual commits', async () => {
    const db = testEnv.authenticatedContext('member').firestore();
    const batch = db.batch();
    batch.set(
      db.doc('groups/g1/events/e1/settlements/s1'),
      eventLeg({ id: 's1', eventId: 'e1' }),
    );
    batch.set(
      db.doc('groups/g1/events/e2/settlements/s2'),
      eventLeg({ id: 's2', eventId: 'e2' }),
    );
    batch.set(db.doc('groups/g1/settlements/gres'), residualLeg());

    await assertSucceeds(batch.commit());

    expect(await docExists('groups/g1/events/e1/settlements/s1')).toBe(true);
    expect(await docExists('groups/g1/events/e2/settlements/s2')).toBe(true);
    expect(await docExists('groups/g1/settlements/gres')).toBe(true);
  });

  // 6b: legs 1..N-1 individually VALID, only the LAST leg invalid (its recipient
  // is not a participant of that event) → the ENTIRE commit rejects and the
  // valid earlier legs roll back (nothing persists). Proves all-or-nothing.
  test('one invalid last leg rejects the WHOLE batch — zero docs persist', async () => {
    const db = testEnv.authenticatedContext('member').firestore();
    const batch = db.batch();
    // Valid legs first.
    batch.set(
      db.doc('groups/g1/events/e1/settlements/s1'),
      eventLeg({ id: 's1', eventId: 'e1' }),
    );
    batch.set(db.doc('groups/g1/settlements/gres'), residualLeg());
    // Invalid LAST leg: recipient 'ghost' is not a participant of e3.
    batch.set(
      db.doc('groups/g1/events/e3/settlements/sBad'),
      eventLeg({ id: 'sBad', eventId: 'e3', recipientParticipantId: 'ghost' }),
    );

    await assertFails(batch.commit());

    // Atomic rollback: not even the two valid legs survived.
    expect(await docExists('groups/g1/events/e1/settlements/s1')).toBe(false);
    expect(await docExists('groups/g1/settlements/gres')).toBe(false);
    expect(await docExists('groups/g1/events/e3/settlements/sBad')).toBe(false);
  });

  // 6c: a batch at the cap (9 distinct-event legs + 1 residual = 10 docs)
  // commits — the shape a kMaxDecomposeLegsAtomic decompose produces.
  test('all-valid batch of 9 event legs + 1 residual commits', async () => {
    const db = testEnv.authenticatedContext('member').firestore();
    const batch = db.batch();
    for (let i = 1; i <= 9; i++) {
      batch.set(
        db.doc(`groups/g1/events/e${i}/settlements/s${i}`),
        eventLeg({ id: `s${i}`, eventId: `e${i}` }),
      );
    }
    batch.set(db.doc('groups/g1/settlements/gres'), residualLeg());

    await assertSucceeds(batch.commit());

    expect(await docExists('groups/g1/events/e9/settlements/s9')).toBe(true);
    expect(await docExists('groups/g1/settlements/gres')).toBe(true);
  });
});
