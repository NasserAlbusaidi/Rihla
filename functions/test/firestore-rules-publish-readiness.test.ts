import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const PROJECT_ID = 'rihla-publish-readiness-rules-test';
const RULES_PATH = resolve(__dirname, '../../security/firestore.rules');

describe('Publish readiness Firestore rules', () => {
  let testEnv: RulesTestEnvironment;

  beforeAll(async () => {
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: readFileSync(RULES_PATH, 'utf8'),
        host: '127.0.0.1',
        port: 8080,
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
      await db.doc('groups/g1/events/e1').set(validEvent());
    });
  }

  function validEvent(overrides: Record<string, unknown> = {}): Record<string, unknown> {
    return {
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
      ...overrides,
    };
  }

  function validExpense(overrides: Record<string, unknown> = {}): Record<string, unknown> {
    return {
      id: 'exp1',
      eventId: 'e1',
      payerParticipantId: 'owner',
      amountFils: 10500,
      currency: 'OMR',
      description: 'Dinner',
      scope: 'global',
      subGroupId: null,
      customSplitParticipants: [],
      receiptUrl: null,
      categoryId: null,
      note: null,
      isDeleted: false,
      deletedAt: null,
      createdAt: new Date().toISOString(),
      ...overrides,
    };
  }

  function validSettlement(overrides: Record<string, unknown> = {}): Record<string, unknown> {
    return {
      id: 'set1',
      eventId: 'e1',
      payerParticipantId: 'member',
      recipientParticipantId: 'owner',
      amountFils: 5000,
      currency: 'OMR',
      note: null,
      isDeleted: false,
      deletedAt: null,
      settledAt: new Date().toISOString(),
      ...overrides,
    };
  }

  function validGroupSettlement(overrides: Record<string, unknown> = {}): Record<string, unknown> {
    return {
      id: 'gset1',
      groupId: 'g1',
      eventId: 'g1',
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

  test('creator can atomically create a group and matching invite code', async () => {
    await testEnv.clearFirestore();
    const ctx = testEnv.authenticatedContext('owner');
    const db = ctx.firestore();
    const batch = db.batch();
    batch.set(db.doc('groups/new-group'), {
      id: 'new-group',
      name: 'New Group',
      inviteCode: 'NEW123',
      createdBy: 'owner',
      memberIds: ['owner'],
      currency: 'OMR',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    batch.set(db.doc('inviteCodes/NEW123'), {
      groupId: 'new-group',
      createdAt: new Date(),
    });

    await assertSucceeds(batch.commit());
  });

  test('invite codes cannot be read, forged, or deleted by arbitrary users', async () => {
    const eve = testEnv.authenticatedContext('eve').firestore();
    await assertFails(eve.doc('inviteCodes/ABC123').get());
    await assertFails(eve.doc('inviteCodes/HACK99').set({
      groupId: 'g1',
      createdAt: new Date(),
    }));
    await assertFails(eve.doc('inviteCodes/ABC123').delete());
  });

  test('non-member cannot join by directly overwriting memberIds', async () => {
    const eve = testEnv.authenticatedContext('eve').firestore();
    await assertFails(eve.doc('groups/g1').update({
      memberIds: ['owner', 'member', 'eve'],
      updatedAt: new Date(),
    }));
  });

  test('member cannot take ownership, but creator can update metadata', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1').update({
      createdBy: 'member',
      updatedAt: new Date(),
    }));
    await assertFails(member.doc('groups/g1').update({
      name: 'Hijacked',
      updatedAt: new Date(),
    }));

    const owner = testEnv.authenticatedContext('owner').firestore();
    await assertSucceeds(owner.doc('groups/g1').update({
      name: 'Updated Crew',
      currency: 'USD',
      updatedAt: new Date(),
    }));
  });

  test('members can update only their own display name', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/members/member').update({
      displayName: 'New Name',
    }));
    await assertFails(member.doc('groups/g1/members/member').update({
      role: 'CREATOR',
    }));
    await assertFails(member.doc('groups/g1/members/owner').delete());
  });

  test('event immutable fields cannot be tampered with', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1').update({
      createdBy: 'member',
      updatedAt: new Date(),
    }));
  });

  test('expenses require valid participant and positive amount', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/exp1').set(validExpense()));
    await assertFails(member.doc('groups/g1/events/e1/expenses/exp2').set(
      validExpense({ id: 'exp2', amountFils: 0 }),
    ));
    await assertFails(member.doc('groups/g1/events/e1/expenses/exp3').set(
      validExpense({ id: 'exp3', payerParticipantId: 'eve' }),
    ));
  });

  test('expenses allow soft delete but deny hard delete', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    const ref = member.doc('groups/g1/events/e1/expenses/exp1');
    await assertSucceeds(ref.set(validExpense()));
    await assertSucceeds(ref.update({
      isDeleted: true,
      deletedAt: new Date().toISOString(),
    }));
    await assertFails(ref.delete());
  });

  test('event settlements and group settlements validate participants and amount', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/settlements/set1').set(validSettlement()));
    await assertFails(member.doc('groups/g1/events/e1/settlements/set2').set(
      validSettlement({ id: 'set2', recipientParticipantId: 'eve' }),
    ));
    await assertSucceeds(member.doc('groups/g1/settlements/gset1').set(validGroupSettlement()));
    await assertFails(member.doc('groups/g1/settlements/gset2').set(
      validGroupSettlement({ id: 'gset2', amountFils: -1 }),
    ));
  });
});
