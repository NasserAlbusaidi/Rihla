import functionsTest from 'firebase-functions-test';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore, Timestamp, WriteBatch } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { createHash } from 'crypto';
import { clearFirestore } from '../fixtures';
import { deleteAccount } from '../../src/callables/deleteAccount';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(deleteAccount);

const deletedUid = 'uid-delete';
const otherUid = 'uid-other';
const oldName = 'Alice Example';
const otherName = 'Omar Other';

async function clearAuthUsers(): Promise<void> {
  const auth = getAuth();
  const users = await auth.listUsers(1000);
  await Promise.all(
    users.users.map((user) => auth.deleteUser(user.uid).catch(() => undefined)),
  );
}

async function clearGlobalDocs(): Promise<void> {
  const db = getFirestore();
  for (const collection of ['fcm_tokens', 'joinAttempts', 'deletionAttempts', 'deletionAudit']) {
    const docs = await db.collection(collection).listDocuments();
    await Promise.all(docs.map((doc) => doc.delete()));
  }
}

async function seedAuthUser(uid = deletedUid): Promise<void> {
  await getAuth().createUser({
    uid,
    email: `${uid}@example.com`,
    password: 'Password123!',
  });
}

async function seedGroup(
  groupId: string,
  memberIds: string[],
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore().doc(`groups/${groupId}`).set({
    id: groupId,
    name: groupId,
    memberIds,
    createdBy: memberIds[0],
    inviteCode: `${groupId}123`.slice(0, 6).toUpperCase(),
    currency: 'OMR',
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    updatedAt: new Date('2026-01-02T00:00:00.000Z'),
    isDeleted: false,
    deletedAt: null,
    ...data,
  });
}

async function seedMember(
  groupId: string,
  uid: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore().doc(`groups/${groupId}/members/${uid}`).set({
    id: uid,
    userId: uid,
    displayName: uid === deletedUid ? oldName : otherName,
    role: uid === deletedUid ? 'CREATOR' : 'MEMBER',
    joinedAt: new Date(uid === deletedUid
      ? '2026-01-01T00:00:00.000Z'
      : '2026-01-03T00:00:00.000Z'),
    isShadow: false,
    ...data,
  });
}

async function seedEvent(
  groupId: string,
  eventId: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore().doc(`groups/${groupId}/events/${eventId}`).set({
    id: eventId,
    groupId,
    name: eventId,
    type: 'trip',
    createdBy: deletedUid,
    participantIds: [deletedUid, otherUid],
    participantNames: {
      [deletedUid]: oldName,
      [otherUid]: otherName,
    },
    modules: { ledger: true },
    isDeleted: false,
    createdAt: new Date('2026-01-04T00:00:00.000Z'),
    updatedAt: new Date('2026-01-05T00:00:00.000Z'),
    ...data,
  });
}

function expectNoDeletedIdentity(data: FirebaseFirestore.DocumentData | undefined): void {
  expect(JSON.stringify(data)).not.toContain(deletedUid);
  expect(JSON.stringify(data)).not.toContain(oldName);
}

beforeEach(async () => {
  delete process.env.DELETE_ACCOUNT_BATCH_LIMIT;
  await clearFirestore();
  await clearGlobalDocs();
  await clearAuthUsers();
  jest.restoreAllMocks();
  jest.spyOn(logger, 'info').mockImplementation(() => undefined);
  jest.spyOn(logger, 'error').mockImplementation(() => undefined);
});

// Re-apply the logger spies after a mid-test jest.restoreAllMocks() (used in the
// retry legs to clear a forced-failure spy) — restoreAllMocks also clears the
// beforeEach logger spies.
function muteLoggers(): void {
  jest.spyOn(logger, 'info').mockImplementation(() => undefined);
  jest.spyOn(logger, 'error').mockImplementation(() => undefined);
}

async function seedExpense(path: string): Promise<void> {
  await getFirestore().doc(path).set({
    id: path.split('/').pop(),
    createdBy: deletedUid,
    payerParticipantId: deletedUid,
    amountFils: 1000,
    currency: 'OMR',
    scope: 'custom',
    splitMode: 'exact',
    customSplitParticipants: [deletedUid, otherUid],
    splitDistribution: { [deletedUid]: 500, [otherUid]: 500 },
    description: 'expense',
    note: 'note',
    receiptUrl: 'receipts/x.png',
    isDeleted: false,
    deletedAt: null,
    createdAt: '2026-01-06T00:00:00.000Z',
  });
}

const tombstoneIdFor = (uid: string): string =>
  `deleted-${createHash('sha1').update(uid).digest('hex').slice(0, 8)}`;

// #1099: spy the three groups-collection reads inside runAccountDeletionCascade
// (S0 at :804, the bounded re-query passes, and the final membership check) so a
// concurrent membership write can be injected deterministically relative to them.
// `hooks.before(n)` / `hooks.after(n)` run (awaited) immediately before / after the
// n-th `groups` query's get() resolves — so a seed in after(1) is durable before any
// re-query yet invisible to S0 (its snapshot is captured first), and a re-add in
// before(n>=2) lands after the prior pass's scrub. Every other method (listDocuments,
// used by clearFirestore, etc.) forwards untouched, so the spy is safe to leave
// installed through afterAll. Seeds MUST use db.doc(...) paths — never
// db.collection('groups') — so the seeding never re-enters this counter.
function spyGroupsReads(
  db: FirebaseFirestore.Firestore,
  hooks: {
    before?: (callNumber: number) => Promise<void>;
    after?: (callNumber: number) => Promise<void>;
  } = {},
): { calls: () => number } {
  const realCollection = db.collection.bind(db);
  let calls = 0;
  jest.spyOn(db, 'collection').mockImplementation(((path: string) => {
    const real = realCollection(path);
    if (path !== 'groups') return real;
    calls += 1;
    const n = calls;
    return new Proxy(real, {
      get(target, prop, receiver) {
        if (prop !== 'where') {
          const forwarded = Reflect.get(target, prop, receiver);
          return typeof forwarded === 'function' ? forwarded.bind(target) : forwarded;
        }
        return (field: string, op: FirebaseFirestore.WhereFilterOp, value: unknown) => {
          const query = target.where(field, op, value as never);
          return new Proxy(query, {
            get(qTarget, qProp, qReceiver) {
              if (qProp !== 'get') {
                const forwarded = Reflect.get(qTarget, qProp, qReceiver);
                return typeof forwarded === 'function' ? forwarded.bind(qTarget) : forwarded;
              }
              return async () => {
                if (hooks.before) await hooks.before(n);
                const snap = await qTarget.get();
                if (hooks.after) await hooks.after(n);
                return snap;
              };
            },
          });
        };
      },
    });
  }) as never);
  return { calls: () => calls };
}

afterAll(async () => {
  await clearFirestore();
  await clearGlobalDocs();
  await clearAuthUsers();
  testEnv.cleanup();
});

describe('deleteAccount', () => {
  test('missing auth is rejected', async () => {
    await expect(wrapped({ data: {} } as any))
      .rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('cascades identity deletion while preserving ledger facts', async () => {
    const db = getFirestore();
    await seedAuthUser();
    await seedGroup('groupA', [deletedUid, otherUid], { createdBy: deletedUid });
    await seedMember('groupA', deletedUid);
    await seedMember('groupA', otherUid);
    await seedGroup('groupB', [deletedUid], { createdBy: deletedUid });
    await seedMember('groupB', deletedUid);
    await seedEvent('groupA', 'eventA');
    await seedEvent('groupA', 'deletedEvent', { isDeleted: true });
    await db.doc('groups/groupA/events/eventA/expenses/paid').set({
      id: 'paid',
      eventId: 'eventA',
      createdBy: deletedUid,
      payerParticipantId: deletedUid,
      amountFils: 12000,
      currency: 'OMR',
      description: `${oldName} dinner`,
      scope: 'custom',
      customSplitParticipants: [deletedUid, otherUid],
      splitMode: 'exact',
      splitDistribution: { [deletedUid]: 6000, [otherUid]: 6000 },
      receiptUrl: 'receipts/alice.png',
      note: `${oldName} note`,
      isDeleted: false,
      deletedAt: null,
      createdAt: '2026-01-06T00:00:00.000Z',
    });
    await db.doc('groups/groupA/events/eventA/expenses/softDeleted').set({
      id: 'softDeleted',
      eventId: 'eventA',
      createdBy: otherUid,
      payerParticipantId: otherUid,
      amountFils: 9000,
      currency: 'OMR',
      description: 'soft deleted split',
      scope: 'custom',
      customSplitParticipants: [deletedUid],
      splitMode: 'shares',
      splitDistribution: { [deletedUid]: 1 },
      receiptUrl: 'receipts/split.png',
      note: 'split note',
      isDeleted: true,
      deletedAt: '2026-01-07T00:00:00.000Z',
      createdAt: '2026-01-06T00:00:00.000Z',
    });
    await db.doc('groups/groupA/events/eventA/settlements/eventSettlement').set({
      id: 'eventSettlement',
      eventId: 'eventA',
      createdBy: otherUid,
      payerParticipantId: otherUid,
      recipientParticipantId: deletedUid,
      payerName: otherName,
      recipientName: oldName,
      amountFils: 3000,
      currency: 'OMR',
      note: `${oldName} settlement note`,
      isDeleted: false,
      deletedAt: null,
      settledAt: '2026-01-08T00:00:00.000Z',
    });
    await db.doc('groups/groupA/settlements/groupSettlement').set({
      id: 'groupSettlement',
      groupId: 'groupA',
      eventId: 'groupA',
      scope: 'group',
      createdBy: deletedUid,
      payerParticipantId: deletedUid,
      recipientParticipantId: otherUid,
      payerName: oldName,
      recipientName: otherName,
      amountFils: 4000,
      currency: 'OMR',
      note: `${oldName} group note`,
      isDeleted: false,
      deletedAt: null,
      settledAt: '2026-01-09T00:00:00.000Z',
    });
    await db.doc('groups/groupA/events/eventA/activity_logs/eventActivity').set({
      id: 'eventActivity',
      eventId: 'eventA',
      actorId: deletedUid,
      targetParticipantId: deletedUid,
      actorName: oldName,
      category: 'MONEY',
      eventType: 'CREATE',
      logText: `${oldName} paid dinner`,
      metadata: {
        actorId: deletedUid,
        actorName: oldName,
        recipientName: oldName,
      },
      createdAt: '2026-01-10T00:00:00.000Z',
    });
    await db.doc('groups/groupA/activity/groupActivity').set({
      id: 'groupActivity',
      type: 'group_settlement',
      actorId: deletedUid,
      actorName: oldName,
      description: `${oldName} settled with ${otherName}`,
      metadata: {
        recipientId: deletedUid,
        recipientName: oldName,
      },
      timestamp: '2026-01-11T00:00:00.000Z',
    });
    await db.doc(`fcm_tokens/${deletedUid}`).set({ token: 'stale-token' });
    await db.doc(`joinAttempts/${deletedUid}`).set({ count: 3 });

    const result = await wrapped({
      data: {},
      auth: { uid: deletedUid },
    } as any);

    expect(result).toMatchObject({
      groupsProcessed: 2,
      expensesScrubbed: 2,
      settlementsScrubbed: 2,
      activityLogsScrubbed: 2,
      membersDeleted: 2,
      groupsOrphanedAndSoftDeleted: 1,
      fcmTokenDeleted: true,
      joinAttemptsDeleted: true,
      authUserDeleted: true,
    });
    expect(result.tombstoneIds).toHaveLength(2);

    const groupA = await db.doc('groups/groupA').get();
    const groupAMemberIds = groupA.data()?.memberIds as string[];
    const groupATombstoneId = groupAMemberIds.find((id) => id.startsWith('deleted-'));
    expect(groupA.data()).toMatchObject({
      createdBy: otherUid,
      isDeleted: false,
    });
    expect(groupATombstoneId).toBeDefined();
    expect(groupAMemberIds).toContain(otherUid);
    expect(groupAMemberIds).not.toContain(deletedUid);
    // #1144 R5: the legacy group (no activeMemberIds) self-heals on this
    // roster write — seeded memberIds-minus-tombstones, then {remove: uid}.
    // The tombstone NEVER enters the active set.
    expect(groupA.data()?.activeMemberIds).toEqual([otherUid]);

    const tombstoneMember = await db.doc(`groups/groupA/members/${groupATombstoneId}`).get();
    const oldMember = await db.doc(`groups/groupA/members/${deletedUid}`).get();
    expect(oldMember.exists).toBe(false);
    expect(tombstoneMember.data()).toMatchObject({
      id: groupATombstoneId,
      userId: groupATombstoneId,
      displayName: 'Deleted member',
      role: 'MEMBER',
      isTombstone: true,
    });
    expectNoDeletedIdentity(tombstoneMember.data());

    const groupB = await db.doc('groups/groupB').get();
    expect(groupB.data()).toMatchObject({
      createdBy: 'deleted-user',
      isDeleted: true,
    });

    const event = await db.doc('groups/groupA/events/eventA').get();
    expect(event.data()).toMatchObject({
      createdBy: 'deleted-user',
    });
    expect(event.data()?.participantIds).toContain(groupATombstoneId);
    expect(event.data()?.participantIds).not.toContain(deletedUid);
    expect(event.data()?.participantNames).toMatchObject({
      [groupATombstoneId!]: 'Deleted member',
      [otherUid]: otherName,
    });
    expectNoDeletedIdentity(event.data());

    const paid = await db.doc('groups/groupA/events/eventA/expenses/paid').get();
    expect(paid.data()).toMatchObject({
      createdBy: 'deleted-user',
      payerParticipantId: groupATombstoneId,
      customSplitParticipants: [groupATombstoneId, otherUid],
      splitDistribution: { [groupATombstoneId!]: 6000, [otherUid]: 6000 },
      receiptUrl: null,
      note: null,
      description: null,
    });
    expect(paid.data()?.amountFils).toBe(12000);
    expectNoDeletedIdentity(paid.data());

    const softDeleted = await db.doc('groups/groupA/events/eventA/expenses/softDeleted').get();
    expect(softDeleted.data()).toMatchObject({
      payerParticipantId: otherUid,
      customSplitParticipants: [groupATombstoneId],
      splitDistribution: { [groupATombstoneId!]: 1 },
      receiptUrl: null,
      note: null,
      description: null,
      isDeleted: true,
    });
    expectNoDeletedIdentity(softDeleted.data());

    const eventSettlement = await db.doc(
      'groups/groupA/events/eventA/settlements/eventSettlement',
    ).get();
    expect(eventSettlement.data()).toMatchObject({
      payerParticipantId: otherUid,
      recipientParticipantId: groupATombstoneId,
      payerName: otherName,
      recipientName: 'Deleted member',
      note: null,
    });
    expectNoDeletedIdentity(eventSettlement.data());

    const groupSettlement = await db.doc('groups/groupA/settlements/groupSettlement').get();
    expect(groupSettlement.data()).toMatchObject({
      createdBy: 'deleted-user',
      payerParticipantId: groupATombstoneId,
      recipientParticipantId: otherUid,
      payerName: 'Deleted member',
      recipientName: otherName,
      note: null,
    });
    expectNoDeletedIdentity(groupSettlement.data());

    const eventActivity = await db.doc(
      'groups/groupA/events/eventA/activity_logs/eventActivity',
    ).get();
    expect(eventActivity.data()).toMatchObject({
      actorId: groupATombstoneId,
      targetParticipantId: groupATombstoneId,
      actorName: 'Deleted member',
    });
    expectNoDeletedIdentity(eventActivity.data());

    const groupActivity = await db.doc('groups/groupA/activity/groupActivity').get();
    expect(groupActivity.data()).toMatchObject({
      actorId: groupATombstoneId,
      actorName: 'Deleted member',
    });
    expectNoDeletedIdentity(groupActivity.data());

    expect((await db.doc(`fcm_tokens/${deletedUid}`).get()).exists).toBe(false);
    expect((await db.doc(`joinAttempts/${deletedUid}`).get()).exists).toBe(false);
    await expect(getAuth().getUser(deletedUid))
      .rejects.toMatchObject({ code: 'auth/user-not-found' });
  });

  describe('#1133 closedBy + spendingSnapshot scrub', () => {
    const DESC_PII = 'dinner-at-my-secret-address-42';

    it('scrubs closedBy uid and spendingSnapshot uids/descriptions from the closed event', async () => {
      await seedAuthUser();
      await seedGroup('groupA', [deletedUid, otherUid], { createdBy: otherUid });
      await seedMember('groupA', deletedUid);
      await seedMember('groupA', otherUid);
      await seedEvent('groupA', 'eventA', {
        createdBy: otherUid,
        isClosed: true,
        closedAt: new Date('2026-01-06T00:00:00.000Z'),
        closedBy: deletedUid,
        spendingSnapshot: {
          v: 1,
          participantCount: 2,
          expenseCount: 1,
          totals: { OMR: 5000 },
          biggest: { OMR: { id: 'e1', amt: 5000, desc: DESC_PII, cat: 'food', payer: deletedUid } },
          payers: { OMR: [{ id: deletedUid, amt: 5000 }, { id: otherUid, amt: 0 }] },
          categories: { OMR: [{ cat: 'food', amt: 5000 }] },
          owed: { OMR: { [deletedUid]: 2500, [otherUid]: 2500 } },
        },
      });

      await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

      const event = (await getFirestore().doc('groups/groupA/events/eventA').get()).data();
      expectNoDeletedIdentity(event);
      const t = tombstoneIdFor(deletedUid);
      expect(event?.closedBy).toBe(t);
      const snap = event?.spendingSnapshot;
      expect(snap.biggest.OMR.payer).toBe(t);
      expect(snap.biggest.OMR).not.toHaveProperty('desc');
      expect(snap.payers.OMR.map((p: { id: string }) => p.id)).toContain(t);
      expect(Object.keys(snap.owed.OMR)).toContain(t);
      expect(JSON.stringify(snap)).not.toContain(DESC_PII);
      expect(snap.owed.OMR[t]).toBe(2500); // amount preserved on re-key
      expect(snap.owed.OMR[otherUid]).toBe(2500);
    });

    it('SUMS (never drops) owed on the #1099 tombstone-collision re-delete', async () => {
      const t = tombstoneIdFor(deletedUid);
      await seedAuthUser();
      await seedGroup('groupC', [deletedUid, otherUid], { createdBy: otherUid });
      await seedMember('groupC', deletedUid);
      await seedMember('groupC', otherUid);
      await seedEvent('groupC', 'eventC', {
        createdBy: otherUid,
        isClosed: true,
        closedAt: new Date('2026-01-06T00:00:00.000Z'),
        closedBy: otherUid,
        // Collision: owed holds BOTH the prior tombstone T and the re-added uid U.
        spendingSnapshot: {
          v: 1,
          participantCount: 2,
          expenseCount: 1,
          totals: { OMR: 3500 },
          biggest: { OMR: { id: 'e1', amt: 3500, payer: otherUid } },
          payers: { OMR: [{ id: deletedUid, amt: 3500 }] },
          categories: { OMR: [{ cat: 'food', amt: 3500 }] },
          owed: { OMR: { [t]: 1000, [deletedUid]: 2500 } },
        },
      });

      await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

      const snap = (await getFirestore().doc('groups/groupC/events/eventC').get()).data()
        ?.spendingSnapshot;
      // MERGE-SUM, not last-write-wins drop (2500) and not overwrite: 1000 + 2500.
      expect(snap.owed.OMR[t]).toBe(3500);
      expect(snap.owed.OMR).not.toHaveProperty(deletedUid);
    });

    it('leaves an unrelated event snapshot (no deleted-user reference) byte-for-byte untouched', async () => {
      await seedAuthUser();
      await seedGroup('groupB', [deletedUid, otherUid], { createdBy: otherUid });
      await seedMember('groupB', deletedUid);
      await seedMember('groupB', otherUid);
      const untouched = {
        v: 1,
        participantCount: 1,
        expenseCount: 1,
        totals: { OMR: 1000 },
        biggest: { OMR: { id: 'x1', amt: 1000, desc: 'others-only-dinner', payer: otherUid } },
        payers: { OMR: [{ id: otherUid, amt: 1000 }] },
        categories: { OMR: [{ cat: 'food', amt: 1000 }] },
        owed: { OMR: { [otherUid]: 1000 } },
      };
      await seedEvent('groupB', 'eventB', {
        createdBy: otherUid,
        participantIds: [otherUid],
        participantNames: { [otherUid]: otherName },
        isClosed: true,
        closedAt: new Date('2026-01-06T00:00:00.000Z'),
        closedBy: otherUid,
        spendingSnapshot: untouched,
      });

      await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

      const event = (await getFirestore().doc('groups/groupB/events/eventB').get()).data();
      expect(event?.spendingSnapshot).toEqual(untouched); // no collateral desc drop
    });

    it('converges on a forged partial-shape snapshot (gate trips, biggest/payers absent) without injecting undefined', async () => {
      await seedAuthUser();
      await seedGroup('groupD', [deletedUid, otherUid], { createdBy: otherUid });
      await seedMember('groupD', deletedUid);
      await seedMember('groupD', otherUid);
      // Rules-legal but hand-rolled: spendingSnapshotBounded checks only
      // `is map && size()<=16`, so a co-member can write a snapshot with the gate
      // tripping via `owed` while `biggest`/`payers` are ABSENT. The scrub must NOT
      // inject `spendingSnapshot.biggest: undefined` (Admin SDK rejects undefined →
      // cascade throws → deletion permanently blocked).
      await seedEvent('groupD', 'eventD', {
        createdBy: otherUid,
        isClosed: true,
        closedAt: new Date('2026-01-06T00:00:00.000Z'),
        closedBy: otherUid,
        spendingSnapshot: { owed: { OMR: { [deletedUid]: 1000 } } },
      });

      const result = await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

      // Cascade CONVERGES: no cascadeFailed, auth user deleted.
      expect(result.cascadeFailed).toEqual([]);
      expect(result.authUserDeleted).toBe(true);
      const snap = (await getFirestore().doc('groups/groupD/events/eventD').get()).data()
        ?.spendingSnapshot;
      const t = tombstoneIdFor(deletedUid);
      expect(snap.owed.OMR[t]).toBe(1000); // re-keyed, value preserved
      expect(snap).not.toHaveProperty('biggest'); // no undefined key injected
      expect(snap).not.toHaveProperty('payers');
    });
  });

  test('second run is idempotent after the UID has been scrubbed', async () => {
    await seedAuthUser();
    await seedGroup('groupA', [deletedUid, otherUid], { createdBy: otherUid });
    await seedMember('groupA', deletedUid);
    await seedMember('groupA', otherUid);

    const first = await wrapped({
      data: {},
      auth: { uid: deletedUid },
    } as any);
    const second = await wrapped({
      data: {},
      auth: { uid: deletedUid },
    } as any);

    expect(first.groupsProcessed).toBe(1);
    expect(second).toMatchObject({
      groupsProcessed: 0,
      expensesScrubbed: 0,
      settlementsScrubbed: 0,
      activityLogsScrubbed: 0,
      membersDeleted: 0,
      groupsOrphanedAndSoftDeleted: 0,
      authUserDeleted: false,
    });
  });

  test('#710 scrubs itemized splitExplanation, lastEditedBy, and stamps the expense scrub sentinel', async () => {
    const db = getFirestore();
    await seedAuthUser();
    await seedGroup('groupA', [deletedUid, otherUid], { createdBy: otherUid });
    await seedMember('groupA', deletedUid);
    await seedMember('groupA', otherUid);
    await seedEvent('groupA', 'eventA');
    await db.doc('groups/groupA/events/eventA/expenses/itemized').set({
      id: 'itemized',
      eventId: 'eventA',
      createdBy: otherUid,
      lastEditedBy: deletedUid,
      payerParticipantId: otherUid,
      amountFils: 12000,
      currency: 'OMR',
      scope: 'custom',
      splitMode: 'exact',
      customSplitParticipants: [deletedUid, otherUid],
      splitDistribution: { [deletedUid]: 6000, [otherUid]: 6000 },
      splitExplanation: {
        type: 'itemized',
        version: 1,
        requestTrace: `manual-${deletedUid}-${oldName}`,
        items: [{
          label: `${oldName} coffee`,
          amountFils: 12000,
          quantity: 1,
          participantIds: [deletedUid],
          allocation: 'equal',
          nested: { [deletedUid]: `opaque-${deletedUid}-${oldName}` },
        }],
      },
      isDeleted: false,
      deletedAt: null,
      createdAt: '2026-01-06T00:00:00.000Z',
    });

    const result = await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

    expect(result.expensesScrubbed).toBe(1);
    const tombstoneId = tombstoneIdFor(deletedUid);
    const expense = (await db.doc('groups/groupA/events/eventA/expenses/itemized').get()).data();
    expect(expense).toMatchObject({
      lastEditedBy: 'deleted-user',
      customSplitParticipants: [tombstoneId, otherUid],
      splitDistribution: { [tombstoneId]: 6000, [otherUid]: 6000 },
      receiptUrl: null,
      note: null,
      description: null,
    });
    expect(expense?.splitExplanation).toMatchObject({
      type: 'itemized',
      version: 1,
      requestTrace: `manual-${tombstoneId}-Deleted member`,
      items: [expect.objectContaining({
        label: 'Deleted member coffee',
        participantIds: [tombstoneId],
        nested: { [tombstoneId]: `opaque-${tombstoneId}-Deleted member` },
      })],
    });
    expect(expense?.deleteAccountScrubAt).toBeInstanceOf(Timestamp);
    expectNoDeletedIdentity(expense);
  });

  test('#710 active pre-join claim state blocks Auth deletion and writes deletionAudit', async () => {
    const db = getFirestore();
    await seedAuthUser();
    await seedGroup('claimGroup', [otherUid, 'shadow-1'], { createdBy: otherUid });
    await seedMember('claimGroup', otherUid);
    await seedMember('claimGroup', 'shadow-1', { isShadow: true, displayName: 'Ali' });
    await db.doc(`groups/claimGroup/claimRequests/${deletedUid}__shadow-1`).set({
      requesterUid: deletedUid,
      requesterDisplayName: oldName,
      shadowMemberId: 'shadow-1',
      shadowDisplayName: 'Ali',
      status: 'claiming',
      createdAt: Timestamp.now(),
      decidedBy: null,
      decidedAt: null,
      claimingBy: otherUid,
      claimingAt: Timestamp.fromMillis(1000),
      claimMutationStartedAt: Timestamp.fromMillis(2000),
    });
    await db.doc('groups/claimGroup/claimShadowLocks/shadow-1').set({
      groupId: 'claimGroup',
      shadowMemberId: 'shadow-1',
      claimerUid: deletedUid,
      requestId: `${deletedUid}__shadow-1`,
      lockedBy: otherUid,
      lockedAt: Timestamp.fromMillis(1000),
      mutationStartedAt: Timestamp.fromMillis(2000),
      updatedAt: Timestamp.fromMillis(2000),
    });

    await expect(wrapped({ data: {}, auth: { uid: deletedUid } } as any))
      .rejects.toMatchObject({ code: 'internal' });

    await expect(getAuth().getUser(deletedUid)).resolves.toMatchObject({ uid: deletedUid });
    const marker = (await db.doc(`deletionAudit/${deletedUid}`).get()).data();
    expect(marker).toMatchObject({ uid: deletedUid, status: 'failed' });
    expect(marker?.cascadeFailed).toContain('claimGroup');
  });

  // #714 P1 #1: the two collectionGroup scrub queries need COLLECTION_GROUP indexes
  // (added to firestore.indexes.json). The emulator ignores indexes, so simulate the
  // prod FAILED_PRECONDITION: it must degrade to partialCascade (auth user preserved,
  // 'claimState' recorded), NOT abort the whole cascade before the Auth-delete gate.
  test('#714 a claim-state scrub query failure degrades to partialCascade (auth preserved)', async () => {
    const db = getFirestore();
    await seedAuthUser();
    jest.spyOn(db, 'collectionGroup').mockImplementation(() => {
      throw new Error('FAILED_PRECONDITION: The query requires an index.');
    });

    await expect(wrapped({ data: {}, auth: { uid: deletedUid } } as any))
      .rejects.toMatchObject({ code: 'internal' });

    // Auth user preserved → the still-valid session can retry the (idempotent) cascade.
    await expect(getAuth().getUser(deletedUid)).resolves.toMatchObject({ uid: deletedUid });
    const marker = (await db.doc(`deletionAudit/${deletedUid}`).get()).data();
    expect(marker?.cascadeFailed).toContain('claimState');
  });

  test('user with no groups still deletes global docs and auth user', async () => {
    const db = getFirestore();
    await seedAuthUser();
    await db.doc(`fcm_tokens/${deletedUid}`).set({ token: 'stale-token' });
    await db.doc(`joinAttempts/${deletedUid}`).set({ count: 2 });

    const result = await wrapped({
      data: {},
      auth: { uid: deletedUid },
    } as any);

    expect(result).toMatchObject({
      groupsProcessed: 0,
      fcmTokenDeleted: true,
      joinAttemptsDeleted: true,
      authUserDeleted: true,
    });
    expect((await db.doc(`fcm_tokens/${deletedUid}`).get()).exists).toBe(false);
    expect((await db.doc(`joinAttempts/${deletedUid}`).get()).exists).toBe(false);
  });

  // #469: deleting a DURABLE account that owns data must remove the Auth user
  // (so reconnecting yields a fresh empty account) AND scrub its data. The #469
  // bug was the client targeting an anon shell; this locks the server half so a
  // regression where the durable Auth user survives a delete is caught.
  // deleteUser removes the entire Auth user including all providerData; a
  // password provider suffices to lock "the durable user is fully removed" (a
  // google.com federated provider would need importUsers, out of scope here).
  test('deleting a durable account that owns a group removes the Auth user and scrubs the group (#469)', async () => {
    const db = getFirestore();
    await seedAuthUser();
    await seedGroup('grp469', [deletedUid]);
    await seedMember('grp469', deletedUid);

    const result = await wrapped({
      data: {},
      auth: { uid: deletedUid },
    } as any);

    expect(result).toMatchObject({ authUserDeleted: true });

    // The durable Auth user is gone — a reconnect would mint a new uid.
    await expect(getAuth().getUser(deletedUid)).rejects.toMatchObject({
      code: 'auth/user-not-found',
    });

    // The solo-owned group is soft-deleted and the member doc removed.
    const group = await db.doc('groups/grp469').get();
    expect(group.data()?.isDeleted).toBe(true);
    expect((await db.doc(`groups/grp469/members/${deletedUid}`).get()).exists)
      .toBe(false);
  });

  // #73: per-UID invocation rate limit (compensating control for soft App Check).
  test('rejects with resource-exhausted once the per-UID limit is reached', async () => {
    const db = getFirestore();
    await seedAuthUser();
    await seedGroup('groupA', [deletedUid, otherUid], { createdBy: otherUid });
    await seedMember('groupA', deletedUid);
    await seedMember('groupA', otherUid);
    // Counter already at the limit, window still open.
    await db.doc(`deletionAttempts/${deletedUid}`).set({
      count: 5,
      windowStart: Timestamp.now(),
      expiresAt: Timestamp.fromMillis(Timestamp.now().toMillis() + 60 * 60 * 1000),
    });

    await expect(wrapped({ data: {}, auth: { uid: deletedUid } } as any))
      .rejects.toMatchObject({ code: 'resource-exhausted' });

    // Cascade must NOT have run: the group still lists the UID and the auth user lives.
    expect((await db.doc('groups/groupA').get()).data()?.memberIds).toContain(deletedUid);
    await expect(getAuth().getUser(deletedUid)).resolves.toMatchObject({ uid: deletedUid });
  });

  test('writes a TTL-bearing counter on a normal deletion', async () => {
    const db = getFirestore();
    await seedAuthUser();
    await seedGroup('groupA', [deletedUid, otherUid], { createdBy: otherUid });
    await seedMember('groupA', deletedUid);
    await seedMember('groupA', otherUid);

    await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

    const counter = (await db.doc(`deletionAttempts/${deletedUid}`).get()).data();
    expect(counter?.count).toBeGreaterThanOrEqual(1);
    expect(counter?.expiresAt).toBeInstanceOf(Timestamp);
    expect((counter?.expiresAt as Timestamp).toMillis())
      .toBeGreaterThan((counter?.windowStart as Timestamp).toMillis());
  });

  test('resets the counter when the prior window has elapsed', async () => {
    const db = getFirestore();
    await seedAuthUser();
    await seedGroup('groupA', [deletedUid, otherUid], { createdBy: otherUid });
    await seedMember('groupA', deletedUid);
    await seedMember('groupA', otherUid);
    // Stale window (2h ago) at the limit — must not block; counter resets to 1.
    await db.doc(`deletionAttempts/${deletedUid}`).set({
      count: 5,
      windowStart: Timestamp.fromMillis(Timestamp.now().toMillis() - 2 * 60 * 60 * 1000),
      expiresAt: Timestamp.fromMillis(Timestamp.now().toMillis() - 60 * 60 * 1000),
    });

    const result = await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

    expect(result.groupsProcessed).toBe(1);
    expect((await db.doc(`deletionAttempts/${deletedUid}`).get()).data()?.count).toBe(1);
  });

  // #46: convergence — a per-group failure must be ISOLATED (other groups still
  // scrubbed), the callable must THROW (so the client doesn't sign out), the Auth
  // user must survive, and a retry must converge.
  test('partial cascade isolates the failure, throws, preserves auth, then converges on retry', async () => {
    const db = getFirestore();
    await seedAuthUser();
    for (const gid of ['groupP', 'groupQ']) {
      await seedGroup(gid, [deletedUid, otherUid], { createdBy: deletedUid });
      await seedMember(gid, deletedUid);
      await seedMember(gid, otherUid);
      await seedEvent(gid, 'ev');
      await seedExpense(`groups/${gid}/events/ev/expenses/e1`);
    }

    // Reject the FIRST Phase-B batch commit once; real for the rest. (Phase C
    // transactions don't go through WriteBatch.prototype.commit, so only one
    // group's child-scrub flush fails.)
    const realCommit = WriteBatch.prototype.commit;
    let commits = 0;
    jest.spyOn(WriteBatch.prototype, 'commit').mockImplementation(function (this: WriteBatch) {
      commits += 1;
      if (commits === 1) return Promise.reject(new Error('forced phase-B failure'));
      return realCommit.apply(this);
    });

    await expect(wrapped({ data: {}, auth: { uid: deletedUid } } as any))
      .rejects.toMatchObject({ code: 'internal' });

    // Auth user preserved.
    await expect(getAuth().getUser(deletedUid)).resolves.toMatchObject({ uid: deletedUid });
    // Exactly one group still lists the uid (the failed one); the other was scrubbed.
    const stillHasUid = await Promise.all(['groupP', 'groupQ'].map(async (gid) =>
      ((await db.doc(`groups/${gid}`).get()).data()?.memberIds as string[]).includes(deletedUid)));
    expect(stillHasUid.filter(Boolean)).toHaveLength(1);

    // ---- retry converges ----
    jest.restoreAllMocks();
    muteLoggers();
    const retry = await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

    expect(retry.cascadeFailed).toEqual([]);
    for (const gid of ['groupP', 'groupQ']) {
      expect(((await db.doc(`groups/${gid}`).get()).data()?.memberIds as string[]))
        .not.toContain(deletedUid);
      expect((await db.doc(`groups/${gid}/members/${deletedUid}`).get()).exists).toBe(false);
    }
    await expect(getAuth().getUser(deletedUid)).rejects.toMatchObject({ code: 'auth/user-not-found' });
  });

  // #46: the "scrubbed but Auth-delete failed" branch (previously untested).
  test('auth-delete failure after a full scrub throws internal and stays retryable', async () => {
    const db = getFirestore();
    await seedAuthUser();
    await seedGroup('groupA', [deletedUid, otherUid], { createdBy: otherUid });
    await seedMember('groupA', deletedUid);
    await seedMember('groupA', otherUid);

    jest.spyOn(getAuth(), 'deleteUser').mockRejectedValueOnce(
      Object.assign(new Error('boom'), { code: 'auth/internal-error' }),
    );

    await expect(wrapped({ data: {}, auth: { uid: deletedUid } } as any))
      .rejects.toMatchObject({ code: 'internal' });

    // Firestore fully scrubbed despite the auth-delete failure...
    expect(((await db.doc('groups/groupA').get()).data()?.memberIds as string[]))
      .not.toContain(deletedUid);
    // ...and the Auth user survives so a retry can finish it.
    await expect(getAuth().getUser(deletedUid)).resolves.toMatchObject({ uid: deletedUid });

    jest.restoreAllMocks();
    muteLoggers();
    const retry = await wrapped({ data: {}, auth: { uid: deletedUid } } as any);
    expect(retry.groupsProcessed).toBe(0);
    await expect(getAuth().getUser(deletedUid)).rejects.toMatchObject({ code: 'auth/user-not-found' });
  });

  // #46: tombstone identity is deterministic (no per-retry accumulation) and never
  // overwrites a real member that happens to occupy the derived id.
  test('tombstone id is deterministic across groups and collision-guarded', async () => {
    const db = getFirestore();
    await seedAuthUser();
    const expectedId = tombstoneIdFor(deletedUid);

    await seedGroup('g1', [deletedUid, otherUid], { createdBy: otherUid });
    await seedMember('g1', deletedUid);
    await seedMember('g1', otherUid);

    await seedGroup('g2', [deletedUid, otherUid, expectedId], { createdBy: otherUid });
    await seedMember('g2', deletedUid);
    await seedMember('g2', otherUid);
    await db.doc(`groups/g2/members/${expectedId}`).set({
      id: expectedId, userId: expectedId, displayName: 'Real Person',
      role: 'MEMBER', joinedAt: new Date('2026-01-02T00:00:00.000Z'), isShadow: false,
    });

    const result = await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

    const g1 = (await db.doc('groups/g1').get()).data()?.memberIds as string[];
    expect(g1).toContain(expectedId);
    expect((await db.doc(`groups/g1/members/${expectedId}`).get()).data())
      .toMatchObject({ isTombstone: true });

    const g2 = (await db.doc('groups/g2').get()).data()?.memberIds as string[];
    expect(g2).toContain(`${expectedId}-2`);
    expect((await db.doc(`groups/g2/members/${expectedId}`).get()).data())
      .toMatchObject({ displayName: 'Real Person' });
    expect((await db.doc(`groups/g2/members/${expectedId}-2`).get()).data())
      .toMatchObject({ isTombstone: true });
    expect(result.tombstoneIds).toContain(expectedId);
    expect(result.tombstoneIds).toContain(`${expectedId}-2`);
  });

  // #46: a torn multi-batch group (Phase B committed a prefix then failed) must
  // stay query-visible with its member doc intact, and converge with no name
  // residue and a single tombstone on retry.
  test('torn multi-batch group stays recoverable and converges without residue', async () => {
    const db = getFirestore();
    process.env.DELETE_ACCOUNT_BATCH_LIMIT = '2';
    await seedAuthUser();
    await seedGroup('big', [deletedUid, otherUid], { createdBy: otherUid });
    await seedMember('big', deletedUid);
    await seedMember('big', otherUid);
    await seedEvent('big', 'ev');
    await seedExpense('groups/big/events/ev/expenses/e1');
    await seedExpense('groups/big/events/ev/expenses/e2');
    await seedExpense('groups/big/events/ev/expenses/e3');
    // Name-only residue: actor is otherUid, the only deletedUid trace is the old name.
    await db.doc('groups/big/activity/a1').set({
      id: 'a1', type: 'note', actorId: otherUid, actorName: otherName,
      description: `${oldName} joined the trip`,
      metadata: { recipientName: oldName },
      timestamp: '2026-01-11T00:00:00.000Z',
    });

    // Commit batch 1 (durable prefix), then fail batch 2 → Phase B throws.
    const realCommit = WriteBatch.prototype.commit;
    let commits = 0;
    jest.spyOn(WriteBatch.prototype, 'commit').mockImplementation(function (this: WriteBatch) {
      commits += 1;
      if (commits === 2) return Promise.reject(new Error('forced mid-group failure'));
      return realCommit.apply(this);
    });

    await expect(wrapped({ data: {}, auth: { uid: deletedUid } } as any))
      .rejects.toMatchObject({ code: 'internal' });

    // [P1] group stays query-visible AND old member survives (so retry resolves the name).
    expect(((await db.doc('groups/big').get()).data()?.memberIds as string[])).toContain(deletedUid);
    expect((await db.doc(`groups/big/members/${deletedUid}`).get()).exists).toBe(true);
    // #714 P1 #4: the accountDeletionInProgress freeze (acquired before Phase B) MUST be
    // released when Phase B throws, or every co-member's writes to this group are frozen
    // group-wide until the same uid's deletionReaper converges.
    expect((await db.doc('groups/big').get()).data()?.accountDeletionInProgress).toBeUndefined();

    // ---- retry (real commit, default batch limit) ----
    delete process.env.DELETE_ACCOUNT_BATCH_LIMIT;
    jest.restoreAllMocks();
    muteLoggers();
    const retry = await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

    expect(retry.cascadeFailed).toEqual([]);
    const tombstoneId = tombstoneIdFor(deletedUid);
    const big = (await db.doc('groups/big').get()).data()?.memberIds as string[];
    expect(big).toContain(tombstoneId);
    expect(big).not.toContain(deletedUid);
    const members = await db.collection('groups/big/members').get();
    expect(members.docs.filter((d) => d.data().isTombstone === true)).toHaveLength(1);
    for (const eid of ['e1', 'e2', 'e3']) {
      const exp = (await db.doc(`groups/big/events/ev/expenses/${eid}`).get()).data();
      expect(JSON.stringify(exp)).not.toContain(deletedUid);
    }
    expect(JSON.stringify((await db.doc('groups/big/activity/a1').get()).data())).not.toContain(oldName);
    await expect(getAuth().getUser(deletedUid)).rejects.toMatchObject({ code: 'auth/user-not-found' });
  });

  // #76: refresh-token revocation + deletionAudit marker backstop.
  function failFirstPhaseBCommit(): void {
    const realCommit = WriteBatch.prototype.commit;
    let commits = 0;
    jest.spyOn(WriteBatch.prototype, 'commit').mockImplementation(function (this: WriteBatch) {
      commits += 1;
      if (commits === 1) return Promise.reject(new Error('forced phase-B failure'));
      return realCommit.apply(this);
    });
  }

  async function seedFailableGroup(gid: string): Promise<void> {
    await seedGroup(gid, [deletedUid, otherUid], { createdBy: otherUid });
    await seedMember(gid, deletedUid);
    await seedMember(gid, otherUid);
    await seedEvent(gid, 'ev');
    await seedExpense(`groups/${gid}/events/ev/expenses/e1`);
  }

  test('#76 revokes refresh tokens before deleting the auth user', async () => {
    await seedAuthUser();
    await seedGroup('groupA', [deletedUid, otherUid], { createdBy: otherUid });
    await seedMember('groupA', deletedUid);
    await seedMember('groupA', otherUid);

    const revokeSpy = jest.spyOn(getAuth(), 'revokeRefreshTokens');
    const deleteSpy = jest.spyOn(getAuth(), 'deleteUser');

    const result = await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

    expect(result.authUserDeleted).toBe(true);
    expect(revokeSpy).toHaveBeenCalledWith(deletedUid);
    expect(deleteSpy).toHaveBeenCalledWith(deletedUid);
    // Revocation must precede deleteUser so a preserved (partial-failure) user
    // can never refresh into a new ID token.
    expect(revokeSpy.mock.invocationCallOrder[0])
      .toBeLessThan(deleteSpy.mock.invocationCallOrder[0]);
  });

  test('#76 revokes refresh tokens even when the cascade partially fails (user preserved)', async () => {
    await seedAuthUser();
    await seedFailableGroup('groupP');

    const revokeSpy = jest.spyOn(getAuth(), 'revokeRefreshTokens');
    failFirstPhaseBCommit();

    await expect(wrapped({ data: {}, auth: { uid: deletedUid } } as any))
      .rejects.toMatchObject({ code: 'internal' });

    expect(revokeSpy).toHaveBeenCalledWith(deletedUid);
    await expect(getAuth().getUser(deletedUid)).resolves.toMatchObject({ uid: deletedUid });
  });

  test('#76 writes a deletionAudit marker on partial failure', async () => {
    const db = getFirestore();
    await seedAuthUser();
    await seedFailableGroup('groupP');
    failFirstPhaseBCommit();

    await expect(wrapped({ data: {}, auth: { uid: deletedUid } } as any))
      .rejects.toMatchObject({ code: 'internal' });

    const marker = (await db.doc(`deletionAudit/${deletedUid}`).get()).data();
    expect(marker).toMatchObject({ uid: deletedUid, status: 'failed', attemptCount: 1 });
    expect(marker?.cascadeFailed).toContain('groupP');
    expect(marker?.expiresAt).toBeInstanceOf(Timestamp);
    expect(marker?.firstFailedAt).toBeInstanceOf(Timestamp);
    expect((marker?.firstFailedAt as Timestamp).toMillis())
      .toBe((marker?.lastAttemptAt as Timestamp).toMillis());
  });

  test('#76 marker attemptCount increments while firstFailedAt is preserved', async () => {
    const db = getFirestore();
    await seedAuthUser();
    await seedFailableGroup('groupP');

    failFirstPhaseBCommit();
    await expect(wrapped({ data: {}, auth: { uid: deletedUid } } as any))
      .rejects.toMatchObject({ code: 'internal' });
    const first = (await db.doc(`deletionAudit/${deletedUid}`).get()).data();

    jest.restoreAllMocks();
    muteLoggers();
    failFirstPhaseBCommit();
    await expect(wrapped({ data: {}, auth: { uid: deletedUid } } as any))
      .rejects.toMatchObject({ code: 'internal' });
    const second = (await db.doc(`deletionAudit/${deletedUid}`).get()).data();

    expect(second?.attemptCount).toBe(2);
    expect((second?.firstFailedAt as Timestamp).toMillis())
      .toBe((first?.firstFailedAt as Timestamp).toMillis());
    expect((second?.lastAttemptAt as Timestamp).toMillis())
      .toBeGreaterThanOrEqual((first?.lastAttemptAt as Timestamp).toMillis());
  });

  test('#76 clears a pre-existing deletionAudit marker on successful deletion', async () => {
    const db = getFirestore();
    await seedAuthUser();
    await seedGroup('groupA', [deletedUid, otherUid], { createdBy: otherUid });
    await seedMember('groupA', deletedUid);
    await seedMember('groupA', otherUid);
    await db.doc(`deletionAudit/${deletedUid}`).set({
      uid: deletedUid,
      status: 'failed',
      cascadeFailed: ['groupA'],
      firstFailedAt: Timestamp.now(),
      lastAttemptAt: Timestamp.now(),
      attemptCount: 1,
      expiresAt: Timestamp.fromMillis(Date.now() + 1000),
    });

    const result = await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

    expect(result.cascadeFailed).toEqual([]);
    expect((await db.doc(`deletionAudit/${deletedUid}`).get()).exists).toBe(false);
  });

  // #294: a creator's member doc is keyed by a random uuid (createGroup writes
  // .doc(uuid.v4()) with userId:uid), not by .doc(uid). The cascade must locate
  // it by the `userId` FIELD, otherwise tx.delete(.doc(uid)) no-ops and the
  // creator's displayName (PII) + dead-uid userId are orphaned in the group.
  test('#294 deletes a uuid-keyed creator member doc and scrubs its PII (sole creator)', async () => {
    const db = getFirestore();
    const creatorDocId = 'creator-uuid-aaaa-bbbb';
    await seedAuthUser();
    await seedGroup('cg', [deletedUid], { createdBy: deletedUid });
    // creator member doc keyed by a uuid, userId points at the deleted uid:
    await db.doc(`groups/cg/members/${creatorDocId}`).set({
      id: creatorDocId,
      userId: deletedUid,
      displayName: oldName,
      role: 'CREATOR',
      joinedAt: new Date('2026-01-01T00:00:00.000Z'),
      isShadow: false,
    });

    const result = await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

    expect(result.membersDeleted).toBe(1);

    // the uuid-keyed creator doc is gone (not orphaned):
    expect((await db.doc(`groups/cg/members/${creatorDocId}`).get()).exists).toBe(false);

    // no member doc anywhere still carries the deleted uid:
    const remaining = await db.collection('groups/cg/members').get();
    for (const doc of remaining.docs) {
      expect(doc.data().userId).not.toBe(deletedUid);
      expectNoDeletedIdentity(doc.data());
    }

    // a tombstone replaced the identity; sole creator ⇒ group soft-deleted:
    const tombstoneId = tombstoneIdFor(deletedUid);
    const tombstone = await db.doc(`groups/cg/members/${tombstoneId}`).get();
    expect(tombstone.data()).toMatchObject({
      userId: tombstoneId,
      displayName: 'Deleted member',
      isTombstone: true,
    });
    const group = await db.doc('groups/cg').get();
    expect(group.data()).toMatchObject({ createdBy: 'deleted-user', isDeleted: true });
    expect(group.data()?.memberIds).not.toContain(deletedUid);
  });

  test('#294 deletes a uuid-keyed creator doc, leaving a real joiner survivor (no uid residue)', async () => {
    const db = getFirestore();
    const creatorDocId = 'creator-uuid-cccc-dddd';
    await seedAuthUser();
    await seedGroup('cg2', [deletedUid, otherUid], { createdBy: deletedUid });
    await db.doc(`groups/cg2/members/${creatorDocId}`).set({
      id: creatorDocId,
      userId: deletedUid,
      displayName: oldName,
      role: 'CREATOR',
      joinedAt: new Date('2026-01-01T00:00:00.000Z'),
      isShadow: false,
    });
    await seedMember('cg2', otherUid); // uid-keyed survivor
    // creator sits in the financial universe (event payer) — money-adjacent axis:
    await seedEvent('cg2', 'eventA');
    await db.doc('groups/cg2/events/eventA/expenses/paid').set({
      id: 'paid',
      eventId: 'eventA',
      createdBy: deletedUid,
      payerParticipantId: deletedUid,
      amountFils: 10000,
      currency: 'OMR',
      scope: 'custom',
      splitMode: 'exact',
      customSplitParticipants: [deletedUid, otherUid],
      splitDistribution: { [deletedUid]: 5000, [otherUid]: 5000 },
      description: 'expense',
      note: 'note',
      receiptUrl: 'receipts/x.png',
      isDeleted: false,
      deletedAt: null,
      createdAt: '2026-01-06T00:00:00.000Z',
    });

    const result = await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

    expect(result.membersDeleted).toBe(1);
    expect((await db.doc(`groups/cg2/members/${creatorDocId}`).get()).exists).toBe(false);

    // #249 money-adjacent: no live member doc still keyed under the deleted uid,
    // so recomputeNet's liveMemberIds no longer treats the departed creator as live.
    const remaining = await db.collection('groups/cg2/members').get();
    for (const doc of remaining.docs) {
      expect(doc.data().userId).not.toBe(deletedUid);
    }

    const survivor = await db.doc(`groups/cg2/members/${otherUid}`).get();
    expect(survivor.data()).toMatchObject({ userId: otherUid, displayName: otherName });

    const group = await db.doc('groups/cg2').get();
    expect(group.data()).toMatchObject({ createdBy: otherUid, isDeleted: false });
    expect(group.data()?.memberIds).toContain(otherUid);
    expect(group.data()?.memberIds).not.toContain(deletedUid);
  });

  // #1138: succession must never appoint an unclaimed shadow or a torn doc as
  // createdBy. A shadow IS in memberIds (addShadowMember arrayUnions the uuid)
  // but never AUTHENTICATES — no request.auth.uid ever equals it — so every
  // createdBy-keyed gate would be permanently unsatisfiable (admin-less group).
  test('#1138 a shadow-only survivor soft-deletes the group instead of being appointed', async () => {
    const db = getFirestore();
    const shadowUuid = 'shadow-uuid-aaaa';
    await seedAuthUser();
    await seedGroup('sg1', [deletedUid, shadowUuid], { createdBy: deletedUid });
    await seedMember('sg1', deletedUid);
    await seedMember('sg1', shadowUuid, {
      isShadow: true,
      displayName: 'Shadow Friend',
      joinedAt: new Date('2026-01-02T00:00:00.000Z'),
    });

    const result = await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

    expect(result.groupsOrphanedAndSoftDeleted).toBe(1);
    const group = (await db.doc('groups/sg1').get()).data() ?? {};
    expect(group.isDeleted).toBe(true);
    expect(group.createdBy).toBe('deleted-user');
  });

  test('#1138 an older shadow loses succession to a newer real member (role flipped)', async () => {
    const db = getFirestore();
    const shadowUuid = 'shadow-uuid-bbbb';
    await seedAuthUser();
    await seedGroup('sg2', [deletedUid, otherUid, shadowUuid], { createdBy: deletedUid });
    await seedMember('sg2', deletedUid);
    await seedMember('sg2', otherUid, { joinedAt: new Date('2026-01-05T00:00:00.000Z') });
    await seedMember('sg2', shadowUuid, {
      isShadow: true,
      displayName: 'Shadow Friend',
      joinedAt: new Date('2026-01-01T00:00:00.000Z'),
    });

    await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

    const group = (await db.doc('groups/sg2').get()).data() ?? {};
    expect(group.createdBy).toBe(otherUid);
    expect(group.isDeleted).toBe(false);
    // Role-flip parity with leaveGroup: the roster badge reads member.role.
    expect((await db.doc(`groups/sg2/members/${otherUid}`).get()).data()?.role).toBe('CREATOR');
    expect((await db.doc(`groups/sg2/members/${shadowUuid}`).get()).data()?.role).toBe('MEMBER');
  });

  test('#1138 a torn doc whose userId fell out of memberIds is never appointed', async () => {
    const db = getFirestore();
    await seedAuthUser();
    await seedGroup('sg3', [deletedUid], { createdBy: deletedUid });
    await seedMember('sg3', deletedUid);
    // Non-shadow doc outside memberIds (torn state): equally admin-less as
    // createdBy under the #1132 rules conjunct — soft-delete instead.
    await seedMember('sg3', 'ghost-user', { joinedAt: new Date('2026-01-02T00:00:00.000Z') });

    const result = await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

    expect(result.groupsOrphanedAndSoftDeleted).toBe(1);
    const group = (await db.doc('groups/sg3').get()).data() ?? {};
    expect(group.isDeleted).toBe(true);
    expect(group.createdBy).toBe('deleted-user');
  });

  // #1099: a membership created concurrently AFTER the S0 snapshot (a join or
  // createGroup landing mid-cascade) must be scrubbed in the SAME run — not left a
  // permanent ghost (a clean run writes no deletionAudit marker, so the reaper never
  // revisits it). RED pre-fix: the late group keeps the uid AND the auth user is
  // deleted.
  test('#1099 a group joined between S0 and the re-query is scrubbed in the same run', async () => {
    const db = getFirestore();
    await seedAuthUser();
    // S0 universe: one co-membered group the cascade scrubs normally.
    await seedGroup('gS0', [deletedUid, otherUid], { createdBy: otherUid });
    await seedMember('gS0', deletedUid);
    await seedMember('gS0', otherUid);

    // A brand-new group commits AFTER S0's read resolves (invisible to S0's snapshot).
    spyGroupsReads(db, {
      after: async (n) => {
        if (n !== 1) return;
        await seedGroup('gLate', [deletedUid, otherUid], { createdBy: otherUid });
        await seedMember('gLate', deletedUid);
        await seedMember('gLate', otherUid);
      },
    });

    const result = await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

    const late = (await db.doc('groups/gLate').get()).data();
    const lateMemberIds = late?.memberIds as string[];
    expect(lateMemberIds).not.toContain(deletedUid);
    expect(lateMemberIds.some((id) => id.startsWith('deleted-'))).toBe(true);
    expect((await db.doc(`groups/gLate/members/${tombstoneIdFor(deletedUid)}`).get()).data())
      .toMatchObject({ isTombstone: true });
    // Clean run ⇒ auth user deleted, no marker.
    expect(result.cascadeFailed).toEqual([]);
    await expect(getAuth().getUser(deletedUid))
      .rejects.toMatchObject({ code: 'auth/user-not-found' });
    expect((await db.doc(`deletionAudit/${deletedUid}`).get()).exists).toBe(false);
  });

  // #1099 (Gate r1-P1 + r2-P1-c): a group scrubbed at S0 that the uid RE-JOINS
  // (memberIds re-populated post-scrub) must be re-processed by the authoritative
  // re-query — an exclude-set of already-seen groups would skip it. The re-scrub
  // REUSES the single existing tombstone (never deleted-<hash>-2) and re-keys money
  // maps by SUM (mergeUidMapKey), so an expense holding BOTH the prior tombstone and
  // the re-joined uid conserves value. RED pre-fix: the re-joined group is a
  // permanent ghost while the auth user is deleted.
  test('#1099 a re-joined group is re-scrubbed with one tombstone and conserved money', async () => {
    const db = getFirestore();
    const T = tombstoneIdFor(deletedUid);
    await seedAuthUser();

    // The "already-scrubbed-then-re-joined" state, committed AFTER S0's read: a live
    // tombstone T, the re-added uid back in memberIds + a fresh member doc, an event
    // whose participantIds already carry T, an already-scrubbed expense (must stay
    // untouched), and a NEW expense split between T and the re-joined uid.
    spyGroupsReads(db, {
      after: async (n) => {
        if (n !== 1) return;
        await seedGroup('gRejoin', [otherUid, T, deletedUid], { createdBy: otherUid });
        await seedMember('gRejoin', otherUid);
        await seedMember('gRejoin', deletedUid);
        await db.doc(`groups/gRejoin/members/${T}`).set({
          id: T, userId: T, displayName: 'Deleted member',
          role: 'MEMBER', joinedAt: new Date('2026-01-01T00:00:00.000Z'),
          isShadow: false, isTombstone: true,
        });
        await seedEvent('gRejoin', 'ev', { participantIds: [T, otherUid, deletedUid] });
        // Already scrubbed at the prior pass — must NOT be double-processed:
        await db.doc('groups/gRejoin/events/ev/expenses/exp1').set({
          id: 'exp1', eventId: 'ev', createdBy: 'deleted-user', payerParticipantId: T,
          amountFils: 12000, currency: 'OMR', scope: 'custom', splitMode: 'exact',
          customSplitParticipants: [T, otherUid],
          splitDistribution: { [T]: 6000, [otherUid]: 6000 },
          description: null, note: null, receiptUrl: null,
          isDeleted: false, deletedAt: null, createdAt: '2026-01-06T00:00:00.000Z',
        });
        // NEW post-rejoin expense holding BOTH T and the re-joined uid:
        await db.doc('groups/gRejoin/events/ev/expenses/exp2').set({
          id: 'exp2', eventId: 'ev', createdBy: deletedUid, payerParticipantId: deletedUid,
          amountFils: 500, currency: 'OMR', scope: 'custom', splitMode: 'exact',
          customSplitParticipants: [T, deletedUid],
          splitDistribution: { [T]: 300, [deletedUid]: 200 },
          description: 'rejoin expense', note: 'n', receiptUrl: 'r.png',
          isDeleted: false, deletedAt: null, createdAt: '2026-01-07T00:00:00.000Z',
        });
      },
    });

    const result = await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

    // Exactly ONE tombstone doc (reuse, not -2).
    const members = await db.collection('groups/gRejoin/members').get();
    expect(members.docs.filter((d) => d.data().isTombstone === true)).toHaveLength(1);
    expect((await db.doc(`groups/gRejoin/members/${T}-2`).get()).exists).toBe(false);
    // uid gone from memberIds; re-joined member doc removed; tombstone retained.
    const gr = (await db.doc('groups/gRejoin').get()).data();
    expect(gr?.memberIds).not.toContain(deletedUid);
    expect(gr?.memberIds).toContain(T);
    expect((await db.doc(`groups/gRejoin/members/${deletedUid}`).get()).exists).toBe(false);

    // Money conserved: exp2's uid slice MERGES into T (SUM), not overwrite → T = 300+200.
    const exp2 = (await db.doc('groups/gRejoin/events/ev/expenses/exp2').get()).data();
    expect(exp2?.splitDistribution).toEqual({ [T]: 500 });
    const exp2Sum = Object.values(exp2?.splitDistribution as Record<string, number>)
      .reduce((a, b) => a + b, 0);
    expect(exp2Sum).toBe(500);
    expect(exp2).toMatchObject({ payerParticipantId: T, createdBy: 'deleted-user' });
    expectNoDeletedIdentity(exp2);

    // Already-scrubbed exp1 untouched (no double count).
    const exp1 = (await db.doc('groups/gRejoin/events/ev/expenses/exp1').get()).data();
    expect(exp1?.splitDistribution).toEqual({ [T]: 6000, [otherUid]: 6000 });

    // Clean re-scrub ⇒ auth deleted, no marker.
    expect(result.cascadeFailed).toEqual([]);
    await expect(getAuth().getUser(deletedUid))
      .rejects.toMatchObject({ code: 'auth/user-not-found' });
    expect((await db.doc(`deletionAudit/${deletedUid}`).get()).exists).toBe(false);
  });

  // #1099: sustained churn — a group whose uid is re-added on EVERY re-query pass —
  // cannot be cleaned within the 3-pass bound, so the FINAL check lands it in
  // cascadeFailed: the auth user is preserved, the deletionAudit marker is written,
  // and the 24h deletionReaper re-runs to convergence. RED pre-fix: no re-query, so
  // the group is scrubbed once and the auth user is deleted with no backstop marker.
  test('#1099 unbounded churn lands the group in cascadeFailed and preserves the auth user', async () => {
    const db = getFirestore();
    await seedAuthUser();
    await seedGroup('gChurn', [deletedUid, otherUid], { createdBy: otherUid });
    await seedMember('gChurn', deletedUid);
    await seedMember('gChurn', otherUid);

    // Re-add the uid before every re-query pass AND the final check (calls #2..#5),
    // faster than the bound can converge.
    spyGroupsReads(db, {
      before: async (n) => {
        if (n < 2) return;
        await db.doc('groups/gChurn').update({ memberIds: FieldValue.arrayUnion(deletedUid) });
      },
    });

    await expect(wrapped({ data: {}, auth: { uid: deletedUid } } as any))
      .rejects.toMatchObject({ code: 'internal' });

    // Auth user preserved; marker written naming the churned group.
    await expect(getAuth().getUser(deletedUid)).resolves.toMatchObject({ uid: deletedUid });
    const marker = (await db.doc(`deletionAudit/${deletedUid}`).get()).data();
    expect(marker).toMatchObject({ uid: deletedUid, status: 'failed' });
    expect(marker?.cascadeFailed).toContain('gChurn');
  });

  // #1099: happy-path pin — with no concurrent write, the re-query passes return
  // empty and terminate immediately; the auth user is deleted and NO marker is
  // written. Guards against the loop spuriously failing a clean deletion.
  test('#1099 no concurrent write: re-query terminates clean, auth deleted, no marker', async () => {
    const db = getFirestore();
    await seedAuthUser();
    await seedGroup('gClean', [deletedUid, otherUid], { createdBy: otherUid });
    await seedMember('gClean', deletedUid);
    await seedMember('gClean', otherUid);

    const spy = spyGroupsReads(db);

    const result = await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

    // S0 + one empty re-query pass + the final check = 3 groups-collection reads.
    expect(spy.calls()).toBe(3);
    expect(result.cascadeFailed).toEqual([]);
    expect(result.authUserDeleted).toBe(true);
    await expect(getAuth().getUser(deletedUid))
      .rejects.toMatchObject({ code: 'auth/user-not-found' });
    expect((await db.doc(`deletionAudit/${deletedUid}`).get()).exists).toBe(false);
  });
});
