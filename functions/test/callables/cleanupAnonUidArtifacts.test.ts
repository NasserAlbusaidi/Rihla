import functionsTest from 'firebase-functions-test';
import { getAuth } from 'firebase-admin/auth';
import { DocumentReference, Transaction, WriteBatch, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';
import { cleanupAnonUidArtifacts } from '../../src/callables/cleanupAnonUidArtifacts';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(cleanupAnonUidArtifacts);
const cleanupSecret = 'test-cleanup-secret-with-enough-entropy-12345';

async function clearAuthUsers(): Promise<void> {
  const auth = getAuth();
  const users = await auth.listUsers(1000);
  await Promise.all(
    users.users.map((user) => auth.deleteUser(user.uid).catch(() => undefined)),
  );
}

async function clearFcmTokens(): Promise<void> {
  const db = getFirestore();
  const docs = await db.collection('fcm_tokens').listDocuments();
  await Promise.all(docs.map((doc) => doc.delete()));
}

async function seedAuthUsers(
  newUid = 'new-uid',
  oldUid = 'old-anon-uid',
): Promise<void> {
  const auth = getAuth();
  await auth.createUser({ uid: oldUid });
  await auth.createUser({
    uid: newUid,
    email: `${newUid}@example.com`,
    password: 'Password123!',
  });
}

async function seedCleanupIntent(
  oldUid = 'old-anon-uid',
  secret = cleanupSecret,
): Promise<void> {
  await getFirestore().doc(`recoveryCleanupIntents/${oldUid}`).set({
    secret,
    createdAt: new Date(),
  });
}

function cleanupCall(
  oldUid = 'old-anon-uid',
  newUid = 'new-uid',
  secret = cleanupSecret,
): Promise<unknown> {
  return wrapped({
    data: { oldUid, cleanupSecret: secret },
    auth: { uid: newUid },
  } as any);
}

async function seedGroup(
  groupId: string,
  memberIds: string[],
  data: Record<string, unknown> = {},
): Promise<void> {
  const db = getFirestore();
  await db.doc(`groups/${groupId}`).set({
    id: groupId,
    name: groupId,
    memberIds,
    createdBy: memberIds[0],
    currency: 'OMR',
    createdAt: new Date(),
    updatedAt: new Date(),
    ...data,
  });
}

async function seedMember(
  groupId: string,
  uid: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  const db = getFirestore();
  await db.doc(`groups/${groupId}/members/${uid}`).set({
    id: uid,
    userId: uid,
    displayName: uid,
    role: 'MEMBER',
    joinedAt: new Date('2026-01-01T00:00:00.000Z'),
    isShadow: false,
    ...data,
  });
}

async function seedEvent(
  groupId: string,
  eventId: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  const db = getFirestore();
  await db.doc(`groups/${groupId}/events/${eventId}`).set({
    id: eventId,
    groupId,
    name: eventId,
    type: 'trip',
    createdBy: 'owner',
    participantIds: ['old-anon-uid'],
    participantNames: { 'old-anon-uid': 'Old Name' },
    modules: { ledger: true },
    isDeleted: false,
    createdAt: new Date(),
    updatedAt: new Date(),
    ...data,
  });
}

beforeEach(async () => {
  // #275: the new CLEANUP_BATCH_LIMIT seam is global-mutable; reset it every
  // test (mirrors deleteAccount.test.ts) so a leak from a forced-chunking test
  // cannot silently force multi-flush onto the money-conservation tests.
  delete process.env.CLEANUP_BATCH_LIMIT;
  await clearFirestore();
  await clearFcmTokens();
  await clearAuthUsers();
  jest.restoreAllMocks();
  jest.spyOn(logger, 'info').mockImplementation(() => undefined);
  jest.spyOn(logger, 'error').mockImplementation(() => undefined);
});

afterAll(async () => {
  await clearFirestore();
  await clearFcmTokens();
  await clearAuthUsers();
  testEnv.cleanup();
});

describe('cleanupAnonUidArtifacts', () => {
  test('anonymous calling UID is rejected', async () => {
    await getAuth().createUser({ uid: 'still-anon' });

    await expect(wrapped({
      data: { oldUid: 'old-anon-uid', cleanupSecret },
      auth: { uid: 'still-anon' },
    } as any)).rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('calling UID equal to oldUid is rejected', async () => {
    await getAuth().createUser({
      uid: 'same-uid',
      email: 'same@example.com',
      password: 'Password123!',
    });

    await expect(wrapped({
      data: { oldUid: 'same-uid', cleanupSecret },
      auth: { uid: 'same-uid' },
    } as any)).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('missing cleanup intent cannot migrate another UID artifacts', async () => {
    await seedAuthUsers();
    await seedGroup('victim-group', ['old-anon-uid']);
    await seedMember('victim-group', 'old-anon-uid');

    await expect(cleanupCall()).rejects.toMatchObject({
      code: 'permission-denied',
    });

    const group = await getFirestore().doc('groups/victim-group').get();
    expect(group.data()?.memberIds).toEqual(['old-anon-uid']);
    await expect(getAuth().getUser('old-anon-uid')).resolves.toBeDefined();
  });

  test('when both UIDs are members, oldUid is removed and survivor retained', async () => {
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid', 'new-uid', 'owner']);
    await seedMember('g1', 'old-anon-uid', { displayName: 'Old Name' });
    await seedMember('g1', 'new-uid', { displayName: 'New Name', role: 'CREATOR' });

    await expect(cleanupCall()).resolves.toMatchObject({
      groupsProcessed: 1,
      cascadeFailed: [],
      authUserDeleted: true,
    });

    const db = getFirestore();
    const group = await db.doc('groups/g1').get();
    const oldMember = await db.doc('groups/g1/members/old-anon-uid').get();
    const newMember = await db.doc('groups/g1/members/new-uid').get();
    expect(group.data()?.memberIds).toEqual(['new-uid', 'owner']);
    expect(oldMember.exists).toBe(false);
    expect(newMember.data()).toMatchObject({
      id: 'new-uid',
      userId: 'new-uid',
      displayName: 'New Name',
      role: 'CREATOR',
    });
  });

  test('when only oldUid is a member, it is replaced and member doc copied', async () => {
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid'], { createdBy: 'owner' });
    await seedMember('g1', 'old-anon-uid', {
      displayName: 'Recovered Name',
      role: 'CREATOR',
      isShadow: true,
    });

    await cleanupCall();

    const db = getFirestore();
    const group = await db.doc('groups/g1').get();
    const oldMember = await db.doc('groups/g1/members/old-anon-uid').get();
    const newMember = await db.doc('groups/g1/members/new-uid').get();
    expect(group.data()?.memberIds).toEqual(['new-uid']);
    expect(oldMember.exists).toBe(false);
    expect(newMember.data()).toMatchObject({
      id: 'new-uid',
      userId: 'new-uid',
      displayName: 'Recovered Name',
      role: 'CREATOR',
      isShadow: true,
    });
    expect(newMember.data()?.joinedAt).toBeDefined();
  });

  // #294: a recovering CREATOR's member doc is keyed by a random uuid (userId:
  // oldUid), so the old `.doc(oldUid)` point read missed it — the copy/delete
  // were gated on a non-existent doc, leaving the recovered creator with no
  // member doc keyed to their new uid + a stale uuid doc pointing at the dead uid.
  // Matching by the `userId` FIELD migrates it (normalized to .doc(newUid)).
  test('#294 migrates a uuid-keyed creator member doc on recovery', async () => {
    const db = getFirestore();
    const creatorDocId = 'creator-uuid-eeee-ffff';
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid'], { createdBy: 'old-anon-uid' });
    // creator member doc keyed by a uuid, userId is the old anon uid:
    await db.doc(`groups/g1/members/${creatorDocId}`).set({
      id: creatorDocId,
      userId: 'old-anon-uid',
      displayName: 'Recovered Creator',
      role: 'CREATOR',
      joinedAt: new Date('2026-01-01T00:00:00.000Z'),
      isShadow: false,
    });

    await cleanupCall();

    const group = await db.doc('groups/g1').get();
    const newMember = await db.doc('groups/g1/members/new-uid').get();
    const oldUuidDoc = await db.doc(`groups/g1/members/${creatorDocId}`).get();

    expect(group.data()?.memberIds).toEqual(['new-uid']);
    expect(group.data()?.createdBy).toBe('new-uid');
    // the uuid-keyed doc is gone, migrated/normalized to .doc(newUid):
    expect(oldUuidDoc.exists).toBe(false);
    expect(newMember.data()).toMatchObject({
      id: 'new-uid',
      userId: 'new-uid',
      displayName: 'Recovered Creator',
      role: 'CREATOR',
    });
    // no member doc anywhere still carries the old uid:
    const remaining = await db.collection('groups/g1/members').get();
    for (const doc of remaining.docs) {
      expect(doc.data().userId).not.toBe('old-anon-uid');
    }
  });

  test('createdBy is rewritten on group, active event, active expense, and settlements', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid'], { createdBy: 'old-anon-uid' });
    await seedMember('g1', 'old-anon-uid');
    await seedEvent('g1', 'active', { createdBy: 'old-anon-uid' });
    await seedEvent('g1', 'deleted', {
      createdBy: 'old-anon-uid',
      isDeleted: true,
    });
    await db.doc('groups/g1/events/active/expenses/x1').set({
      id: 'x1',
      createdBy: 'old-anon-uid',
      isDeleted: false,
    });
    await db.doc('groups/g1/events/active/expenses/x2').set({
      id: 'x2',
      createdBy: 'old-anon-uid',
      isDeleted: true,
    });
    await db.doc('groups/g1/events/active/settlements/s1').set({
      id: 's1',
      createdBy: 'old-anon-uid',
    });

    await cleanupCall();

    const group = await db.doc('groups/g1').get();
    const activeEvent = await db.doc('groups/g1/events/active').get();
    const deletedEvent = await db.doc('groups/g1/events/deleted').get();
    const activeExpense = await db.doc('groups/g1/events/active/expenses/x1').get();
    const deletedExpense = await db.doc('groups/g1/events/active/expenses/x2').get();
    const settlement = await db.doc('groups/g1/events/active/settlements/s1').get();
    expect(group.data()?.createdBy).toBe('new-uid');
    expect(activeEvent.data()?.createdBy).toBe('new-uid');
    expect(deletedEvent.data()?.createdBy).toBe('old-anon-uid');
    expect(activeExpense.data()?.createdBy).toBe('new-uid');
    expect(deletedExpense.data()?.createdBy).toBe('old-anon-uid');
    // #216: settlement createdBy migrates (settlements are append-only live
    // financial records; the recovered user must retain ownership of them).
    expect(settlement.data()?.createdBy).toBe('new-uid');
  });

  test('event participantIds and participantNames replace oldUid with calling UID', async () => {
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid']);
    await seedMember('g1', 'old-anon-uid');
    await seedEvent('g1', 'e1', {
      participantIds: ['old-anon-uid', 'owner'],
      participantNames: {
        'old-anon-uid': 'Old Name',
        owner: 'Owner',
      },
    });

    await cleanupCall();

    const event = await getFirestore().doc('groups/g1/events/e1').get();
    expect(event.data()?.participantIds).toEqual(['new-uid', 'owner']);
    expect(event.data()?.participantNames).toEqual({
      'new-uid': 'Old Name',
      owner: 'Owner',
    });
  });

  // #216: the recovery cascade must migrate the FINANCIAL ledger surface
  // (expense payer/split/customSplit + event & group settlement payer/recipient/
  // createdBy) oldUid -> newUid, otherwise the balance engine treats the
  // now-deleted oldUid as a "former financial actor" and splits the recovered
  // user into two. These are MIGRATE semantics (repoint UID refs only), NOT the
  // scrub semantics of deleteAccount — display names / notes are left intact.
  test('#216 active expense payer/split/customSplit migrate oldUid -> newUid', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid'], { createdBy: 'owner' });
    await seedMember('g1', 'old-anon-uid');
    await seedEvent('g1', 'e1', {
      participantIds: ['old-anon-uid', 'owner'],
      participantNames: { 'old-anon-uid': 'Old Name', owner: 'Owner' },
    });
    await db.doc('groups/g1/events/e1/expenses/x1').set({
      id: 'x1',
      createdBy: 'old-anon-uid',
      payerParticipantId: 'old-anon-uid',
      splitDistribution: { 'old-anon-uid': 1500, owner: 1500 },
      customSplitParticipants: ['old-anon-uid', 'owner'],
      isDeleted: false,
    });

    await cleanupCall();

    const x1 = (await db.doc('groups/g1/events/e1/expenses/x1').get()).data();
    expect(x1?.payerParticipantId).toBe('new-uid');
    expect(x1?.createdBy).toBe('new-uid');
    expect(x1?.splitDistribution).toEqual({ 'new-uid': 1500, owner: 1500 });
    expect(x1?.customSplitParticipants).toEqual(['new-uid', 'owner']);
  });

  test('#216 splitDistribution collision sums subunits; customSplit dedupes', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    // Both oldUid and newUid are members of the same group/expense — the
    // collision case deleteAccount.renameMapKey would silently clobber.
    await seedGroup('g1', ['old-anon-uid', 'new-uid', 'owner']);
    await seedMember('g1', 'old-anon-uid', { displayName: 'Old' });
    await seedMember('g1', 'new-uid', { displayName: 'New' });
    await seedEvent('g1', 'e1', {
      participantIds: ['old-anon-uid', 'new-uid', 'owner'],
      participantNames: {
        'old-anon-uid': 'Old',
        'new-uid': 'New',
        owner: 'Owner',
      },
    });
    await db.doc('groups/g1/events/e1/expenses/x1').set({
      id: 'x1',
      createdBy: 'owner',
      payerParticipantId: 'owner',
      // exact split, amount 3000 subunits; old=1000 + new=500 must MERGE to 1500
      // so sum stays 3000 (conservation) — not be clobbered to 1000.
      splitDistribution: { 'old-anon-uid': 1000, 'new-uid': 500, owner: 1500 },
      customSplitParticipants: ['old-anon-uid', 'new-uid', 'owner'],
      isDeleted: false,
    });

    await cleanupCall();

    const x1 = (await db.doc('groups/g1/events/e1/expenses/x1').get()).data();
    const dist = x1?.splitDistribution as Record<string, number>;
    expect(dist['old-anon-uid']).toBeUndefined();
    expect(dist['new-uid']).toBe(1500);
    expect(dist.owner).toBe(1500);
    // conservation: total subunits unchanged
    expect(Object.values(dist).reduce((a, b) => a + b, 0)).toBe(3000);
    // custom split collapses the duplicated person to a single head
    expect(x1?.customSplitParticipants).toEqual(['new-uid', 'owner']);
  });

  test('#216 event settlement payer/recipient/createdBy migrate; names preserved', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid']);
    await seedMember('g1', 'old-anon-uid', { displayName: 'Old Name' });
    await seedEvent('g1', 'e1');
    // oldUid as payer
    await db.doc('groups/g1/events/e1/settlements/s1').set({
      id: 's1',
      payerParticipantId: 'old-anon-uid',
      recipientParticipantId: 'owner',
      payerName: 'Old Name',
      recipientName: 'Owner',
      createdBy: 'old-anon-uid',
      isDeleted: false,
    });
    // oldUid as recipient
    await db.doc('groups/g1/events/e1/settlements/s2').set({
      id: 's2',
      payerParticipantId: 'owner',
      recipientParticipantId: 'old-anon-uid',
      payerName: 'Owner',
      recipientName: 'Old Name',
      createdBy: 'owner',
      isDeleted: false,
    });

    await cleanupCall();

    const s1 = (await db.doc('groups/g1/events/e1/settlements/s1').get()).data();
    expect(s1?.payerParticipantId).toBe('new-uid');
    expect(s1?.recipientParticipantId).toBe('owner');
    expect(s1?.createdBy).toBe('new-uid');
    // migrate-not-scrub: denormalized display name is the SAME person, untouched
    expect(s1?.payerName).toBe('Old Name');
    expect(s1?.recipientName).toBe('Owner');

    const s2 = (await db.doc('groups/g1/events/e1/settlements/s2').get()).data();
    expect(s2?.payerParticipantId).toBe('owner');
    expect(s2?.recipientParticipantId).toBe('new-uid');
    expect(s2?.createdBy).toBe('owner');
    expect(s2?.recipientName).toBe('Old Name');
  });

  test('#216 group-level settlement payer/recipient/createdBy migrate', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid']);
    await seedMember('g1', 'old-anon-uid', { displayName: 'Old Name' });
    await db.doc('groups/g1/settlements/gs1').set({
      id: 'gs1',
      payerParticipantId: 'owner',
      recipientParticipantId: 'old-anon-uid',
      payerName: 'Owner',
      recipientName: 'Old Name',
      createdBy: 'old-anon-uid',
      isDeleted: false,
    });

    await cleanupCall();

    const gs1 = (await db.doc('groups/g1/settlements/gs1').get()).data();
    expect(gs1?.recipientParticipantId).toBe('new-uid');
    expect(gs1?.createdBy).toBe('new-uid');
    expect(gs1?.payerParticipantId).toBe('owner');
    expect(gs1?.recipientName).toBe('Old Name');
  });

  test('#216 soft-deleted expense financial fields are NOT migrated (inert residual)', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid']);
    await seedMember('g1', 'old-anon-uid');
    await seedEvent('g1', 'e1');
    await db.doc('groups/g1/events/e1/expenses/xdel').set({
      id: 'xdel',
      createdBy: 'old-anon-uid',
      payerParticipantId: 'old-anon-uid',
      splitDistribution: { 'old-anon-uid': 1000 },
      isDeleted: true,
    });

    await cleanupCall();

    const xdel = (await db.doc('groups/g1/events/e1/expenses/xdel').get()).data();
    // Soft-deleted expenses never feed balances; left active-only by design
    // (matches the existing createdBy policy). The oldUid ref is inert.
    expect(xdel?.payerParticipantId).toBe('old-anon-uid');
    expect(xdel?.createdBy).toBe('old-anon-uid');
  });

  // #217: the recovery cascade must also migrate the ACTIVITY surface
  // (event activity_logs + group activity) oldUid -> newUid. MIGRATE semantics:
  // repoint actorId/targetParticipantId + UID-bearing metadata VALUES only;
  // actorName/logText/description are denormalized display strings for the SAME
  // recovered person and are left untouched (contrast deleteAccount, which scrubs
  // them to "Deleted member"). Activity is non-financial — the balance engine
  // never reads it — so these are inert orphans, not money bugs; we migrate them
  // for completeness (same defect class as #216).
  test('#217 event activity_logs actorId/targetParticipantId migrate; names untouched', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid']);
    await seedMember('g1', 'old-anon-uid', { displayName: 'Old Name' });
    await seedEvent('g1', 'e1');
    await db.doc('groups/g1/events/e1/activity_logs/a1').set({
      id: 'a1',
      eventId: 'e1',
      category: 'MONEY',
      eventType: 'CREATE',
      logText: 'Old Name added an expense',
      actorId: 'old-anon-uid',
      targetParticipantId: 'old-anon-uid',
      actorName: 'Old Name',
      metadata: {},
      createdAt: '2026-01-01T00:00:00.000Z',
    });
    // A log by another actor must be left completely untouched (no write).
    await db.doc('groups/g1/events/e1/activity_logs/a2').set({
      id: 'a2',
      eventId: 'e1',
      category: 'MONEY',
      eventType: 'CREATE',
      logText: 'Owner added an expense',
      actorId: 'owner',
      actorName: 'Owner',
      metadata: {},
      createdAt: '2026-01-02T00:00:00.000Z',
    });

    await cleanupCall();

    const a1 = (await db.doc('groups/g1/events/e1/activity_logs/a1').get()).data();
    expect(a1?.actorId).toBe('new-uid');
    expect(a1?.targetParticipantId).toBe('new-uid');
    // migrate-not-scrub: display strings for the SAME person, untouched
    expect(a1?.actorName).toBe('Old Name');
    expect(a1?.logText).toBe('Old Name added an expense');
    expect(a1?.createdAt).toBe('2026-01-01T00:00:00.000Z');

    const a2 = (await db.doc('groups/g1/events/e1/activity_logs/a2').get()).data();
    expect(a2?.actorId).toBe('owner');
  });

  test('#217 event activity_logs metadata UID values migrate; non-UID untouched', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid']);
    await seedMember('g1', 'old-anon-uid');
    await seedEvent('g1', 'e1');
    await db.doc('groups/g1/events/e1/activity_logs/a1').set({
      id: 'a1',
      eventId: 'e1',
      category: 'MONEY',
      eventType: 'CREATE',
      logText: 'Old Name added an expense for 3.000 OMR',
      actorId: 'owner',
      actorName: 'Owner',
      metadata: {
        expenseId: 'x1',
        amount: '3.000',
        amountFils: 3000,
        currency: 'OMR',
        payerParticipantId: 'old-anon-uid',
        customSplitParticipants: ['old-anon-uid', 'owner'],
        scope: 'global',
      },
      createdAt: '2026-01-01T00:00:00.000Z',
    });

    await cleanupCall();

    const a1 = (await db.doc('groups/g1/events/e1/activity_logs/a1').get()).data();
    const meta = a1?.metadata as Record<string, unknown>;
    expect(meta.payerParticipantId).toBe('new-uid');
    expect(meta.customSplitParticipants).toEqual(['new-uid', 'owner']);
    // non-UID metadata is byte-identical
    expect(meta.expenseId).toBe('x1');
    expect(meta.amount).toBe('3.000');
    expect(meta.amountFils).toBe(3000);
    expect(meta.currency).toBe('OMR');
    expect(meta.scope).toBe('global');
    // actorId here is 'owner' (not oldUid) — unchanged
    expect(a1?.actorId).toBe('owner');
  });

  test('#217 group activity actorId + metadata.recipientId migrate; names untouched', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid']);
    await seedMember('g1', 'old-anon-uid', { displayName: 'Old Name' });
    await db.doc('groups/g1/activity/ga1').set({
      id: 'ga1',
      type: 'group_settlement',
      actorId: 'old-anon-uid',
      actorName: 'Old Name',
      description: 'settled 5.000 OMR with Owner',
      metadata: { amount: '5.000', recipientId: 'old-anon-uid' },
      timestamp: '2026-01-01T00:00:00.000Z',
    });
    // member_joined by another actor with UID-free metadata: left untouched.
    await db.doc('groups/g1/activity/ga2').set({
      id: 'ga2',
      type: 'member_joined',
      actorId: 'owner',
      actorName: 'Owner',
      description: 'joined the group',
      metadata: { groupId: 'g1' },
      timestamp: '2026-01-02T00:00:00.000Z',
    });

    await cleanupCall();

    const ga1 = (await db.doc('groups/g1/activity/ga1').get()).data();
    expect(ga1?.actorId).toBe('new-uid');
    expect((ga1?.metadata as Record<string, unknown>).recipientId).toBe('new-uid');
    expect((ga1?.metadata as Record<string, unknown>).amount).toBe('5.000');
    // migrate-not-scrub
    expect(ga1?.actorName).toBe('Old Name');
    expect(ga1?.description).toBe('settled 5.000 OMR with Owner');
    expect(ga1?.timestamp).toBe('2026-01-01T00:00:00.000Z');

    const ga2 = (await db.doc('groups/g1/activity/ga2').get()).data();
    expect(ga2?.actorId).toBe('owner');
    expect((ga2?.metadata as Record<string, unknown>).groupId).toBe('g1');
  });

  test('#217 soft-deleted event activity_logs are NOT migrated (active-only, inert)', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid']);
    await seedMember('g1', 'old-anon-uid');
    await seedEvent('g1', 'edel', { isDeleted: true });
    await db.doc('groups/g1/events/edel/activity_logs/a1').set({
      id: 'a1',
      eventId: 'edel',
      category: 'MONEY',
      eventType: 'CREATE',
      logText: 'Old Name added an expense',
      actorId: 'old-anon-uid',
      actorName: 'Old Name',
      metadata: {},
      createdAt: '2026-01-01T00:00:00.000Z',
    });

    await cleanupCall();

    const a1 = (await db.doc('groups/g1/events/edel/activity_logs/a1').get()).data();
    // Active-only policy, matching #216's soft-deleted-expense skip: the feed
    // never surfaces a soft-deleted event's activity, so the oldUid ref is inert.
    expect(a1?.actorId).toBe('old-anon-uid');
  });

  // #217 adversarial / identity-collision axis: when newUid is ALREADY a member
  // (both-UIDs case), the activity metadata array DUPLICATES (not sums, not dedups)
  // while the parallel expense splitDistribution SUMS — proving the two paths use
  // deliberately different collision semantics on the same axis. Activity metadata
  // is display-only and never aggregated, so a dup is inert; money must conserve.
  test('#217 both-members collision: metadata array dups (NOT sums) while splitDistribution sums', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid', 'new-uid', 'owner']);
    await seedMember('g1', 'old-anon-uid', { displayName: 'Old' });
    await seedMember('g1', 'new-uid', { displayName: 'New' });
    await seedEvent('g1', 'e1', {
      participantIds: ['old-anon-uid', 'new-uid', 'owner'],
      participantNames: { 'old-anon-uid': 'Old', 'new-uid': 'New', owner: 'Owner' },
    });
    await db.doc('groups/g1/events/e1/expenses/x1').set({
      id: 'x1',
      createdBy: 'owner',
      payerParticipantId: 'owner',
      splitDistribution: { 'old-anon-uid': 1000, 'new-uid': 500, owner: 1500 },
      customSplitParticipants: ['old-anon-uid', 'new-uid', 'owner'],
      isDeleted: false,
    });
    await db.doc('groups/g1/events/e1/activity_logs/a1').set({
      id: 'a1',
      eventId: 'e1',
      category: 'MONEY',
      eventType: 'CREATE',
      logText: 'an expense',
      actorId: 'old-anon-uid',
      actorName: 'Old',
      metadata: {
        payerParticipantId: 'owner',
        customSplitParticipants: ['old-anon-uid', 'new-uid', 'owner'],
      },
      createdAt: '2026-01-01T00:00:00.000Z',
    });

    await cleanupCall();

    // Money path: splitDistribution conserves by SUMMING the collision (#216).
    const x1 = (await db.doc('groups/g1/events/e1/expenses/x1').get()).data();
    const dist = x1?.splitDistribution as Record<string, number>;
    expect(dist['new-uid']).toBe(1500);
    expect(Object.values(dist).reduce((a, b) => a + b, 0)).toBe(3000);
    // Activity path: inert display array DUPLICATES (no sum, no dedup), actorId migrates.
    const a1 = (await db.doc('groups/g1/events/e1/activity_logs/a1').get()).data();
    expect(a1?.actorId).toBe('new-uid');
    expect((a1?.metadata as Record<string, unknown>).customSplitParticipants)
      .toEqual(['new-uid', 'new-uid', 'owner']);
  });

  // #217: a forced activity-write failure must enter the cascadeFailed gate
  // (#46) — preserve the old anon Auth user + the cleanup intent for retry. The
  // existing per-group-failure test (above) throws in the READ phase, before any
  // activity write, so it does not cover this surface.
  // #275: activity writes now go through the Phase B BatchWriter, not a
  // transaction, so the spy retargets to WriteBatch.prototype.commit (the
  // mechanism deleteAccount.test.ts already proves works; there is no
  // WriteBatch.prototype.update spy precedent). The seeded group has ONLY an
  // activity-log doc (no expenses/settlements), so the single Phase B flush IS
  // the activity write — rejecting that commit is precisely an activity-write
  // failure. Assertions unchanged.
  test('#217 activity write failure gates auth delete + preserves intent', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid']);
    await seedMember('g1', 'old-anon-uid');
    await seedEvent('g1', 'e1');
    await db.doc('groups/g1/events/e1/activity_logs/a1').set({
      id: 'a1',
      eventId: 'e1',
      category: 'MONEY',
      eventType: 'CREATE',
      logText: 'Old Name added an expense',
      actorId: 'old-anon-uid',
      actorName: 'Old Name',
      metadata: {},
      createdAt: '2026-01-01T00:00:00.000Z',
    });

    const spy = jest
      .spyOn(WriteBatch.prototype, 'commit')
      .mockImplementation(function (this: WriteBatch) {
        return Promise.reject(new Error('forced activity batch commit failure'));
      });

    try {
      const result = await cleanupCall() as {
        cascadeFailed: string[];
        authUserDeleted: boolean;
      };

      expect(result.cascadeFailed).toEqual(['g1']);
      expect(result.authUserDeleted).toBe(false);
      await expect(getAuth().getUser('old-anon-uid')).resolves.toBeDefined();
      expect((await db.doc('recoveryCleanupIntents/old-anon-uid').get()).exists)
        .toBe(true);
    } finally {
      spy.mockRestore();
    }
  });

  test('deleted anon auth user returns authUserDeleted true', async () => {
    await seedAuthUsers();
    await seedCleanupIntent();

    const result = await cleanupCall() as { authUserDeleted: boolean };

    expect(result.authUserDeleted).toBe(true);
    await expect(getAuth().getUser('old-anon-uid'))
      .rejects.toMatchObject({ code: 'auth/user-not-found' });
  });

  test('auth/user-not-found during auth delete returns false without throwing', async () => {
    await seedAuthUsers();
    await seedCleanupIntent();
    await getAuth().deleteUser('old-anon-uid');

    await expect(cleanupCall()).resolves.toMatchObject({
      authUserDeleted: false,
    });
  });

  // AC1 (#46 phase 1): per-group failure must NOT delete the old anon
  // auth user and must NOT consume the cleanup intent. fcm/joinAttempts
  // deletes run BEFORE the Auth-delete gate so that recoverable identity
  // residue is scrubbed even when groups partially fail.
  test('per-group failure preserves auth user and cleanup intent (#46 AC1)', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await db.doc('fcm_tokens/old-anon-uid').set({ token: 'stale' });
    await db.doc('joinAttempts/old-anon-uid').set({ failCount: 3 });
    await seedGroup('good', ['old-anon-uid']);
    await seedMember('good', 'old-anon-uid');
    await seedGroup('bad', ['old-anon-uid']);
    await seedMember('bad', 'old-anon-uid');
    await seedEvent('bad', 'bad-event', { participantIds: 'old-anon-uid' });

    const result = await cleanupCall() as {
      groupsProcessed: number;
      cascadeFailed: string[];
      authUserDeleted: boolean;
      fcmTokenDeleted: boolean;
      joinAttemptsDeleted: boolean;
    };

    expect(result.groupsProcessed).toBe(1);
    expect(result.cascadeFailed).toEqual(['bad']);

    // P0 zombie-auth bug fix: Auth.deleteUser is gated on cascadeFailed.length === 0
    expect(result.authUserDeleted).toBe(false);
    await expect(getAuth().getUser('old-anon-uid')).resolves.toBeDefined();

    // Reorder: fcm/joinAttempts ARE attempted even when groups fail,
    // so identity residue is scrubbed and a retry doesn't see it.
    expect(result.fcmTokenDeleted).toBe(true);
    expect(result.joinAttemptsDeleted).toBe(true);
    expect((await db.doc('fcm_tokens/old-anon-uid').get()).exists).toBe(false);
    expect((await db.doc('joinAttempts/old-anon-uid').get()).exists).toBe(false);

    // Intent is preserved so the client can retry within the 15-min window
    expect((await db.doc('recoveryCleanupIntents/old-anon-uid').get()).exists)
      .toBe(true);

    // Group state: good migrated, bad untouched
    const good = await db.doc('groups/good').get();
    const bad = await db.doc('groups/bad').get();
    expect(good.data()?.memberIds).toEqual(['new-uid']);
    expect(bad.data()?.memberIds).toEqual(['old-anon-uid']);
  });

  // AC1b: fcm delete failure must enter cascadeFailed and gate Auth-delete.
  test('fcm delete failure gates auth delete (#46 AC1b)', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await db.doc('fcm_tokens/old-anon-uid').set({ token: 'stale' });

    const originalDelete = DocumentReference.prototype.delete;
    const spy = jest
      .spyOn(DocumentReference.prototype, 'delete')
      .mockImplementation(function (this: DocumentReference) {
        if (this.path === 'fcm_tokens/old-anon-uid') {
          return Promise.reject(new Error('forced fcm delete failure'));
        }
        return originalDelete.call(this);
      });

    try {
      const result = await cleanupCall() as {
        cascadeFailed: string[];
        authUserDeleted: boolean;
        fcmTokenDeleted: boolean;
      };

      expect(result.cascadeFailed).toContain('fcm_tokens');
      expect(result.authUserDeleted).toBe(false);
      expect(result.fcmTokenDeleted).toBe(false);
      await expect(getAuth().getUser('old-anon-uid')).resolves.toBeDefined();
      expect((await db.doc('recoveryCleanupIntents/old-anon-uid').get()).exists)
        .toBe(true);
    } finally {
      spy.mockRestore();
    }
  });

  // AC1c: joinAttempts delete failure must enter cascadeFailed and gate.
  test('joinAttempts delete failure gates auth delete (#46 AC1c)', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await db.doc('joinAttempts/old-anon-uid').set({ failCount: 3 });

    const originalDelete = DocumentReference.prototype.delete;
    const spy = jest
      .spyOn(DocumentReference.prototype, 'delete')
      .mockImplementation(function (this: DocumentReference) {
        if (this.path === 'joinAttempts/old-anon-uid') {
          return Promise.reject(new Error('forced joinAttempts delete failure'));
        }
        return originalDelete.call(this);
      });

    try {
      const result = await cleanupCall() as {
        cascadeFailed: string[];
        authUserDeleted: boolean;
        joinAttemptsDeleted: boolean;
      };

      expect(result.cascadeFailed).toContain('joinAttempts');
      expect(result.authUserDeleted).toBe(false);
      expect(result.joinAttemptsDeleted).toBe(false);
      await expect(getAuth().getUser('old-anon-uid')).resolves.toBeDefined();
      expect((await db.doc('recoveryCleanupIntents/old-anon-uid').get()).exists)
        .toBe(true);
    } finally {
      spy.mockRestore();
    }
  });

  test('fcm token for oldUid is deleted when present', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await db.doc('fcm_tokens/old-anon-uid').set({ token: 'stale-token' });

    const result = await cleanupCall() as { fcmTokenDeleted: boolean };

    const fcmToken = await db.doc('fcm_tokens/old-anon-uid').get();
    expect(result.fcmTokenDeleted).toBe(true);
    expect(fcmToken.exists).toBe(false);
  });

  test('absent fcm token returns false without error', async () => {
    await seedAuthUsers();
    await seedCleanupIntent();

    await expect(cleanupCall()).resolves.toMatchObject({
      fcmTokenDeleted: false,
    });
  });

  test('join attempt and cleanup intent for oldUid are deleted after cleanup', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await db.doc('joinAttempts/old-anon-uid').set({ failCount: 3 });

    await expect(cleanupCall()).resolves.toMatchObject({
      joinAttemptsDeleted: true,
    });

    expect((await db.doc('joinAttempts/old-anon-uid').get()).exists).toBe(false);
    expect((await db.doc('recoveryCleanupIntents/old-anon-uid').get()).exists)
      .toBe(false);
  });

  // #275: the per-group cascade is now a chunked BatchWriter (Phase B child
  // scrubs) + a bounded transactional Phase C (identity retirement), escaping
  // the 500-write-per-transaction cliff. These three tests pin the convergence
  // contract the non-atomic execution relies on.

  // ARCHITECTURE-DISTINGUISHING RED: on the old single-transaction code, forcing
  // the group-doc update (the FIRST write of the one transaction) to fail rolled
  // back EVERYTHING — the splitDistribution sum never committed. On the rewrite,
  // Phase B's batch already committed the sum before Phase C's identity write
  // fails, so the sum is durable and the retry must NOT apply it a second time.
  test('#275 torn identity write keeps the batched split sum; retry does not double-sum', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid', 'new-uid', 'owner']);
    await seedMember('g1', 'old-anon-uid', { displayName: 'Old' });
    await seedMember('g1', 'new-uid', { displayName: 'New' });
    await seedEvent('g1', 'e1', {
      participantIds: ['old-anon-uid', 'new-uid', 'owner'],
      participantNames: { 'old-anon-uid': 'Old', 'new-uid': 'New', owner: 'Owner' },
    });
    await db.doc('groups/g1/events/e1/expenses/x1').set({
      id: 'x1',
      createdBy: 'owner',
      payerParticipantId: 'owner',
      splitDistribution: { 'old-anon-uid': 1000, 'new-uid': 500, owner: 1500 },
      isDeleted: false,
    });

    // Reject the group-doc update. On the rewrite this is the Phase C
    // transaction (Transaction.prototype.update on groups/g1), AFTER Phase B's
    // batch committed; on the old code it is the first tx.update of the single
    // transaction, taking the whole cascade (and the sum) down with it.
    const originalUpdate = Transaction.prototype.update;
    const spy = jest
      .spyOn(Transaction.prototype, 'update')
      .mockImplementation(function (this: Transaction, ref: any, ...rest: any[]) {
        if (typeof ref?.path === 'string' && ref.path === 'groups/g1') {
          throw new Error('forced group-update failure');
        }
        return (originalUpdate as any).call(this, ref, ...rest);
      });

    let firstResult: any;
    try {
      firstResult = await cleanupCall();
    } finally {
      spy.mockRestore();
    }

    expect(firstResult.cascadeFailed).toEqual(['g1']);
    expect(firstResult.authUserDeleted).toBe(false);

    // The batched sum survives the failed identity write.
    const x1AfterFail = (await db.doc('groups/g1/events/e1/expenses/x1').get()).data();
    const distAfterFail = x1AfterFail?.splitDistribution as Record<string, number>;
    expect(distAfterFail['new-uid']).toBe(1500);
    expect(distAfterFail['old-anon-uid']).toBeUndefined();
    // Group stays query-visible (oldUid still a member) so the retry converges.
    expect((await db.doc('groups/g1').get()).data()?.memberIds).toContain('old-anon-uid');
    await expect(getAuth().getUser('old-anon-uid')).resolves.toBeDefined();

    // Retry, no spy → converges with NO double-sum.
    const secondResult = await cleanupCall() as {
      cascadeFailed: string[];
      authUserDeleted: boolean;
    };
    expect(secondResult.cascadeFailed).toEqual([]);
    expect(secondResult.authUserDeleted).toBe(true);

    const x1Final = (await db.doc('groups/g1/events/e1/expenses/x1').get()).data();
    const distFinal = x1Final?.splitDistribution as Record<string, number>;
    expect(distFinal['new-uid']).toBe(1500); // NOT 2000 — mergeUidMapKey saw no oldUid key
    expect(Object.values(distFinal).reduce((a, b) => a + b, 0)).toBe(3000);
    expect((await db.doc('groups/g1').get()).data()?.memberIds).toEqual(['new-uid', 'owner']);
  });

  // A cascade spanning MULTIPLE batch flushes (forced via the low CLEANUP_BATCH_
  // LIMIT seam) produces the identical fully-migrated end state — the testable
  // surrogate for the un-seedable 500-doc cliff (mirrors deleteAccount's
  // DELETE_ACCOUNT_BATCH_LIMIT='2' torn-multi-batch test).
  test('#275 cascade spanning multiple batch flushes still converges', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid', 'owner'], { createdBy: 'old-anon-uid' });
    await seedMember('g1', 'old-anon-uid', { displayName: 'Old' });
    await seedEvent('g1', 'e1', {
      participantIds: ['old-anon-uid', 'owner'],
      participantNames: { 'old-anon-uid': 'Old', owner: 'Owner' },
    });
    for (let i = 0; i < 6; i += 1) {
      await db.doc(`groups/g1/events/e1/expenses/x${i}`).set({
        id: `x${i}`,
        createdBy: 'old-anon-uid',
        payerParticipantId: 'old-anon-uid',
        splitDistribution: { 'old-anon-uid': 1000, owner: 1000 },
        isDeleted: false,
      });
    }

    process.env.CLEANUP_BATCH_LIMIT = '3';
    try {
      await expect(cleanupCall()).resolves.toMatchObject({
        groupsProcessed: 1,
        cascadeFailed: [],
        authUserDeleted: true,
      });
    } finally {
      delete process.env.CLEANUP_BATCH_LIMIT;
    }

    const group = await db.doc('groups/g1').get();
    expect(group.data()?.memberIds).toEqual(['new-uid', 'owner']);
    expect(group.data()?.createdBy).toBe('new-uid');
    for (let i = 0; i < 6; i += 1) {
      const x = (await db.doc(`groups/g1/events/e1/expenses/x${i}`).get()).data();
      const dist = x?.splitDistribution as Record<string, number>;
      expect(x?.payerParticipantId).toBe('new-uid');
      expect(x?.createdBy).toBe('new-uid');
      expect(dist['new-uid']).toBe(1000);
      expect(dist['old-anon-uid']).toBeUndefined();
    }
    await expect(getAuth().getUser('old-anon-uid'))
      .rejects.toMatchObject({ code: 'auth/user-not-found' });
  });

  // ORDERING (§3b): the identity write that removes oldUid from memberIds is
  // Phase C, AFTER Phase B's flush. A Phase B child-write failure must leave the
  // group query-visible (oldUid still in memberIds) so the #46 retry converges.
  test('#275 a Phase B child-write failure leaves the group query-visible for retry', async () => {
    const db = getFirestore();
    await seedAuthUsers();
    await seedCleanupIntent();
    await seedGroup('g1', ['old-anon-uid'], { createdBy: 'owner' });
    await seedMember('g1', 'old-anon-uid', { displayName: 'Old' });
    await seedEvent('g1', 'e1', {
      participantIds: ['old-anon-uid', 'owner'],
      participantNames: { 'old-anon-uid': 'Old', owner: 'Owner' },
    });
    await db.doc('groups/g1/events/e1/expenses/x1').set({
      id: 'x1',
      createdBy: 'old-anon-uid',
      payerParticipantId: 'old-anon-uid',
      splitDistribution: { 'old-anon-uid': 1000, owner: 1000 },
      isDeleted: false,
    });

    const spy = jest
      .spyOn(WriteBatch.prototype, 'commit')
      .mockImplementation(function (this: WriteBatch) {
        return Promise.reject(new Error('forced batch commit failure'));
      });

    let result: any;
    try {
      result = await cleanupCall();
    } finally {
      spy.mockRestore();
    }

    expect(result.cascadeFailed).toEqual(['g1']);
    expect(result.authUserDeleted).toBe(false);
    // memberIds untouched: Phase C (the identity write) never ran.
    expect((await db.doc('groups/g1').get()).data()?.memberIds).toEqual(['old-anon-uid']);
    await expect(getAuth().getUser('old-anon-uid')).resolves.toBeDefined();
    expect((await db.doc('recoveryCleanupIntents/old-anon-uid').get()).exists).toBe(true);
  });
});
