import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import * as messaging from 'firebase-admin/messaging';
import { expenseNotifier } from '../../src/triggers/expenseNotifier';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrap = testEnv.wrap(expenseNotifier);
const FIRE_TIME = '2026-07-01T00:00:00.000Z';

function expenseEvent(
  data: Record<string, unknown>,
  params: { gid: string; eid: string; expenseId: string },
  id = 'evt-expense-1',
) {
  const path = `groups/${params.gid}/events/${params.eid}/expenses/${params.expenseId}`;
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

async function seedGroup(gid: string, name: string, memberIds: string[]): Promise<void> {
  await getFirestore().doc(`groups/${gid}`).set({ id: gid, name, memberIds });
}

async function seedEvent(
  gid: string,
  eid: string,
  participantIds: string[],
): Promise<void> {
  await getFirestore()
    .doc(`groups/${gid}/events/${eid}`)
    .set({ id: eid, participantIds });
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
  amountFils: 10500,
  currency: 'OMR',
  description: 'Dinner',
  isDeleted: false,
  scope: 'global',
};

describe('expenseNotifier', () => {
  test('equally/global (no splitDistribution) notifies all event participants minus creator', async () => {
    await seedGroup('g1', 'Salalah Trip', ['creator', 'p2', 'p3']);
    await seedEvent('g1', 'e1', ['creator', 'p2', 'p3']);
    await seedMember('g1', 'creator', 'Ahmed');
    await seedToken('p2');
    await seedToken('p3');
    const sendEach = mockSendEach(2);

    await wrap(
      expenseEvent(
        { ...base, payerParticipantId: 'creator', createdBy: 'creator', lastEditedBy: 'creator' },
        { gid: 'g1', eid: 'e1', expenseId: 'x1' },
      ),
    );

    expect(tokensOf(sendEach)).toEqual(['tok-p2', 'tok-p3']);
    const msg = sendEach.mock.calls[0][0][0];
    expect(msg.notification.title).toBe('Salalah Trip');
    expect(msg.notification.body).toContain('Ahmed');
    expect(msg.notification.body).toContain('10.500');
    expect(msg.notification.body).toContain('Dinner');
    expect(msg.data).toEqual({ type: 'expense', groupId: 'g1', eventId: 'e1' });
  });

  test('splitDistribution keys are the recipients; payer added when payer != creator', async () => {
    await seedGroup('g1', 'Trip', ['creator', 'p2', 'p3', 'payer']);
    await seedMember('g1', 'creator', 'Sara');
    await seedToken('p2');
    await seedToken('p3');
    await seedToken('payer');
    const sendEach = mockSendEach(3);

    await wrap(
      expenseEvent(
        {
          ...base,
          scope: 'custom',
          splitMode: 'shares',
          splitDistribution: { p2: 2, p3: 1 },
          payerParticipantId: 'payer',
          createdBy: 'creator',
          lastEditedBy: 'creator',
        },
        { gid: 'g1', eid: 'e1', expenseId: 'x1' },
      ),
    );

    expect(tokensOf(sendEach)).toEqual(['tok-p2', 'tok-p3', 'tok-payer']);
  });

  test('zero-share participant is NOT notified (false-buzz guard)', async () => {
    await seedGroup('g1', 'Trip', ['creator', 'p2', 'p3']);
    await seedMember('g1', 'creator', 'Sara');
    await seedToken('p2');
    await seedToken('p3');
    const sendEach = mockSendEach(1);

    await wrap(
      expenseEvent(
        {
          ...base,
          splitMode: 'shares',
          splitDistribution: { p2: 0, p3: 2 },
          payerParticipantId: 'creator',
          createdBy: 'creator',
          lastEditedBy: 'creator',
        },
        { gid: 'g1', eid: 'e1', expenseId: 'x1' },
      ),
    );

    expect(tokensOf(sendEach)).toEqual(['tok-p3']);
  });

  test('custom + equally uses customSplitParticipants (no distribution)', async () => {
    await seedGroup('g1', 'Trip', ['creator', 'p2', 'p3']);
    await seedMember('g1', 'creator', 'Sara');
    await seedToken('p2');
    await seedToken('p3');
    const sendEach = mockSendEach(2);

    await wrap(
      expenseEvent(
        {
          ...base,
          scope: 'custom',
          customSplitParticipants: ['p2', 'p3'],
          payerParticipantId: 'creator',
          createdBy: 'creator',
          lastEditedBy: 'creator',
        },
        { gid: 'g1', eid: 'e1', expenseId: 'x1' },
      ),
    );

    expect(tokensOf(sendEach)).toEqual(['tok-p2', 'tok-p3']);
  });

  test('personal scope notifies nobody when payer is the creator', async () => {
    await seedGroup('g1', 'Trip', ['creator']);
    await seedToken('creator');
    const sendEach = mockSendEach(0);

    await wrap(
      expenseEvent(
        {
          ...base,
          scope: 'personal',
          payerParticipantId: 'creator',
          createdBy: 'creator',
          lastEditedBy: 'creator',
        },
        { gid: 'g1', eid: 'e1', expenseId: 'x1' },
      ),
    );

    expect(sendEach).not.toHaveBeenCalled();
  });

  test('deleted-on-create expense is not notified', async () => {
    await seedGroup('g1', 'Trip', ['creator', 'p2']);
    await seedEvent('g1', 'e1', ['creator', 'p2']);
    await seedToken('p2');
    const sendEach = mockSendEach(0);

    await wrap(
      expenseEvent(
        { ...base, isDeleted: true, payerParticipantId: 'creator', createdBy: 'creator' },
        { gid: 'g1', eid: 'e1', expenseId: 'x1' },
      ),
    );

    expect(sendEach).not.toHaveBeenCalled();
  });

  test('unresolved actor falls back to localized "Someone" per recipient locale', async () => {
    await seedGroup('g1', 'Trip', ['creator', 'p2', 'p3']);
    await seedEvent('g1', 'e1', ['creator', 'p2', 'p3']);
    // no member doc for creator -> actor unresolved
    await seedToken('p2', 'en');
    await seedToken('p3', 'ar');
    const sendEach = mockSendEach(2);

    await wrap(
      expenseEvent(
        { ...base, payerParticipantId: 'creator', createdBy: 'creator' },
        { gid: 'g1', eid: 'e1', expenseId: 'x1' },
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
    await seedGroup('g1', 'Trip', ['creator', 'p2']);
    await seedEvent('g1', 'e1', ['creator', 'p2']);
    await seedMember('g1', 'creator', 'Ahmed');
    // no token for p2
    const sendEach = mockSendEach(0);

    await wrap(
      expenseEvent(
        { ...base, payerParticipantId: 'creator', createdBy: 'creator' },
        { gid: 'g1', eid: 'e1', expenseId: 'x1' },
      ),
    );

    expect(sendEach).not.toHaveBeenCalled();
  });

  test('formats the expense currency (JPY scale 1), not the group currency', async () => {
    await seedGroup('g1', 'Tokyo', ['creator', 'p2']);
    await seedEvent('g1', 'e1', ['creator', 'p2']);
    await seedMember('g1', 'creator', 'Ahmed');
    await seedToken('p2');
    const sendEach = mockSendEach(1);

    await wrap(
      expenseEvent(
        { ...base, currency: 'JPY', amountFils: 1000, payerParticipantId: 'creator', createdBy: 'creator' },
        { gid: 'g1', eid: 'e1', expenseId: 'x1' },
      ),
    );

    expect(sendEach.mock.calls[0][0][0].notification.body).toContain('1000');
  });

  test('retrying the same Eventarc create event sends only once', async () => {
    await seedGroup('g1', 'Trip', ['creator', 'p2']);
    await seedEvent('g1', 'e1', ['creator', 'p2']);
    await seedMember('g1', 'creator', 'Ahmed');
    await seedToken('p2');
    const sendEach = mockSendEach(1);
    const event = expenseEvent(
      { ...base, payerParticipantId: 'creator', createdBy: 'creator' },
      { gid: 'g1', eid: 'e1', expenseId: 'x1' },
      'evt-expense-retry',
    );

    await wrap(event);
    await wrap(event);

    expect(sendEach).toHaveBeenCalledTimes(1);
  });

  test('#1141: split naming a departed historical participant does not push them; current parties do', async () => {
    // leave/remove never prunes event participantIds (#1131), so a split can
    // still name a departed member with a positive share and a live token.
    await seedGroup('g1', 'Muscat Trip', ['creator', 'staying']);
    await seedMember('g1', 'creator', 'Ali');
    await seedToken('staying');
    await seedToken('departed'); // positive share + valid token, no longer a member
    const sendEach = mockSendEach(1);

    await wrap(
      expenseEvent(
        {
          ...base,
          scope: 'custom',
          splitMode: 'shares',
          splitDistribution: { staying: 1, departed: 1 },
          payerParticipantId: 'creator',
          createdBy: 'creator',
          lastEditedBy: 'creator',
        },
        { gid: 'g1', eid: 'e1', expenseId: 'x1' },
      ),
    );

    expect(tokensOf(sendEach)).toEqual(['tok-staying']);
  });
});
