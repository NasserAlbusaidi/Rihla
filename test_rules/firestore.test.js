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
 *  - Group create validation (name, memberIds, currency required)
 *  - Group delete blocked for everyone
 *  - Subcollection access requires parent group membership
 *  - inviteCodes publicly readable, authenticated writable
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
      name: 'Test Group',
      memberIds: [],
      currency: 'OMR',
      createdAt: new Date(),
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
        name: 'Weekend Trip',
        memberIds: ['user-creator'],
        currency: 'OMR',
        createdAt: new Date(),
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

describe('Group subcollection access', () => {
  test('member can read group subcollection document', async () => {
    await seedGroup('group1', { memberIds: ['user-member'] });
    await seedSubcollectionDoc('group1', 'expenses', 'exp1');
    const db = authedDb('user-member');
    await assertSucceeds(
      db.collection('groups').doc('group1').collection('expenses').doc('exp1').get()
    );
  });

  test('non-member cannot read group subcollection', async () => {
    await seedGroup('group1', { memberIds: ['user-member'] });
    await seedSubcollectionDoc('group1', 'expenses', 'exp1');
    const db = authedDb('user-nonmember');
    await assertFails(
      db.collection('groups').doc('group1').collection('expenses').doc('exp1').get()
    );
  });

  test('member can write to group subcollection', async () => {
    await seedGroup('group1', { memberIds: ['user-member'] });
    const db = authedDb('user-member');
    await assertSucceeds(
      db
        .collection('groups')
        .doc('group1')
        .collection('expenses')
        .doc('exp-new')
        .set({ amount_fils: 5000, currency: 'OMR', description: 'Dinner' })
    );
  });

  test('unauthenticated user cannot read group subcollection', async () => {
    await seedGroup('group1', { memberIds: ['user-member'] });
    await seedSubcollectionDoc('group1', 'expenses', 'exp1');
    const db = unauthDb();
    await assertFails(
      db.collection('groups').doc('group1').collection('expenses').doc('exp1').get()
    );
  });
});

// ---------------------------------------------------------------------------
// Tests: Invite codes
// ---------------------------------------------------------------------------

describe('Invite codes', () => {
  test('anyone can read invite codes (unauthenticated)', async () => {
    await seedInviteCode('INVITE123');
    const db = unauthDb();
    await assertSucceeds(db.collection('inviteCodes').doc('INVITE123').get());
  });

  test('authenticated user can write invite codes', async () => {
    const db = authedDb('user-creator');
    await assertSucceeds(
      db.collection('inviteCodes').doc('NEWINVITE').set({
        groupId: 'group1',
        expiresAt: new Date(),
      })
    );
  });

  test('authenticated user can read invite codes', async () => {
    await seedInviteCode('INVITE456');
    const db = authedDb('user-member');
    await assertSucceeds(db.collection('inviteCodes').doc('INVITE456').get());
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
