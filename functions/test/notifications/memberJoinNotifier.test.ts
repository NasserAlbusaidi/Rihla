import { getFirestore } from 'firebase-admin/firestore';
import * as messaging from 'firebase-admin/messaging';
import { notifyMemberJoin } from '../../src/notifications/memberJoinNotifier';

// #1141 — direct unit test for the member-join fence. notifyMemberJoin is a
// plain exported function called fire-and-forget from joinGroupByInviteCode
// AFTER a committed join, with the PRE-join member snapshot. The callable test
// cannot interleave a leave between snapshot and send, so the fence is pinned
// here at the notifier unit (no wrap needed).

async function clearAll(): Promise<void> {
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
  token: string,
  locale = 'en',
): Promise<void> {
  await getFirestore()
    .doc(`fcm_tokens/${uid}`)
    .set({ user_id: uid, token, locale, platform: 'android' });
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

function tokensOf(sendEach: jest.Mock): string[] {
  return (sendEach.mock.calls[0]?.[0] ?? []).map((m: { token: string }) => m.token);
}

beforeEach(async () => {
  await clearAll();
});

afterEach(() => jest.restoreAllMocks());

afterAll(async () => {
  await clearAll();
});

describe('notifyMemberJoin membership fence (#1141)', () => {
  test('#1141: pre-join member who left before send gets no member-joined push', async () => {
    // Fresh group state: 'stale-member' already left; joiner committed.
    await seedGroup('g1', ['creator-1', 'joiner-1']);
    await seedToken('creator-1', 'tok-creator-1', 'en');
    await seedToken('stale-member', 'tok-stale', 'en');
    const sendEach = mockSendEach([{ success: true }]);

    // Pre-join snapshot still names stale-member.
    await notifyMemberJoin('g1', 'joiner-1', 'Zed', 'G', ['creator-1', 'stale-member']);

    expect(tokensOf(sendEach)).toEqual(['tok-creator-1']);
  });

  test('#1141: fresh-lookup failure (missing group) sends nothing (fail-closed)', async () => {
    await seedToken('creator-1', 'tok-creator-1', 'en');
    const sendEach = mockSendEach([]);

    await notifyMemberJoin('missing', 'joiner-1', 'Zed', 'G', ['creator-1']);

    expect(sendEach).not.toHaveBeenCalled();
  });

  test('#1141: joiner stays excluded even though fresh memberIds now contains them', async () => {
    await seedGroup('g1', ['creator-1', 'joiner-1']);
    await seedToken('creator-1', 'tok-creator-1', 'en');
    await seedToken('joiner-1', 'tok-joiner-1', 'en');
    const sendEach = mockSendEach([{ success: true }]);

    // existingMemberIds deliberately includes the joiner to prove the joiner
    // exclusion (`id !== joinerUid`) still holds — the fence's fresh read DOES
    // contain joiner-1, but the joiner must never be a target.
    await notifyMemberJoin('g1', 'joiner-1', 'Zed', 'G', ['creator-1', 'joiner-1']);

    expect(tokensOf(sendEach)).toEqual(['tok-creator-1']);
  });
});
