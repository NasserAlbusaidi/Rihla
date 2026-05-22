import functionsTest from 'firebase-functions-test';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';
import {
  advanceDeleteAccountJob,
  deleteAccount,
  getDeleteAccountJobStatus,
  startOrResumeDeleteAccountJob,
} from '../../src/callables/deleteAccount';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(deleteAccount);
const wrappedStartJob = testEnv.wrap(startOrResumeDeleteAccountJob);
const wrappedAdvanceJob = testEnv.wrap(advanceDeleteAccountJob);
const wrappedGetJobStatus = testEnv.wrap(getDeleteAccountJobStatus);

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
  for (const collection of ['fcm_tokens', 'joinAttempts']) {
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
  await getFirestore()
    .doc(`groups/${groupId}`)
    .set({
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
  await getFirestore()
    .doc(`groups/${groupId}/members/${uid}`)
    .set({
      id: uid,
      userId: uid,
      displayName: uid === deletedUid ? oldName : otherName,
      role: uid === deletedUid ? 'CREATOR' : 'MEMBER',
      joinedAt: new Date(
        uid === deletedUid
          ? '2026-01-01T00:00:00.000Z'
          : '2026-01-03T00:00:00.000Z',
      ),
      isShadow: false,
      ...data,
    });
}

async function seedEvent(
  groupId: string,
  eventId: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore()
    .doc(`groups/${groupId}/events/${eventId}`)
    .set({
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

function expectNoDeletedIdentity(
  data: FirebaseFirestore.DocumentData | undefined,
): void {
  expect(JSON.stringify(data)).not.toContain(deletedUid);
  expect(JSON.stringify(data)).not.toContain(oldName);
}

beforeEach(async () => {
  await clearFirestore();
  await clearGlobalDocs();
  await clearAuthUsers();
  jest.restoreAllMocks();
  jest.spyOn(logger, 'info').mockImplementation(() => undefined);
  jest.spyOn(logger, 'error').mockImplementation(() => undefined);
});

afterAll(async () => {
  await clearFirestore();
  await clearGlobalDocs();
  await clearAuthUsers();
  testEnv.cleanup();
});

describe('deleteAccount', () => {
  test('missing auth is rejected', async () => {
    await expect(wrapped({ data: {} } as any)).rejects.toMatchObject({
      code: 'unauthenticated',
    });
  });

  test('cascades identity deletion while preserving ledger facts', async () => {
    const db = getFirestore();
    await seedAuthUser();
    await seedGroup('groupA', [deletedUid, otherUid], {
      createdBy: deletedUid,
    });
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
    await db
      .doc('groups/groupA/events/eventA/settlements/eventSettlement')
      .set({
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
    await db
      .doc('groups/groupA/events/eventA/activity_logs/eventActivity')
      .set({
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
    const groupATombstoneId = groupAMemberIds.find((id) =>
      id.startsWith('deleted-'),
    );
    expect(groupA.data()).toMatchObject({
      createdBy: otherUid,
      isDeleted: false,
    });
    expect(groupATombstoneId).toBeDefined();
    expect(groupAMemberIds).toContain(otherUid);
    expect(groupAMemberIds).not.toContain(deletedUid);

    const tombstoneMember = await db
      .doc(`groups/groupA/members/${groupATombstoneId}`)
      .get();
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

    const paid = await db
      .doc('groups/groupA/events/eventA/expenses/paid')
      .get();
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

    const softDeleted = await db
      .doc('groups/groupA/events/eventA/expenses/softDeleted')
      .get();
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

    const eventSettlement = await db
      .doc('groups/groupA/events/eventA/settlements/eventSettlement')
      .get();
    expect(eventSettlement.data()).toMatchObject({
      payerParticipantId: otherUid,
      recipientParticipantId: groupATombstoneId,
      payerName: otherName,
      recipientName: 'Deleted member',
      note: null,
    });
    expectNoDeletedIdentity(eventSettlement.data());

    const groupSettlement = await db
      .doc('groups/groupA/settlements/groupSettlement')
      .get();
    expect(groupSettlement.data()).toMatchObject({
      createdBy: 'deleted-user',
      payerParticipantId: groupATombstoneId,
      recipientParticipantId: otherUid,
      payerName: 'Deleted member',
      recipientName: otherName,
      note: null,
    });
    expectNoDeletedIdentity(groupSettlement.data());

    const eventActivity = await db
      .doc('groups/groupA/events/eventA/activity_logs/eventActivity')
      .get();
    expect(eventActivity.data()).toMatchObject({
      actorId: groupATombstoneId,
      targetParticipantId: groupATombstoneId,
      actorName: 'Deleted member',
    });
    expectNoDeletedIdentity(eventActivity.data());

    const groupActivity = await db
      .doc('groups/groupA/activity/groupActivity')
      .get();
    expect(groupActivity.data()).toMatchObject({
      actorId: groupATombstoneId,
      actorName: 'Deleted member',
    });
    expectNoDeletedIdentity(groupActivity.data());

    expect((await db.doc(`fcm_tokens/${deletedUid}`).get()).exists).toBe(false);
    expect((await db.doc(`joinAttempts/${deletedUid}`).get()).exists).toBe(
      false,
    );
    await expect(getAuth().getUser(deletedUid)).rejects.toMatchObject({
      code: 'auth/user-not-found',
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
    expect((await db.doc(`joinAttempts/${deletedUid}`).get()).exists).toBe(
      false,
    );
  });
});

describe('deleteAccount resumable job', () => {
  test('start, status, and bounded advances converge to complete deletion', async () => {
    const db = getFirestore();
    await seedAuthUser();
    await seedGroup('groupA', [deletedUid, otherUid], {
      createdBy: deletedUid,
    });
    await seedMember('groupA', deletedUid);
    await seedMember('groupA', otherUid);
    await seedEvent('groupA', 'eventA');
    await db.doc(`fcm_tokens/${deletedUid}`).set({ token: 'stale-token' });

    const start = await wrappedStartJob({
      data: {},
      auth: { uid: deletedUid },
    } as any);
    expect(start).toMatchObject({
      jobId: deletedUid,
      kind: 'deleteAccount',
      status: 'running',
      current: 0,
      total: 2,
    });

    const status = await wrappedGetJobStatus({
      data: { jobId: deletedUid },
      auth: { uid: deletedUid },
    } as any);
    expect(status).toMatchObject({
      jobId: deletedUid,
      kind: 'deleteAccount',
      status: 'running',
    });

    const afterGroup = await wrappedAdvanceJob({
      data: { jobId: deletedUid },
      auth: { uid: deletedUid },
    } as any);
    expect(afterGroup).toMatchObject({
      status: 'running',
      current: 1,
      counters: {
        groupsProcessed: 1,
        tombstoneIds: 1,
      },
    });
    const afterGroupOutput = afterGroup.output as {
      tombstoneIds: string[];
    };
    const tombstoneId = afterGroupOutput.tombstoneIds[0];
    expect(tombstoneId).toMatch(/^deleted-/);
    expect(
      (await db.doc(`groups/groupA/members/${deletedUid}`).get()).exists,
    ).toBe(false);
    expect(
      (await db.doc(`groups/groupA/members/${tombstoneId}`).get()).exists,
    ).toBe(true);

    const complete = await wrappedAdvanceJob({
      data: { jobId: deletedUid },
      auth: { uid: deletedUid },
    } as any);
    expect(complete).toMatchObject({
      status: 'complete',
      current: 2,
      output: {
        groupsProcessed: 1,
        fcmTokenDeleted: true,
        authUserDeleted: true,
      },
    });
    expect((await db.doc(`fcm_tokens/${deletedUid}`).get()).exists).toBe(false);
    await expect(getAuth().getUser(deletedUid)).rejects.toMatchObject({
      code: 'auth/user-not-found',
    });
  });

  test('status and advance reject another uid', async () => {
    await seedAuthUser();
    await wrappedStartJob({
      data: {},
      auth: { uid: deletedUid },
    } as any);

    await expect(
      wrappedGetJobStatus({
        data: { jobId: deletedUid },
        auth: { uid: otherUid },
      } as any),
    ).rejects.toMatchObject({ code: 'permission-denied' });
    await expect(
      wrappedAdvanceJob({
        data: { jobId: deletedUid },
        auth: { uid: otherUid },
      } as any),
    ).rejects.toMatchObject({ code: 'permission-denied' });
  });
});
