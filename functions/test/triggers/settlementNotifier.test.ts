import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import * as messaging from 'firebase-admin/messaging';
import {
  eventSettlementNotifier,
  groupSettlementNotifier,
} from '../../src/triggers/settlementNotifier';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapEvent = testEnv.wrap(eventSettlementNotifier);
const wrapGroup = testEnv.wrap(groupSettlementNotifier);
const FIRE_TIME = '2026-07-01T00:00:00.000Z';

function eventSettlement(
  data: Record<string, unknown>,
  params: { gid: string; eid: string; settlementId: string },
  id = 'evt-settlement-1',
) {
  const path = `groups/${params.gid}/events/${params.eid}/settlements/${params.settlementId}`;
  return {
    data: testEnv.firestore.makeDocumentSnapshot(data, path),
    params,
    id,
    time: FIRE_TIME,
  };
}

function groupSettlement(
  data: Record<string, unknown>,
  params: { gid: string; settlementId: string },
  id = 'evt-group-settlement-1',
) {
  const path = `groups/${params.gid}/settlements/${params.settlementId}`;
  return {
    data: testEnv.firestore.makeDocumentSnapshot(data, path),
    params,
    id,
    time: FIRE_TIME,
  };
}

function mockSendEach(count: number): jest.Mock {
  const sendEach = jest.fn().mockResolvedValue({
    successCount: count,
    failureCount: 0,
    responses: Array.from({ length: count }, () => ({
      success: true,
      messageId: 'm',
    })),
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

async function seedGroup(gid: string, name: string): Promise<void> {
  await getFirestore().doc(`groups/${gid}`).set({ id: gid, name });
}

async function clearAll(): Promise<void> {
  const db = getFirestore();
  await db.recursiveDelete(db.collection('fcm_tokens'));
  await db.recursiveDelete(db.collection('groups'));
  await db.recursiveDelete(db.collection('notificationDeliveries'));
}

beforeEach(async () => {
  await clearAll();
});

afterEach(() => jest.restoreAllMocks());

afterAll(async () => {
  await clearAll();
  testEnv.cleanup();
});

const base = {
  amountFils: 10500,
  currency: 'OMR',
  payerName: 'Ahmed',
  recipientName: 'Bilal',
  isDeleted: false,
};

describe('eventSettlementNotifier', () => {
  test('notifies the counterparty (parties minus actor), not the actor', async () => {
    await seedGroup('g1', 'Salalah Trip');
    await seedToken('payer');
    await seedToken('recipient');
    const sendEach = mockSendEach(1);

    // actor created the settlement and is the payer -> only recipient notified
    await wrapEvent(
      eventSettlement(
        { ...base, payerParticipantId: 'payer', recipientParticipantId: 'recipient', createdBy: 'payer' },
        { gid: 'g1', eid: 'e1', settlementId: 's1' },
      ),
    );

    const messages = sendEach.mock.calls[0][0];
    expect(messages).toHaveLength(1);
    expect(messages[0].token).toBe('tok-recipient');
    expect(messages[0].data).toEqual({ type: 'settlement', groupId: 'g1', eventId: 'e1' });
    expect(messages[0].notification.title).toBe('Salalah Trip');
    expect(messages[0].notification.body).toContain('Ahmed'); // actor = payer
    expect(messages[0].notification.body).toContain('10.500');
  });

  test('third-party recorder notifies BOTH parties and labels actor "Someone"', async () => {
    await seedGroup('g1', 'Trip');
    await seedToken('payer');
    await seedToken('recipient');
    const sendEach = mockSendEach(2);

    await wrapEvent(
      eventSettlement(
        { ...base, payerParticipantId: 'payer', recipientParticipantId: 'recipient', createdBy: 'thirdparty' },
        { gid: 'g1', eid: 'e1', settlementId: 's1' },
      ),
    );

    const messages = sendEach.mock.calls[0][0];
    expect(messages).toHaveLength(2);
    expect(messages[0].notification.body).toContain('Someone');
    expect(messages[0].notification.body).not.toContain('Bilal');
  });

  test('third-party recorder uses the localized empty-name fallback for an Arabic recipient (#483)', async () => {
    await seedGroup('g1', 'Trip');
    await seedToken('payer', 'ar');
    await seedToken('recipient', 'ar');
    const sendEach = mockSendEach(2);

    await wrapEvent(
      eventSettlement(
        { ...base, payerParticipantId: 'payer', recipientParticipantId: 'recipient', createdBy: 'thirdparty' },
        { gid: 'g1', eid: 'e1', settlementId: 's1' },
      ),
    );

    const messages = sendEach.mock.calls[0][0];
    expect(messages).toHaveLength(2);
    // The Arabic recipient must get 'شخص ما', NOT the English 'Someone'.
    expect(messages[0].notification.body).toContain('شخص ما');
    expect(messages[0].notification.body).not.toContain('Someone');
  });

  test('deleted settlement is not notified', async () => {
    await seedGroup('g1', 'Trip');
    await seedToken('recipient');
    const sendEach = mockSendEach(0);

    await wrapEvent(
      eventSettlement(
        { ...base, isDeleted: true, payerParticipantId: 'payer', recipientParticipantId: 'recipient', createdBy: 'payer' },
        { gid: 'g1', eid: 'e1', settlementId: 's1' },
      ),
    );

    expect(sendEach).not.toHaveBeenCalled();
  });

  test('counterparty with no token is skipped (no send)', async () => {
    await seedGroup('g1', 'Trip');
    // no token for recipient
    const sendEach = mockSendEach(0);

    await wrapEvent(
      eventSettlement(
        { ...base, payerParticipantId: 'payer', recipientParticipantId: 'recipient', createdBy: 'payer' },
        { gid: 'g1', eid: 'e1', settlementId: 's1' },
      ),
    );

    expect(sendEach).not.toHaveBeenCalled();
  });

  test('retrying the same Eventarc create event sends only once', async () => {
    await seedGroup('g1', 'Trip');
    await seedToken('recipient');
    const sendEach = mockSendEach(1);
    const event = eventSettlement(
      { ...base, payerParticipantId: 'payer', recipientParticipantId: 'recipient', createdBy: 'payer' },
      { gid: 'g1', eid: 'e1', settlementId: 's1' },
      'evt-settlement-retry',
    );

    await wrapEvent(event);
    await wrapEvent(event);

    expect(sendEach).toHaveBeenCalledTimes(1);
  });
});

describe('groupSettlementNotifier', () => {
  test('group settlement payload omits eventId', async () => {
    await seedGroup('g1', 'Trip');
    await seedToken('recipient');
    const sendEach = mockSendEach(1);

    await wrapGroup(
      groupSettlement(
        { ...base, payerParticipantId: 'payer', recipientParticipantId: 'recipient', createdBy: 'payer' },
        { gid: 'g1', settlementId: 's1' },
      ),
    );

    expect(sendEach.mock.calls[0][0][0].data).toEqual({ type: 'settlement', groupId: 'g1' });
  });

  test('retrying the same Eventarc group settlement event sends only once', async () => {
    await seedGroup('g1', 'Trip');
    await seedToken('recipient');
    const sendEach = mockSendEach(1);
    const event = groupSettlement(
      { ...base, payerParticipantId: 'payer', recipientParticipantId: 'recipient', createdBy: 'payer' },
      { gid: 'g1', settlementId: 's1' },
      'evt-group-settlement-retry',
    );

    await wrapGroup(event);
    await wrapGroup(event);

    expect(sendEach).toHaveBeenCalledTimes(1);
  });
});
