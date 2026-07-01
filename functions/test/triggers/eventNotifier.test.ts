import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import * as messaging from 'firebase-admin/messaging';
import { eventNotifier } from '../../src/triggers/eventNotifier';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrap = testEnv.wrap(eventNotifier);
const FIRE_TIME = '2026-07-01T00:00:00.000Z';

function eventCreated(
  data: Record<string, unknown>,
  params: { gid: string; eid: string },
  id = 'evt-event-1',
) {
  const path = `groups/${params.gid}/events/${params.eid}`;
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

// Seed a member doc keyed by a NON-uid id with userId as a FIELD — proves the
// #294 userId-field match (the creator's doc is keyed by a random uuid).
async function seedMember(
  gid: string,
  uid: string,
  displayName: string,
): Promise<void> {
  await getFirestore()
    .doc(`groups/${gid}/members/doc-${uid}-uuid`)
    .set({ userId: uid, displayName });
}

async function clearAll(): Promise<void> {
  const db = getFirestore();
  await db.recursiveDelete(db.collection('fcm_tokens'));
  await db.recursiveDelete(db.collection('groups'));
  await db.recursiveDelete(db.collection('notificationDeliveries'));
}

function tokensOf(sendEach: jest.Mock): string[] {
  return (sendEach.mock.calls[0]?.[0] ?? [])
    .map((m: { token: string }) => m.token)
    .sort();
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
  name: 'Salalah Trip',
  isDeleted: false,
};

describe('eventNotifier', () => {
  test('notifies all event participants minus the creator', async () => {
    await seedGroup('g1', 'Road Trips');
    await seedMember('g1', 'creator', 'Ahmed');
    await seedToken('p2');
    await seedToken('p3');
    const sendEach = mockSendEach(2);

    await wrap(
      eventCreated(
        { ...base, createdBy: 'creator', participantIds: ['creator', 'p2', 'p3'] },
        { gid: 'g1', eid: 'e1' },
      ),
    );

    expect(tokensOf(sendEach)).toEqual(['tok-p2', 'tok-p3']);
    const msg = sendEach.mock.calls[0][0][0];
    expect(msg.notification.title).toBe('Road Trips');
    expect(msg.notification.body).toContain('Ahmed');
    expect(msg.notification.body).toContain('Salalah Trip');
    expect(msg.data).toEqual({ type: 'event', groupId: 'g1', eventId: 'e1' });
  });

  // [P2 Gate] third-party creator: the body must name the CREATOR (the actor),
  // never a recipient — the settlementNotifier mislabel-the-actor guard, applied.
  test('body names the creator, not a recipient', async () => {
    await seedGroup('g1', 'Trip');
    await seedMember('g1', 'creator', 'Layla');
    await seedMember('g1', 'p2', 'Bilal');
    await seedToken('p2');
    const sendEach = mockSendEach(1);

    await wrap(
      eventCreated(
        { ...base, createdBy: 'creator', participantIds: ['creator', 'p2'] },
        { gid: 'g1', eid: 'e1' },
      ),
    );

    const body = sendEach.mock.calls[0][0][0].notification.body;
    expect(body).toContain('Layla');
    expect(body).not.toContain('Bilal');
  });

  test('single-participant (creator-only) event notifies nobody', async () => {
    await seedGroup('g1', 'Trip');
    await seedMember('g1', 'creator', 'Ahmed');
    await seedToken('creator');
    const sendEach = mockSendEach(0);

    await wrap(
      eventCreated(
        { ...base, createdBy: 'creator', participantIds: ['creator'] },
        { gid: 'g1', eid: 'e1' },
      ),
    );

    expect(sendEach).not.toHaveBeenCalled();
  });

  test('deleted-on-create event is not notified', async () => {
    await seedGroup('g1', 'Trip');
    await seedToken('p2');
    const sendEach = mockSendEach(0);

    await wrap(
      eventCreated(
        { ...base, isDeleted: true, createdBy: 'creator', participantIds: ['creator', 'p2'] },
        { gid: 'g1', eid: 'e1' },
      ),
    );

    expect(sendEach).not.toHaveBeenCalled();
  });

  test('unresolved actor falls back to localized "Someone" per recipient locale', async () => {
    await seedGroup('g1', 'Trip');
    // no member doc for creator -> actor unresolved
    await seedToken('p2', 'en');
    await seedToken('p3', 'ar');
    const sendEach = mockSendEach(2);

    await wrap(
      eventCreated(
        { ...base, createdBy: 'creator', participantIds: ['creator', 'p2', 'p3'] },
        { gid: 'g1', eid: 'e1' },
      ),
    );

    const byToken = Object.fromEntries(
      sendEach.mock.calls[0][0].map((m: { token: string; notification: { body: string } }) => [
        m.token,
        m.notification.body,
      ]),
    );
    expect(byToken['tok-p2']).toContain('Someone');
    expect(byToken['tok-p3']).toContain('شخص ما');
  });

  test('target with no token is skipped (no send)', async () => {
    await seedGroup('g1', 'Trip');
    await seedMember('g1', 'creator', 'Ahmed');
    // no token for p2
    const sendEach = mockSendEach(0);

    await wrap(
      eventCreated(
        { ...base, createdBy: 'creator', participantIds: ['creator', 'p2'] },
        { gid: 'g1', eid: 'e1' },
      ),
    );

    expect(sendEach).not.toHaveBeenCalled();
  });

  test('empty event name drops the trailing separator cleanly', async () => {
    await seedGroup('g1', 'Trip');
    await seedMember('g1', 'creator', 'Ahmed');
    await seedToken('p2');
    const sendEach = mockSendEach(1);

    await wrap(
      eventCreated(
        { name: '', isDeleted: false, createdBy: 'creator', participantIds: ['creator', 'p2'] },
        { gid: 'g1', eid: 'e1' },
      ),
    );

    const body = sendEach.mock.calls[0][0][0].notification.body;
    expect(body).toContain('Ahmed');
    expect(body).not.toContain('·');
    expect(body.trim()).toBe('Ahmed created a new event.');
  });

  test('retrying the same Eventarc create event sends only once', async () => {
    await seedGroup('g1', 'Trip');
    await seedMember('g1', 'creator', 'Ahmed');
    await seedToken('p2');
    const sendEach = mockSendEach(1);
    const event = eventCreated(
      { ...base, createdBy: 'creator', participantIds: ['creator', 'p2'] },
      { gid: 'g1', eid: 'e1' },
      'evt-event-retry',
    );

    await wrap(event);
    await wrap(event);

    expect(sendEach).toHaveBeenCalledTimes(1);
  });
});
