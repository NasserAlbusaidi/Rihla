/**
 * Firestore Security Rule Tests
 *
 * Tests group membership enforcement via @firebase/rules-unit-testing.
 * Requires Firebase Emulator running (Firestore on 8080, Auth on 9099).
 *
 * Run via: npm test (with emulator running)
 * Or via:  npm run test:emulator (starts emulator then runs tests)
 *
 * Coverage:
 *  - Unauthenticated access denied
 *  - Non-member access denied
 *  - Member read/update allowed
 *  - Group create validation (full #190 shape: id/inviteCode/createdBy/
 *    memberIds/currency/timestamps/soft-delete pair required)
 *  - Group delete blocked for everyone
 *  - Event-scope subcollection access requires parent group membership
 *  - inviteCodes admin-readable only; create restricted to group creator
 *  - Settlements append-only (B3): no update/delete, event- and group-scope
 *  - Expense ownership (B1): createdBy immutable, creator-only edit/soft-delete,
 *    one-way soft-delete
 */

import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';

const __dirname = dirname(fileURLToPath(import.meta.url));
const RULES_FILE = resolve(__dirname, '../security/firestore.rules');
const rulesContent = readFileSync(RULES_FILE, 'utf8');

const PROJECT_ID = 'rihla-test';
const FIRESTORE_HOST = '127.0.0.1';
const FIRESTORE_PORT = 8080;

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: rulesContent,
      host: FIRESTORE_HOST,
      port: FIRESTORE_PORT,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Returns a Firestore instance authenticated as the given UID.
 */
function authedDb(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

/**
 * Returns an unauthenticated Firestore instance.
 */
function unauthDb() {
  return testEnv.unauthenticatedContext().firestore();
}

/**
 * Seeds a group document directly (bypasses security rules).
 * @param {string} groupId
 * @param {object} data - partial group data merged with defaults
 */
async function seedGroup(groupId, data = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('groups').doc(groupId).set({
      id: groupId,
      name: 'Test Group',
      inviteCode: 'SEEDCODE',
      createdBy: 'user-member',
      memberIds: [],
      currency: 'OMR',
      createdAt: new Date(),
      updatedAt: new Date(),
      isDeleted: false,
      deletedAt: null,
      ...data,
    });
  });
}

/**
 * Seeds a subcollection document directly (bypasses security rules).
 */
async function seedSubcollectionDoc(groupId, subcollection, docId, data = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db
      .collection('groups')
      .doc(groupId)
      .collection(subcollection)
      .doc(docId)
      .set({ note: 'seeded', ...data });
  });
}

/**
 * Seeds an invite code document directly.
 */
async function seedInviteCode(code, data = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.collection('inviteCodes').doc(code).set({
      groupId: 'group1',
      expiresAt: new Date(),
      ...data,
    });
  });
}

/**
 * Seeds an event document under a group (bypasses rules).
 * Minimal shape — only the fields the rules read (participantIds, isDeleted).
 */
async function seedEvent(groupId, eventId, data = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context
      .firestore()
      .collection('groups')
      .doc(groupId)
      .collection('events')
      .doc(eventId)
      .set({ participantIds: [], isDeleted: false, ...data });
  });
}

/**
 * Builds a fully rules-valid event-scope expense doc (validExpenseBase shape).
 * Note: expense `createdAt`/`deletedAt` are STRINGS, not timestamps.
 */
function expenseDoc(eventId, overrides = {}) {
  return {
    id: 'exp1',
    eventId,
    createdBy: 'user-creator',
    payerParticipantId: 'user-creator',
    amountFils: 5000,
    currency: 'OMR',
    description: 'Dinner',
    scope: 'global',
    subGroupId: null,
    customSplitParticipants: [],
    splitMode: 'equally',
    splitDistribution: { 'user-creator': 2500, 'user-other': 2500 },
    receiptUrl: null,
    categoryId: null,
    note: null,
    isDeleted: false,
    deletedAt: null,
    createdAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  };
}

/**
 * Seeds an event-scope expense at groups/{g}/events/{e}/expenses/{id}.
 */
async function seedEventExpense(groupId, eventId, docId, overrides = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context
      .firestore()
      .collection('groups')
      .doc(groupId)
      .collection('events')
      .doc(eventId)
      .collection('expenses')
      .doc(docId)
      .set(expenseDoc(eventId, { id: docId, ...overrides }));
  });
}

/**
 * Builds a fully rules-valid group-scope settlement doc.
 * `eventId` is pinned to `groupId` per the group-settlement sentinel (#71).
 */
function groupSettlementDoc(groupId, overrides = {}) {
  return {
    id: 'gset1',
    groupId,
    eventId: groupId,
    createdBy: 'user-creator',
    scope: 'group',
    payerParticipantId: 'user-creator',
    recipientParticipantId: 'user-other',
    amountFils: 3000,
    currency: 'OMR',
    note: null,
    payerName: null,
    recipientName: null,
    isDeleted: false,
    deletedAt: null,
    settledAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  };
}

/**
 * Seeds a group-scope settlement at groups/{g}/settlements/{id}.
 */
async function seedGroupSettlement(groupId, docId, overrides = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context
      .firestore()
      .collection('groups')
      .doc(groupId)
      .collection('settlements')
      .doc(docId)
      .set(groupSettlementDoc(groupId, { id: docId, ...overrides }));
  });
}

// ---------------------------------------------------------------------------
// Tests: Group document access
// ---------------------------------------------------------------------------

describe('Group document access', () => {
  test('unauthenticated user cannot read group', async () => {
    await seedGroup('group1', { memberIds: [] });
    const db = unauthDb();
    await assertFails(db.collection('groups').doc('group1').get());
  });

  test('non-member cannot read group', async () => {
    await seedGroup('group1', { memberIds: ['user-member'] });
    const db = authedDb('user-nonmember');
    await assertFails(db.collection('groups').doc('group1').get());
  });

  test('member can read group', async () => {
    await seedGroup('group1', { memberIds: ['user-member'] });
    const db = authedDb('user-member');
    await assertSucceeds(db.collection('groups').doc('group1').get());
  });

  test('member can update group', async () => {
    await seedGroup('group1', { memberIds: ['user-member'] });
    const db = authedDb('user-member');
    await assertSucceeds(
      db.collection('groups').doc('group1').update({ name: 'Updated Name' })
    );
  });

  test('non-member cannot update group', async () => {
    await seedGroup('group1', { memberIds: ['user-member'] });
    const db = authedDb('user-nonmember');
    await assertFails(
      db.collection('groups').doc('group1').update({ name: 'Hack Attempt' })
    );
  });

  test('nobody can delete group (member)', async () => {
    await seedGroup('group1', { memberIds: ['user-member'] });
    const db = authedDb('user-member');
    await assertFails(db.collection('groups').doc('group1').delete());
  });

  test('nobody can delete group (unauthenticated)', async () => {
    await seedGroup('group1', { memberIds: [] });
    const db = unauthDb();
    await assertFails(db.collection('groups').doc('group1').delete());
  });
});

// ---------------------------------------------------------------------------
// Tests: Group creation validation
// ---------------------------------------------------------------------------

describe('Group creation validation', () => {
  test('authenticated user can create group with valid fields', async () => {
    const db = authedDb('user-creator');
    await assertSucceeds(
      db.collection('groups').doc('new-group').set({
        id: 'new-group',
        name: 'Weekend Trip',
        inviteCode: 'WKND01',
        createdBy: 'user-creator',
        memberIds: ['user-creator'],
        currency: 'OMR',
        createdAt: new Date(),
        updatedAt: new Date(),
        isDeleted: false,
        deletedAt: null,
      })
    );
  });

  test('cannot create group without name', async () => {
    const db = authedDb('user-creator');
    await assertFails(
      db.collection('groups').doc('bad-group').set({
        memberIds: ['user-creator'],
        currency: 'OMR',
        createdAt: new Date(),
      })
    );
  });

  test('cannot create group with empty name', async () => {
    const db = authedDb('user-creator');
    await assertFails(
      db.collection('groups').doc('bad-group').set({
        name: '',
        memberIds: ['user-creator'],
        currency: 'OMR',
        createdAt: new Date(),
      })
    );
  });

  test('cannot create group without memberIds', async () => {
    const db = authedDb('user-creator');
    await assertFails(
      db.collection('groups').doc('bad-group').set({
        name: 'Test',
        currency: 'OMR',
        createdAt: new Date(),
      })
    );
  });

  test('cannot create group without currency', async () => {
    const db = authedDb('user-creator');
    await assertFails(
      db.collection('groups').doc('bad-group').set({
        name: 'Test',
        memberIds: ['user-creator'],
        createdAt: new Date(),
      })
    );
  });

  test('unauthenticated user cannot create group', async () => {
    const db = unauthDb();
    await assertFails(
      db.collection('groups').doc('anon-group').set({
        name: 'Anon Group',
        memberIds: [],
        currency: 'OMR',
        createdAt: new Date(),
      })
    );
  });
});

// ---------------------------------------------------------------------------
// Tests: Subcollection access
// ---------------------------------------------------------------------------

// Expenses live under groups/{g}/events/{e}/expenses — NOT directly under the
// group. (The old version of these tests wrote to groups/{g}/expenses, which
// only ever matched the root default-deny; they "passed" solely because the
// suite was never run in CI.)
describe('Group subcollection access', () => {
  test('member can read an event-scope expense', async () => {
    await seedGroup('group1', { memberIds: ['user-member'] });
    await seedEvent('group1', 'event1', { participantIds: ['user-member'] });
    await seedEventExpense('group1', 'event1', 'exp1', {
      createdBy: 'user-member',
      payerParticipantId: 'user-member',
      splitDistribution: { 'user-member': 5000 },
    });
    const db = authedDb('user-member');
    await assertSucceeds(
      db
        .collection('groups')
        .doc('group1')
        .collection('events')
        .doc('event1')
        .collection('expenses')
        .doc('exp1')
        .get()
    );
  });

  test('non-member cannot read an event-scope expense', async () => {
    await seedGroup('group1', { memberIds: ['user-member'] });
    await seedEvent('group1', 'event1', { participantIds: ['user-member'] });
    await seedEventExpense('group1', 'event1', 'exp1', {
      createdBy: 'user-member',
      payerParticipantId: 'user-member',
      splitDistribution: { 'user-member': 5000 },
    });
    const db = authedDb('user-nonmember');
    await assertFails(
      db
        .collection('groups')
        .doc('group1')
        .collection('events')
        .doc('event1')
        .collection('expenses')
        .doc('exp1')
        .get()
    );
  });

  test('participant can create an event-scope expense', async () => {
    await seedGroup('group1', { memberIds: ['user-member'] });
    await seedEvent('group1', 'event1', { participantIds: ['user-member'] });
    const db = authedDb('user-member');
    await assertSucceeds(
      db
        .collection('groups')
        .doc('group1')
        .collection('events')
        .doc('event1')
        .collection('expenses')
        .doc('exp-new')
        .set(
          expenseDoc('event1', {
            id: 'exp-new',
            createdBy: 'user-member',
            payerParticipantId: 'user-member',
            customSplitParticipants: [],
            splitDistribution: { 'user-member': 5000 },
          })
        )
    );
  });

  test('unauthenticated user cannot read an event-scope expense', async () => {
    await seedGroup('group1', { memberIds: ['user-member'] });
    await seedEvent('group1', 'event1', { participantIds: ['user-member'] });
    await seedEventExpense('group1', 'event1', 'exp1', {
      createdBy: 'user-member',
      payerParticipantId: 'user-member',
      splitDistribution: { 'user-member': 5000 },
    });
    const db = unauthDb();
    await assertFails(
      db
        .collection('groups')
        .doc('group1')
        .collection('events')
        .doc('event1')
        .collection('expenses')
        .doc('exp1')
        .get()
    );
  });
});

// ---------------------------------------------------------------------------
// Tests: Invite codes
// ---------------------------------------------------------------------------

// Invite codes are admin-readable only — clients join via the
// joinGroupByInviteCode callable so codes can't be brute-forced through direct
// reads. Create is restricted to the owning group's creator, with the code doc
// keyed to the group's own inviteCode.
describe('Invite codes', () => {
  test('invite codes are not readable by unauthenticated clients', async () => {
    await seedInviteCode('INVITE123');
    const db = unauthDb();
    await assertFails(db.collection('inviteCodes').doc('INVITE123').get());
  });

  test('invite codes are not readable by authenticated clients', async () => {
    await seedInviteCode('INVITE456');
    const db = authedDb('user-member');
    await assertFails(db.collection('inviteCodes').doc('INVITE456').get());
  });

  test('group creator can create a matching invite code', async () => {
    await seedGroup('group1', {
      createdBy: 'user-creator',
      inviteCode: 'NEWINVITE',
      memberIds: ['user-creator'],
    });
    const db = authedDb('user-creator');
    await assertSucceeds(
      db.collection('inviteCodes').doc('NEWINVITE').set({
        groupId: 'group1',
        createdAt: new Date(),
      })
    );
  });

  test('non-creator cannot create an invite code for a group', async () => {
    await seedGroup('group1', {
      createdBy: 'user-creator',
      inviteCode: 'NEWINVITE',
      memberIds: ['user-creator'],
    });
    const db = authedDb('user-other');
    await assertFails(
      db.collection('inviteCodes').doc('NEWINVITE').set({
        groupId: 'group1',
        createdAt: new Date(),
      })
    );
  });
});

// ---------------------------------------------------------------------------
// Tests: Default deny
// ---------------------------------------------------------------------------

describe('Default deny for unknown collections', () => {
  test('unauthenticated user cannot read unknown collection', async () => {
    const db = unauthDb();
    await assertFails(db.collection('unknown').doc('doc1').get());
  });

  test('authenticated user cannot read unknown collection', async () => {
    const db = authedDb('user-x');
    await assertFails(db.collection('unknown').doc('doc1').get());
  });
});

// ---------------------------------------------------------------------------
// Tests: Settlements are append-only (B3)
//
// Corrections are new offsetting rows — never an update or delete of an
// existing settlement. Covers both group-scope settlements
// (groups/{g}/settlements) and event-scope settlements
// (groups/{g}/events/{e}/settlements). Neither had any rules-level test.
// ---------------------------------------------------------------------------

describe('Settlements are append-only (B3)', () => {
  test('group settlement creator cannot update own settlement', async () => {
    await seedGroup('group1', {
      memberIds: ['user-creator', 'user-other'],
      createdBy: 'user-creator',
    });
    await seedGroupSettlement('group1', 'gset1', { createdBy: 'user-creator' });
    const db = authedDb('user-creator');
    await assertFails(
      db
        .collection('groups')
        .doc('group1')
        .collection('settlements')
        .doc('gset1')
        .update({ note: 'corrected' })
    );
  });

  test('group settlement creator cannot soft-delete own settlement', async () => {
    await seedGroup('group1', {
      memberIds: ['user-creator', 'user-other'],
      createdBy: 'user-creator',
    });
    await seedGroupSettlement('group1', 'gset1', { createdBy: 'user-creator' });
    const db = authedDb('user-creator');
    await assertFails(
      db
        .collection('groups')
        .doc('group1')
        .collection('settlements')
        .doc('gset1')
        .update({ isDeleted: true, deletedAt: '2026-02-01T00:00:00.000Z' })
    );
  });

  test('group settlement creator cannot hard-delete own settlement', async () => {
    await seedGroup('group1', {
      memberIds: ['user-creator', 'user-other'],
      createdBy: 'user-creator',
    });
    await seedGroupSettlement('group1', 'gset1', { createdBy: 'user-creator' });
    const db = authedDb('user-creator');
    await assertFails(
      db
        .collection('groups')
        .doc('group1')
        .collection('settlements')
        .doc('gset1')
        .delete()
    );
  });

  test('event settlement cannot be updated', async () => {
    await seedGroup('group1', { memberIds: ['user-creator'], createdBy: 'user-creator' });
    await seedEvent('group1', 'event1', { participantIds: ['user-creator'] });
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .collection('groups')
        .doc('group1')
        .collection('events')
        .doc('event1')
        .collection('settlements')
        .doc('eset1')
        .set({
          id: 'eset1',
          eventId: 'event1',
          createdBy: 'user-creator',
          payerParticipantId: 'user-creator',
          recipientParticipantId: 'user-other',
          amountFils: 2000,
          currency: 'OMR',
          note: null,
          payerName: null,
          recipientName: null,
          isDeleted: false,
          deletedAt: null,
          settledAt: '2026-01-01T00:00:00.000Z',
        });
    });
    const db = authedDb('user-creator');
    await assertFails(
      db
        .collection('groups')
        .doc('group1')
        .collection('events')
        .doc('event1')
        .collection('settlements')
        .doc('eset1')
        .update({ note: 'corrected' })
    );
  });

  test('event settlement cannot be hard-deleted', async () => {
    await seedGroup('group1', { memberIds: ['user-creator'], createdBy: 'user-creator' });
    await seedEvent('group1', 'event1', { participantIds: ['user-creator'] });
    await seedSubcollectionDoc('group1', 'events', 'event1');
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .collection('groups')
        .doc('group1')
        .collection('events')
        .doc('event1')
        .collection('settlements')
        .doc('eset1')
        .set({ id: 'eset1', eventId: 'event1', createdBy: 'user-creator' });
    });
    const db = authedDb('user-creator');
    await assertFails(
      db
        .collection('groups')
        .doc('group1')
        .collection('events')
        .doc('event1')
        .collection('settlements')
        .doc('eset1')
        .delete()
    );
  });
});

// ---------------------------------------------------------------------------
// Tests: Expense ownership + soft-delete (B1)
//
// createdBy is immutable; only the creator may edit or soft-delete an expense;
// soft-delete is one-way (un-delete is denied).
// ---------------------------------------------------------------------------

describe('Expense ownership and soft-delete (B1)', () => {
  async function seedGroupEventExpense(overrides = {}) {
    await seedGroup('group1', {
      memberIds: ['user-creator', 'user-other'],
      createdBy: 'user-creator',
    });
    await seedEvent('group1', 'event1', {
      participantIds: ['user-creator', 'user-other'],
    });
    await seedEventExpense('group1', 'event1', 'exp1', overrides);
  }

  function expenseRef(db) {
    return db
      .collection('groups')
      .doc('group1')
      .collection('events')
      .doc('event1')
      .collection('expenses')
      .doc('exp1');
  }

  test('non-creator participant cannot edit an expense', async () => {
    await seedGroupEventExpense();
    const db = authedDb('user-other');
    await assertFails(expenseRef(db).update({ description: 'Hijacked' }));
  });

  test('createdBy is immutable — creator cannot reassign it', async () => {
    await seedGroupEventExpense();
    const db = authedDb('user-creator');
    await assertFails(expenseRef(db).update({ createdBy: 'user-other' }));
  });

  test('creator can soft-delete own expense', async () => {
    await seedGroupEventExpense();
    const db = authedDb('user-creator');
    await assertSucceeds(
      expenseRef(db).update({
        isDeleted: true,
        deletedAt: '2026-02-01T00:00:00.000Z',
      })
    );
  });

  test('non-creator cannot soft-delete an expense', async () => {
    await seedGroupEventExpense();
    const db = authedDb('user-other');
    await assertFails(
      expenseRef(db).update({
        isDeleted: true,
        deletedAt: '2026-02-01T00:00:00.000Z',
      })
    );
  });

  test('un-delete (isDeleted true -> false) is denied', async () => {
    await seedGroupEventExpense({
      isDeleted: true,
      deletedAt: '2026-01-15T00:00:00.000Z',
    });
    const db = authedDb('user-creator');
    await assertFails(
      expenseRef(db).update({ isDeleted: false, deletedAt: null })
    );
  });
});
