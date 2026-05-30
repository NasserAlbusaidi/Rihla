import functionsTest from 'firebase-functions-test';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp, WriteBatch } from 'firebase-admin/firestore';
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
  for (const collection of ['fcm_tokens', 'joinAttempts', 'deletionAttempts']) {
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
});
