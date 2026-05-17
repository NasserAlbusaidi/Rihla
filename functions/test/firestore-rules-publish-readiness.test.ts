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

  function validGroup(groupId: string, overrides: Record<string, unknown> = {}): Record<string, unknown> {
    return {
      id: groupId,
      name: 'New Group',
      inviteCode: `${groupId.toUpperCase()}123`,
      createdBy: 'owner',
      memberIds: ['owner'],
      currency: 'OMR',
      createdAt: new Date(),
      updatedAt: new Date(),
      ...overrides,
    };
  }

  async function addGroupMember(userId: string, displayName = userId): Promise<void> {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      const groupRef = db.doc('groups/g1');
      const groupSnap = await groupRef.get();
      const group = groupSnap.data() as { memberIds: string[] };
      const memberIds = group.memberIds.includes(userId)
        ? group.memberIds
        : [...group.memberIds, userId];

      await groupRef.update({
        memberIds,
        updatedAt: new Date(),
      });
      await db.doc(`groups/g1/members/${userId}`).set({
        id: userId,
        userId,
        displayName,
        role: 'MEMBER',
        joinedAt: new Date(),
        isShadow: false,
      });
    });
  }

  async function seedEvent(eventId: string, overrides: Record<string, unknown>): Promise<void> {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`groups/g1/events/${eventId}`).set(validEvent(overrides));
    });
  }

  function validExpense(overrides: Record<string, unknown> = {}): Record<string, unknown> {
    return {
      id: 'exp1',
      eventId: 'e1',
      createdBy: 'member',
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
      createdBy: 'member',
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

  function withoutField(data: Record<string, unknown>, field: string): Record<string, unknown> {
    const copy = { ...data };
    delete copy[field];
    return copy;
  }

  async function seedExpense(overrides: Record<string, unknown> = {}): Promise<void> {
    const data = validExpense({ createdBy: 'owner', ...overrides });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`groups/g1/events/e1/expenses/${data.id}`).set(data);
    });
  }

  async function seedEventSettlement(overrides: Record<string, unknown> = {}): Promise<void> {
    const data = validSettlement({ createdBy: 'owner', ...overrides });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`groups/g1/events/e1/settlements/${data.id}`).set(data);
    });
  }

  async function seedGroupSettlement(overrides: Record<string, unknown> = {}): Promise<void> {
    const data = validGroupSettlement({ createdBy: 'owner', ...overrides });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`groups/g1/settlements/${data.id}`).set(data);
    });
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

  test('group create accepts valid display name boundaries', async () => {
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertSucceeds(owner.doc('groups/group-one-char').set(
      validGroup('group-one-char', {
        name: 'A',
        inviteCode: 'ONE123',
      }),
    ));
    await assertSucceeds(owner.doc('groups/group-thirty-two').set(
      validGroup('group-thirty-two', {
        name: 'A'.repeat(32),
        inviteCode: 'THIRTY2',
      }),
    ));
    await assertSucceeds(owner.doc('groups/group-reserved-prefix').set(
      validGroup('group-reserved-prefix', {
        name: '(former member) Aisha',
        inviteCode: 'PREFX1',
      }),
    ));
    await assertSucceeds(owner.doc('groups/group-reserved-middle').set(
      validGroup('group-reserved-middle', {
        name: 'Aisha (former member) Al Busaidi',
        inviteCode: 'MIDL01',
      }),
    ));
  });

  test('group create rejects empty, overlong, and control-character names', async () => {
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertFails(owner.doc('groups/group-empty').set(
      validGroup('group-empty', {
        name: '',
        inviteCode: 'EMPTY0',
      }),
    ));
    await assertFails(owner.doc('groups/group-thirty-three').set(
      validGroup('group-thirty-three', {
        name: 'A'.repeat(33),
        inviteCode: 'THIRTY3',
      }),
    ));
    await assertFails(owner.doc('groups/group-newline').set(
      validGroup('group-newline', {
        name: 'Line\nBreak',
        inviteCode: 'NEWLINE',
      }),
    ));
    await assertFails(owner.doc('groups/group-null-byte').set(
      validGroup('group-null-byte', {
        name: 'Null\x00Byte',
        inviteCode: 'NULLBYT',
      }),
    ));
    await assertFails(owner.doc('groups/group-reserved-suffix').set(
      validGroup('group-reserved-suffix', {
        name: 'Aisha (former member)',
        inviteCode: 'SUFFIX',
      }),
    ));
  });

  test('group update rejects whitespace-only display name', async () => {
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertFails(owner.doc('groups/g1').update({
      name: '   ',
      updatedAt: new Date(),
    }));
  });

  test('invite codes cannot be read, listed, forged, or deleted by arbitrary users', async () => {
    const eve = testEnv.authenticatedContext('eve').firestore();
    await assertFails(eve.doc('inviteCodes/ABC123').get());
    await assertFails(eve.collection('inviteCodes').get());
    await assertFails(eve.doc('inviteCodes/HACK99').set({
      groupId: 'g1',
      createdAt: new Date(),
    }));
    await assertFails(eve.doc('inviteCodes/ABC123').delete());
  });

  test('join attempt counters are not readable or writable by clients', async () => {
    const owner = testEnv.authenticatedContext('owner').firestore();
    await assertFails(owner.doc('joinAttempts/owner').get());
    await assertFails(owner.collection('joinAttempts').get());
    await assertFails(owner.doc('joinAttempts/owner').set({
      failCount: 1,
      firstFailAt: new Date(),
      lockedUntil: null,
    }));
  });

  test('creator can atomically delete group, member docs, and invite code', async () => {
    const owner = testEnv.authenticatedContext('owner').firestore();
    const batch = owner.batch();
    batch.delete(owner.doc('groups/g1/members/owner'));
    batch.delete(owner.doc('groups/g1/members/member'));
    batch.delete(owner.doc('inviteCodes/ABC123'));
    batch.delete(owner.doc('groups/g1'));

    await assertSucceeds(batch.commit());
  });

  test('creator can delete group when legacy invite code lookup is missing', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('inviteCodes/ABC123').delete();
    });

    const owner = testEnv.authenticatedContext('owner').firestore();
    const batch = owner.batch();
    batch.delete(owner.doc('groups/g1/members/owner'));
    batch.delete(owner.doc('groups/g1/members/member'));
    batch.delete(owner.doc('inviteCodes/ABC123'));
    batch.delete(owner.doc('groups/g1'));

    await assertSucceeds(batch.commit());
  });

  test('non-member cannot add another user or drop existing members while joining', async () => {
    const eve = testEnv.authenticatedContext('eve').firestore();
    await assertFails(eve.doc('groups/g1').update({
      memberIds: ['owner', 'member', 'mallory'],
      updatedAt: new Date(),
    }));
    await assertFails(eve.doc('groups/g1').update({
      memberIds: ['owner', 'eve'],
      updatedAt: new Date(),
    }));
  });

  test('non-member cannot self-join through direct Firestore writes', async () => {
    const eve = testEnv.authenticatedContext('eve').firestore();
    await assertFails(eve.doc('inviteCodes/ABC123').get());

    await assertFails(eve.doc('groups/g1').update({
      memberIds: ['owner', 'member', 'eve'],
      updatedAt: new Date(),
    }));
    await assertFails(eve.doc('groups/g1/members/eve').set({
      id: 'eve',
      userId: 'eve',
      displayName: 'Eve',
      role: 'MEMBER',
      joinedAt: new Date(),
      isShadow: false,
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

  test('participant can rename event', async () => {
    const member = testEnv.authenticatedContext('member').firestore();

    await assertSucceeds(member.doc('groups/g1/events/e1').update({
      name: 'Updated Camp',
      description: 'Bring warm layers.',
      updatedAt: new Date(),
    }));
  });

  test('event create accepts valid participant display names', async () => {
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertSucceeds(owner.doc('groups/g1/events/e-valid-name').set(
      validEvent({
        name: 'A',
        createdBy: 'owner',
        participantIds: ['owner'],
        participantNames: { owner: 'Owner' },
      }),
    ));
    await assertSucceeds(owner.doc('groups/g1/events/e-valid-reserved-middle').set(
      validEvent({
        name: 'A',
        createdBy: 'owner',
        participantIds: ['owner'],
        participantNames: { owner: '(former member) Owner' },
      }),
    ));
  });

  test('event create rejects invalid participant display names', async () => {
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertFails(owner.doc('groups/g1/events/e-empty-name').set(
      validEvent({
        createdBy: 'owner',
        participantIds: ['owner', 'member'],
        participantNames: { owner: 'Owner', member: '' },
      }),
    ));
    await assertFails(owner.doc('groups/g1/events/e-overlong-name').set(
      validEvent({
        createdBy: 'owner',
        participantIds: ['owner', 'member'],
        participantNames: { owner: 'Owner', member: 'A'.repeat(33) },
      }),
    ));
    await assertFails(owner.doc('groups/g1/events/e-control-name').set(
      validEvent({
        createdBy: 'owner',
        participantIds: ['owner', 'member'],
        participantNames: { owner: 'Owner', member: 'Bad\nName' },
      }),
    ));
    await assertFails(owner.doc('groups/g1/events/e-reserved-suffix-name').set(
      validEvent({
        createdBy: 'owner',
        participantIds: ['owner', 'member'],
        participantNames: { owner: 'Owner', member: 'Aisha (former member)' },
      }),
    ));
  });

  test('participant can shift event dates', async () => {
    const member = testEnv.authenticatedContext('member').firestore();

    await assertSucceeds(member.doc('groups/g1/events/e1').update({
      startDate: new Date('2026-01-15T08:00:00.000Z'),
      endDate: new Date('2026-01-17T18:00:00.000Z'),
      updatedAt: new Date(),
    }));
  });

  test('participant can add another participant', async () => {
    await addGroupMember('guest', 'Guest');
    const member = testEnv.authenticatedContext('member').firestore();

    await assertSucceeds(member.doc('groups/g1/events/e1').update({
      participantIds: ['owner', 'member', 'guest'],
      participantNames: { owner: 'Owner', member: 'Member', guest: 'Guest' },
      updatedAt: new Date(),
    }));
  });

  test('participant cannot remove a participant', async () => {
    const member = testEnv.authenticatedContext('member').firestore();

    await assertFails(member.doc('groups/g1/events/e1').update({
      participantIds: ['member'],
      updatedAt: new Date(),
    }));
  });

  test('participant cannot rename a peer', async () => {
    const member = testEnv.authenticatedContext('member').firestore();

    await assertFails(member.doc('groups/g1/events/e1').update({
      participantNames: { owner: 'Renamed Owner', member: 'Member' },
      updatedAt: new Date(),
    }));
  });

  test('participant cannot toggle event modules', async () => {
    const member = testEnv.authenticatedContext('member').firestore();

    await assertFails(member.doc('groups/g1/events/e1').update({
      modules: { ledger: false },
      updatedAt: new Date(),
    }));
  });

  test('participant cannot soft-delete event', async () => {
    const member = testEnv.authenticatedContext('member').firestore();

    await assertFails(member.doc('groups/g1/events/e1').update({
      isDeleted: true,
      deletedAt: new Date(),
      updatedAt: new Date(),
    }));
  });

  test('event creator can remove a participant', async () => {
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertSucceeds(owner.doc('groups/g1/events/e1').update({
      participantIds: ['owner'],
      updatedAt: new Date(),
    }));
  });

  test('event creator can soft-delete event', async () => {
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertSucceeds(owner.doc('groups/g1/events/e1').update({
      isDeleted: true,
      deletedAt: new Date(),
      updatedAt: new Date(),
    }));
  });

  test('group creator can soft-delete an event they did not create or join', async () => {
    await seedEvent('e2', {
      createdBy: 'member',
      participantIds: ['member'],
      participantNames: { member: 'Member' },
    });
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertSucceeds(owner.doc('groups/g1/events/e2').update({
      isDeleted: true,
      deletedAt: new Date(),
      updatedAt: new Date(),
    }));
  });

  test('group creator can remove a participant from an event they did not create', async () => {
    await addGroupMember('peer', 'Peer');
    await seedEvent('e2', {
      createdBy: 'member',
      participantIds: ['member', 'peer'],
      participantNames: { member: 'Member', peer: 'Peer' },
    });
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertSucceeds(owner.doc('groups/g1/events/e2').update({
      participantIds: ['member'],
      participantNames: { member: 'Member' },
      updatedAt: new Date(),
    }));
  });

  test('random group member who is not participant or creator cannot update event', async () => {
    await addGroupMember('peer', 'Peer');
    const peer = testEnv.authenticatedContext('peer').firestore();

    await assertFails(peer.doc('groups/g1/events/e1').update({
      name: 'Peer Edit',
      updatedAt: new Date(),
    }));
  });

  test('soft-delete cannot be undone', async () => {
    await seedEvent('e1', {
      isDeleted: true,
      deletedAt: new Date(),
    });
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertFails(owner.doc('groups/g1/events/e1').update({
      isDeleted: false,
      deletedAt: null,
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

  test('expenses allow valid custom splits and reject unknown split modes', async () => {
    const member = testEnv.authenticatedContext('member').firestore();

    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expCustom').set(
      validExpense({
        id: 'expCustom',
        splitMode: 'exact',
        splitDistribution: { owner: 1234 },
      }),
    ));

    const ref = member.doc('groups/g1/events/e1/expenses/exp1');
    await assertSucceeds(ref.set(validExpense()));
    await assertSucceeds(ref.update({
      splitMode: 'percent',
      splitDistribution: { owner: 50, member: 50 },
    }));

    await assertFails(member.doc('groups/g1/events/e1/expenses/expInvalid').set(
      validExpense({
        id: 'expInvalid',
        splitMode: 'totally_made_up',
        splitDistribution: { owner: 1234 },
      }),
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

  test('expense creator can update own record', async () => {
    await seedExpense();
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertSucceeds(owner.doc('groups/g1/events/e1/expenses/exp1').update({
      amountFils: 12500,
    }));
  });

  test('expense non-creator cannot update peer record', async () => {
    await seedExpense();
    const member = testEnv.authenticatedContext('member').firestore();

    await assertFails(member.doc('groups/g1/events/e1/expenses/exp1').update({
      amountFils: 12500,
    }));
  });

  test('expense non-creator cannot soft-delete peer record', async () => {
    await seedExpense();
    const member = testEnv.authenticatedContext('member').firestore();

    await assertFails(member.doc('groups/g1/events/e1/expenses/exp1').update({
      isDeleted: true,
      deletedAt: new Date().toISOString(),
    }));
  });

  test('expense create without createdBy is rejected', async () => {
    const member = testEnv.authenticatedContext('member').firestore();

    await assertFails(member.doc('groups/g1/events/e1/expenses/expMissingCreator').set(
      withoutField(validExpense({ id: 'expMissingCreator' }), 'createdBy'),
    ));
  });

  test('expense create with mismatched createdBy is rejected', async () => {
    const member = testEnv.authenticatedContext('member').firestore();

    await assertFails(member.doc('groups/g1/events/e1/expenses/expWrongCreator').set(
      validExpense({ id: 'expWrongCreator', createdBy: 'owner' }),
    ));
  });

  test('expense update cannot mutate createdBy', async () => {
    await seedExpense();
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertFails(owner.doc('groups/g1/events/e1/expenses/exp1').update({
      createdBy: 'member',
    }));
  });

  test('expense creator can soft-delete own record', async () => {
    await seedExpense();
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertSucceeds(owner.doc('groups/g1/events/e1/expenses/exp1').update({
      isDeleted: true,
      deletedAt: new Date().toISOString(),
    }));
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

  test('new settlement creates with createdBy stamps still succeed', async () => {
    const member = testEnv.authenticatedContext('member').firestore();

    await assertSucceeds(member.doc('groups/g1/events/e1/settlements/setB3').set(
      validSettlement({ id: 'setB3', createdBy: 'member' }),
    ));
    await assertSucceeds(member.doc('groups/g1/settlements/gsetB3').set(
      validGroupSettlement({ id: 'gsetB3', createdBy: 'member' }),
    ));
  });

  test('event settlement creator cannot update own record', async () => {
    await seedEventSettlement();
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertFails(owner.doc('groups/g1/events/e1/settlements/set1').update({
      note: 'Settled after dinner',
    }));
  });

  test('event settlement non-creator cannot update peer record', async () => {
    await seedEventSettlement();
    const member = testEnv.authenticatedContext('member').firestore();

    await assertFails(member.doc('groups/g1/events/e1/settlements/set1').update({
      note: 'Hijacked note',
    }));
  });

  test('event settlement non-creator cannot soft-delete peer record', async () => {
    await seedEventSettlement();
    const member = testEnv.authenticatedContext('member').firestore();

    await assertFails(member.doc('groups/g1/events/e1/settlements/set1').update({
      isDeleted: true,
      deletedAt: new Date().toISOString(),
    }));
  });

  test('event settlement create without createdBy is rejected', async () => {
    const member = testEnv.authenticatedContext('member').firestore();

    await assertFails(member.doc('groups/g1/events/e1/settlements/setMissingCreator').set(
      withoutField(validSettlement({ id: 'setMissingCreator' }), 'createdBy'),
    ));
  });

  test('event settlement creator cannot delete own record', async () => {
    await seedEventSettlement();
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertFails(owner.doc('groups/g1/events/e1/settlements/set1').delete());
  });

  test('group settlement creator cannot update own record', async () => {
    await seedGroupSettlement();
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertFails(owner.doc('groups/g1/settlements/gset1').update({
      note: 'Settled at group level',
    }));
  });

  test('group settlement non-creator cannot update peer record', async () => {
    await seedGroupSettlement();
    const member = testEnv.authenticatedContext('member').firestore();

    await assertFails(member.doc('groups/g1/settlements/gset1').update({
      note: 'Hijacked group note',
    }));
  });

  test('group settlement non-creator cannot soft-delete peer record', async () => {
    await seedGroupSettlement();
    const member = testEnv.authenticatedContext('member').firestore();

    await assertFails(member.doc('groups/g1/settlements/gset1').update({
      isDeleted: true,
      deletedAt: new Date().toISOString(),
    }));
  });

  test('group settlement create without createdBy is rejected', async () => {
    const member = testEnv.authenticatedContext('member').firestore();

    await assertFails(member.doc('groups/g1/settlements/gsetMissingCreator').set(
      withoutField(validGroupSettlement({ id: 'gsetMissingCreator' }), 'createdBy'),
    ));
  });

  test('group settlement update cannot mutate createdBy', async () => {
    await seedGroupSettlement();
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertFails(owner.doc('groups/g1/settlements/gset1').update({
      createdBy: 'member',
    }));
  });

  test('group settlement creator cannot delete own record', async () => {
    await seedGroupSettlement();
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertFails(owner.doc('groups/g1/settlements/gset1').delete());
  });
});
