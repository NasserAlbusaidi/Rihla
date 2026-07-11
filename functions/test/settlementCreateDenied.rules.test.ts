import {
  initializeTestEnvironment,
  assertFails,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// #1129: settlement creates are CALLABLE-ONLY. These pins are the vulnerability
// regression tests — authored RED against pre-#1129 rules (where a member could
// direct-write ANY positiveInt amountFils with zero outstanding, #1093 residual
// 4) and green once the rules flip denies every client settlement create in
// both scopes, plus the settlement-typed activity forge (a client-writable
// 'event_settlement'/'group_settlement' activity row with no settlement doc
// behind it would be phantom history — the recordSettlement callable is the
// only author of both now).
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/settlementCreateDenied.rules.test.ts" npm run test:emulator`

const PROJECT_ID = 'rihla-settlement-create-denied-rules-test';
const RULES_PATH = resolve(__dirname, '../../security/firestore.rules');
const [FIRESTORE_HOST, FIRESTORE_PORT] =
  (process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080').split(':');

describe('#1129 settlement creates are callable-only — client direct writes DENIED', () => {
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

  const SD1_ID = 'sd1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  // The exact write-map the pre-#1129 client serialized (buildSettlementDoc) —
  // a payload that PASSED every pre-flip shape gate. Denial must come from the
  // create path itself, not a shape rejection.
  function eventSettlement(): Record<string, unknown> {
    return {
      id: SD1_ID,
      eventId: 'e1',
      createdBy: 'member',
      payerParticipantId: 'member',
      recipientParticipantId: 'owner',
      amountFils: 999999, // the #1093 residual-4 forge: no outstanding behind it
      currency: 'OMR',
      note: null,
      payerName: 'Member',
      recipientName: 'Owner',
      isDeleted: false,
      deletedAt: null,
      settledAt: new Date().toISOString(),
    };
  }

  function groupSettlement(): Record<string, unknown> {
    return {
      id: SD1_ID,
      groupId: 'g1',
      eventId: 'g1',
      createdBy: 'member',
      scope: 'group',
      payerParticipantId: 'member',
      recipientParticipantId: 'owner',
      amountFils: 999999,
      currency: 'OMR',
      note: null,
      payerName: 'Member',
      recipientName: 'Owner',
      isDeleted: false,
      deletedAt: null,
      settledAt: new Date().toISOString(),
    };
  }

  test('event-scope client settlement create is DENIED (any payload, any member)', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(
      member.doc(`groups/g1/events/e1/settlements/${SD1_ID}`).set(eventSettlement()),
    );
  });

  test('group-scope client settlement create is DENIED (any payload, any member)', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(
      member.doc(`groups/g1/settlements/${SD1_ID}`).set(groupSettlement()),
    );
  });

  test('client create of an event_settlement-typed activity row is DENIED (phantom-history forge)', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(
      member.doc('groups/g1/activity/act_forge_1').set({
        id: 'act_forge_1',
        type: 'event_settlement',
        actorId: 'member',
        actorName: 'Member',
        description: 'settled OMR 999.999 with Owner',
        metadata: {
          amountFils: 999999,
          currency: 'OMR',
          fromUserId: 'member',
          toUserId: 'owner',
          fromName: 'Member',
          toName: 'Owner',
          eventId: 'e1',
        },
        timestamp: new Date().toISOString(),
      }),
    );
  });

  test('client create of a group_settlement-typed activity row is DENIED (phantom-history forge)', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(
      member.doc('groups/g1/activity/act_forge_2').set({
        id: 'act_forge_2',
        type: 'group_settlement',
        actorId: 'member',
        actorName: 'Member',
        description: 'settled OMR 999.999 with Owner',
        metadata: {
          amount: '999.999',
          recipientId: 'owner',
          currency: 'OMR',
          fromUserId: 'member',
          toUserId: 'owner',
          fromName: 'Member',
          toName: 'Owner',
        },
        timestamp: new Date().toISOString(),
      }),
    );
  });
});
