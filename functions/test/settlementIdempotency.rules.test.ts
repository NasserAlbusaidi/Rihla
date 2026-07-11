import {
  initializeTestEnvironment,
  assertFails,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// #1093 → #1129 lineage. #1093's deterministic dedup ids leaned on ONE rules
// floor: a second `set()` at an existing id is an UPDATE, and both settlement
// blocks hard-deny update (`allow update: if false` — event block + group
// block, security/firestore.rules). #1129 then made settlement creates
// CALLABLE-ONLY (recordSettlement, Admin SDK): the CREATE arm is now denied
// for clients too, so the dedup collision fires server-side in the callable's
// idempotency probe instead of at the rules boundary. This suite pins BOTH
// floors: any client create is denied regardless of payload/id, and the
// update-deny still holds for a client set() at an EXISTING (Admin-seeded) id
// — including merge:true — so a legacy queued client replay can never mutate a
// recorded settlement.

const PROJECT_ID = 'rihla-settlement-idempotency-rules-test';
const RULES_PATH = resolve(__dirname, '../../security/firestore.rules');
const [FIRESTORE_HOST, FIRESTORE_PORT] =
  (process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080').split(':');

describe('#1093/#1129 settlement write floors — callable-only create + deny-on-existing-id', () => {
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
        isDeleted: false,
        deletedAt: null,
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
      await db.doc('groups/g1/events/e1').set({
        id: 'e1',
        name: 'Weekend Camp',
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
      });
    });
  }

  // A deterministic-shaped id — 'sd1' + 40 hex chars, matching the (now
  // server-side) deterministicSettlementId output shape. The rules never
  // inspect id format, so a literal fixed string is an equally valid probe.
  const DETERMINISTIC_ID =
    'sd1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  function validSettlement(overrides: Record<string, unknown> = {}): Record<string, unknown> {
    return {
      id: DETERMINISTIC_ID,
      eventId: 'e1',
      createdBy: 'member',
      payerParticipantId: 'member',
      recipientParticipantId: 'owner',
      amountFils: 5000,
      currency: 'OMR',
      note: null,
      payerName: 'Member',
      recipientName: 'Owner',
      isDeleted: false,
      deletedAt: null,
      settledAt: new Date().toISOString(),
      ...overrides,
    };
  }

  function validGroupSettlement(overrides: Record<string, unknown> = {}): Record<string, unknown> {
    return {
      id: DETERMINISTIC_ID,
      groupId: 'g1',
      eventId: 'g1',
      createdBy: 'member',
      scope: 'group',
      payerParticipantId: 'member',
      recipientParticipantId: 'owner',
      amountFils: 5000,
      currency: 'OMR',
      note: null,
      payerName: 'Member',
      recipientName: 'Owner',
      isDeleted: false,
      deletedAt: null,
      settledAt: new Date().toISOString(),
      ...overrides,
    };
  }

  async function seedExisting(path: string, data: Record<string, unknown>): Promise<void> {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(path).set(data);
    });
  }

  describe('event scope (groups/{gid}/events/{eid}/settlements/{id})', () => {
    test('(1) #1129: create at a fresh id with a fully-valid payload is DENIED — callable-only', async () => {
      const member = testEnv.authenticatedContext('member').firestore();

      await assertFails(
        member
          .doc(`groups/g1/events/e1/settlements/${DETERMINISTIC_ID}`)
          .set(validSettlement()),
      );
    });

    test('(2) set() at an EXISTING id is DENIED (update path, allow update: if false)', async () => {
      await seedExisting(
        `groups/g1/events/e1/settlements/${DETERMINISTIC_ID}`,
        validSettlement(),
      );
      const member = testEnv.authenticatedContext('member').firestore();

      await assertFails(
        member
          .doc(`groups/g1/events/e1/settlements/${DETERMINISTIC_ID}`)
          .set(validSettlement()),
      );
    });

    test('(3) set(..., { merge: true }) at an EXISTING id is ALSO DENIED — merge does not escape the update deny', async () => {
      await seedExisting(
        `groups/g1/events/e1/settlements/${DETERMINISTIC_ID}`,
        validSettlement(),
      );
      const member = testEnv.authenticatedContext('member').firestore();

      await assertFails(
        member
          .doc(`groups/g1/events/e1/settlements/${DETERMINISTIC_ID}`)
          .set(validSettlement({ note: 'merged note' }), { merge: true }),
      );
    });
  });

  describe('group scope (groups/{gid}/settlements/{id})', () => {
    test('(1) #1129: create at a fresh id with a fully-valid payload is DENIED — callable-only', async () => {
      const member = testEnv.authenticatedContext('member').firestore();

      await assertFails(
        member
          .doc(`groups/g1/settlements/${DETERMINISTIC_ID}`)
          .set(validGroupSettlement()),
      );
    });

    test('(2) set() at an EXISTING id is DENIED (update path, allow update: if false)', async () => {
      await seedExisting(
        `groups/g1/settlements/${DETERMINISTIC_ID}`,
        validGroupSettlement(),
      );
      const member = testEnv.authenticatedContext('member').firestore();

      await assertFails(
        member
          .doc(`groups/g1/settlements/${DETERMINISTIC_ID}`)
          .set(validGroupSettlement()),
      );
    });

    test('(3) set(..., { merge: true }) at an EXISTING id is ALSO DENIED — merge does not escape the update deny', async () => {
      await seedExisting(
        `groups/g1/settlements/${DETERMINISTIC_ID}`,
        validGroupSettlement(),
      );
      const member = testEnv.authenticatedContext('member').firestore();

      await assertFails(
        member
          .doc(`groups/g1/settlements/${DETERMINISTIC_ID}`)
          .set(validGroupSettlement({ note: 'merged note' }), { merge: true }),
      );
    });
  });
});
