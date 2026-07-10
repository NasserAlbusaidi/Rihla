import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// #1093: deterministic settlement dedup ids lean on ONE floor — a second
// `set()` at an id that already exists is evaluated as an UPDATE by Firestore
// rules, and both settlement blocks already hard-deny update
// (`allow update: if false`, security/firestore.rules:988 event / :1230
// group — verified 2026-07-11). This suite pins that floor directly against
// the emulator so a future rules edit that accidentally opens update on
// either settlement block cannot silently break the #1093 design without a
// test going red. NO rules change ships with this file.

const PROJECT_ID = 'rihla-settlement-idempotency-rules-test';
const RULES_PATH = resolve(__dirname, '../../security/firestore.rules');
const [FIRESTORE_HOST, FIRESTORE_PORT] =
  (process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080').split(':');

describe('#1093 settlement idempotency — deny-on-existing-id floor', () => {
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
      await db.doc('inviteCodes/ABC123').set({
        groupId: 'g1',
        createdAt: new Date(),
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

  // A deterministic-shaped id — 'sd1' + 40 hex chars, matching
  // SettlementService.deterministicSettlementId's output shape. The rules
  // never inspect id format (Invariant 3), so a literal fixed string is an
  // equally valid probe of the deny-on-existing-id floor.
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

  describe('event scope (groups/{gid}/events/{eid}/settlements/{id})', () => {
    test('(1) create at a deterministic id with a valid payload is ALLOWED', async () => {
      const member = testEnv.authenticatedContext('member').firestore();

      await assertSucceeds(
        member
          .doc(`groups/g1/events/e1/settlements/${DETERMINISTIC_ID}`)
          .set(validSettlement()),
      );
    });

    test(
      '(2) a second set() at the SAME id — same auth member — is DENIED ' +
        '(evaluated as an update; allow update: if false)',
      async () => {
        const member = testEnv.authenticatedContext('member').firestore();
        await member
          .doc(`groups/g1/events/e1/settlements/${DETERMINISTIC_ID}`)
          .set(validSettlement());

        await assertFails(
          member
            .doc(`groups/g1/events/e1/settlements/${DETERMINISTIC_ID}`)
            .set(validSettlement()),
        );
      },
    );

    test(
      '(2b) a second set() at the SAME id — DIFFERENT auth member (settle-on-' +
        'behalf racing the same pair from another device) — is DENIED',
      async () => {
        const member = testEnv.authenticatedContext('member').firestore();
        const owner = testEnv.authenticatedContext('owner').firestore();
        await member
          .doc(`groups/g1/events/e1/settlements/${DETERMINISTIC_ID}`)
          .set(validSettlement());

        await assertFails(
          owner
            .doc(`groups/g1/events/e1/settlements/${DETERMINISTIC_ID}`)
            .set(validSettlement({ createdBy: 'owner' })),
        );
      },
    );

    test(
      '(3) set(..., { merge: true }) at the SAME id is ALSO DENIED — merge ' +
        'does not escape the update-path deny',
      async () => {
        const member = testEnv.authenticatedContext('member').firestore();
        await member
          .doc(`groups/g1/events/e1/settlements/${DETERMINISTIC_ID}`)
          .set(validSettlement());

        await assertFails(
          member
            .doc(`groups/g1/events/e1/settlements/${DETERMINISTIC_ID}`)
            .set(validSettlement({ note: 'merged note' }), { merge: true }),
        );
      },
    );
  });

  describe('group scope (groups/{gid}/settlements/{id})', () => {
    test('(1) create at a deterministic id with a valid payload is ALLOWED', async () => {
      const member = testEnv.authenticatedContext('member').firestore();

      await assertSucceeds(
        member
          .doc(`groups/g1/settlements/${DETERMINISTIC_ID}`)
          .set(validGroupSettlement()),
      );
    });

    test(
      '(2) a second set() at the SAME id — same auth member — is DENIED ' +
        '(evaluated as an update; allow update: if false)',
      async () => {
        const member = testEnv.authenticatedContext('member').firestore();
        await member
          .doc(`groups/g1/settlements/${DETERMINISTIC_ID}`)
          .set(validGroupSettlement());

        await assertFails(
          member
            .doc(`groups/g1/settlements/${DETERMINISTIC_ID}`)
            .set(validGroupSettlement()),
        );
      },
    );

    test(
      '(2b) a second set() at the SAME id — DIFFERENT auth member — is DENIED',
      async () => {
        const member = testEnv.authenticatedContext('member').firestore();
        const owner = testEnv.authenticatedContext('owner').firestore();
        await member
          .doc(`groups/g1/settlements/${DETERMINISTIC_ID}`)
          .set(validGroupSettlement());

        await assertFails(
          owner
            .doc(`groups/g1/settlements/${DETERMINISTIC_ID}`)
            .set(validGroupSettlement({ createdBy: 'owner' })),
        );
      },
    );

    test(
      '(3) set(..., { merge: true }) at the SAME id is ALSO DENIED — merge ' +
        'does not escape the update-path deny',
      async () => {
        const member = testEnv.authenticatedContext('member').firestore();
        await member
          .doc(`groups/g1/settlements/${DETERMINISTIC_ID}`)
          .set(validGroupSettlement());

        await assertFails(
          member
            .doc(`groups/g1/settlements/${DETERMINISTIC_ID}`)
            .set(validGroupSettlement({ note: 'merged note' }), { merge: true }),
        );
      },
    );
  });
});
