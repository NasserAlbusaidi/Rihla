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

  // #441: money data must never be born under a discardable anonymous UID.
  // Anonymous-provider tokens are rejected on group + inviteCode creation;
  // every other provider (incl. the option-less default 'custom' used by the
  // tests above) passes.
  describe('#441 durable-credential gate on group creation', () => {
    function groupCreatePayload(uid: string, groupId: string, code: string) {
      return {
        id: groupId,
        name: 'Gate Group',
        inviteCode: code,
        createdBy: uid,
        memberIds: [uid],
        currency: 'OMR',
        createdAt: new Date(),
        updatedAt: new Date(),
        isDeleted: false,
        deletedAt: null,
      };
    }

    test('anonymous provider cannot create a group (even valid-shaped)', async () => {
      await testEnv.clearFirestore();
      const anon = testEnv.authenticatedContext('anon-uid', {
        firebase: { sign_in_provider: 'anonymous' },
      });

      await assertFails(
        anon
          .firestore()
          .doc('groups/anon-group')
          .set(groupCreatePayload('anon-uid', 'anon-group', 'ANON12')),
      );
    });

    test('anonymous provider cannot create the group + inviteCode batch', async () => {
      await testEnv.clearFirestore();
      const anon = testEnv.authenticatedContext('anon-uid', {
        firebase: { sign_in_provider: 'anonymous' },
      });
      const db = anon.firestore();
      const batch = db.batch();
      batch.set(
        db.doc('groups/anon-group'),
        groupCreatePayload('anon-uid', 'anon-group', 'ANON12'),
      );
      batch.set(db.doc('inviteCodes/ANON12'), {
        groupId: 'anon-group',
        createdAt: new Date(),
      });

      await assertFails(batch.commit());
    });

    test('google.com provider can create the group + inviteCode batch', async () => {
      await testEnv.clearFirestore();
      const linked = testEnv.authenticatedContext('google-uid', {
        firebase: { sign_in_provider: 'google.com' },
      });
      const db = linked.firestore();
      const batch = db.batch();
      batch.set(
        db.doc('groups/linked-group'),
        groupCreatePayload('google-uid', 'linked-group', 'LINK12'),
      );
      batch.set(db.doc('inviteCodes/LINK12'), {
        groupId: 'linked-group',
        createdAt: new Date(),
      });

      await assertSucceeds(batch.commit());
    });
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

  test('display-name length counts UTF-16 code units, not code points (#527 refuted)', async () => {
    // Verified against the Firestore rules emulator (2026-06-19): isValidDisplayName
    // gates on `s.size() <= 32`, and string.size() counts UTF-16 code units, NOT
    // Unicode code points. A 2-unit astral emoji (U+1F389) costs 2 toward the cap:
    // 16 emoji = 32 units (accepted); 17 emoji = 34 units (rejected).
    //
    // This REFUTES #527's premise that size() is code-point-based. The client
    // validator (lib/core/utils/name_validators.dart) uses Dart String.length,
    // which ALSO counts UTF-16 units — so client and server already agree.
    // Switching the client to runes.length (code points) would make it ACCEPT
    // names the server REJECTS (permission-denied on 17+ astral chars). Do not
    // "align" the two to code points; they are already aligned on UTF-16 units.
    const owner = testEnv.authenticatedContext('owner').firestore();
    await assertSucceeds(owner.doc('groups/g-emoji-16').set(
      validGroup('g-emoji-16', { name: '\u{1F389}'.repeat(16), inviteCode: 'EMOJI16' }),
    ));
    await assertFails(owner.doc('groups/g-emoji-17').set(
      validGroup('g-emoji-17', { name: '\u{1F389}'.repeat(17), inviteCode: 'EMOJI17' }),
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

  // #278 claim/merge (PR8): claimRequests is fully callable-mediated
  // (`allow read, write: if false`). Unlike the other group subcollections it is
  // NOT member-gated — even `owner` (a member AND the creator of g1) must be
  // denied both read and write. A client read would need a non-member carve-out
  // (the requester is pre-join, D8); a client write would forge an approval.
  test('#278 claim requests are not readable or writable by clients (even a member/creator)', async () => {
    const owner = testEnv.authenticatedContext('owner').firestore();
    await assertFails(owner.doc('groups/g1/claimRequests/owner__shadow').get());
    await assertFails(owner.collection('groups/g1/claimRequests').get());
    await assertFails(owner.doc('groups/g1/claimRequests/owner__shadow').set({
      requesterUid: 'owner',
      requesterDisplayName: 'Owner',
      shadowMemberId: 'shadow',
      shadowDisplayName: 'Ali',
      status: 'pending',
    }));
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

  test('member can NO LONGER client self-leave — server-only via leaveGroup (#290)', async () => {
    // The full self-leave batch (drop self from memberIds + delete own member
    // doc) is rejected: `validSelfLeave` was removed from group `allow update`.
    const member = testEnv.authenticatedContext('member').firestore();
    const batch = member.batch();
    batch.update(member.doc('groups/g1'), {
      memberIds: ['owner'],
      updatedAt: new Date(),
    });
    batch.delete(member.doc('groups/g1/members/member'));
    await assertFails(batch.commit());
  });

  test('member cannot self-delete their member doc without the (now-blocked) memberIds drop (#290)', async () => {
    // Lone member-doc delete: validMemberDelete self-branch needs
    // !(uid in memberIds-after), but memberIds is unchanged here → denied.
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/members/member').delete());
  });

  test('creator can NO LONGER client-remove another member — server-only via removeMember (#318)', async () => {
    // #318: validCreatorRemoveMember was dropped from group `allow update`. The
    // full creator-remove batch (drop target from memberIds + delete the target
    // member doc) is now rejected — creator-remove is server-authoritative.
    const owner = testEnv.authenticatedContext('owner').firestore();
    const batch = owner.batch();
    batch.update(owner.doc('groups/g1'), {
      memberIds: ['owner'],
      updatedAt: new Date(),
    });
    batch.delete(owner.doc('groups/g1/members/member'));
    await assertFails(batch.commit());
  });

  test('creator cannot lone-delete another member doc without the (now-blocked) memberIds drop (#318)', async () => {
    // validMemberDelete CREATOR branch needs !(target in memberIds-after); the
    // memberIds drop is the only way to satisfy it and it is now forbidden, so a
    // lone member-doc delete is denied. Byte-for-byte the #290 argument via the
    // CREATOR branch (758-760, 800-802).
    const owner = testEnv.authenticatedContext('owner').firestore();
    await assertFails(owner.doc('groups/g1/members/member').delete());
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

  test('#524 a member cannot forge a duplicate member doc under a non-uid id', async () => {
    // `member` is in memberIds and already has members/member. Before the fix
    // they could create unlimited extra docs under fresh client-chosen ids with
    // their own userId (roster/identity pollution). The rule now binds the doc
    // id to auth.uid, so a non-uid-keyed create is denied.
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/members/forged-1').set({
      id: 'forged-1',
      userId: 'member',
      displayName: 'Member',
      role: 'MEMBER',
      joinedAt: new Date(),
      isShadow: false,
    }));
  });

  test('#524 a member in memberIds can still create their own uid-keyed member doc', async () => {
    // The legit createGroup creator self-add path: a uid in memberIds with no
    // member doc yet creates members/{uid} (id == uid == auth.uid). Must remain
    // allowed — the fix must not over-block the single legitimate self-create.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      const snap = await db.doc('groups/g1').get();
      const ids = (snap.data() as { memberIds: string[] }).memberIds;
      await db.doc('groups/g1').update({
        memberIds: [...ids, 'newcomer'],
        updatedAt: new Date(),
      });
    });
    const newcomer = testEnv.authenticatedContext('newcomer').firestore();
    await assertSucceeds(newcomer.doc('groups/g1/members/newcomer').set({
      id: 'newcomer',
      userId: 'newcomer',
      displayName: 'Newcomer',
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
      updatedAt: new Date(),
    }));
  });

  test('#261 creator cannot change the group currency after creation (immutable)', async () => {
    // #261 (Model A): currency is settable ONLY at create. Dropping it from the
    // validCreatorMetadataUpdate allow-list makes any update that touches
    // currency fall outside hasOnly(['name','updatedAt']) → denied. (Was allowed
    // pre-#261 via the currency branch.) g1 is OMR; USD is a divergent change.
    const owner = testEnv.authenticatedContext('owner').firestore();
    await assertFails(owner.doc('groups/g1').update({
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

  // #528: positiveInt caps amountFils at Number.MAX_SAFE_INTEGER (2^53-1). The
  // safe-max boundary stays ACCEPTED — this pins the cap is not set too low,
  // which would reject legitimate (if absurd) large amounts.
  //
  // The > cap REJECT path is NOT exercisable from this JS harness: @firebase/
  // firestore serializes any number above 2^53-1 as a doubleValue (already
  // rejected by `value is int`, one clause earlier) and refuses BigInt writes
  // outright (verified empirically 2026-06-19). Only a Dart int64 or Admin SDK
  // can persist a genuine integerValue above the cap — the exact forged-write
  // the rules clause backstops, but which this client SDK cannot emit. The
  // client-side guard (MoneySerializer.fitsSafeSubunits) carries the tested
  // money-safety weight; this clause is defense-in-depth.
  test('#528 amountFils at the safe-integer cap (2^53-1) is accepted', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expCap').set(
      validExpense({ id: 'expCap', amountFils: 9007199254740991 }),
    ));
    await assertSucceeds(member.doc('groups/g1/events/e1/settlements/setCap').set(
      validSettlement({ id: 'setCap', amountFils: 9007199254740991 }),
    ));
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
      lastEditedBy: 'member', // #248 PR4: self-attribution mandatory
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
      lastEditedBy: 'member', // #248 PR4: stamp so the denial isolates the ghost-participant guard
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
      lastEditedBy: 'owner',
    }));
    await assertSucceeds(ref.update({
      note: 'archival note',
      lastEditedBy: 'owner', // #248 PR4: self-attribution mandatory
    }));
    await assertSucceeds(ref.update({
      isDeleted: true,
      deletedAt: new Date().toISOString(),
      lastEditedBy: 'owner', // #248 PR4: self-attribution mandatory
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
      lastEditedBy: 'owner', // #248 PR4: stamp so the denial isolates the stale-payer guard
    }));
  });

  test('expenses allow soft delete but deny hard delete', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    const ref = member.doc('groups/g1/events/e1/expenses/exp1');
    await assertSucceeds(ref.set(validExpense()));
    await assertSucceeds(ref.update({
      isDeleted: true,
      deletedAt: new Date().toISOString(),
      lastEditedBy: 'member', // #248 PR4: self-attribution mandatory
    }));
    await assertFails(ref.delete());
  });

  test('expense creator can update own record', async () => {
    await seedExpense();
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertSucceeds(owner.doc('groups/g1/events/e1/expenses/exp1').update({
      amountFils: 12500,
      lastEditedBy: 'owner', // #248 PR4: self-attribution mandatory
    }));
  });

  // #248 PR4: edit is now OPEN to any event participant (was creator-only).
  test('#248 PR4 participant non-creator CAN update peer record', async () => {
    await seedExpense(); // createdBy: 'owner'
    const member = testEnv.authenticatedContext('member').firestore();

    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/exp1').update({
      amountFils: 12500,
      lastEditedBy: 'member',
    }));
  });

  test('#248 PR4 participant non-creator CAN soft-delete peer record', async () => {
    await seedExpense(); // createdBy: 'owner'
    const member = testEnv.authenticatedContext('member').firestore();

    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/exp1').update({
      isDeleted: true,
      deletedAt: new Date().toISOString(),
      lastEditedBy: 'member',
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
      lastEditedBy: 'owner', // #248 PR4: stamp so the denial isolates createdBy-immutability, not the pin
    }));
  });

  test('expense creator can soft-delete own record', async () => {
    await seedExpense();
    const owner = testEnv.authenticatedContext('owner').firestore();

    await assertSucceeds(owner.doc('groups/g1/events/e1/expenses/exp1').update({
      isDeleted: true,
      deletedAt: new Date().toISOString(),
      lastEditedBy: 'owner', // #248 PR4: self-attribution mandatory
    }));
  });

  // === #248 PR1: lastEditedBy field — permit + pin (== auth.uid, gated) + soft-delete carry ===

  test('#248 expense create with lastEditedBy == auth.uid is allowed', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expLE').set(
      validExpense({ id: 'expLE', createdBy: 'member', lastEditedBy: 'member' }),
    ));
  });

  test('#248 expense create with forged lastEditedBy is rejected', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/expenses/expForge').set(
      validExpense({ id: 'expForge', createdBy: 'member', lastEditedBy: 'owner' }),
    ));
  });

  test('#248 legacy expense create WITHOUT lastEditedBy still allowed', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expLegacy').set(
      validExpense({ id: 'expLegacy', createdBy: 'member' }),
    ));
  });

  test('#248 creator update setting lastEditedBy == auth.uid is allowed', async () => {
    await seedExpense(); // createdBy: 'owner'
    const owner = testEnv.authenticatedContext('owner').firestore();
    await assertSucceeds(owner.doc('groups/g1/events/e1/expenses/exp1').update({
      amountFils: 12500,
      lastEditedBy: 'owner',
    }));
  });

  test('#248 creator update forging lastEditedBy != auth.uid is rejected', async () => {
    await seedExpense(); // createdBy: 'owner'
    const owner = testEnv.authenticatedContext('owner').firestore();
    await assertFails(owner.doc('groups/g1/events/e1/expenses/exp1').update({
      amountFils: 12500,
      lastEditedBy: 'member',
    }));
  });

  // #248 PR4: the lastEditedBy pin is now present-AND-equal (was diff-gated). An
  // update must self-attribute the editor — omitting lastEditedBy is denied — so
  // the audit trigger can never fall back to createdBy and blame the wrong person.
  // Reverses the PR1 "old-client update WITHOUT lastEditedBy still allowed" case:
  // the live client always re-stamps on every update path, so the merge-preservation
  // footgun that motivated diff-gating no longer applies (no real users → safe).
  test('#248 PR4 update WITHOUT lastEditedBy is denied (editor must self-attribute)', async () => {
    await seedExpense(); // createdBy: 'owner', no lastEditedBy
    const owner = testEnv.authenticatedContext('owner').firestore();
    await assertFails(owner.doc('groups/g1/events/e1/expenses/exp1').update({
      amountFils: 12500, // omits lastEditedBy -> would let the trigger blame createdBy
    }));
  });

  // The misattribution hole the refuter caught: a non-creator participant could
  // edit a peer's money and, by omitting lastEditedBy, have the tamper-proof audit
  // log name the CREATOR. The present-and-equal pin closes it.
  test('#248 PR4 non-creator update OMITTING lastEditedBy is denied (anti-misattribution)', async () => {
    await seedExpense(); // createdBy: 'owner'
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/expenses/exp1').update({
      amountFils: 99999, // no lastEditedBy -> trigger would blame 'owner'
    }));
  });

  test('#248 PR4 non-creator soft-delete OMITTING lastEditedBy is denied', async () => {
    await seedExpense(); // createdBy: 'owner'
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/expenses/exp1').update({
      isDeleted: true,
      deletedAt: new Date().toISOString(), // no lastEditedBy
    }));
  });

  test('#248 creator soft-delete carrying lastEditedBy is allowed (validSoftDelete loosened)', async () => {
    await seedExpense();
    const owner = testEnv.authenticatedContext('owner').firestore();
    await assertSucceeds(owner.doc('groups/g1/events/e1/expenses/exp1').update({
      isDeleted: true,
      deletedAt: new Date().toISOString(),
      lastEditedBy: 'owner',
    }));
  });

  // === #248 PR4: OPEN edit — any event participant edits/deletes; identity guards hold ===

  test('#248 PR4 participant non-creator CAN update with own lastEditedBy', async () => {
    await seedExpense(); // createdBy: 'owner'
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/exp1').update({
      amountFils: 12500,
      lastEditedBy: 'member',
    }));
  });

  test('#248 PR4 participant non-creator FORGING lastEditedBy is rejected', async () => {
    await seedExpense(); // createdBy: 'owner'
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/expenses/exp1').update({
      amountFils: 12500,
      lastEditedBy: 'owner', // framing the creator — pinned to auth.uid, rejected
    }));
  });

  test('#248 PR4 participant non-creator cannot mutate createdBy', async () => {
    await seedExpense(); // createdBy: 'owner'
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/expenses/exp1').update({
      createdBy: 'member',
      lastEditedBy: 'member',
    }));
  });

  test('#248 PR4 participant non-creator update re-sending a negative splitDistribution is denied', async () => {
    await seedExpense({
      splitMode: 'shares',
      splitDistribution: { owner: 1, member: 1 },
    }); // createdBy: 'owner'
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/expenses/exp1').update({
      splitDistribution: { owner: -1, member: 2 }, // #192/#194 holds across the wider WHO
      lastEditedBy: 'member',
    }));
  });

  test('#248 PR4 non-member outsider cannot update expense', async () => {
    await seedExpense(); // createdBy: 'owner'
    const eve = testEnv.authenticatedContext('eve').firestore(); // not in g1.memberIds
    await assertFails(eve.doc('groups/g1/events/e1/expenses/exp1').update({
      amountFils: 12500,
      lastEditedBy: 'eve',
    }));
  });

  // The boundary that matters: the gate is isEventParticipant (participantIds),
  // NOT isGroupMember (memberIds). A group member who is not on THIS event's
  // participant list cannot edit its expenses.
  test('#248 PR4 group-member who is NOT an event participant cannot update expense', async () => {
    await seedEvent('e2', { participantIds: ['owner'] }); // member NOT a participant of e2
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('groups/g1/events/e2/expenses/expE2').set(
        validExpense({
          id: 'expE2',
          eventId: 'e2',
          createdBy: 'owner',
          payerParticipantId: 'owner',
        }),
      );
    });
    const member = testEnv.authenticatedContext('member').firestore(); // in g1.memberIds, NOT in e2.participantIds
    await assertFails(member.doc('groups/g1/events/e2/expenses/expE2').update({
      amountFils: 12500,
      lastEditedBy: 'member',
    }));
  });

  // B3 append-only guard. NOTE: stays green regardless of the validSoftDelete
  // loosening, because settlement updates are dead-denied at `allow update: if
  // false` (firestore.rules:735) — it does NOT detect drift in validSoftDelete
  // (validEventSettlementUpdate at :677 is dead code). Kept to pin B3 against
  // any future re-wiring of validEventSettlementUpdate.
  test('#248 settlement soft-delete carrying lastEditedBy is still denied', async () => {
    await seedEventSettlement(); // createdBy: 'owner'
    const owner = testEnv.authenticatedContext('owner').firestore();
    await assertFails(owner.doc('groups/g1/events/e1/settlements/set1').update({
      isDeleted: true,
      deletedAt: new Date().toISOString(),
      lastEditedBy: 'owner',
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
      lastEditedBy: 'member', // #248 PR4: stamp so the denial isolates #192 (negative split)
    }));
  });

  test('#192 soft-delete of a legacy expense with a negative splitDistribution is still allowed (no regression)', async () => {
    await seedExpense({ id: 'expDel', createdBy: 'member', splitMode: 'shares', splitDistribution: { owner: 2, member: -3 } });
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expDel').update({
      isDeleted: true,
      deletedAt: new Date().toISOString(),
      lastEditedBy: 'member', // #248 PR4: self-attribution mandatory
    }));
  });

  // ===========================================================================
  // #382 PR-6 (per-expense currency) — an expense's currency need only be a
  // SUPPORTED code (validCurrency floor in validExpenseBase); it no longer has
  // to equal the owning group's currency. group.currency is now just the
  // smart DEFAULT for new expenses. The four currencyMatchesGroup clauses are
  // deleted; a divergent-but-supported code is allowed, an unsupported code
  // (XYZ) is still denied by the floor.
  // ===========================================================================
  test('#382 expense create with a currency divergent from the group is allowed', async () => {
    // g1 is OMR; USD is allow-listed (validCurrency passes). Post-PR-6 the
    // currencyMatchesGroup equality is gone, so a divergent supported code is
    // accepted — the validCurrency floor is the sole currency gate.
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expUsd').set(
      validExpense({ id: 'expUsd', currency: 'USD' }),
    ));
  });

  test('#382 expense create with an unsupported currency code is still denied (validCurrency floor)', async () => {
    // Divergent AND invalid: XYZ is not in the 10-code allow-list, so the
    // validExpenseBase validCurrency floor rejects it even after the
    // currencyMatchesGroup equality is removed.
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/expenses/expXyz').set(
      validExpense({ id: 'expXyz', currency: 'XYZ' }),
    ));
  });

  test('#261 expense create with the group currency is allowed', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expOmr').set(
      validExpense({ id: 'expOmr', currency: 'OMR' }),
    ));
  });

  test('#382 expense update that changes currency to a divergent supported code is allowed', async () => {
    await seedExpense({ id: 'expCurU', createdBy: 'member' }); // OMR
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expCurU').update({
      currency: 'USD',
      lastEditedBy: 'member', // #248 PR4: stamp so the success isolates the currency change (not the lastEditedBy pin)
    }));
  });

  test('#261 soft-delete of a legacy divergent-currency expense is still allowed (diff-gate, no regression)', async () => {
    // The discriminating carve-out: a USD doc in an OMR group. The soft-delete
    // diff is {isDeleted,deletedAt,lastEditedBy} — currency is absent, so the
    // diff-gated check short-circuits true and the delete passes. This would
    // FAIL if currencyMatchesGroup were (mistakenly) placed unconditionally in
    // validExpenseBase ('USD' != 'OMR' → deny). Mirrors the #192 carve-out above.
    await seedExpense({ id: 'expCurDel', createdBy: 'member', currency: 'USD' });
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expCurDel').update({
      isDeleted: true,
      deletedAt: new Date().toISOString(),
      lastEditedBy: 'member', // #248 PR4: self-attribution mandatory
    }));
  });

  // ===========================================================================
  // #193 — settlement currency: allow-list (matches MoneySerializer scale keys)
  // + group-settlement cross-currency equality with the owning group.
  // #261 (Model A): event-settlement cross-currency equality is now ENFORCED
  // too (was DEFERRED to #61) — every settlement currency must equal the owning
  // group's currency. A tautology today (event settle-up still hardcodes 'OMR'
  // and every group is OMR); Phase 2 MUST move settle-up off the 'OMR' hardcode
  // to group.currency or non-OMR groups' settle-up writes get PERMISSION_DENIED.
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

  test('#382 group settlement with a supported-but-divergent currency is allowed', async () => {
    // Group g1 currency is OMR; USD is in the allow-list. Post-PR-6 the
    // group-settlement currency==group.currency equality is gone, so a divergent
    // supported code is accepted (the stepped-settle UI only offers non-zero
    // buckets client-side; the server validates a supported code, L3).
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/settlements/gsetUsd').set(
      validGroupSettlement({ id: 'gsetUsd', currency: 'USD' }),
    ));
  });

  test('#382 group settlement with an unsupported currency code is still denied (validSettlementCore floor)', async () => {
    // Divergent AND invalid: XYZ is not in the allow-list, so validSettlementCore
    // rejects it even after the group.currency equality is removed.
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/settlements/gsetXyz').set(
      validGroupSettlement({ id: 'gsetXyz', currency: 'XYZ' }),
    ));
  });

  test('#382 event settlement with a divergent supported currency is allowed', async () => {
    // #382 PR-6: event settlement currency need only be a supported code, not
    // equal to the owning group's currency (g1 is OMR; USD is allow-listed). The
    // currencyMatchesGroup equality in validEventSettlementBase is deleted; the
    // validSettlementCore floor is the sole currency gate.
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/settlements/setUsd').set(
      validSettlement({ id: 'setUsd', currency: 'USD' }),
    ));
  });

  test('#382 event settlement with an unsupported currency code is still denied (validSettlementCore floor)', async () => {
    // Divergent AND invalid: XYZ is not in the allow-list, so validSettlementCore
    // rejects it even after the currencyMatchesGroup equality is removed.
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/settlements/setXyzDiv').set(
      validSettlement({ id: 'setXyzDiv', currency: 'XYZ' }),
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
      lastEditedBy: 'member', // #248 PR4: stamp so the denial isolates #194 (control-char free-text)
    }));
  });

  test('#194 soft-delete of a legacy expense with an over-280 description is still allowed (no regression)', async () => {
    await seedExpense({ id: 'expLongDel', createdBy: 'member', description: 'a'.repeat(500) });
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expLongDel').update({
      isDeleted: true,
      deletedAt: new Date().toISOString(),
      lastEditedBy: 'member', // #248 PR4: self-attribution mandatory
    }));
  });

  // #248 PR 2 — event activity_logs are now SERVER-ONLY. validActivityCreate was
  // removed from the create OR-list; the expenseAuditLogger trigger (Admin SDK,
  // bypasses rules) is the sole writer, so a client cannot forge an audit entry.
  function validActivityLog(overrides: Record<string, unknown> = {}): Record<string, unknown> {
    return {
      id: 'aLE',
      eventId: 'e1',
      category: 'MONEY',
      eventType: 'CREATE',
      logText: 'Member added an expense for 10.500 OMR',
      actorId: 'member',
      actorName: 'Member',
      metadata: {},
      createdAt: new Date().toISOString(),
      ...overrides,
    };
  }

  test('#248 participant can NO LONGER create an event activity_logs entry (server-only)', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/activity_logs/aLE').set(validActivityLog()));
  });

  test('#248 a forged MONEY/UPDATE audit entry from a client is rejected', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/activity_logs/aFake').set(
      validActivityLog({ id: 'aFake', eventType: 'UPDATE', metadata: { amountFils: 999999 } }),
    ));
  });

  test('#248 even an actorId == auth.uid client create is rejected (no client write at all)', async () => {
    // pre-lock this passed (validActivityCreate only pinned actorId == auth.uid);
    // post-lock there is no client create path for activity_logs.
    const owner = testEnv.authenticatedContext('owner').firestore();
    await assertFails(owner.doc('groups/g1/events/e1/activity_logs/aOwn').set(
      validActivityLog({ id: 'aOwn', actorId: 'owner', actorName: 'Owner' }),
    ));
  });

  test('#248 server (Admin SDK / rules-disabled) CAN write an event activity_logs entry', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await assertSucceeds(ctx.firestore().doc('groups/g1/events/e1/activity_logs/aSrv').set(
        validActivityLog({ id: 'aSrv', eventType: 'UPDATE' }),
      ));
    });
  });

  test('#248 a group member can still READ event activity_logs (read unchanged)', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('groups/g1/events/e1/activity_logs/aRead').set(
        validActivityLog({ id: 'aRead' }),
      );
    });
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/activity_logs/aRead').get());
  });

  // #366 — balance aggregate: server-only write, member read.
  function validAggregate(): Record<string, unknown> {
    return {
      schemaVersion: 2,
      currency: 'OMR',
      netMilliByCurrency: { OMR: { owner: 1000, member: -1000 } },
      perEventNetMilliByCurrency: { e1: { OMR: { owner: 1000, member: -1000 } } },
      eventCount: 1,
      degraded: false,
      sourceTimeMs: 1,
    };
  }

  async function seedAggregate(): Promise<void> {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('groups/g1/aggregates/balance').set(validAggregate());
    });
  }

  test('#366 a group member can READ the balance aggregate', async () => {
    await seedAggregate();
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/aggregates/balance').get());
  });

  test('#366 a non-member cannot read the balance aggregate', async () => {
    await seedAggregate();
    const stranger = testEnv.authenticatedContext('stranger').firestore();
    await assertFails(stranger.doc('groups/g1/aggregates/balance').get());
  });

  test('#366 a member cannot CREATE the balance aggregate (server-only write)', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/aggregates/balance').set(validAggregate()));
  });

  test('#366 a member cannot UPDATE the balance aggregate — forging home display is blocked', async () => {
    await seedAggregate();
    const owner = testEnv.authenticatedContext('owner').firestore();
    await assertFails(owner.doc('groups/g1/aggregates/balance').update({ netMilli: { owner: 999999 } }));
  });

  test('#366 a member cannot DELETE the balance aggregate', async () => {
    await seedAggregate();
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/aggregates/balance').delete());
  });

  test('#366 server (Admin SDK / rules-disabled) CAN write the balance aggregate', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await assertSucceeds(ctx.firestore().doc('groups/g1/aggregates/balance').set(validAggregate()));
    });
  });
});
