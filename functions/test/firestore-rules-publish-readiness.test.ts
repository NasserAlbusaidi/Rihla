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
      // #1144 R5: the create-path producer (group_provider.dart) writes
      // activeMemberIds == memberIds; validGroupCreate requires equality.
      // Tracks a memberIds override automatically; an explicit
      // activeMemberIds override still wins (it spreads after this).
      activeMemberIds: (overrides.memberIds as string[] | undefined) ?? ['owner'],
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
      activeMemberIds: ['owner'], // #1144 R5: producer writes it == memberIds
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
        activeMemberIds: [uid], // #1144 R5: producer writes it == memberIds
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

    // #245/#874: STANDARD-PATH property — a seeded event create is valid once its
    // group exists (isGroupMember/groupMembers() read groups/{gid}.memberIds, the
    // group DOC, never member subcollection docs), WITHOUT any member doc. Since
    // #874 stageGroup writes the seeded event in the founding batch (not chained
    // after the group ack), but this rule property still holds for the
    // group-committed-first shape and pins that the event rule never depends on a
    // member subcollection doc. The founding-batch (all-in-one) shape is covered
    // by the '#874 founding batch' describe below.
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

  // #874: offline group creation writes group + inviteCode + creator member doc
  // + #245 seeded event in ONE atomic WriteBatch (a single mutation — no
  // FlutterFire host-call reorder race, offline-correct, survives process-kill).
  // The member + event create rules accept the group being created in the SAME
  // batch via after-state (getAfter/existsAfter -> groupFoundingBatchByCreator).
  // On the PRE-#874 rules the 4-write batch is REJECTED (isGroupMember reads
  // pre-batch state -> group absent -> deny), so the positive test is RED before
  // the rules change.
  describe('#874 founding batch (member + event ride the group-create batch)', () => {
    function memberDoc(uid: string, role = 'CREATOR'): Record<string, unknown> {
      return {
        id: uid,
        userId: uid,
        displayName: 'Founder',
        role,
        joinedAt: new Date(),
        isShadow: false,
      };
    }

    function seededEventDoc(
      groupId: string,
      uid: string,
      overrides: Record<string, unknown> = {},
    ): Record<string, unknown> {
      return validEvent({
        name: 'Founding Trip',
        type: 'trip',
        groupId,
        createdBy: uid,
        participantIds: [uid],
        participantNames: { [uid]: 'Founder' },
        ...overrides,
      });
    }

    test('creator commits group + inviteCode + member + seeded event in ONE '
      + 'atomic batch', async () => {
      await testEnv.clearFirestore();
      const db = testEnv.authenticatedContext('founder').firestore();
      const batch = db.batch();
      batch.set(
        db.doc('groups/fg'),
        validGroup('fg', {
          createdBy: 'founder',
          memberIds: ['founder'],
          inviteCode: 'FG1234',
        }),
      );
      batch.set(db.doc('inviteCodes/FG1234'), {
        groupId: 'fg',
        createdAt: new Date(),
      });
      batch.set(db.doc('groups/fg/members/founder'), memberDoc('founder'));
      batch.set(db.doc('groups/fg/events/seed'), seededEventDoc('fg', 'founder'));

      await assertSucceeds(batch.commit());
    });

    test('atomic: an INDIVIDUALLY-VALID member leg is still sunk when only the '
      + 'group leg is malformed (isolates atomicity)', async () => {
      await testEnv.clearFirestore();
      const db = testEnv.authenticatedContext('founder').firestore();
      const batch = db.batch();
      // The group leg fails validGroupCreate on currency ALONE, while leaving
      // createdBy == founder and memberIds == [founder] intact — so the member
      // leg's own groupFoundingBatchByCreator (existsAfter + after-memberIds +
      // after-createdBy) is INDIVIDUALLY valid. The batch must still be denied,
      // proving it's atomicity (not the member leg's own checks) that sinks it.
      batch.set(
        db.doc('groups/fg'),
        validGroup('fg', {
          createdBy: 'founder',
          memberIds: ['founder'],
          inviteCode: 'FG1234',
          currency: 'NOTACURRENCY',
        }),
      );
      batch.set(db.doc('inviteCodes/FG1234'), {
        groupId: 'fg',
        createdAt: new Date(),
      });
      batch.set(db.doc('groups/fg/members/founder'), memberDoc('founder'));

      await assertFails(batch.commit());
    });

    test('the !exists guard forces a PRE-EXISTING soft-deleted group down the '
      + 'standard path — member/event create is denied', async () => {
      // g1 already exists (seeded) — soft-delete it, then attempt member/event
      // creates that are NOT part of a group-create batch. groupFoundingBatchByCreator
      // is off (exists()==true), so groupAllowsClientWrites gates and denies.
      await updateSeedGroup({ isDeleted: true, deletedAt: new Date() });
      const db = testEnv.authenticatedContext('owner').firestore();

      await assertFails(
        db.doc('groups/g1/members/late-owner-doc').set(memberDoc('owner')),
      );
      await assertFails(
        db.doc('groups/g1/events/late').set(
          seededEventDoc('g1', 'owner', { participantIds: ['owner'] }),
        ),
      );
    });

    test('a standalone member create against a group that neither exists nor is '
      + 'in the batch is denied (existsAfter false)', async () => {
      // No group-create in this write and no such group exists -> both
      // isGroupMember and groupFoundingBatchByCreator are false. Proves the
      // founding branch cannot be tricked into firing without a real same-batch
      // group create.
      await testEnv.clearFirestore();
      const db = testEnv.authenticatedContext('ghost').firestore();
      await assertFails(
        db.doc('groups/no-such-group/members/ghost').set(memberDoc('ghost')),
      );
      await assertFails(
        db.doc('groups/no-such-group/events/e').set(
          seededEventDoc('no-such-group', 'ghost'),
        ),
      );
    });

    test('founding-batch event with a participant outside the after-memberIds '
      + 'is denied (isolates the founding event membership guard)', async () => {
      await testEnv.clearFirestore();
      const db = testEnv.authenticatedContext('founder').firestore();
      const batch = db.batch();
      batch.set(
        db.doc('groups/fg'),
        validGroup('fg', {
          createdBy: 'founder',
          memberIds: ['founder'],
          inviteCode: 'FG1234',
        }),
      );
      batch.set(db.doc('inviteCodes/FG1234'), {
        groupId: 'fg',
        createdAt: new Date(),
      });
      batch.set(db.doc('groups/fg/members/founder'), memberDoc('founder'));
      // Event smuggles a stranger into participantIds; after-memberIds is
      // [founder], so hasOnly(...) fails and the whole atomic batch is denied.
      batch.set(
        db.doc('groups/fg/events/seed'),
        seededEventDoc('fg', 'founder', {
          participantIds: ['founder', 'stranger'],
          participantNames: { founder: 'Founder', stranger: 'Stranger' },
        }),
      );

      await assertFails(batch.commit());
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
      activeMemberIds: ['owner'], // #1144 R5: producer writes it == memberIds
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

  describe('#1135 departed event participant light-update authority', () => {
    async function departMember(remainingMemberIds: string[]): Promise<void> {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await db.doc('groups/g1').update({
          memberIds: remainingMemberIds,
          updatedAt: new Date(),
        });
        await db.doc('groups/g1/members/member').delete();
      });
    }

    test('departed participant cannot rename an event', async () => {
      await departMember(['owner']);
      const departed = testEnv.authenticatedContext('member').firestore();
      await assertFails(departed.doc('groups/g1/events/e1').update({
        name: 'Hijacked Camp',
        updatedAt: new Date(),
      }));
    });

    test('departed participant cannot add a current member to an event', async () => {
      await addGroupMember('guest', 'Guest');
      await departMember(['owner', 'guest']);
      const departed = testEnv.authenticatedContext('member').firestore();
      await assertFails(departed.doc('groups/g1/events/e1').update({
        participantIds: ['owner', 'member', 'guest'],
        participantNames: { owner: 'Owner', member: 'Member', guest: 'Guest' },
        updatedAt: new Date(),
      }));
    });

    test('departed participant cannot remove self while renaming an event', async () => {
      await departMember(['owner']);
      const departed = testEnv.authenticatedContext('member').firestore();
      await assertFails(departed.doc('groups/g1/events/e1').update({
        name: 'Hijacked Camp',
        participantIds: ['owner'],
        updatedAt: new Date(),
      }));
    });
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

    test('#1129 closed-event settlement create is DENIED like any client settlement create (post-close acceptance lives in recordSettlement)', async () => {
      await updateSeedEvent({ isClosed: true, closedAt: new Date(), closedBy: 'owner' });
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e1/settlements/setClosed').set(
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
    // #1129: the settlement half of this pin moved into recordSettlement's
    // own input validation (client settlement creates are denied outright).
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

  // The gate is BOTH isGroupMember (memberIds, #1131) AND isEventParticipant
  // (participantIds). This test pins the participation half: a group member who
  // is not on THIS event's participant list cannot edit its expenses. The
  // membership half is pinned by the '#1131 departed member' describe below.
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

  describe('#1131 departed member loses expense write authority', () => {
    // leaveGroup/removeMember drop the uid from memberIds + delete the member
    // doc but NEVER prune event participantIds (balance-universe preservation),
    // so participation alone must not grant writes: the gate requires CURRENT
    // membership too. Read access was always membership-gated; these pin the
    // write side to the same boundary.
    async function departMember(): Promise<void> {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await db.doc('groups/g1').update({ memberIds: ['owner'], updatedAt: new Date() });
        await db.doc('groups/g1/members/member').delete();
      });
    }

    test('departed member (still in participantIds) cannot CREATE an expense', async () => {
      await departMember();
      const departed = testEnv.authenticatedContext('member').firestore();
      await assertFails(departed.doc('groups/g1/events/e1/expenses/expDeparted').set(
        validExpense({ id: 'expDeparted', createdBy: 'member', payerParticipantId: 'member' }),
      ));
    });

    test('departed member cannot UPDATE an expense', async () => {
      await seedExpense(); // createdBy 'owner'
      await departMember();
      const departed = testEnv.authenticatedContext('member').firestore();
      await assertFails(departed.doc('groups/g1/events/e1/expenses/exp1').update({
        amountFils: 12500,
        lastEditedBy: 'member',
      }));
    });

    test('departed member cannot SOFT-DELETE an expense', async () => {
      await seedExpense();
      await departMember();
      const departed = testEnv.authenticatedContext('member').firestore();
      await assertFails(departed.doc('groups/g1/events/e1/expenses/exp1').update({
        isDeleted: true,
        deletedAt: new Date().toISOString(),
        lastEditedBy: 'member',
      }));
    });

    // Over-blocking guard, #1144 revision: the remaining member keeps full
    // write authority for CURRENT-member expenses. The pre-#1144 version of
    // this test pinned the old #249-era counterparty allowance (creates/edits
    // whose splitDistribution referenced the departed uid) — #1144's
    // current-party policy deliberately reverses that (a leave-departed
    // party left at exact zero; new exposure re-opens their balance), so
    // those cases now live as DENY tests in the '#1144 current-party policy'
    // describe. What must stay true: current-member-only writes flow freely,
    // and metadata edits of departed-referencing docs stay open.
    test('remaining member still creates and edits current-member expenses after a departure', async () => {
      await seedExpense({
        splitMode: 'exact',
        splitDistribution: { owner: 5250, member: 5250 }, // written pre-departure
      });
      await departMember();
      const owner = testEnv.authenticatedContext('owner').firestore();
      // Metadata edit of the departed-referencing doc stays open (#1144 R6).
      await assertSucceeds(owner.doc('groups/g1/events/e1/expenses/exp1').update({
        note: 'still annotatable',
        lastEditedBy: 'owner',
      }));
      // New current-member-only expense on the same event flows freely
      // (exact keys ⊆ memberIds; the departed uid stays on the roster).
      await assertSucceeds(owner.doc('groups/g1/events/e1/expenses/expOwner').set(
        validExpense({
          id: 'expOwner',
          createdBy: 'owner',
          payerParticipantId: 'owner',
          splitMode: 'exact',
          splitDistribution: { owner: 10500 },
        }),
      ));
      // And allocation-editing it keeps working (all parties current, pre+post).
      await assertSucceeds(owner.doc('groups/g1/events/e1/expenses/expOwner').update({
        amountFils: 12500,
        splitDistribution: { owner: 12500 },
        lastEditedBy: 'owner',
      }));
    });
  });

  describe('#1132 departed creator loses admin authority', () => {
    // leaveGroup never reassigns createdBy, so a creator who left kept every
    // createdBy-keyed power. Membership is now a conjunct on isCreator,
    // requesterIsEventAdmin, and validMemberDelete's creator branch.
    //
    // CONFOUND GUARD (Gate round 1): validEventBase re-asserts
    // participantIds.hasOnly(groupMembers()). If we left the departed creator in
    // e1.participantIds while dropping them from memberIds, the admin soft-delete
    // would deny PRE-fix via that check (not via authority) → false RED. So
    // departCreator ALSO prunes 'owner' from e1.participantIds/participantNames,
    // making requesterIsEventAdmin the SOLE gate (createdBy stays 'owner'). The
    // close path (validEventCloseToggle) skips validEventBase, but we prune
    // uniformly so every event test isolates the conjunct.
    async function departCreator(): Promise<void> {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await db.doc('groups/g1').update({ memberIds: ['member'], updatedAt: new Date() });
        await db.doc('groups/g1/members/owner').delete();
        await db.doc('groups/g1/events/e1').update({
          participantIds: ['member'],
          participantNames: { member: 'Member' },
        });
      });
    }

    async function seedShadow(id: string, name: string): Promise<void> {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc(`groups/g1/members/${id}`).set({
          id, userId: id, displayName: name,
          role: 'MEMBER', joinedAt: new Date(), isShadow: true,
        });
      });
    }

    test('departed creator cannot rename the group', async () => {
      await departCreator();
      const departed = testEnv.authenticatedContext('owner').firestore();
      await assertFails(departed.doc('groups/g1').update({
        name: 'Hijacked', updatedAt: new Date(),
      }));
    });

    test('departed creator cannot set the group stamp', async () => {
      await departCreator();
      const departed = testEnv.authenticatedContext('owner').firestore();
      await assertFails(departed.doc('groups/g1').update({
        glyph: 'tent', inkIndex: 2, updatedAt: new Date(),
      }));
    });

    test('departed creator cannot admin-soft-delete an event', async () => {
      await departCreator();
      const departed = testEnv.authenticatedContext('owner').firestore();
      await assertFails(departed.doc('groups/g1/events/e1').update({
        isDeleted: true, deletedAt: new Date(), updatedAt: new Date(),
      }));
    });

    test('departed creator cannot close an event', async () => {
      await departCreator();
      const departed = testEnv.authenticatedContext('owner').firestore();
      await assertFails(departed.doc('groups/g1/events/e1').update({
        isClosed: true, closedAt: new Date(), closedBy: 'owner', updatedAt: new Date(),
      }));
    });

    test('departed creator cannot delete a shadow member doc', async () => {
      await seedShadow('shadow-uuid-1', 'Guest');
      await departCreator();
      const departed = testEnv.authenticatedContext('owner').firestore();
      await assertFails(departed.doc('groups/g1/members/shadow-uuid-1').delete());
    });

    // Over-block guards: a creator who is STILL a member keeps every power.
    test('current creator still renames, stamps, and closes', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertSucceeds(owner.doc('groups/g1').update({
        name: 'Renamed Crew', updatedAt: new Date(),
      }));
      await assertSucceeds(owner.doc('groups/g1').update({
        glyph: 'tent', inkIndex: 2, updatedAt: new Date(),
      }));
      await assertSucceeds(owner.doc('groups/g1/events/e1').update({
        isClosed: true, closedAt: new Date(), closedBy: 'owner', updatedAt: new Date(),
      }));
    });

    test('current creator still admin-soft-deletes an event', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertSucceeds(owner.doc('groups/g1/events/e1').update({
        isDeleted: true, deletedAt: new Date(), updatedAt: new Date(),
      }));
    });

    test('current creator still deletes a shadow member doc', async () => {
      await seedShadow('shadow-uuid-2', 'Guest2');
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertSucceeds(owner.doc('groups/g1/members/shadow-uuid-2').delete());
    });
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

  test('#1129 client settlement creates are DENIED in both scopes with fully-VALID payloads (callable-only)', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(member.doc('groups/g1/events/e1/settlements/set1').set(validSettlement()));
    await assertFails(member.doc('groups/g1/settlements/gset1').set(validGroupSettlement()));
  });

  describe('#1129 settlement create denial (formerly the #752 client authz surface)', () => {
    // The #752 relaxations (isGroupMember writer, groupSettleUpId link shape)
    // moved INTO the recordSettlement callable, which mirrors them server-side
    // (functions/test/callables/recordSettlement.*.test.ts). Rules-side, every
    // client create is denied — member, non-participant peer, and stranger
    // alike — whatever the payload carries.
    test('a group-member peer (the old #752 relaxation) can no longer client-create an event settlement', async () => {
      await addGroupMember('peer', 'Peer');
      await seedEvent('eRelax', { participantIds: ['owner', 'member'] });
      const peer = testEnv.authenticatedContext('peer').firestore();
      await assertFails(peer.doc('groups/g1/events/eRelax/settlements/setRelax').set(
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

    test('a groupSettleUpId-tagged (decompose-shaped) client leg is denied like any other create', async () => {
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e1/settlements/setLink').set(
        validSettlement({ id: 'setLink', groupSettleUpId: 'su-abc' }),
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

  // ===========================================================================
  // #889 — correction marker foundation: deny-by-omission on
  // `correctionOfSettlementId` (no change to the hasOnly() key lists — pinning
  // the existing denial), and the tightened non-blank `groupSettleUpId` guard.
  // ===========================================================================
  describe('#889 correction marker foundation', () => {
    test('#1129 unmarked event settlement create is now ALSO denied (callable-only superseded the baseline)', async () => {
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e1/settlements/setUnmarked').set(
        validSettlement({ id: 'setUnmarked' }),
      ));
    });

    test('#1129 unmarked group settlement create is now ALSO denied (callable-only superseded the baseline)', async () => {
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/settlements/gsetUnmarked').set(
        validGroupSettlement({ id: 'gsetUnmarked' }),
      ));
    });

    test('client-created event settlement carrying correctionOfSettlementId is denied (hasOnly-omission)', async () => {
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e1/settlements/setMarked').set(
        validSettlement({ id: 'setMarked', correctionOfSettlementId: 'orig1' }),
      ));
    });

    test('client-created group settlement carrying correctionOfSettlementId is denied (hasOnly-omission)', async () => {
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/settlements/gsetMarked').set(
        validGroupSettlement({ id: 'gsetMarked', correctionOfSettlementId: 'orig1' }),
      ));
    });




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

  test('#808/#1129 each client-written group activity type is accepted (event_created/event_deleted/member_joined — settlement types are server-only now)', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    for (const type of ['event_created', 'event_deleted', 'member_joined']) {
      const id = `ga-ok-${type}`;
      await assertSucceeds(
        member.doc(`groups/g1/activity/${id}`).set(validGroupActivity({ id, type })),
      );
    }
  });


  test('#808 a client cannot forge server-only or unknown group activity types', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    for (const type of ['expense_added', 'expense_edited', 'expense_deleted', 'member_left', 'event_settlement', 'group_settlement', 'totally_made_up']) {
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
          validGroupActivity({ id, type: 'event_created', metadata: { amountFils } }),
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
          type: 'event_created',
          metadata: { amountFils: 10500, currency: 'ZZZ' },
        }),
      ),
    );
  });

  test('#814 a client cannot forge a non-string legacy amount', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    await assertFails(
      member.doc('groups/g1/activity/ga-814-amount').set(
        validGroupActivity({ id: 'ga-814-amount', type: 'event_created', metadata: { amount: 42 } }),
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
        validGroupActivity({ id: 'ga-818-forge-recipientid', type: 'event_created', metadata: { recipientId: 42 } }),
      ),
    );
    await assertFails(
      member.doc('groups/g1/activity/ga-818-forge-fromuserid').set(
        validGroupActivity({ id: 'ga-818-forge-fromuserid', type: 'event_created', metadata: { fromUserId: 42 } }),
      ),
    );
    await assertFails(
      member.doc('groups/g1/activity/ga-818-forge-touserid').set(
        validGroupActivity({ id: 'ga-818-forge-touserid', type: 'event_created', metadata: { toUserId: 42 } }),
      ),
    );
    await assertFails(
      member.doc('groups/g1/activity/ga-818-forge-fromname').set(
        validGroupActivity({
          id: 'ga-818-forge-fromname',
          type: 'event_created',
          metadata: { fromUserId: 'member', toUserId: 'owner', fromName: 5, toName: 'Owner' },
        }),
      ),
    );
    await assertFails(
      member.doc('groups/g1/activity/ga-818-forge-toname').set(
        validGroupActivity({
          id: 'ga-818-forge-toname',
          type: 'event_created',
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
        validGroupActivity({ id: 'ga-814-toobig', type: 'event_created', metadata }),
      ),
    );
  });

  test('#814 legitimate client metadata shapes still succeed', async () => {
    const member = testEnv.authenticatedContext('member').firestore();
    // #1129: settlement-typed rows are server-only now; the settlement
    // metadata SHAPES stay client-floor-validated via a client-writable type
    // (validActivityMetadata is type-agnostic), so the #814/#818 value floors
    // keep their positive anchors without a settlement type.
    await assertSucceeds(
      member.doc('groups/g1/activity/ga-814-ok-settle').set(
        validGroupActivity({
          id: 'ga-814-ok-settle',
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

  describe('#1144 departure fence quiesces client writes', () => {
    // leaveGroup/removeMember recompute the departing member's net UNDER a
    // departureInProgress group-doc lock (the fifth groupAllowsClientWrites
    // flag); every client write must freeze for that window or a mid-departure
    // balance-input write invalidates the zero-check basis (the #1144-B race).
    // Each case asserts the SAME write is denied under the fence and allowed
    // once it lifts — pinning the freeze to the flag, not to fixture noise.
    async function engageDepartureFence(): Promise<void> {
      await updateSeedGroup({
        departureInProgress: true,
        departureLockedAt: new Date(),
        departureLockedBy: 'member',
      });
    }

    async function liftDepartureFence(): Promise<void> {
      await updateSeedGroup({
        departureInProgress: false,
        departureLockedAt: deleteSentinel(),
        departureLockedBy: deleteSentinel(),
      });
    }

    test('fence blocks expense CREATE; lifting restores it', async () => {
      await engageDepartureFence();
      const member = testEnv.authenticatedContext('member').firestore();
      const write = () => member.doc('groups/g1/events/e1/expenses/expFence').set(
        validExpense({ id: 'expFence', createdBy: 'member', payerParticipantId: 'member' }),
      );
      await assertFails(write());
      await liftDepartureFence();
      await assertSucceeds(write());
    });

    test('fence blocks expense metadata UPDATE; lifting restores it', async () => {
      await seedExpense();
      await engageDepartureFence();
      const member = testEnv.authenticatedContext('member').firestore();
      const write = () => member.doc('groups/g1/events/e1/expenses/exp1').update({
        note: 'fenced note',
        lastEditedBy: 'member',
      });
      await assertFails(write());
      await liftDepartureFence();
      await assertSucceeds(write());
    });



    test('fence blocks event light UPDATE; lifting restores it', async () => {
      await engageDepartureFence();
      const member = testEnv.authenticatedContext('member').firestore();
      const write = () => member.doc('groups/g1/events/e1').update({
        name: 'Fenced Rename',
        updatedAt: new Date(),
      });
      await assertFails(write());
      await liftDepartureFence();
      await assertSucceeds(write());
    });

    test('fence blocks member self-rename; lifting restores it', async () => {
      await engageDepartureFence();
      const member = testEnv.authenticatedContext('member').firestore();
      const write = () => member.doc('groups/g1/members/member').update({
        displayName: 'Fenced Name',
      });
      await assertFails(write());
      await liftDepartureFence();
      await assertSucceeds(write());
    });
  });

  describe('#1144 current-party policy', () => {
    // Parties of a NEW or allocation-edited expense must be CURRENT members;
    // event-settlement parties must be current members too. `memberIds`
    // contains unclaimed-shadow uuids (addShadowMember arrayUnion) AND
    // deleteAccount tombstone ids (uid→tombstoneId SWAP, deleteAccount.ts:616
    // — never a removal), so ghosts stay settleable while leave/remove-
    // departed identities (hard-removed) are blocked. Fixtures:
    //   D 'departed'  — in event participantIds, ABSENT from memberIds, no
    //                   member doc (the leave/remove post-state).
    //   T 'ghost-t'   — IN memberIds AND participantIds, member doc keyed T
    //                   with isTombstone:true (the deleteAccount post-state;
    //                   deleteAccount.ts:502 swaps it into participantIds).
    const D = 'departed';
    const T = 'ghost-t';
    const SHADOW = 'shadow-uuid-9';

    // e2: event whose roster retains departed D.
    async function seedDepartedRosterEvent(): Promise<void> {
      await seedEvent('e2', {
        participantIds: ['owner', 'member', D],
        participantNames: { owner: 'Owner', member: 'Member', [D]: 'Dana' },
      });
    }

    // e3: event with ghost T — T also joins memberIds + gets a tombstone doc.
    async function seedGhostEvent(): Promise<void> {
      await updateSeedGroup({ memberIds: ['owner', 'member', T] });
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc(`groups/g1/members/${T}`).set({
          id: T,
          userId: T,
          displayName: 'Former member',
          role: 'MEMBER',
          joinedAt: new Date(),
          isShadow: false,
          isTombstone: true,
        });
      });
      await seedEvent('e3', {
        participantIds: ['owner', 'member', T],
        participantNames: { owner: 'Owner', member: 'Member', [T]: 'Former member' },
      });
    }

    async function seedShadowEvent(): Promise<void> {
      await updateSeedGroup({ memberIds: ['owner', 'member', SHADOW] });
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc(`groups/g1/members/${SHADOW}`).set({
          id: SHADOW,
          userId: SHADOW,
          displayName: 'Guest',
          role: 'MEMBER',
          joinedAt: new Date(),
          isShadow: true,
        });
      });
      await seedEvent('e4', {
        participantIds: ['owner', 'member', SHADOW],
        participantNames: { owner: 'Owner', member: 'Member', [SHADOW]: 'Guest' },
      });
    }

    async function seedE2Expense(overrides: Record<string, unknown> = {}): Promise<void> {
      const data = validExpense({ id: 'expD', eventId: 'e2', createdBy: 'owner', ...overrides });
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc(`groups/g1/events/e2/expenses/${data.id}`).set(data);
      });
    }

    // --- deny: new exposure for a leave/remove-departed party ---

    test('1. expense CREATE with departed payer → denied', async () => {
      await seedDepartedRosterEvent();
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e2/expenses/x1').set(
        validExpense({ id: 'x1', eventId: 'e2', createdBy: 'member', payerParticipantId: D }),
      ));
    });

    test('2. exact-mode CREATE with departed split key → denied', async () => {
      await seedDepartedRosterEvent();
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e2/expenses/x2').set(
        validExpense({
          id: 'x2', eventId: 'e2', createdBy: 'member', payerParticipantId: 'member',
          splitMode: 'exact', splitDistribution: { member: 5250, [D]: 5250 },
        }),
      ));
    });

    test('3. custom-scope CREATE with departed custom participant → denied', async () => {
      await seedDepartedRosterEvent();
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e2/expenses/x3').set(
        validExpense({
          id: 'x3', eventId: 'e2', createdBy: 'member', payerParticipantId: 'member',
          scope: 'custom', customSplitParticipants: ['member', D],
        }),
      ));
    });

    test('4. equal-mode CREATE on the departed-roster event → denied (roster is the divisor)', async () => {
      await seedDepartedRosterEvent();
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e2/expenses/x4').set(
        validExpense({ id: 'x4', eventId: 'e2', createdBy: 'member', payerParticipantId: 'member' }),
      ));
    });

    test('5. allocation edit (amount) of an expense with departed payer → denied', async () => {
      await seedDepartedRosterEvent();
      await seedE2Expense({ payerParticipantId: D, splitMode: 'exact', splitDistribution: { owner: 5250, member: 5250 } });
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e2/expenses/expD').update({
        amountFils: 12500,
        splitDistribution: { owner: 6250, member: 6250 },
        lastEditedBy: 'member',
      }));
    });

    test('6. allocation edit REMOVING the departed split key → denied (pre-state fail-closed)', async () => {
      await seedDepartedRosterEvent();
      await seedE2Expense({ payerParticipantId: 'owner', splitMode: 'exact', splitDistribution: { owner: 5250, [D]: 5250 } });
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e2/expenses/expD').update({
        splitDistribution: { owner: 10500 },
        lastEditedBy: 'member',
      }));
    });

    test('7. soft-delete of an expense with departed payer → denied', async () => {
      await seedDepartedRosterEvent();
      await seedE2Expense({ payerParticipantId: D, splitMode: 'exact', splitDistribution: { owner: 5250, member: 5250 } });
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e2/expenses/expD').update({
        isDeleted: true,
        deletedAt: new Date().toISOString(),
        lastEditedBy: 'member',
      }));
    });

    test('8. soft-delete of an equal-mode expense on the departed-roster event → denied', async () => {
      await seedDepartedRosterEvent();
      await seedE2Expense({ payerParticipantId: 'owner' }); // global equal — roster-derived
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e2/expenses/expD').update({
        isDeleted: true,
        deletedAt: new Date().toISOString(),
        lastEditedBy: 'member',
      }));
    });


    // --- allow: everything the policy must NOT break ---

    test('10. metadata-only edit of a departed-payer expense → allowed (history stays annotatable)', async () => {
      await seedDepartedRosterEvent();
      await seedE2Expense({ payerParticipantId: D, splitMode: 'exact', splitDistribution: { owner: 5250, member: 5250 } });
      const member = testEnv.authenticatedContext('member').firestore();
      await assertSucceeds(member.doc('groups/g1/events/e2/expenses/expD').update({
        note: 'annotated after departure',
        lastEditedBy: 'member',
      }));
    });

    test('11. equal-mode CREATE on an all-current roster → allowed', async () => {
      const member = testEnv.authenticatedContext('member').firestore();
      await assertSucceeds(member.doc('groups/g1/events/e1/expenses/x11').set(
        validExpense({ id: 'x11', createdBy: 'member', payerParticipantId: 'member' }),
      ));
    });

    test('12. exact-mode CREATE with member-only keys ON the departed-roster event → allowed', async () => {
      await seedDepartedRosterEvent();
      const member = testEnv.authenticatedContext('member').firestore();
      await assertSucceeds(member.doc('groups/g1/events/e2/expenses/x12').set(
        validExpense({
          id: 'x12', eventId: 'e2', createdBy: 'member', payerParticipantId: 'member',
          splitMode: 'exact', splitDistribution: { owner: 5250, member: 5250 },
        }),
      ));
    });



    test('15. shadow uuid as payer and split key → allowed (shadows are current members)', async () => {
      await seedShadowEvent();
      const member = testEnv.authenticatedContext('member').firestore();
      await assertSucceeds(member.doc('groups/g1/events/e4/expenses/x15').set(
        validExpense({
          id: 'x15', eventId: 'e4', createdBy: 'member', payerParticipantId: SHADOW,
          splitMode: 'exact', splitDistribution: { member: 5250, [SHADOW]: 5250 },
        }),
      ));
    });

    test('16. expense CREATE with ghost split key → ALLOWED — pins residual R5', async () => {
      // R5 LEGACY-FALLBACK pin: this group has NO activeMemberIds, so the
      // gates fall back to memberIds and a ghost split key still lands —
      // exactly the pre-#1144-R5 behavior. With the field present this is
      // DENIED (see "#1144 R5 activeMemberIds" R5-2 below). Converges when
      // any roster writer self-heals the field.
      await seedGhostEvent();
      const member = testEnv.authenticatedContext('member').firestore();
      await assertSucceeds(member.doc('groups/g1/events/e3/expenses/x16').set(
        validExpense({
          id: 'x16', eventId: 'e3', createdBy: 'member', payerParticipantId: 'member',
          splitMode: 'exact', splitDistribution: { member: 5250, [T]: 5250 },
        }),
      ));
    });

    // --- D9: admin roster removals may not drop a non-current-member key ---

    test('17. admin roster removal of the departed key → denied (D9 — dropping D re-divides their equal splits)', async () => {
      await seedDepartedRosterEvent();
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertFails(owner.doc('groups/g1/events/e2').update({
        participantIds: ['owner', 'member'],
        updatedAt: new Date(),
      }));
    });

    test('18. admin roster removal of a CURRENT member → allowed', async () => {
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertSucceeds(owner.doc('groups/g1/events/e1').update({
        participantIds: ['owner'],
        updatedAt: new Date(),
      }));
    });

    test('19. admin soft-delete of the departed-roster event → denied (existing L474 post-state freeze, pinned)', async () => {
      await seedDepartedRosterEvent();
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertFails(owner.doc('groups/g1/events/e2').update({
        isDeleted: true,
        deletedAt: new Date(),
        updatedAt: new Date(),
      }));
    });
  });

  describe('#1144 R5 activeMemberIds', () => {
    // activeMemberIds = memberIds MINUS deleteAccount tombstone ids (shadow
    // uuids stay in — shadows are legitimate expense parties). Server-
    // maintained after create; rules fall back to memberIds when ABSENT
    // (legacy groups keep today's exact behavior). Gates switched to it:
    // expense CREATE parties (:852 arm), the D9 roster-removal guard, event
    // CREATE rosters, and roster-ADD deltas on light+admin event updates.
    // The expense UPDATE path (pre/post/soft-delete) deliberately stays on
    // memberIds — ghost history must remain correctable (deleteAccount
    // cleanup lane; Gate R1 adversary P1).
    const T = 'ghost-t';
    const SHADOW = 'shadow-uuid-9';

    // Ghost fixture with the field PRESENT: T in memberIds+participantIds
    // (deleteAccount post-state) but excluded from activeMemberIds.
    async function seedActivatedGhostGroup(): Promise<void> {
      await updateSeedGroup({
        // Shadows are arrayUnion'd into memberIds by addShadowMember — the
        // shadow sits in BOTH sets; the tombstone only in memberIds.
        memberIds: ['owner', 'member', T, SHADOW],
        activeMemberIds: ['owner', 'member', SHADOW],
      });
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc(`groups/g1/members/${T}`).set({
          id: T,
          userId: T,
          displayName: 'Former member',
          role: 'MEMBER',
          joinedAt: new Date(),
          isShadow: false,
          isTombstone: true,
        });
        await ctx.firestore().doc(`groups/g1/members/${SHADOW}`).set({
          id: SHADOW,
          userId: SHADOW,
          displayName: 'Guest',
          role: 'MEMBER',
          joinedAt: new Date(),
          isShadow: true,
        });
      });
      // e5: ghost-rostered event; e6: all-active event with the shadow.
      await seedEvent('e5', {
        participantIds: ['owner', 'member', T],
        participantNames: { owner: 'Owner', member: 'Member', [T]: 'Former member' },
      });
      await seedEvent('e6', {
        participantIds: ['owner', 'member', SHADOW],
        participantNames: { owner: 'Owner', member: 'Member', [SHADOW]: 'Guest' },
      });
    }

    async function seedGhostPaidExpense(): Promise<void> {
      const data = validExpense({
        id: 'expT', eventId: 'e5', createdBy: 'owner', payerParticipantId: T,
        splitMode: 'exact', splitDistribution: { member: 5250, [T]: 5250 },
      });
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc(`groups/g1/events/e5/expenses/${data.id}`).set(data);
      });
    }

    // --- deny: no NEW exposure for a ghost when the field is present ---

    test('R5-1. expense CREATE with ghost payer → denied', async () => {
      await seedActivatedGhostGroup();
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e5/expenses/r1').set(
        validExpense({ id: 'r1', eventId: 'e5', createdBy: 'member', payerParticipantId: T }),
      ));
    });

    test('R5-2. exact-mode CREATE with ghost split key → denied (flips the legacy R5 pin when the field is present)', async () => {
      await seedActivatedGhostGroup();
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e5/expenses/r2').set(
        validExpense({
          id: 'r2', eventId: 'e5', createdBy: 'member', payerParticipantId: 'member',
          splitMode: 'exact', splitDistribution: { member: 5250, [T]: 5250 },
        }),
      ));
    });

    test('R5-3. custom-scope CREATE with ghost in customSplitParticipants → denied', async () => {
      await seedActivatedGhostGroup();
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e5/expenses/r3').set(
        validExpense({
          id: 'r3', eventId: 'e5', createdBy: 'member', payerParticipantId: 'member',
          scope: 'custom', customSplitParticipants: ['member', T],
        }),
      ));
    });

    test('R5-4. roster-derived (equal) CREATE on the ghost-rostered event → denied (roster is the divisor)', async () => {
      await seedActivatedGhostGroup();
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e5/expenses/r4').set(
        validExpense({ id: 'r4', eventId: 'e5', createdBy: 'member', payerParticipantId: 'member' }),
      ));
    });

    test('R5-5. admin roster removal of the ghost key → denied (D9 gate switched to activeMemberIds)', async () => {
      await seedActivatedGhostGroup();
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertFails(owner.doc('groups/g1/events/e5').update({
        participantIds: ['owner', 'member'],
        updatedAt: new Date(),
      }));
    });

    test('R5-6. event CREATE rostering the ghost → denied', async () => {
      await seedActivatedGhostGroup();
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/eNew').set(validEvent({
        participantIds: ['owner', 'member', T],
        participantNames: { owner: 'Owner', member: 'Member', [T]: 'Former member' },
        createdBy: 'member',
      })));
    });

    test('R5-7. light roster ADD of the ghost → denied (added keys must be active)', async () => {
      await seedActivatedGhostGroup();
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e1').update({
        participantIds: ['owner', 'member', T],
        participantNames: { owner: 'Owner', member: 'Member', [T]: 'Former member' },
        updatedAt: new Date(),
      }));
    });

    test('R5-8. admin roster ADD of the ghost → denied (creator NOT a participant → light path unreachable, ADMIN branch exercised)', async () => {
      await seedActivatedGhostGroup();
      // e7: creator-owned event that does NOT roster the creator — the light
      // path's requesterIsParticipant fails, so this write can only pass (or
      // be denied) through validEventAdminUpdate.
      await seedEvent('e7', {
        participantIds: ['member'],
        participantNames: { member: 'Member' },
      });
      const owner = testEnv.authenticatedContext('owner').firestore();
      await assertFails(owner.doc('groups/g1/events/e7').update({
        participantIds: ['member', T],
        participantNames: { member: 'Member', [T]: 'Former member' },
        updatedAt: new Date(),
      }));
    });

    // --- allow: shadows stay first-class; ghost HISTORY stays correctable ---

    test('R5-9. shadow as payer and split key → allowed (shadows are IN activeMemberIds)', async () => {
      await seedActivatedGhostGroup();
      const member = testEnv.authenticatedContext('member').firestore();
      await assertSucceeds(member.doc('groups/g1/events/e6/expenses/r9').set(
        validExpense({
          id: 'r9', eventId: 'e6', createdBy: 'member', payerParticipantId: SHADOW,
          splitMode: 'exact', splitDistribution: { member: 5250, [SHADOW]: 5250 },
        }),
      ));
    });

    test('R5-10. exact-mode CREATE among active members on the ghost-rostered event → allowed (frozen-entry events stay usable)', async () => {
      await seedActivatedGhostGroup();
      const member = testEnv.authenticatedContext('member').firestore();
      await assertSucceeds(member.doc('groups/g1/events/e5/expenses/r10').set(
        validExpense({
          id: 'r10', eventId: 'e5', createdBy: 'member', payerParticipantId: 'member',
          splitMode: 'exact', splitDistribution: { owner: 5250, member: 5250 },
        }),
      ));
    });

    test('R5-11. event settlement with the ghost as recipient → DENIED like every client settlement create (#1129); ghost settleability lives in the callable', async () => {
      // Pre-#1129 this pinned "ghosts stay settleable" at the RULES layer
      // (memberIds gate — debt cleanup). Settlement creates are now
      // callable-only, so the rules deny this for everyone; the ghost
      // (tombstone) settleability property is pinned server-side by the
      // recordSettlement emulator table ("tombstone ghost in both → allowed",
      // functions/test/callables/recordSettlement.event.test.ts).
      await seedActivatedGhostGroup();
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1/events/e5/settlements/rs11').set(
        validSettlement({
          id: 'rs11', eventId: 'e5', createdBy: 'member',
          payerParticipantId: 'member', recipientParticipantId: T,
          payerName: 'Member', recipientName: 'Former member',
        }),
      ));
    });

    test('R5-12. soft-delete of a ghost-paid expense → allowed (update path stays memberIds — cleanup lane)', async () => {
      await seedActivatedGhostGroup();
      await seedGhostPaidExpense();
      const member = testEnv.authenticatedContext('member').firestore();
      await assertSucceeds(member.doc('groups/g1/events/e5/expenses/expT').update({
        isDeleted: true,
        deletedAt: new Date().toISOString(),
        lastEditedBy: 'member',
      }));
    });

    test('R5-13. amount edit of a ghost-paid expense → allowed (ghost history stays correctable)', async () => {
      await seedActivatedGhostGroup();
      await seedGhostPaidExpense();
      const member = testEnv.authenticatedContext('member').firestore();
      await assertSucceeds(member.doc('groups/g1/events/e5/expenses/expT').update({
        amountFils: 9000,
        splitDistribution: { member: 4500, [T]: 4500 },
        lastEditedBy: 'member',
      }));
    });

    test('R5-14. allocation edit INTRODUCING the ghost → allowed — pins residual R5-edit', async () => {
      // Deliberate boundary: the update path stays on memberIds so ghost
      // history remains correctable; an introduction-only gate was rejected
      // as #723 budget on the update chain. Pickers filter ghosts (#1149).
      await seedActivatedGhostGroup();
      const data = validExpense({
        id: 'expM', eventId: 'e5', createdBy: 'member', payerParticipantId: 'member',
        splitMode: 'exact', splitDistribution: { owner: 5250, member: 5250 },
      });
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc('groups/g1/events/e5/expenses/expM').set(data);
      });
      const member = testEnv.authenticatedContext('member').firestore();
      await assertSucceeds(member.doc('groups/g1/events/e5/expenses/expM').update({
        splitDistribution: { member: 5250, [T]: 5250 },
        lastEditedBy: 'member',
      }));
    });

    test('R5-15. legacy group WITHOUT activeMemberIds: ghost payer CREATE → allowed (fallback pins the safe degradation)', async () => {
      // Same state as R5-1 but the field is absent → rules fall back to
      // memberIds, i.e. exactly today's shipped behavior. The pre-existing
      // "16. expense CREATE with ghost split key → ALLOWED" pin above is the
      // split-key twin of this fallback.
      await updateSeedGroup({ memberIds: ['owner', 'member', T] });
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc(`groups/g1/members/${T}`).set({
          id: T, userId: T, displayName: 'Former member', role: 'MEMBER',
          joinedAt: new Date(), isShadow: false, isTombstone: true,
        });
      });
      await seedEvent('e5', {
        participantIds: ['owner', 'member', T],
        participantNames: { owner: 'Owner', member: 'Member', [T]: 'Former member' },
      });
      const member = testEnv.authenticatedContext('member').firestore();
      await assertSucceeds(member.doc('groups/g1/events/e5/expenses/r15').set(
        validExpense({ id: 'r15', eventId: 'e5', createdBy: 'member', payerParticipantId: T }),
      ));
    });

    // --- group create + refresh contracts ---

    test('R5-16a. group CREATE with activeMemberIds == [uid] → allowed', async () => {
      const creator = testEnv.authenticatedContext('newuser').firestore();
      await assertSucceeds(creator.doc('groups/gNew').set(validGroup('gNew', {
        createdBy: 'newuser',
        memberIds: ['newuser'],
        activeMemberIds: ['newuser'],
      })));
    });

    test('R5-16b. group CREATE with activeMemberIds ≠ memberIds → denied', async () => {
      const creator = testEnv.authenticatedContext('newuser').firestore();
      await assertFails(creator.doc('groups/gNew').set(validGroup('gNew', {
        createdBy: 'newuser',
        memberIds: ['newuser'],
        activeMemberIds: ['newuser', 'someone-else'],
      })));
    });

    test('R5-16c. group CREATE without activeMemberIds → denied (new clients always write it)', async () => {
      const creator = testEnv.authenticatedContext('newuser').firestore();
      const data = validGroup('gNew', {
        createdBy: 'newuser',
        memberIds: ['newuser'],
      });
      delete data.activeMemberIds; // the helper now defaults it — strip to model an OLD client
      await assertFails(creator.doc('groups/gNew').set(data));
    });

    test('R5-17. client memberIds-refresh touching activeMemberIds → denied (server-maintained after create)', async () => {
      await updateSeedGroup({ activeMemberIds: ['owner', 'member'] });
      const member = testEnv.authenticatedContext('member').firestore();
      await assertFails(member.doc('groups/g1').update({
        memberIds: ['owner', 'member'],
        activeMemberIds: ['owner'],
        updatedAt: new Date(),
      }));
    });
  });
});
