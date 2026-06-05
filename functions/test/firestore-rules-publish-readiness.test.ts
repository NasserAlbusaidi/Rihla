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
const [FIRESTORE_HOST, FIRESTORE_PORT] =
  (process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080').split(':');

describe('Publish readiness Firestore rules', () => {
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
      // #190: the create-path producer writes the soft-delete pair; validGroupCreate
      // now requires it.
      isDeleted: false,
      deletedAt: null,
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

  async function updateSeedGroup(overrides: Record<string, unknown>): Promise<void> {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('groups/g1').update(overrides);
    });
  }

  async function updateSeedEvent(overrides: Record<string, unknown>): Promise<void> {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('groups/g1/events/e1').update(overrides);
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
      // #185: the client (settlement_service.dart addSettlement) writes
      // payerName/recipientName on EVERY event settlement. Mirror that here so
      // the suite exercises the real write shape, matching validGroupSettlement.
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
      // #190: producer writes the soft-delete pair (validGroupCreate requires it).
      isDeleted: false,
      deletedAt: null,
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

  test('deletion attempt counters are not readable or writable by clients', async () => {
    const owner = testEnv.authenticatedContext('owner').firestore();
    await assertFails(owner.doc('deletionAttempts/owner').get());
    await assertFails(owner.collection('deletionAttempts').get());
    await assertFails(owner.doc('deletionAttempts/owner').set({
      count: 1,
      windowStart: new Date(),
      expiresAt: new Date(),
    }));
  });

  test('recovery cleanup intent can only be created by the retiring UID with a TTL expiresAt', async () => {
    const owner = testEnv.authenticatedContext('owner').firestore();
    const member = testEnv.authenticatedContext('member').firestore();
    // #170: intents now carry `expiresAt` so a Firestore TTL can reap abandoned
    // bearer-secret docs. The client computes expiresAt = now + 24h (a concrete
    // Timestamp) and writes `createdAt` via serverTimestamp(), which the rules
    // engine resolves to request.time. This package has no client firebase SDK,
    // so we use concrete `new Date()` values — the same `expiresAt > createdAt`
    // comparison the rule enforces, with createdAt as an explicit operand.
    const now = Date.now();
    const day = 24 * 60 * 60 * 1000;
    const validIntent = {
      secret: 'client-generated-secret-with-enough-entropy-12345',
      createdAt: new Date(now),
      expiresAt: new Date(now + day),
    };
    const intent = (overrides: Record<string, unknown>) => ({
      ...validIntent,
      ...overrides,
    });

    // Happy path: create, then overwrite (recovery re-entry rewrites the doc via
    // .set — a fresh expiresAt, never shortening the createdAt-based validity).
    await assertSucceeds(owner.doc('recoveryCleanupIntents/owner').set(validIntent));
    await assertSucceeds(owner.doc('recoveryCleanupIntents/owner').set(intent({
      secret: 'client-generated-secret-with-enough-entropy-67890',
    })));
    // The update verb is also gated by validCleanupIntent (full post-state shape).
    await assertSucceeds(owner.doc('recoveryCleanupIntents/owner').update(intent({})));

    // A different UID cannot write someone else's intent (uid != oldUid).
    await assertFails(member.doc('recoveryCleanupIntents/owner').set(validIntent));

    // #170 (the load-bearing RED): expiresAt is mandatory — a write omitting it
    // is rejected so the TTL always has a field to key on. (.set replaces the
    // doc, so the field is genuinely absent, unlike a merging update.)
    await assertFails(owner.doc('recoveryCleanupIntents/owner').set({
      secret: 'client-generated-secret-with-enough-entropy-12345',
      createdAt: new Date(now),
    }));

    // #170: expiresAt must be after createdAt — a past expiresAt that would make
    // the TTL reap a fresh, still-valid intent immediately is rejected.
    await assertFails(owner.doc('recoveryCleanupIntents/owner').set(
      intent({ expiresAt: new Date(now - 1000) }),
    ));

    // #170: expiresAt must be a timestamp, not another type.
    await assertFails(owner.doc('recoveryCleanupIntents/owner').set(
      intent({ expiresAt: 12345 }),
    ));

    // Secret length bound still enforced (doc id matches uid so this isolates
    // the secret predicate, not the uid check).
    await assertFails(owner.doc('recoveryCleanupIntents/owner').set(
      intent({ secret: 'short' }),
    ));

    // Unknown extra key still rejected (hasOnly admits expiresAt, not newUid).
    await assertFails(owner.doc('recoveryCleanupIntents/owner').set(
      intent({ newUid: 'member' }),
    ));

    // Client can never read or delete the intent directly.
    await assertFails(owner.doc('recoveryCleanupIntents/owner').get());
    await assertFails(owner.doc('recoveryCleanupIntents/owner').delete());
  });

  // #190: group deletion is server-authoritative (deleteGroup callable, Admin
  // SDK). The direct client delete path is locked (`allow delete: if false;`)
  // so the balance-zero gate + soft-delete cascade cannot be bypassed by a
  // tampered client. These two cases were `assertSucceeds` pre-#190 and are
  // flipped to `assertFails` here (spec §8.2 cases 1-2). RED against the
  // current rule (`allow delete: if isCreator();`): the delete SUCCEEDS, so
  // `assertFails` rejects.
  test('creator can NO LONGER client-delete group + member docs + invite code (server-only, #190)', async () => {
    const owner = testEnv.authenticatedContext('owner').firestore();
    const batch = owner.batch();
    batch.delete(owner.doc('groups/g1/members/owner'));
    batch.delete(owner.doc('groups/g1/members/member'));
    batch.delete(owner.doc('inviteCodes/ABC123'));
    batch.delete(owner.doc('groups/g1'));

    await assertFails(batch.commit());
  });

  test('creator can NO LONGER client-delete group when legacy invite code lookup is missing (#190)', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('inviteCodes/ABC123').delete();
    });

    const owner = testEnv.authenticatedContext('owner').firestore();
    const batch = owner.batch();
    batch.delete(owner.doc('groups/g1/members/owner'));
    batch.delete(owner.doc('groups/g1/members/member'));
    batch.delete(owner.doc('inviteCodes/ABC123'));
    batch.delete(owner.doc('groups/g1'));

    await assertFails(batch.commit());
  });

  // #190 §8.2 cases 3-5: the new server-authoritative delete lock + the
  // isDeleted create-path producer gate, folded here from the standalone
  // firestore-rules-delete-group-lock.test.ts (deleted; this is the consolidated
  // owner). RED against current rules: case 3 SUCCEEDS today (creator can
  // delete), `deleteGroupAttempts` does not exist as a server-only match, and
  // `validGroupCreate.hasOnly` rejects `isDeleted`/`deletedAt` so case 5's
  // assertSucceeds fails.
  test('creator cannot client-delete the bare group doc (server-only, #190)', async () => {
    const owner = testEnv.authenticatedContext('owner').firestore();
    await assertFails(owner.doc('groups/g1').delete());
  });

  test('member cannot delete the group doc (#190)', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1').delete());
  });

  test('deleteGroupAttempts counters are not readable or writable by clients (#190)', async () => {
    const owner = testEnv.authenticatedContext('owner').firestore();
    await assertFails(owner.doc('deleteGroupAttempts/owner').get());
    await assertFails(owner.collection('deleteGroupAttempts').get());
    await assertFails(
      owner.doc('deleteGroupAttempts/owner').set({
        count: 1,
        windowStart: new Date(),
        expiresAt: new Date(Date.now() + 60 * 60 * 1000),
      }),
    );
  });

  test('validGroupCreate permits isDeleted:false/deletedAt:null and rejects isDeleted:true on create (#190 HARD REQ #6)', async () => {
    const owner = testEnv.authenticatedContext('owner').firestore();
    const baseGroup = {
      id: 'g-new',
      name: 'Fresh Crew',
      inviteCode: 'NEW123',
      createdBy: 'owner',
      memberIds: ['owner'],
      currency: 'OMR',
      createdAt: new Date(),
      updatedAt: new Date(),
    };

    // Producer fix: createGroup writes isDeleted:false + deletedAt:null. The
    // widened hasOnly + the `isDeleted == false && deletedAt == null` assertion
    // must permit this. RED today: hasOnly rejects the two extra keys.
    await assertSucceeds(
      owner.doc('groups/g-new').set({
        ...baseGroup,
        isDeleted: false,
        deletedAt: null,
      }),
    );

    // A group created already-deleted is forbidden (the producer must write
    // false; soft-delete only happens server-side via the callable update).
    await assertFails(
      owner.doc('groups/g-new-2').set({
        ...baseGroup,
        id: 'g-new-2',
        inviteCode: 'NEW456',
        isDeleted: true,
        deletedAt: new Date(),
      }),
    );
  });

  test('#205 soft-deleted group rejects stale client writes while preserving reads', async () => {
    await updateSeedGroup({
      isDeleted: true,
      deletedAt: new Date(),
      updatedAt: new Date(),
    });

    const owner = testEnv.authenticatedContext('owner').firestore();
    const member = testEnv.authenticatedContext('member').firestore();

    await assertSucceeds(member.doc('groups/g1').get());
    await assertFails(owner.doc('groups/g1').update({
      name: 'Zombie Crew',
      updatedAt: new Date(),
    }));
    await assertFails(owner.doc('groups/g1/events/e-after').set(
      validEvent({
        name: 'After Delete',
        createdBy: 'owner',
        participantIds: ['owner'],
        participantNames: { owner: 'Owner' },
      }),
    ));
    await assertFails(member.doc('groups/g1/members/member').update({
      displayName: 'Late Rename',
    }));
    await assertFails(member.doc('groups/g1/activity/a-after').set({
      id: 'a-after',
      type: 'manual',
      actorId: 'member',
      actorName: 'Member',
      description: 'late activity',
      metadata: {},
      timestamp: new Date().toISOString(),
    }));
    await assertFails(member.doc('groups/g1/settlements/gset-after').set(
      validGroupSettlement({ id: 'gset-after', createdBy: 'member' }),
    ));
  });

  test('#205 soft-deleted event rejects stale event writes while preserving reads', async () => {
    await updateSeedEvent({
      isDeleted: true,
      deletedAt: new Date(),
      updatedAt: new Date(),
    });

    const member = testEnv.authenticatedContext('member').firestore();

    await assertSucceeds(member.doc('groups/g1/events/e1').get());
    await assertFails(member.doc('groups/g1/events/e1').update({
      name: 'Zombie Event',
      updatedAt: new Date(),
    }));
    await assertFails(member.doc('groups/g1/events/e1/expenses/exp-after').set(
      validExpense({ id: 'exp-after', createdBy: 'member' }),
    ));
    await assertFails(member.doc('groups/g1/events/e1/settlements/set-after').set(
      validSettlement({ id: 'set-after', createdBy: 'member' }),
    ));
    await assertFails(member.doc('groups/g1/events/e1/activity_logs/a-after').set({
      id: 'a-after',
      eventId: 'e1',
      category: 'ledger',
      eventType: 'expense.created',
      logText: 'late activity',
      actorId: 'member',
      actorName: 'Member',
      metadata: {},
      createdAt: new Date().toISOString(),
    }));
  });

  test('#205 deleteGroup quiesce marker rejects writes before final isDeleted', async () => {
    await updateSeedGroup({
      isDeleted: false,
      deletingInProgress: true,
      deleteLockedAt: new Date(),
      deleteLockedBy: 'owner',
      updatedAt: new Date(),
    });

    const owner = testEnv.authenticatedContext('owner').firestore();
    const member = testEnv.authenticatedContext('member').firestore();

    await assertSucceeds(member.doc('groups/g1').get());
    await assertFails(owner.doc('groups/g1').update({
      name: 'During Delete',
      updatedAt: new Date(),
    }));
    await assertFails(owner.doc('groups/g1/events/e-during').set(
      validEvent({
        name: 'During Delete',
        createdBy: 'owner',
        participantIds: ['owner'],
        participantNames: { owner: 'Owner' },
      }),
    ));
    await assertFails(member.doc('groups/g1/events/e1/expenses/exp-during').set(
      validExpense({ id: 'exp-during', createdBy: 'member' }),
    ));
    await assertFails(member.doc('groups/g1/events/e1/settlements/set-during').set(
      validSettlement({ id: 'set-during', createdBy: 'member' }),
    ));
    await assertFails(member.doc('groups/g1/settlements/gset-during').set(
      validGroupSettlement({ id: 'gset-during', createdBy: 'member' }),
    ));
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

  test('#191 expenses reject splitDistribution keys outside event participants', async () => {
    const member = testEnv.authenticatedContext('member').firestore();

    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expShares').set(
      validExpense({
        id: 'expShares',
        splitMode: 'shares',
        splitDistribution: { owner: 1, member: 1 },
      }),
    ));

    await assertFails(member.doc('groups/g1/events/e1/expenses/expGhostCreate').set(
      validExpense({
        id: 'expGhostCreate',
        splitMode: 'shares',
        splitDistribution: { owner: 1, ghost: 1 },
      }),
    ));

    const ref = member.doc('groups/g1/events/e1/expenses/expUpdateGhost');
    await assertSucceeds(ref.set(validExpense({ id: 'expUpdateGhost' })));
    await assertFails(ref.update({
      splitMode: 'percent',
      splitDistribution: { owner: 50000, ghost: 50000 },
    }));
  });

  test('#191 stale splitDistribution after participant removal can still be archived', async () => {
    const owner = testEnv.authenticatedContext('owner').firestore();
    const ref = owner.doc('groups/g1/events/e1/expenses/expStale');

    await assertSucceeds(ref.set(validExpense({
      id: 'expStale',
      createdBy: 'owner',
      splitMode: 'shares',
      splitDistribution: { owner: 1, member: 1 },
    })));
    await assertSucceeds(owner.doc('groups/g1/events/e1').update({
      participantIds: ['owner'],
      updatedAt: new Date(),
    }));

    await assertFails(ref.update({
      amountFils: 24000,
    }));
    await assertSucceeds(ref.update({
      note: 'archival note',
    }));
    await assertSucceeds(ref.update({
      isDeleted: true,
      deletedAt: new Date().toISOString(),
    }));
  });

  test('#191 stale payer after participant removal remains soft-delete denied by design', async () => {
    const owner = testEnv.authenticatedContext('owner').firestore();
    const ref = owner.doc('groups/g1/events/e1/expenses/expStalePayer');

    await assertSucceeds(ref.set(validExpense({
      id: 'expStalePayer',
      createdBy: 'owner',
      payerParticipantId: 'member',
      splitMode: 'shares',
      splitDistribution: { owner: 1, member: 1 },
    })));
    await assertSucceeds(owner.doc('groups/g1/events/e1').update({
      participantIds: ['owner'],
      updatedAt: new Date(),
    }));

    // #191 only relaxes unchanged stale splitDistribution keys. The existing
    // payerParticipantId participant guard still re-runs on every update.
    await assertFails(ref.update({
      isDeleted: true,
      deletedAt: new Date().toISOString(),
    }));
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

  // --- #48 shared-settlement-core characterization ---
  // These lock the 9 predicates shared by validEventSettlementBase and
  // validGroupSettlementBase. They must be green BEFORE the validSettlementCore
  // extraction (current behavior) and stay green AFTER (preservation proof).
  // Each negative doc is otherwise-valid so the only failing predicate is the
  // one under test (assertFails reports permission-denied, not the reason).

  test('settlement rejects non-positive amount in both scopes', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/settlements/setZero').set(
      validSettlement({ id: 'setZero', amountFils: 0 }),
    ));
    await assertFails(member.doc('groups/g1/events/e1/settlements/setNeg').set(
      validSettlement({ id: 'setNeg', amountFils: -1 }),
    ));
    await assertFails(member.doc('groups/g1/settlements/gsetZero').set(
      validGroupSettlement({ id: 'gsetZero', amountFils: 0 }),
    ));
    await assertFails(member.doc('groups/g1/settlements/gsetNeg').set(
      validGroupSettlement({ id: 'gsetNeg', amountFils: -1 }),
    ));
  });

  test('settlement rejects invalid currency type and length in both scopes', async () => {
    // validCurrency (rules:48) only checks `is string && size() == 3`, so a bogus
    // 3-letter code like 'ZZZ' PASSES by design (see #48 plan, Gate [P2]). We
    // assert only the two real rejections: non-string, and wrong length.
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/settlements/setCurType').set(
      validSettlement({ id: 'setCurType', currency: 123 }),
    ));
    await assertFails(member.doc('groups/g1/events/e1/settlements/setCurLen').set(
      validSettlement({ id: 'setCurLen', currency: 'US' }),
    ));
    await assertFails(member.doc('groups/g1/settlements/gsetCurType').set(
      validGroupSettlement({ id: 'gsetCurType', currency: 123 }),
    ));
    await assertFails(member.doc('groups/g1/settlements/gsetCurLen').set(
      validGroupSettlement({ id: 'gsetCurLen', currency: 'EURO' }),
    ));
  });

  test('settlement rejects payer equal to recipient in both scopes', async () => {
    // 'owner' is a valid participant (event) and member (group) in both scopes,
    // so the only failing predicate is payerParticipantId != recipientParticipantId.
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/settlements/setSelf').set(
      validSettlement({ id: 'setSelf', payerParticipantId: 'owner', recipientParticipantId: 'owner' }),
    ));
    await assertFails(member.doc('groups/g1/settlements/gsetSelf').set(
      validGroupSettlement({ id: 'gsetSelf', payerParticipantId: 'owner', recipientParticipantId: 'owner' }),
    ));
  });

  test('settlement rejects non-string note in both scopes', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/settlements/setNote').set(
      validSettlement({ id: 'setNote', note: 123 }),
    ));
    await assertFails(member.doc('groups/g1/settlements/gsetNote').set(
      validGroupSettlement({ id: 'gsetNote', note: 123 }),
    ));
  });

  test('settlement rejects missing settledAt in both scopes', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/settlements/setNoSettledAt').set(
      withoutField(validSettlement({ id: 'setNoSettledAt' }), 'settledAt'),
    ));
    await assertFails(member.doc('groups/g1/settlements/gsetNoSettledAt').set(
      withoutField(validGroupSettlement({ id: 'gsetNoSettledAt' }), 'settledAt'),
    ));
  });

  // --- #48 scope-shape characterization ---
  // These stay OUT of validSettlementCore but are touched by the edit. They prove
  // keys().hasOnly and the group-only predicates remain in the per-scope validators.

  test('settlement rejects unknown extra key in both scopes', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/settlements/setExtra').set(
      validSettlement({ id: 'setExtra', surprise: 'x' }),
    ));
    await assertFails(member.doc('groups/g1/settlements/gsetExtra').set(
      validGroupSettlement({ id: 'gsetExtra', surprise: 'x' }),
    ));
  });

  test('group settlement rejects eventId not equal to groupId (sentinel lock for #71)', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/settlements/gsetBadEventId').set(
      validGroupSettlement({ id: 'gsetBadEventId', eventId: 'e1' }),
    ));
  });

  test('group settlement rejects scope other than group', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/settlements/gsetBadScope').set(
      validGroupSettlement({ id: 'gsetBadScope', scope: 'personal' }),
    ));
  });

  test('group settlement rejects invalid payer and recipient display names', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/settlements/gsetCtrlPayer').set(
      validGroupSettlement({ id: 'gsetCtrlPayer', payerName: 'Bad\nName' }),
    ));
    await assertFails(member.doc('groups/g1/settlements/gsetLongRecipient').set(
      validGroupSettlement({ id: 'gsetLongRecipient', recipientName: 'A'.repeat(33) }),
    ));
  });

  // --- #185 event-settlement display-name parity ---
  // validEventSettlementBase omitted payerName/recipientName from hasOnly while
  // the client writes them on every event settlement -> PERMISSION_DENIED, event
  // settle-up broken. These lock the event rule to the group rule's name handling.

  test('event settlement create accepts the full client key-set incl payer/recipient names', async () => {
    // Regression lock for #185: built from settlement_service.dart addSettlement's
    // exact key-set, independent of the validSettlement() builder so a future
    // builder refactor cannot silently drop this coverage.
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/settlements/setNames').set({
      id: 'setNames',
      eventId: 'e1',
      payerParticipantId: 'member',
      recipientParticipantId: 'owner',
      payerName: 'Member',
      recipientName: 'Owner',
      amountFils: 5000,
      currency: 'OMR',
      note: null,
      isDeleted: false,
      deletedAt: null,
      settledAt: new Date().toISOString(),
      createdBy: 'member',
    }));
  });

  test('event settlement accepts null payer and recipient display names', async () => {
    // Pre-name-field docs and name-less rows render as 'Someone'; null must stay
    // allowed via isValidNullableDisplayName.
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/settlements/setNullNames').set(
      validSettlement({ id: 'setNullNames', payerName: null, recipientName: null }),
    ));
  });

  test('event settlement rejects invalid payer and recipient display names', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/settlements/setCtrlPayer').set(
      validSettlement({ id: 'setCtrlPayer', payerName: 'Bad\nName' }),
    ));
    await assertFails(member.doc('groups/g1/events/e1/settlements/setLongRecipient').set(
      validSettlement({ id: 'setLongRecipient', recipientName: 'A'.repeat(33) }),
    ));
  });

  // ===========================================================================
  // #192 — splitDistribution value-domain: non-negative integers only.
  // Spec: docs/plans/2026-06-02-rules-value-domain-hardening.md
  // The check is enforced in the create/update wrappers (unconditional on
  // create, diff-gated on update) so a legacy/forged negative doc stays
  // soft-deletable. Today rules only check `splitDistribution is map`.
  // ===========================================================================
  test('#192 expense create with valid non-negative shares splitDistribution is allowed', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expPos').set(
      validExpense({ id: 'expPos', splitMode: 'shares', splitDistribution: { owner: 2, member: 3 } }),
    ));
  });

  test('#192 expense create with a negative splitDistribution value is denied', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/expenses/expNeg').set(
      validExpense({ id: 'expNeg', splitMode: 'shares', splitDistribution: { owner: 2, member: -3 } }),
    ));
  });

  test('#192 expense create with an empty splitDistribution map is allowed (preserved)', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expEmpty').set(
      validExpense({ id: 'expEmpty', splitMode: 'shares', splitDistribution: {} }),
    ));
  });

  test('#192 expense update that re-sends a negative splitDistribution is denied', async () => {
    await seedExpense({ id: 'expU', createdBy: 'member', splitMode: 'shares', splitDistribution: { owner: 2, member: 3 } });
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/expenses/expU').update({
      splitDistribution: { owner: 5, member: -2 },
    }));
  });

  test('#192 soft-delete of a legacy expense with a negative splitDistribution is still allowed (no regression)', async () => {
    await seedExpense({ id: 'expDel', createdBy: 'member', splitMode: 'shares', splitDistribution: { owner: 2, member: -3 } });
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expDel').update({
      isDeleted: true,
      deletedAt: new Date().toISOString(),
    }));
  });

  // ===========================================================================
  // #193 — settlement currency: allow-list (matches MoneySerializer scale keys)
  // + group-settlement cross-currency equality with the owning group.
  // Event-settlement cross-currency equality is DEFERRED to #61 (event
  // settle-up hardcodes 'OMR'; the equality would be a tautology-today /
  // landmine-tomorrow). Today validCurrency only checks `size() == 3`.
  // ===========================================================================
  test('#193 event settlement with a supported currency is allowed', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/settlements/setOmr').set(
      validSettlement({ id: 'setOmr', currency: 'OMR' }),
    ));
  });

  test('#193 event settlement with an unsupported 3-char currency is denied', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/settlements/setXyz').set(
      validSettlement({ id: 'setXyz', currency: 'XYZ' }),
    ));
  });

  test('#193 event settlement with a lowercase currency code is denied', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/settlements/setLower').set(
      validSettlement({ id: 'setLower', currency: 'omr' }),
    ));
  });

  test('#193 group settlement with currency matching the group currency is allowed', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/settlements/gsetMatch').set(
      validGroupSettlement({ id: 'gsetMatch', currency: 'OMR' }),
    ));
  });

  test('#193 group settlement with a supported-but-divergent currency is denied', async () => {
    // Group g1 currency is OMR; USD is in the allow-list but mismatches the group.
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/settlements/gsetUsd').set(
      validGroupSettlement({ id: 'gsetUsd', currency: 'USD' }),
    ));
  });

  test('#193 event settlement with a divergent supported currency is allowed (cross-currency equality deferred to #61)', async () => {
    // Documents the deliberate deferral: event settle-up hardcodes OMR, so the
    // event-side equality would be a tautology until #61 lands multi-currency.
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/settlements/setUsd').set(
      validSettlement({ id: 'setUsd', currency: 'USD' }),
    ));
  });

  // ===========================================================================
  // #194 — free text (note/description/categoryId/receiptUrl/subGroupId):
  // bounded (<=280) + control-char-free. Enforced in create wrappers
  // (unconditional) and the expense update wrapper (diff-gated). Settlements
  // are append-only (no update path) so settlement note is create-only.
  // Today these fields pass bare `nullableString` (type only).
  // ===========================================================================
  test('#194 expense create with a normal description is allowed', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expDesc').set(
      validExpense({ id: 'expDesc', description: 'Team dinner at the souq' }),
    ));
  });

  test('#194 expense create with a control character in description is denied', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/expenses/expCtrl').set(
      validExpense({ id: 'expCtrl', description: 'line1\nline2' }),
    ));
  });

  test('#194 expense create with a description over 280 chars is denied', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/expenses/expLong').set(
      validExpense({ id: 'expLong', description: 'a'.repeat(281) }),
    ));
  });

  test('#194 event settlement create with a control character in note is denied', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/settlements/setNote').set(
      validSettlement({ id: 'setNote', note: 'paid\nback' }),
    ));
  });

  test('#194 event settlement create with a note over 280 chars is denied', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/settlements/setNoteLong').set(
      validSettlement({ id: 'setNoteLong', note: 'a'.repeat(281) }),
    ));
  });

  test('#194 group settlement create with a control character in note is denied', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/settlements/gsetNote').set(
      validGroupSettlement({ id: 'gsetNote', note: 'a\tb' }),
    ));
  });

  test('#194 expense update that changes description to a control-char value is denied', async () => {
    await seedExpense({ id: 'expEdit', createdBy: 'member' });
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/expenses/expEdit').update({
      description: 'bad\nvalue',
    }));
  });

  test('#194 soft-delete of a legacy expense with an over-280 description is still allowed (no regression)', async () => {
    await seedExpense({ id: 'expLongDel', createdBy: 'member', description: 'a'.repeat(500) });
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expLongDel').update({
      isDeleted: true,
      deletedAt: new Date().toISOString(),
    }));
  });
});
