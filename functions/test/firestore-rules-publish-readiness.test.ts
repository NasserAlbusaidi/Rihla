import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
// rules-unit-testing v5 hands back a COMPAT Firestore instance (the suite uses
// the namespaced `db.doc(...).set/update` API, not the modular `doc(db, ...)`),
// so a field-DELETE sentinel must come from the compat FieldValue, NOT the
// modular `deleteField()` nor `firebase-admin`'s FieldValue (Admin context only).
import firebase from 'firebase/compat/app';
import 'firebase/compat/firestore';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const deleteSentinel = (): unknown => firebase.firestore.FieldValue.delete();

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
      // #723: the create-path producer (Event.toFirestoreMap) writes the close
      // triple; validEventCreate whitelists them (all born false/null).
      isClosed: false,
      closedAt: null,
      closedBy: null,
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

  // #818: the #441 durable-credential gate on group creation is REMOVED.
  // Post-#648 an anonymous user can already join groups and add expenses on a
  // discardable UID, so the create gate no longer protects its founding
  // invariant — anonymous provider tokens now
  // pass group + inviteCode creation the same as every other provider.
  describe('#818 anonymous provider can create groups (durable-credential gate removed)', () => {
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

    test('anonymous provider can create a group (valid-shaped)', async () => {
      await testEnv.clearFirestore();
      const anon = testEnv.authenticatedContext('anon-uid', {
        firebase: { sign_in_provider: 'anonymous' },
      });

      await assertSucceeds(
        anon
          .firestore()
          .doc('groups/anon-group')
          .set(groupCreatePayload('anon-uid', 'anon-group', 'ANON12')),
      );
    });

    test('anonymous provider can create the group + inviteCode batch', async () => {
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

      await assertSucceeds(batch.commit());
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

    // #245: stageGroup chains the seeded event on the group batch ack, BEFORE
    // the creator's member doc write completes. This pins the ordering
    // assumption that chain rests on: isGroupMember/groupMembers() read
    // groups/{gid}.memberIds (the group DOC), never member subcollection docs,
    // so the event create is valid the instant the batch commits.
    test('#245 seeded event create is valid right after the group batch, '
      + 'WITHOUT any member doc', async () => {
      await testEnv.clearFirestore();
      const linked = testEnv.authenticatedContext('google-uid', {
        firebase: { sign_in_provider: 'google.com' },
      });
      const db = linked.firestore();
      const batch = db.batch();
      batch.set(
        db.doc('groups/seed-group'),
        groupCreatePayload('google-uid', 'seed-group', 'SEED12'),
      );
      batch.set(db.doc('inviteCodes/SEED12'), {
        groupId: 'seed-group',
        createdAt: new Date(),
      });
      await assertSucceeds(batch.commit());

      // The exact seed payload stageGroup writes (Event.toFirestoreMap):
      // trip type, creator-only participants, born-open close triple.
      await assertSucceeds(
        db.doc('groups/seed-group/events/seeded-1').set(
          validEvent({
            name: 'Gate Group',
            type: 'trip',
            groupId: 'seed-group',
            createdBy: 'google-uid',
            participantIds: ['google-uid'],
            participantNames: { 'google-uid': 'Nasser' },
          }),
        ),
      );
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

  // #287 / trip-stamps PR-2a: the group glyph (allow-listed enum string) and
  // inkIndex (int 0..5) are accepted+bounded on create and on creator-only
  // metadata edit. A field-DELETE clears a stamp back to monogram (post-write
  // key absent → passes the `!('glyph' in data)` guard); an explicit null is
  // neither absent nor a valid value → DENIED.
  describe('#287 group glyph + inkIndex (create & creator-edit)', () => {
    test('create accepts a valid glyph + inkIndex', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertSucceeds(owner.doc('groups/g-stamp-valid').set(
        validGroup('g-stamp-valid', {
          inviteCode: 'STAMP1',
          glyph: 'tent',
          inkIndex: 3,
        }),
      ));
    });

    test('create still accepts a group with no glyph/inkIndex (allow-list regression guard)', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertSucceeds(owner.doc('groups/g-stamp-absent').set(
        validGroup('g-stamp-absent', { inviteCode: 'STAMP2' }),
      ));
    });

    test('create accepts a monogram group (inkIndex only, no glyph)', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertSucceeds(owner.doc('groups/g-stamp-mono').set(
        validGroup('g-stamp-mono', { inviteCode: 'STAMP3', inkIndex: 0 }),
      ));
    });

    test('create rejects a forged glyph value', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertFails(owner.doc('groups/g-stamp-forged').set(
        validGroup('g-stamp-forged', { inviteCode: 'STAMP4', glyph: 'pwned' }),
      ));
    });

    test('create rejects a non-string glyph', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertFails(owner.doc('groups/g-stamp-glyphtype').set(
        validGroup('g-stamp-glyphtype', { inviteCode: 'STAMP5', glyph: 5 }),
      ));
    });

    test('create rejects an explicit null glyph', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertFails(owner.doc('groups/g-stamp-glyphnull').set(
        validGroup('g-stamp-glyphnull', { inviteCode: 'STAMP6', glyph: null }),
      ));
    });

    test('create rejects an inkIndex above the range', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertFails(owner.doc('groups/g-stamp-inkhigh').set(
        validGroup('g-stamp-inkhigh', { inviteCode: 'STAMP7', inkIndex: 6 }),
      ));
    });

    test('create rejects a negative inkIndex', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertFails(owner.doc('groups/g-stamp-inklow').set(
        validGroup('g-stamp-inklow', { inviteCode: 'STAMP8', inkIndex: -1 }),
      ));
    });

    test('create rejects a non-int inkIndex', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertFails(owner.doc('groups/g-stamp-inktype').set(
        validGroup('g-stamp-inktype', { inviteCode: 'STAMP9', inkIndex: '3' }),
      ));
    });

    test('creator can edit glyph + inkIndex to valid values', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertSucceeds(owner.doc('groups/g1').update({
        glyph: 'wave',
        inkIndex: 2,
        updatedAt: new Date(),
      }));
    });

    test('creator can clear glyph back to monogram (field-delete)', async () => {
      // Seed a REAL glyph first (rules-disabled) so the delete is a genuine
      // present→absent transition: affectedKeys() then includes 'glyph', which
      // the OLD hasOnly(['name','updatedAt']) would have rejected. Without this
      // seed, deleting an absent field is a no-op (affectedKeys()={updatedAt})
      // and the test passes vacuously even against the old rules.
      await updateSeedGroup({ glyph: 'tent' });
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertSucceeds(owner.doc('groups/g1').update({
        glyph: deleteSentinel(),
        updatedAt: new Date(),
      }));
    });

    test('creator can clear inkIndex (field-delete)', async () => {
      // Seed a REAL inkIndex first (rules-disabled) so the delete is a genuine
      // present→absent transition (affectedKeys() includes 'inkIndex'), not a
      // vacuous no-op against the old allow-list.
      await updateSeedGroup({ inkIndex: 3 });
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertSucceeds(owner.doc('groups/g1').update({
        inkIndex: deleteSentinel(),
        updatedAt: new Date(),
      }));
    });

    test('a non-creator cannot edit the glyph', async () => {
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1').update({
        glyph: 'wave',
        updatedAt: new Date(),
      }));
    });

    test('creator cannot edit the glyph to a forged value', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertFails(owner.doc('groups/g1').update({
        glyph: 'x',
        updatedAt: new Date(),
      }));
    });
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

  test('#710 claim shadow locks are not readable or writable by clients', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('groups/g1/claimShadowLocks/shadow').set({
        groupId: 'g1',
        shadowMemberId: 'shadow',
        claimerUid: 'claimer',
        requestId: 'claimer__shadow',
        lockedBy: 'owner',
        lockedAt: new Date(),
        updatedAt: new Date(),
      });
    });

    const owner = testEnv.authenticatedContext('owner').firestore();
    await assertFails(owner.doc('groups/g1/claimShadowLocks/shadow').get());
    await assertFails(owner.collection('groups/g1/claimShadowLocks').get());
    await assertFails(owner.doc('groups/g1/claimShadowLocks/other-shadow').set({
      groupId: 'g1',
      shadowMemberId: 'other-shadow',
      claimerUid: 'owner',
      requestId: 'owner__other-shadow',
      lockedBy: 'owner',
      lockedAt: new Date(),
      updatedAt: new Date(),
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

  test('#710 claim/account-deletion freeze markers reject stale client writes while preserving reads', async () => {
    await updateSeedGroup({
      claimingInProgress: true,
      claimLockedAt: new Date(),
      updatedAt: new Date(),
    });

    const owner = testEnv.authenticatedContext('owner').firestore();
    const member = testEnv.authenticatedContext('member').firestore();

    await assertSucceeds(member.doc('groups/g1').get());
    await assertFails(owner.doc('groups/g1').update({
      name: 'During Claim',
      updatedAt: new Date(),
    }));
    await assertFails(owner.doc('groups/g1/events/e-during-claim').set(
      validEvent({
        name: 'During Claim',
        createdBy: 'owner',
        participantIds: ['owner'],
        participantNames: { owner: 'Owner' },
      }),
    ));
    await assertFails(member.doc('groups/g1/events/e1/expenses/exp-during-claim').set(
      validExpense({ id: 'exp-during-claim', createdBy: 'member' }),
    ));

    await updateSeedGroup({
      claimingInProgress: deleteSentinel(),
      claimLockedAt: deleteSentinel(),
      accountDeletionInProgress: true,
      accountDeletionUid: 'member',
      accountDeletionLockedAt: new Date(),
      updatedAt: new Date(),
    });

    await assertFails(owner.doc('groups/g1').update({
      name: 'During Account Delete',
      updatedAt: new Date(),
    }));
    await assertFails(member.doc('groups/g1/events/e1/expenses/exp-during-account-delete').set(
      validExpense({ id: 'exp-during-account-delete', createdBy: 'member' }),
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

  describe('#723 event close lifecycle', () => {
    test('admin (event creator) can close the event', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertSucceeds(owner.doc('groups/g1/events/e1').update({
        isClosed: true,
        closedAt: new Date(),
        closedBy: 'owner',
        updatedAt: new Date(),
      }));
    });

    test('group creator can close an event they did not create', async () => {
      await seedEvent('e2', {
        createdBy: 'member',
        participantIds: ['member'],
        participantNames: { member: 'Member' },
      });
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertSucceeds(owner.doc('groups/g1/events/e2').update({
        isClosed: true,
        closedAt: new Date(),
        closedBy: 'owner',
        updatedAt: new Date(),
      }));
    });

    test('non-admin participant cannot close the event', async () => {
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e1').update({
        isClosed: true,
        closedAt: new Date(),
        closedBy: 'member',
        updatedAt: new Date(),
      }));
    });

    test('close with closedBy != caller is rejected', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertFails(owner.doc('groups/g1/events/e1').update({
        isClosed: true,
        closedAt: new Date(),
        closedBy: 'member',
        updatedAt: new Date(),
      }));
    });

    test('close bundling an unrelated key (name) is rejected', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertFails(owner.doc('groups/g1/events/e1').update({
        isClosed: true,
        closedAt: new Date(),
        closedBy: 'owner',
        name: 'Sneaky rename',
        updatedAt: new Date(),
      }));
    });

    test('close without a closedAt timestamp is rejected', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertFails(owner.doc('groups/g1/events/e1').update({
        isClosed: true,
        closedAt: null,
        closedBy: 'owner',
        updatedAt: new Date(),
      }));
    });

    test('admin can close an event with a departed participant (#249 / [P2])', async () => {
      // 'member' leaves the group (drops out of memberIds) but stays an event
      // participant. Close must still succeed — the close path must NOT re-run
      // participantIds.hasOnly(groupMembers()).
      await updateSeedGroup({ memberIds: ['owner'] });
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertSucceeds(owner.doc('groups/g1/events/e1').update({
        isClosed: true,
        closedAt: new Date(),
        closedBy: 'owner',
        updatedAt: new Date(),
      }));
    });

    test('admin can reopen a closed event', async () => {
      await updateSeedEvent({ isClosed: true, closedAt: new Date(), closedBy: 'owner' });
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertSucceeds(owner.doc('groups/g1/events/e1').update({
        isClosed: false,
        closedAt: null,
        closedBy: null,
        updatedAt: new Date(),
      }));
    });

    test('non-admin cannot reopen a closed event', async () => {
      await updateSeedEvent({ isClosed: true, closedAt: new Date(), closedBy: 'owner' });
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e1').update({
        isClosed: false,
        closedAt: null,
        closedBy: null,
        updatedAt: new Date(),
      }));
    });

    // NOTE: there is no "reopen a never-closed event" negative test — on a
    // never-closed event the close triple is already false/null/null, so a
    // reopen-shaped write diffs to ['updatedAt'] only and is a harmless no-op
    // metadata bump (legitimately allowed by the light path). The reopen guard
    // (before.isClosed must be present + true) is exercised by the close/reopen
    // round-trip tests above.

    test('participant can still rename a closed event (meta edits stay allowed)', async () => {
      await updateSeedEvent({ isClosed: true, closedAt: new Date(), closedBy: 'owner' });
      const member = testEnv.authenticatedContext('member').firestore();
      await assertSucceeds(member.doc('groups/g1/events/e1').update({
        name: 'Renamed after close',
        updatedAt: new Date(),
      }));
    });

    test('closed event REJECTS expense create', async () => {
      await updateSeedEvent({ isClosed: true, closedAt: new Date(), closedBy: 'owner' });
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e1/expenses/expClosed').set(
        validExpense({ id: 'expClosed' }),
      ));
    });

    test('closed event REJECTS expense update', async () => {
      await seedExpense({ id: 'expEdit' });
      await updateSeedEvent({ isClosed: true, closedAt: new Date(), closedBy: 'owner' });
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e1/expenses/expEdit').update({
        amountFils: 20000,
        lastEditedBy: 'member',
      }));
    });

    test('closed event REJECTS expense soft-delete', async () => {
      await seedExpense({ id: 'expDel' });
      await updateSeedEvent({ isClosed: true, closedAt: new Date(), closedBy: 'owner' });
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e1/expenses/expDel').update({
        isDeleted: true,
        deletedAt: new Date().toISOString(),
        lastEditedBy: 'member',
      }));
    });

    test('closed event STILL ACCEPTS settlement create (settlements stay live)', async () => {
      await updateSeedEvent({ isClosed: true, closedAt: new Date(), closedBy: 'owner' });
      const member = testEnv.authenticatedContext('member').firestore();
      await assertSucceeds(member.doc('groups/g1/events/e1/settlements/setClosed').set(
        validSettlement({ id: 'setClosed' }),
      ));
    });

    test('open event still accepts expense create (no regression)', async () => {
      const member = testEnv.authenticatedContext('member').firestore();
      await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expOpen').set(
        validExpense({ id: 'expOpen' }),
      ));
    });

    test('event born closed is rejected; born open is accepted', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertFails(owner.doc('groups/g1/events/e-born-closed').set(
        validEvent({ createdBy: 'owner', isClosed: true, closedAt: new Date(), closedBy: 'owner' }),
      ));
      await assertSucceeds(owner.doc('groups/g1/events/e-born-open').set(
        validEvent({ createdBy: 'owner' }),
      ));
    });

    // ── #766 spendingSnapshot (frozen SPENDING half; opaque, display-only) ──
    test('#766 close WITH a bounded spendingSnapshot map is accepted', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertSucceeds(owner.doc('groups/g1/events/e1').update({
        isClosed: true,
        closedAt: new Date(),
        closedBy: 'owner',
        updatedAt: new Date(),
        spendingSnapshot: { v: 1, participantCount: 2, totals: { OMR: 100000 } },
      }));
    });

    test('#766 close with an oversized spendingSnapshot (>16 keys) is rejected', async () => {
      const big: Record<string, unknown> = {};
      for (let i = 0; i < 17; i++) big[`k${i}`] = i;
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertFails(owner.doc('groups/g1/events/e1').update({
        isClosed: true,
        closedAt: new Date(),
        closedBy: 'owner',
        updatedAt: new Date(),
        spendingSnapshot: big,
      }));
    });

    test('#766 close with a non-map spendingSnapshot is rejected', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertFails(owner.doc('groups/g1/events/e1').update({
        isClosed: true,
        closedAt: new Date(),
        closedBy: 'owner',
        updatedAt: new Date(),
        spendingSnapshot: 'not-a-map',
      }));
    });

    test('#766 reopen that DELETEs spendingSnapshot is accepted', async () => {
      await updateSeedEvent({
        isClosed: true,
        closedAt: new Date(),
        closedBy: 'owner',
        spendingSnapshot: { v: 1, participantCount: 2 },
      });
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertSucceeds(owner.doc('groups/g1/events/e1').update({
        isClosed: false,
        closedAt: null,
        closedBy: null,
        updatedAt: new Date(),
        spendingSnapshot: deleteSentinel(),
      }));
    });

    test('#766 writing spendingSnapshot WITHOUT a close transition is rejected (close-only)', async () => {
      // Admin, open event, no isClosed change → no valid close/reopen branch, and
      // spendingSnapshot is absent from the light/admin allow-lists.
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertFails(owner.doc('groups/g1/events/e1').update({
        spendingSnapshot: { v: 1 },
        updatedAt: new Date(),
      }));
    });
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

  test('#710 expenses tolerate existing server scrub sentinels but clients cannot create them', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/expenses/expSentinelCreate').set(
      validExpense({
        id: 'expSentinelCreate',
        claimRekeyAt: new Date(),
        deleteAccountScrubAt: new Date(),
      }),
    ));

    await seedExpense({
      id: 'expSentinel',
      claimRekeyAt: new Date(),
      deleteAccountScrubAt: new Date(),
    });
    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expSentinel').update({
      note: 'ordinary edit',
      lastEditedBy: 'member',
    }));
    await assertFails(member.doc('groups/g1/events/e1/expenses/expSentinel').update({
      claimRekeyAt: new Date(),
      lastEditedBy: 'member',
    }));
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

  test('#203 splitExplanation accepted as opaque display-only map (create)', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expSE').set(
      validExpense({
        id: 'expSE',
        splitMode: 'exact',
        splitDistribution: { owner: 500, member: 500 },
        splitExplanation: {
          type: 'itemized',
          version: 1,
          items: [
            { label: 'Latte', amountFils: 500, quantity: 1, participantIds: ['owner'], allocation: 'equal' },
            { label: 'Mocha', amountFils: 500, quantity: 1, participantIds: ['member'], allocation: 'equal' },
          ],
        },
      }),
    ));
  });

  test('#203 splitExplanation accepted on update (proves the SECOND/affectedKeys allowlist)', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    const ref = member.doc('groups/g1/events/e1/expenses/expSEUpd');
    await assertSucceeds(ref.set(validExpense({ id: 'expSEUpd' })));
    await assertSucceeds(ref.update({
      splitExplanation: { type: 'itemized', version: 1, items: [] },
      lastEditedBy: 'member', // #248 PR4: self-attribution mandatory
    }));
  });

  test('#203 splitExplanation rejected when not a map (pins `is map`)', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/expenses/expSEBad').set(
      validExpense({ id: 'expSEBad', splitExplanation: 'not-a-map' }),
    ));
  });

  test('#203 splitExplanation rejected with >64 top-level keys (entry-count cap, NOT array length — Firestore 1MB doc limit bounds payload)', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    const big: Record<string, number> = {};
    for (let i = 0; i < 65; i++) big[`k${i}`] = i;
    await assertFails(member.doc('groups/g1/events/e1/expenses/expSEBig').set(
      validExpense({ id: 'expSEBig', splitExplanation: big }),
    ));
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

  describe('#752 group-settlement decompose: event-settlement authz + groupSettleUpId link', () => {
    // validEventSettlementCreate now gates on isGroupMember (was
    // isEventParticipant), so a group-level settle-up decomposed into per-event
    // docs — written by a group member who is NOT a participant of the event —
    // is accepted. The counterparties STILL must be event participants.
    test('group member who is NOT an event participant CAN create an event settlement between two participants', async () => {
      await addGroupMember('peer', 'Peer'); // peer ∈ g1.memberIds, NOT in eRelax.participantIds
      await seedEvent('eRelax', { participantIds: ['owner', 'member'] });
      const peer = testEnv.authenticatedContext('peer').firestore();
      await assertSucceeds(peer.doc('groups/g1/events/eRelax/settlements/setRelax').set(
        validSettlement({
          id: 'setRelax',
          eventId: 'eRelax',
          createdBy: 'peer',
          payerParticipantId: 'owner',
          recipientParticipantId: 'member',
          payerName: 'Owner',
          recipientName: 'Member',
        }),
      ));
    });

    test('a NON-member still cannot create an event settlement', async () => {
      await seedEvent('eRelax', { participantIds: ['owner', 'member'] });
      const stranger = testEnv.authenticatedContext('stranger').firestore(); // NOT in g1.memberIds
      await assertFails(stranger.doc('groups/g1/events/eRelax/settlements/setX').set(
        validSettlement({
          id: 'setX',
          eventId: 'eRelax',
          createdBy: 'stranger',
          payerParticipantId: 'owner',
          recipientParticipantId: 'member',
        }),
      ));
    });

    test('counterparties must STILL be event participants (party gate unchanged)', async () => {
      await addGroupMember('peer', 'Peer');
      await seedEvent('eRelax', { participantIds: ['owner', 'member'] });
      const peer = testEnv.authenticatedContext('peer').firestore();
      // peer is a group member but NOT an eRelax participant — using it as a
      // counterparty must still fail.
      await assertFails(peer.doc('groups/g1/events/eRelax/settlements/setBad').set(
        validSettlement({
          id: 'setBad',
          eventId: 'eRelax',
          createdBy: 'peer',
          payerParticipantId: 'owner',
          recipientParticipantId: 'peer', // NOT an eRelax participant
        }),
      ));
    });

    test('event settlement carrying a string groupSettleUpId is accepted', async () => {
      const member = testEnv.authenticatedContext('member').firestore();
      await assertSucceeds(member.doc('groups/g1/events/e1/settlements/setLink').set(
        validSettlement({ id: 'setLink', groupSettleUpId: 'su-abc' }),
      ));
    });

    test('event settlement carrying a non-string groupSettleUpId is rejected', async () => {
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e1/settlements/setLinkBad').set(
        validSettlement({ id: 'setLinkBad', groupSettleUpId: 123 }),
      ));
    });

    test('group settlement carrying a string groupSettleUpId is accepted', async () => {
      const member = testEnv.authenticatedContext('member').firestore();
      await assertSucceeds(member.doc('groups/g1/settlements/gsetLink').set(
        validGroupSettlement({ id: 'gsetLink', groupSettleUpId: 'su-xyz' }),
      ));
    });

    test('settlement with the groupSettleUpId key omitted is still accepted', async () => {
      const member = testEnv.authenticatedContext('member').firestore();
      // validSettlement() carries NO groupSettleUpId key — pins the
      // `!('groupSettleUpId' in data) || ...` guard against a direct-access regression.
      await assertSucceeds(member.doc('groups/g1/events/e1/settlements/setNoLink').set(
        validSettlement({ id: 'setNoLink' }),
      ));
    });
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

  // #808 PR1 — group activity `type` is now ALLOW-LISTED for client creates.
  // Before this, `type is string` accepted anything: a member could forge
  // `expense_added` (server-only fan-in vocabulary) or `member_left`
  // (written only by the leaveGroup/removeMember callables via Admin SDK).
  function validGroupActivity(overrides: Record<string, unknown> = {}): Record<string, unknown> {
    return {
      id: 'ga1',
      type: 'event_created',
      actorId: 'member',
      actorName: 'Member',
      description: 'created an event',
      metadata: {},
      timestamp: new Date().toISOString(),
      ...overrides,
    };
  }

  test('#808 each client-written group activity type is accepted (event_created/event_deleted/group_settlement/member_joined)', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    for (const type of ['event_created', 'event_deleted', 'group_settlement', 'member_joined']) {
      const id = `ga-ok-${type}`;
      await assertSucceeds(
        member.doc(`groups/g1/activity/${id}`).set(validGroupActivity({ id, type })),
      );
    }
  });

  test('#808 a client cannot forge server-only or unknown group activity types', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    for (const type of ['expense_added', 'expense_edited', 'expense_deleted', 'member_left', 'totally_made_up']) {
      const id = `ga-forge-${type}`;
      await assertFails(
        member.doc(`groups/g1/activity/${id}`).set(validGroupActivity({ id, type })),
      );
    }
  });

  test('#808 the server (Admin SDK / rules-disabled) CAN write expense_* and member_left group entries', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await assertSucceeds(ctx.firestore().doc('groups/g1/activity/ga-srv').set(
        validGroupActivity({
          id: 'ga-srv',
          type: 'expense_added',
          actorId: 'owner',
          actorName: 'Owner',
          description: 'added Dinner (10.500 OMR)',
          metadata: { expenseId: 'exp1', eventId: 'e1', eventName: 'Trip', amountFils: 10500, currency: 'OMR' },
        }),
      ));
    });
  });

  // #814 — value-domain floor for client-forgeable group-activity metadata.
  // Before this, `metadata is map` accepted any shape: a member could forge
  // `amountFils: NaN`/negative fils, unsupported currencies, or non-string
  // names that the display layer (#815/#816) must otherwise defend against.
  test('#814 a client cannot forge non-finite or negative amountFils', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    const forgeries = [NaN, Infinity, 10.5, -100];
    for (const amountFils of forgeries) {
      const id = `ga-814-amountfils-${String(amountFils)}`;
      await assertFails(
        member.doc(`groups/g1/activity/${id}`).set(
          validGroupActivity({ id, type: 'group_settlement', metadata: { amountFils } }),
        ),
      );
    }
  });

  test('#814 a client cannot forge an unsupported metadata currency', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(
      member.doc('groups/g1/activity/ga-814-currency').set(
        validGroupActivity({
          id: 'ga-814-currency',
          type: 'group_settlement',
          metadata: { amountFils: 10500, currency: 'ZZZ' },
        }),
      ),
    );
  });

  test('#814 a client cannot forge a non-string legacy amount', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(
      member.doc('groups/g1/activity/ga-814-amount').set(
        validGroupActivity({ id: 'ga-814-amount', type: 'group_settlement', metadata: { amount: 42 } }),
      ),
    );
  });

  test('#814 a client cannot forge a non-string eventName', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(
      member.doc('groups/g1/activity/ga-814-eventname').set(
        validGroupActivity({
          id: 'ga-814-eventname',
          type: 'event_created',
          metadata: { eventName: 42 },
        }),
      ),
    );
  });

  test('#814 a client cannot forge non-string memberName or memberAction', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(
      member.doc('groups/g1/activity/ga-814-membername').set(
        validGroupActivity({ id: 'ga-814-membername', type: 'group_settlement', metadata: { memberName: 42 } }),
      ),
    );
    await assertFails(
      member.doc('groups/g1/activity/ga-814-memberaction').set(
        validGroupActivity({ id: 'ga-814-memberaction', type: 'group_settlement', metadata: { memberAction: 42 } }),
      ),
    );
  });

  // #818 Wave 3.1 — recipientId promoted from opaque to typed alongside the
  // four new direction keys.
  test('#818 a client cannot forge non-string recipientId/fromUserId/toUserId/fromName/toName', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(
      member.doc('groups/g1/activity/ga-818-forge-recipientid').set(
        validGroupActivity({ id: 'ga-818-forge-recipientid', type: 'group_settlement', metadata: { recipientId: 42 } }),
      ),
    );
    await assertFails(
      member.doc('groups/g1/activity/ga-818-forge-fromuserid').set(
        validGroupActivity({ id: 'ga-818-forge-fromuserid', type: 'group_settlement', metadata: { fromUserId: 42 } }),
      ),
    );
    await assertFails(
      member.doc('groups/g1/activity/ga-818-forge-touserid').set(
        validGroupActivity({ id: 'ga-818-forge-touserid', type: 'group_settlement', metadata: { toUserId: 42 } }),
      ),
    );
    await assertFails(
      member.doc('groups/g1/activity/ga-818-forge-fromname').set(
        validGroupActivity({
          id: 'ga-818-forge-fromname',
          type: 'group_settlement',
          metadata: { fromUserId: 'member', toUserId: 'owner', fromName: 5, toName: 'Owner' },
        }),
      ),
    );
    await assertFails(
      member.doc('groups/g1/activity/ga-818-forge-toname').set(
        validGroupActivity({
          id: 'ga-818-forge-toname',
          type: 'group_settlement',
          metadata: { fromUserId: 'member', toUserId: 'owner', fromName: 'Member', toName: 5 },
        }),
      ),
    );
  });

  test('#814 a client cannot forge a metadata map with more than 16 keys', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    const metadata: Record<string, unknown> = {};
    for (let i = 0; i < 17; i += 1) {
      metadata[`k${i}`] = `v${i}`;
    }
    await assertFails(
      member.doc('groups/g1/activity/ga-814-toobig').set(
        validGroupActivity({ id: 'ga-814-toobig', type: 'group_settlement', metadata }),
      ),
    );
  });

  test('#814 legitimate client metadata shapes still succeed', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertSucceeds(
      member.doc('groups/g1/activity/ga-814-ok-settle').set(
        validGroupActivity({
          id: 'ga-814-ok-settle',
          type: 'group_settlement',
          metadata: { amount: '12.500', recipientId: 'member', currency: 'OMR' },
        }),
      ),
    );
    // #818 Wave 3.1: the full directional shape (7 keys) is accepted — the
    // legacy 3-key shape above is the anchor this must not regress.
    await assertSucceeds(
      member.doc('groups/g1/activity/ga-818-ok-directional').set(
        validGroupActivity({
          id: 'ga-818-ok-directional',
          type: 'group_settlement',
          metadata: {
            amount: '12.500',
            recipientId: 'member',
            currency: 'OMR',
            fromUserId: 'member',
            toUserId: 'owner',
            fromName: 'Member',
            toName: 'Owner',
          },
        }),
      ),
    );
    await assertSucceeds(
      member.doc('groups/g1/activity/ga-814-ok-event').set(
        validGroupActivity({
          id: 'ga-814-ok-event',
          type: 'event_created',
          metadata: { eventId: 'e1', eventName: 'Trip' },
        }),
      ),
    );
    await assertSucceeds(
      member.doc('groups/g1/activity/ga-814-ok-join').set(
        validGroupActivity({
          id: 'ga-814-ok-join',
          type: 'member_joined',
          metadata: { groupId: 'g1' },
        }),
      ),
    );
    await assertSucceeds(
      member.doc('groups/g1/activity/ga-814-ok-empty').set(
        validGroupActivity({ id: 'ga-814-ok-empty', metadata: {} }),
      ),
    );
    await assertSucceeds(
      member.doc('groups/g1/activity/ga-814-ok-opaque').set(
        validGroupActivity({
          id: 'ga-814-ok-opaque',
          metadata: { someFutureId: 'abc' },
        }),
      ),
    );
    await assertSucceeds(
      member.doc('groups/g1/activity/ga-814-ok-faninshape').set(
        validGroupActivity({
          id: 'ga-814-ok-faninshape',
          metadata: { amountFils: 10500, currency: 'OMR' },
        }),
      ),
    );
  });

  test('#814 the server (Admin SDK / rules-disabled) can still write garbage-shaped metadata on member_left', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await assertSucceeds(ctx.firestore().doc('groups/g1/activity/ga-814-srv').set(
        validGroupActivity({
          id: 'ga-814-srv',
          type: 'member_left',
          actorId: 'owner',
          actorName: 'Owner',
          description: 'Member left the group',
          metadata: { memberName: 42 },
        }),
      ));
    });
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
