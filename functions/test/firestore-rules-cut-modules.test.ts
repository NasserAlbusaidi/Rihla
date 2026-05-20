import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// BLOCKER 2 verification — Phase 39 (SHIP-01) restricts the Firestore module
// wildcard so cut subcollections (gear, gear_items, documents, memories,
// trip_memories, logistics, sub_groups) cannot match any allow rule even when
// the requester is a group member. Surviving subcollections (expenses, activity)
// remain accessible.

const PROJECT_ID = 'rihla-rules-test';
const RULES_PATH = resolve(__dirname, '../../security/firestore.rules');
const [FIRESTORE_HOST, FIRESTORE_PORT] =
  (process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080').split(':');

describe('Phase 39 — cut module subcollections are denied', () => {
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
    // Seed group + event with the test user as a member/participant.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('groups/g1').set({
        name: 'Test Group',
        memberIds: ['uid-member'],
        createdBy: 'uid-member',
        currency: 'OMR',
      });
      await ctx.firestore().doc('groups/g1/events/e1').set({
        name: 'Test Event',
        type: 'trip',
        participantIds: ['uid-member'],
        participantNames: { 'uid-member': 'Test' },
        isDeleted: false,
      });
    });
  });

  const cutCollections = [
    'documents',
    'memories',
    'trip_memories',
    'gear',
    'gear_items',
    'logistics',
    'sub_groups',
  ];

  const survivingCollections = ['expenses', 'settlements', 'activity_logs'];

  for (const cut of cutCollections) {
    test(`member CANNOT read /groups/g1/events/e1/${cut}/x`, async () => {
      const ctx = testEnv.authenticatedContext('uid-member');
      await assertFails(
        ctx.firestore().doc(`groups/g1/events/e1/${cut}/x`).get(),
      );
    });

    test(`member CANNOT write /groups/g1/events/e1/${cut}/x`, async () => {
      const ctx = testEnv.authenticatedContext('uid-member');
      await assertFails(
        ctx.firestore().doc(`groups/g1/events/e1/${cut}/x`).set({ foo: 'bar' }),
      );
    });
  }

  for (const survive of survivingCollections) {
    test(`member CAN read /groups/g1/events/e1/${survive}/x`, async () => {
      const ctx = testEnv.authenticatedContext('uid-member');
      await assertSucceeds(
        ctx.firestore().doc(`groups/g1/events/e1/${survive}/x`).get(),
      );
    });
  }
});
