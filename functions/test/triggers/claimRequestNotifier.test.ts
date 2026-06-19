import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import * as messaging from 'firebase-admin/messaging';
import { claimRequestNotifier } from '../../src/triggers/claimRequestNotifier';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrap = testEnv.wrap(claimRequestNotifier);

const PATH = 'groups/g1/claimRequests/req1';
const FIRE_TIME = '2026-06-18T00:00:00.000Z';
const params = { gid: 'g1', requestId: 'req1' };

// onDocumentWritten v2 contract: wrap(fn) takes { data: Change, params, id, time }.
function snap(data: Record<string, unknown>) {
  return testEnv.firestore.makeDocumentSnapshot(data, PATH);
}
function absent() {
  // empty data → resource-only proto → .exists === false (create/delete edge)
  return testEnv.firestore.makeDocumentSnapshot({}, PATH);
}
function fire(before: unknown, after: unknown) {
  return wrap({ data: testEnv.makeChange(before, after), params, id: 'evt1', time: FIRE_TIME });
}

// A pending claim-request doc as written by requestClaimShadow.ts:121-130.
function pending(o: Record<string, unknown> = {}) {
  return {
    requesterUid: 'R',
    requesterDisplayName: 'Sam',
    shadowMemberId: 'shadow-uuid',
    shadowDisplayName: 'Dad',
    status: 'pending',
    decidedBy: null,
    decidedAt: null,
    ...o,
  };
}

function mockSendEach(count: number): jest.Mock {
  const sendEach = jest.fn().mockResolvedValue({
    successCount: count,
    failureCount: 0,
    responses: Array.from({ length: count }, () => ({ success: true, messageId: 'm' })),
  });
  jest
    .spyOn(messaging, 'getMessaging')
    .mockReturnValue({ sendEach } as unknown as messaging.Messaging);
  return sendEach;
}

async function seedToken(uid: string, locale = 'en'): Promise<void> {
  await getFirestore()
    .doc(`fcm_tokens/${uid}`)
    .set({ user_id: uid, token: `tok-${uid}`, locale, platform: 'android' });
}

async function seedGroup(gid: string, name: string, createdBy: string): Promise<void> {
  await getFirestore().doc(`groups/${gid}`).set({ id: gid, name, createdBy });
}

async function clearAll(): Promise<void> {
  const db = getFirestore();
  for (const coll of ['fcm_tokens', 'groups']) {
    const docs = await db.collection(coll).listDocuments();
    await Promise.all(docs.map((d) => d.delete()));
  }
}

beforeEach(async () => {
  await clearAll();
});

afterEach(() => jest.restoreAllMocks());

afterAll(async () => {
  await clearAll();
  testEnv.cleanup();
});

describe('claimRequestNotifier', () => {
  test('a new pending request notifies the group creator', async () => {
    await seedGroup('g1', 'Salalah Trip', 'creator');
    await seedToken('creator');
    const sendEach = mockSendEach(1);

    await fire(absent(), snap(pending()));

    const messages = sendEach.mock.calls[0][0];
    expect(messages).toHaveLength(1);
    expect(messages[0].token).toBe('tok-creator');
    expect(messages[0].data).toEqual({ type: 'claim_request', groupId: 'g1' });
    expect(messages[0].notification.title).toBe('Salalah Trip');
    expect(messages[0].notification.body).toContain('Sam'); // requester
    expect(messages[0].notification.body).toContain('Dad'); // shadow being claimed
  });

  test('a declined→pending re-open notifies the creator again', async () => {
    await seedGroup('g1', 'Trip', 'creator');
    await seedToken('creator');
    const sendEach = mockSendEach(1);

    await fire(snap(pending({ status: 'declined' })), snap(pending()));

    expect(sendEach).toHaveBeenCalledTimes(1);
    expect(sendEach.mock.calls[0][0][0].token).toBe('tok-creator');
  });

  test('pending→claimed notifies the REQUESTER (not the creator) (#565)', async () => {
    await seedGroup('g1', 'Salalah Trip', 'creator');
    await seedToken('R'); // the requester
    await seedToken('creator');
    const sendEach = mockSendEach(1);

    await fire(snap(pending()), snap(pending({ status: 'claimed' })));

    const messages = sendEach.mock.calls[0][0];
    expect(messages).toHaveLength(1);
    expect(messages[0].token).toBe('tok-R'); // requester, NOT creator
    expect(messages[0].data).toEqual({ type: 'claim_decided', groupId: 'g1' });
    expect(messages[0].notification.title).toBe('Salalah Trip');
    expect(messages[0].notification.body).toContain('Dad'); // shadow whose spot
    expect(messages[0].notification.body).toContain('approved');
  });

  test('pending→declined notifies the REQUESTER with decline copy (#565)', async () => {
    await seedGroup('g1', 'Trip', 'creator');
    await seedToken('R');
    const sendEach = mockSendEach(1);

    await fire(snap(pending()), snap(pending({ status: 'declined' })));

    const messages = sendEach.mock.calls[0][0];
    expect(messages).toHaveLength(1);
    expect(messages[0].token).toBe('tok-R');
    expect(messages[0].data).toEqual({ type: 'claim_decided', groupId: 'g1' });
    expect(messages[0].notification.body).toContain('Dad');
    expect(messages[0].notification.body).toContain('declined');
  });

  test('decide with an empty requesterUid does not notify (#565)', async () => {
    await seedGroup('g1', 'Trip', 'creator');
    const sendEach = mockSendEach(0);

    await fire(
      snap(pending({ requesterUid: '' })),
      snap(pending({ requesterUid: '', status: 'claimed' })),
    );

    expect(sendEach).not.toHaveBeenCalled();
  });

  test('Arabic requester gets the Arabic decide body (#565)', async () => {
    await seedGroup('g1', 'Trip', 'creator');
    await seedToken('R', 'ar');
    const sendEach = mockSendEach(1);

    await fire(snap(pending()), snap(pending({ status: 'claimed' })));

    const body = sendEach.mock.calls[0][0][0].notification.body;
    expect(body).toContain('Dad');
    expect(body).toContain('الموافقة'); // "approval" — proves Arabic copy
  });

  test('pending→pending no-op rewrite does NOT notify', async () => {
    await seedGroup('g1', 'Trip', 'creator');
    await seedToken('creator');
    const sendEach = mockSendEach(0);

    await fire(snap(pending()), snap(pending()));

    expect(sendEach).not.toHaveBeenCalled();
  });

  test('delete (after absent) does NOT notify', async () => {
    await seedGroup('g1', 'Trip', 'creator');
    await seedToken('creator');
    const sendEach = mockSendEach(0);

    await fire(snap(pending()), absent());

    expect(sendEach).not.toHaveBeenCalled();
  });

  test('creator with no FCM token: no send, no throw (anon creator)', async () => {
    await seedGroup('g1', 'Trip', 'creator');
    // deliberately no token for the creator
    const sendEach = mockSendEach(0);

    await fire(absent(), snap(pending()));

    expect(sendEach).not.toHaveBeenCalled();
  });

  test('defensive: requester is the creator → no self-notify', async () => {
    await seedGroup('g1', 'Trip', 'creator');
    await seedToken('creator');
    const sendEach = mockSendEach(0);

    await fire(absent(), snap(pending({ requesterUid: 'creator' })));

    expect(sendEach).not.toHaveBeenCalled();
  });

  test('Arabic creator gets the Arabic body', async () => {
    await seedGroup('g1', 'Trip', 'creator');
    await seedToken('creator', 'ar');
    const sendEach = mockSendEach(1);

    await fire(absent(), snap(pending()));

    const body = sendEach.mock.calls[0][0][0].notification.body;
    expect(body).toContain('Sam');
    expect(body).toContain('Dad');
    expect(body).toContain('يريد'); // "wants" — proves Arabic copy, not English
  });
});
