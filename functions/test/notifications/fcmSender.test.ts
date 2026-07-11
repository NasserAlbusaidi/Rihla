import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import * as messaging from 'firebase-admin/messaging';
import { sendToUids } from '../../src/notifications/fcmSender';

const notificationDeliveryTtlMs = 90 * 24 * 60 * 60 * 1000;

async function clearNotificationState(): Promise<void> {
  const db = getFirestore();
  await db.recursiveDelete(db.collection('fcm_tokens'));
  await db.recursiveDelete(db.collection('notificationDeliveries'));
  await db.recursiveDelete(db.collection('groups'));
}

async function seedGroup(gid: string, memberIds: string[]): Promise<void> {
  await getFirestore().doc(`groups/${gid}`).set({ id: gid, name: 'G', memberIds });
}

async function seedToken(
  uid: string,
  token: string | null,
  locale?: string,
): Promise<void> {
  const data: Record<string, unknown> = { user_id: uid, platform: 'android' };
  if (token !== null) data.token = token;
  if (locale !== undefined) data.locale = locale;
  await getFirestore().doc(`fcm_tokens/${uid}`).set(data);
}

function mockSendEach(
  perMessage: Array<{ success: boolean; code?: string }>,
): jest.Mock {
  const sendEach = jest.fn().mockResolvedValue({
    successCount: perMessage.filter((r) => r.success).length,
    failureCount: perMessage.filter((r) => !r.success).length,
    responses: perMessage.map((r) =>
      r.success
        ? { success: true, messageId: 'mid' }
        : { success: false, error: { code: r.code } },
    ),
  });
  jest
    .spyOn(messaging, 'getMessaging')
    .mockReturnValue({ sendEach } as unknown as messaging.Messaging);
  return sendEach;
}

const build = (locale: 'en' | 'ar') => ({
  title: 'T',
  body: locale === 'ar' ? 'نص' : 'text',
});

beforeEach(async () => {
  await clearNotificationState();
});

afterEach(() => {
  jest.restoreAllMocks();
});

afterAll(async () => {
  await clearNotificationState();
});

describe('sendToUids', () => {
  test('sends one localized message per uid with a token', async () => {
    await seedToken('a', 'tok-a', 'en');
    await seedToken('b', 'tok-b', 'ar');
    const sendEach = mockSendEach([
      { success: true },
      { success: true },
    ]);

    await sendToUids(['a', 'b'], build, { type: 'settlement', groupId: 'g1' });

    expect(sendEach).toHaveBeenCalledTimes(1);
    const messages = sendEach.mock.calls[0][0];
    expect(messages).toHaveLength(2);
    const byToken = Object.fromEntries(messages.map((m: any) => [m.token, m]));
    expect(byToken['tok-a'].notification.body).toBe('text');
    expect(byToken['tok-b'].notification.body).toBe('نص'); // ar locale
    expect(byToken['tok-a'].data).toEqual({ type: 'settlement', groupId: 'g1' });
  });

  test('skips uids with no token document and uids with empty token', async () => {
    await seedToken('has', 'tok', 'en');
    await seedToken('empty', ''); // present but empty token
    // 'missing' has no doc at all
    const sendEach = mockSendEach([{ success: true }]);

    await sendToUids(['has', 'empty', 'missing'], build, { type: 'x', groupId: 'g' });

    const messages = sendEach.mock.calls[0][0];
    expect(messages).toHaveLength(1);
    expect(messages[0].token).toBe('tok');
  });

  test('dedups repeated uids', async () => {
    await seedToken('a', 'tok-a', 'en');
    const sendEach = mockSendEach([{ success: true }]);

    await sendToUids(['a', 'a', 'a'], build, { type: 'x', groupId: 'g' });

    expect(sendEach.mock.calls[0][0]).toHaveLength(1);
  });

  test('no token records -> sendEach never called (fast path)', async () => {
    const sendEach = mockSendEach([]);
    await sendToUids(['nobody'], build, { type: 'x', groupId: 'g' });
    expect(sendEach).not.toHaveBeenCalled();
  });

  test('empty uids -> no-op, sendEach never called', async () => {
    const sendEach = mockSendEach([]);
    await sendToUids([], build, { type: 'x', groupId: 'g' });
    await sendToUids(['', '  '.trim()], build, { type: 'x', groupId: 'g' });
    expect(sendEach).not.toHaveBeenCalled();
  });

  test('prunes tokens that are not-registered / invalid', async () => {
    await seedToken('dead', 'tok-dead', 'en');
    await seedToken('live', 'tok-live', 'en');
    mockSendEach([
      { success: false, code: 'messaging/registration-token-not-registered' },
      { success: true },
    ]);

    await sendToUids(['dead', 'live'], build, { type: 'x', groupId: 'g' });

    const db = getFirestore();
    expect((await db.doc('fcm_tokens/dead').get()).exists).toBe(false);
    expect((await db.doc('fcm_tokens/live').get()).exists).toBe(true);
  });

  test('does NOT prune on a transient (non-prunable) error code', async () => {
    await seedToken('flaky', 'tok-flaky', 'en');
    mockSendEach([{ success: false, code: 'messaging/internal-error' }]);

    await sendToUids(['flaky'], build, { type: 'x', groupId: 'g' });

    expect((await getFirestore().doc('fcm_tokens/flaky').get()).exists).toBe(true);
  });

  test('never throws when sendEach rejects', async () => {
    await seedToken('a', 'tok-a', 'en');
    jest.spyOn(messaging, 'getMessaging').mockReturnValue({
      sendEach: jest.fn().mockRejectedValue(new Error('network down')),
    } as unknown as messaging.Messaging);

    await expect(
      sendToUids(['a'], build, { type: 'x', groupId: 'g' }),
    ).resolves.toBeUndefined();
    // token retained on transient failure
    expect((await getFirestore().doc('fcm_tokens/a').get()).exists).toBe(true);
  });

  test('legacy doc with no locale field defaults to en copy', async () => {
    await seedToken('legacy', 'tok-legacy'); // no locale
    const sendEach = mockSendEach([{ success: true }]);

    await sendToUids(['legacy'], build, { type: 'x', groupId: 'g' });

    expect(sendEach.mock.calls[0][0][0].notification.body).toBe('text');
  });

  test('same dedupeKey sends once and writes one marker', async () => {
    await seedToken('a', 'tok-a', 'en');
    const sendEach = mockSendEach([{ success: true }]);

    await sendToUids(
      ['a'],
      build,
      { type: 'expense', groupId: 'g' },
      { dedupeKey: 'expense:create:g:e:x:event-1' },
    );
    await sendToUids(
      ['a'],
      build,
      { type: 'expense', groupId: 'g' },
      { dedupeKey: 'expense:create:g:e:x:event-1' },
    );

    expect(sendEach).toHaveBeenCalledTimes(1);
    const markers = await getFirestore().collection('notificationDeliveries').get();
    expect(markers.size).toBe(1);
    const marker = markers.docs[0].data();
    expect(marker).toMatchObject({
      key: 'expense:create:g:e:x:event-1',
      data: { type: 'expense', groupId: 'g' },
    });
    expect(marker.createdAt).toBeInstanceOf(Timestamp);
    expect(marker.expiresAt).toBeInstanceOf(Timestamp);
    expect(marker.expiresAt.toMillis() - marker.createdAt.toMillis()).toBe(
      notificationDeliveryTtlMs,
    );
  });

  test('different dedupeKeys send independently', async () => {
    await seedToken('a', 'tok-a', 'en');
    const sendEach = mockSendEach([{ success: true }, { success: true }]);

    await sendToUids(
      ['a'],
      build,
      { type: 'event', groupId: 'g' },
      { dedupeKey: 'event:create:g:e:event-1' },
    );
    await sendToUids(
      ['a'],
      build,
      { type: 'event', groupId: 'g' },
      { dedupeKey: 'event:create:g:e:event-2' },
    );

    expect(sendEach).toHaveBeenCalledTimes(2);
  });
});

describe('membership fence (#1141)', () => {
  test('drops targets absent from fresh memberIds, keeps current members', async () => {
    await seedGroup('g1', ['a']);
    await seedToken('a', 'tok-a', 'en');
    await seedToken('departed', 'tok-departed', 'en');
    const sendEach = mockSendEach([{ success: true }]);

    await sendToUids(['a', 'departed'], build, { type: 'expense', groupId: 'g1' }, {
      requireCurrentMembershipOf: 'g1',
    });

    expect(sendEach).toHaveBeenCalledTimes(1);
    const tokens = sendEach.mock.calls[0][0].map((m: { token: string }) => m.token);
    expect(tokens).toEqual(['tok-a']);
  });

  test('group doc missing → sends nothing', async () => {
    await seedToken('a', 'tok-a', 'en');
    const sendEach = mockSendEach([]);

    await sendToUids(['a'], build, { type: 'expense', groupId: 'missing' }, {
      requireCurrentMembershipOf: 'missing',
    });

    expect(sendEach).not.toHaveBeenCalled();
  });

  test('memberIds absent → sends nothing (fail-closed, never committed fallback)', async () => {
    await getFirestore().doc('groups/g2').set({ id: 'g2', name: 'G' }); // no memberIds
    await seedToken('a', 'tok-a', 'en');
    const sendEach = mockSendEach([]);

    await sendToUids(['a'], build, { type: 'expense', groupId: 'g2' }, {
      requireCurrentMembershipOf: 'g2',
    });

    expect(sendEach).not.toHaveBeenCalled();
  });

  test('fence refusal does not burn the dedupe marker', async () => {
    await seedToken('a', 'tok-a', 'en');
    const sendEach = mockSendEach([{ success: true }]);

    // First attempt: group missing → nothing sent, marker NOT claimed.
    await sendToUids(['a'], build, { type: 'expense', groupId: 'g3' }, {
      dedupeKey: 'k-1141', requireCurrentMembershipOf: 'g3',
    });
    expect(sendEach).not.toHaveBeenCalled();
    const markers = await getFirestore().collection('notificationDeliveries').get();
    expect(markers.size).toBe(0);

    // Duplicate invocation after the group exists: same key still deliverable.
    await seedGroup('g3', ['a']);
    await sendToUids(['a'], build, { type: 'expense', groupId: 'g3' }, {
      dedupeKey: 'k-1141', requireCurrentMembershipOf: 'g3',
    });
    expect(sendEach).toHaveBeenCalledTimes(1);
  });

  test('post-fence empty target set does not burn the dedupe marker', async () => {
    await seedGroup('g4', ['member-without-token']);
    await seedToken('departed', 'tok-departed', 'en');
    const sendEach = mockSendEach([]);

    await sendToUids(['departed'], build, { type: 'expense', groupId: 'g4' }, {
      dedupeKey: 'k-empty', requireCurrentMembershipOf: 'g4',
    });

    expect(sendEach).not.toHaveBeenCalled();
    const markers = await getFirestore().collection('notificationDeliveries').get();
    expect(markers.size).toBe(0);
  });

  test('option absent → committed targets pass through unchanged', async () => {
    // No group doc at all; legacy behavior must not require one.
    await seedToken('a', 'tok-a', 'en');
    const sendEach = mockSendEach([{ success: true }]);

    await sendToUids(['a'], build, { type: 'claim_decided', groupId: 'nowhere' });

    expect(sendEach).toHaveBeenCalledTimes(1);
  });
});
