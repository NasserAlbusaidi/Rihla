import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import * as messaging from 'firebase-admin/messaging';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';
import { joinGroupByInviteCode } from '../../src/callables/joinGroupByInviteCode';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(joinGroupByInviteCode);

async function seedInviteGroup(): Promise<void> {
  const db = getFirestore();
  await db.doc('groups/g1').set({
    id: 'g1',
    name: 'Desert Crew',
    inviteCode: 'ABC123',
    createdBy: 'owner',
    memberIds: ['owner'],
    currency: 'OMR',
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  await db.doc('groups/g1/members/owner').set({
    id: 'owner',
    userId: 'owner',
    displayName: 'Owner',
    role: 'CREATOR',
    joinedAt: new Date(),
    isShadow: false,
  });
  await db.doc('inviteCodes/ABC123').set({
    groupId: 'g1',
    createdAt: new Date(),
  });
}

async function seedEvent(
  eventId: string,
  data: Record<string, unknown> = {},
  groupId = 'g1',
): Promise<void> {
  const db = getFirestore();
  await db.doc(`groups/${groupId}/events/${eventId}`).set({
    id: eventId,
    groupId,
    name: `Event ${eventId}`,
    type: 'trip',
    createdBy: 'owner',
    participantIds: ['owner'],
    participantNames: { owner: 'Owner' },
    modules: { ledger: true },
    isDeleted: false,
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    updatedAt: 'stable',
    ...data,
  });
}

beforeEach(async () => {
  await clearFirestore();
  await seedInviteGroup();
});

afterAll(async () => {
  await clearFirestore();
  testEnv.cleanup();
});

afterEach(() => {
  jest.restoreAllMocks();
});

describe('joinGroupByInviteCode', () => {
  test('unauthenticated request rejected', async () => {
    await expect(wrapped({ data: { inviteCode: 'ABC123' }, auth: undefined } as any))
      .rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('invalid invite code rejected without revealing groups', async () => {
    await expect(wrapped({
      data: { inviteCode: 'NOPE99', displayName: 'Eve' },
      auth: { uid: 'eve' },
    } as any)).rejects.toMatchObject({ code: 'not-found' });
  });

  test('bad invite attempts lock the caller after five failures', async () => {
    for (let i = 0; i < 5; i += 1) {
      await expect(wrapped({
        data: { inviteCode: 'NOPE99', displayName: 'Eve' },
        auth: { uid: 'eve' },
      } as any)).rejects.toMatchObject({ code: 'not-found' });
    }

    await expect(wrapped({
      data: { inviteCode: 'NOPE99', displayName: 'Eve' },
      auth: { uid: 'eve' },
    } as any)).rejects.toMatchObject({ code: 'resource-exhausted' });
  });

  // #648: an anonymous user may JOIN and participate. #818 later removed the
  // matching group/invite-code create gate.
  // Anon membership is identity-equivalent to durable at the rules layer
  // (validExpenseCreate → isEventParticipant), so the join callable no longer
  // rejects anonymous providers. (#647 closes the populated-shell swap hole.)
  test('anonymous provider joins successfully (#648)', async () => {
    const res = await wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Anon' },
      auth: { uid: 'anon-1', token: { firebase: { sign_in_provider: 'anonymous' } } },
    } as any);

    expect(res).toEqual({ groupId: 'g1' });
    const db = getFirestore();
    expect((await db.doc('groups/g1').get()).data()?.memberIds).toContain('anon-1');
    expect((await db.doc('groups/g1/members/anon-1').get()).exists).toBe(true);
  });

  test('google.com provider joins successfully', async () => {
    const res = await wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Googled' },
      auth: { uid: 'googled', token: { firebase: { sign_in_provider: 'google.com' } } },
    } as any);

    expect(res).toEqual({ groupId: 'g1' });
    expect((await getFirestore().doc('groups/g1/members/googled').get()).exists)
      .toBe(true);
  });

  test('join adds uid to group and creates member document', async () => {
    const res = await wrapped({
      data: { inviteCode: 'abc123', displayName: 'Alice' },
      auth: { uid: 'alice' },
    } as any);

    expect(res).toEqual({ groupId: 'g1' });
    const db = getFirestore();
    const groupSnap = await db.doc('groups/g1').get();
    expect(groupSnap.data()?.memberIds).toContain('alice');

    const memberSnap = await db.doc('groups/g1/members/alice').get();
    expect(memberSnap.exists).toBe(true);
    expect(memberSnap.data()).toMatchObject({
      id: 'alice',
      userId: 'alice',
      displayName: 'Alice',
      role: 'MEMBER',
      isShadow: false,
    });
  });

  test('new join with no events does not create event writes', async () => {
    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'No Events' },
      auth: { uid: 'no-events' },
    } as any)).resolves.toEqual({ groupId: 'g1' });

    const eventsSnap = await getFirestore().collection('groups/g1/events').get();
    expect(eventsSnap.empty).toBe(true);
  });

  test('new join fans out uid and normalized display name to every event', async () => {
    const db = getFirestore();
    await seedEvent('e1');
    await seedEvent('e2', {
      participantIds: ['owner', 'existing'],
      participantNames: { owner: 'Owner', existing: 'Existing' },
    });

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: '  Alice Example  ' },
      auth: { uid: 'alice' },
    } as any)).resolves.toEqual({ groupId: 'g1' });

    const e1 = await db.doc('groups/g1/events/e1').get();
    const e2 = await db.doc('groups/g1/events/e2').get();
    expect(e1.data()?.participantIds).toEqual(['owner', 'alice']);
    expect(e2.data()?.participantIds).toEqual(['owner', 'existing', 'alice']);
    expect(e1.data()?.participantNames).toMatchObject({
      owner: 'Owner',
      alice: 'Alice Example',
    });
    expect(e2.data()?.participantNames).toMatchObject({
      owner: 'Owner',
      existing: 'Existing',
      alice: 'Alice Example',
    });
    expect(e1.data()?.updatedAt).not.toBe('stable');
    expect(e2.data()?.updatedAt).not.toBe('stable');
  });

  test('new join skips soft-deleted events', async () => {
    const db = getFirestore();
    await seedEvent('active');
    await seedEvent('deleted', { isDeleted: true });

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Alice' },
      auth: { uid: 'alice' },
    } as any)).resolves.toEqual({ groupId: 'g1' });

    const active = await db.doc('groups/g1/events/active').get();
    const deleted = await db.doc('groups/g1/events/deleted').get();
    expect(active.data()?.participantIds).toContain('alice');
    expect(deleted.data()?.participantIds).toEqual(['owner']);
    expect(deleted.data()?.participantNames).toEqual({ owner: 'Owner' });
    expect(deleted.data()?.updatedAt).toBe('stable');
  });

  test('join is rejected when the group is soft-deleted (#78 race with deleteAccount Phase C)', async () => {
    const db = getFirestore();
    // deleteAccount Phase C soft-deletes an owner-only orphan group
    // (isDeleted: true). A join racing that commit must not resurrect the dead
    // group by arrayUnion-ing a member into it.
    await seedEvent('active');
    await db.doc('groups/g1').update({ isDeleted: true, deletedAt: new Date() });

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Alice' },
      auth: { uid: 'alice' },
    } as any)).rejects.toMatchObject({ code: 'not-found' });

    // No membership written: memberIds unchanged, member doc not created.
    const groupSnap = await db.doc('groups/g1').get();
    expect(groupSnap.data()?.memberIds).toEqual(['owner']);
    const memberSnap = await db.doc('groups/g1/members/alice').get();
    expect(memberSnap.exists).toBe(false);
    // No event fanout into the dead group's events.
    const active = await db.doc('groups/g1/events/active').get();
    expect(active.data()?.participantIds).toEqual(['owner']);

    // Intentional, asserted so it stays visible: a valid code pointing at a
    // soft-deleted group is a lookup failure (code 'not-found' ∈ isLookupFailure),
    // so it counts toward the 5/hr lock exactly like an invalid code.
    const attemptSnap = await db.doc('joinAttempts/alice').get();
    expect(attemptSnap.exists).toBe(true);
    expect(attemptSnap.data()?.failCount).toBe(1);
  });

  test('join is rejected while deleteGroup is quiescing the group (#205)', async () => {
    const db = getFirestore();
    await seedEvent('active');
    await db.doc('groups/g1').update({
      isDeleted: false,
      deletingInProgress: true,
      deleteLockedAt: new Date(),
      deleteLockedBy: 'owner',
    });

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Alice' },
      auth: { uid: 'alice' },
    } as any)).rejects.toMatchObject({ code: 'not-found' });

    const groupSnap = await db.doc('groups/g1').get();
    expect(groupSnap.data()?.memberIds).toEqual(['owner']);
    const memberSnap = await db.doc('groups/g1/members/alice').get();
    expect(memberSnap.exists).toBe(false);
    const active = await db.doc('groups/g1/events/active').get();
    expect(active.data()?.participantIds).toEqual(['owner']);
  });

  test('join is rejected while a departure lock is held (#1144) — fan-in must not land in the recompute window', async () => {
    const db = getFirestore();
    await seedEvent('active');
    await db.doc('groups/g1').update({
      departureInProgress: true,
      departureLockedAt: new Date(),
      departureLockedBy: 'owner',
    });

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Alice' },
      auth: { uid: 'alice' },
    } as any)).rejects.toMatchObject({ code: 'not-found' });

    const groupSnap = await db.doc('groups/g1').get();
    expect(groupSnap.data()?.memberIds).toEqual(['owner']);
    const active = await db.doc('groups/g1/events/active').get();
    expect(active.data()?.participantIds).toEqual(['owner']);
  });

  test('quiesced group returns not-found before the event-count guard (#205)', async () => {
    const db = getFirestore();
    const batch = db.batch();
    for (let i = 0; i < 401; i += 1) {
      batch.set(db.doc(`groups/g1/events/e${i}`), {
        id: `e${i}`,
        groupId: 'g1',
        name: `Event ${i}`,
        type: 'trip',
        createdBy: 'owner',
        participantIds: ['owner'],
        participantNames: { owner: 'Owner' },
        modules: { ledger: true },
        isDeleted: false,
        createdAt: new Date('2026-01-01T00:00:00.000Z'),
        updatedAt: 'stable',
      });
    }
    await batch.commit();
    await db.doc('groups/g1').update({
      isDeleted: false,
      deletingInProgress: true,
      deleteLockedAt: new Date(),
      deleteLockedBy: 'owner',
    });

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Alice' },
      auth: { uid: 'alice' },
    } as any)).rejects.toMatchObject({ code: 'not-found' });

    const attemptSnap = await db.doc('joinAttempts/alice').get();
    expect(attemptSnap.exists).toBe(true);
    expect(attemptSnap.data()?.failCount).toBe(1);
  });

  test('already-member re-join heals stale event participantIds', async () => {
    const db = getFirestore();
    await db.doc('groups/g1').update({ memberIds: ['owner', 'alice'] });
    await db.doc('groups/g1/members/alice').set({
      id: 'alice',
      userId: 'alice',
      displayName: 'Alice',
      role: 'MEMBER',
      joinedAt: new Date(),
      isShadow: false,
    });
    await seedEvent('stale', { participantIds: ['owner'], participantNames: { owner: 'Owner' } });

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Alice' },
      auth: { uid: 'alice' },
    } as any)).resolves.toEqual({ groupId: 'g1' });

    const event = await db.doc('groups/g1/events/stale').get();
    expect(event.data()?.participantIds).toEqual(['owner', 'alice']);
    expect(event.data()?.participantNames).toMatchObject({ alice: 'Alice' });
  });

  test('already-member re-join leaves synced events untouched', async () => {
    const db = getFirestore();
    await db.doc('groups/g1').update({ memberIds: ['owner', 'alice'] });
    await db.doc('groups/g1/members/alice').set({
      id: 'alice',
      userId: 'alice',
      displayName: 'Alice',
      role: 'MEMBER',
      joinedAt: new Date(),
      isShadow: false,
    });
    await seedEvent('synced', {
      participantIds: ['owner', 'alice'],
      participantNames: { owner: 'Owner', alice: 'Alice' },
    });

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Alice' },
      auth: { uid: 'alice' },
    } as any)).resolves.toEqual({ groupId: 'g1' });

    const event = await db.doc('groups/g1/events/synced').get();
    expect(event.data()?.participantIds).toEqual(['owner', 'alice']);
    expect(event.data()?.participantNames).toEqual({ owner: 'Owner', alice: 'Alice' });
    expect(event.data()?.updatedAt).toBe('stable');
  });

  test('malformed event participantIds rejects without partial writes', async () => {
    const db = getFirestore();
    await seedEvent('good');
    await seedEvent('bad', { participantIds: 'owner' });

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Mallory' },
      auth: { uid: 'mallory' },
    } as any)).rejects.toMatchObject({ code: 'failed-precondition' });

    const group = await db.doc('groups/g1').get();
    const member = await db.doc('groups/g1/members/mallory').get();
    const good = await db.doc('groups/g1/events/good').get();
    expect(group.data()?.memberIds).not.toContain('mallory');
    expect(member.exists).toBe(false);
    expect(good.data()?.participantIds).toEqual(['owner']);
    expect(good.data()?.participantNames).toEqual({ owner: 'Owner' });
    expect(good.data()?.updatedAt).toBe('stable');
  });

  test('new join does not touch events in other groups', async () => {
    const db = getFirestore();
    await db.doc('groups/g2').set({
      id: 'g2',
      name: 'Other Crew',
      inviteCode: 'DEF456',
      createdBy: 'owner',
      memberIds: ['owner'],
      currency: 'OMR',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await seedEvent('other', {}, 'g2');
    await seedEvent('target');

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Alice' },
      auth: { uid: 'alice' },
    } as any)).resolves.toEqual({ groupId: 'g1' });

    const target = await db.doc('groups/g1/events/target').get();
    const other = await db.doc('groups/g2/events/other').get();
    expect(target.data()?.participantIds).toContain('alice');
    expect(other.data()?.participantIds).toEqual(['owner']);
    expect(other.data()?.participantNames).toEqual({ owner: 'Owner' });
    expect(other.data()?.updatedAt).toBe('stable');
  });

  test('missing display name falls back to Anonymous', async () => {
    await expect(wrapped({
      data: { inviteCode: 'ABC123' },
      auth: { uid: 'anon' },
    } as any)).resolves.toEqual({ groupId: 'g1' });

    const memberSnap = await getFirestore().doc('groups/g1/members/anon').get();
    expect(memberSnap.data()?.displayName).toBe('Anonymous');
  });

  test('display name length mirrors Firestore rules limit', async () => {
    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'A'.repeat(33) },
      auth: { uid: 'long-name' },
    } as any)).rejects.toMatchObject({ code: 'invalid-argument' });

    const memberSnap = await getFirestore()
      .doc('groups/g1/members/long-name')
      .get();
    expect(memberSnap.exists).toBe(false);
  });

  test('display name rejects control characters before Admin SDK writes', async () => {
    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Eve\nMallory' },
      auth: { uid: 'bad-name' },
    } as any)).rejects.toMatchObject({ code: 'invalid-argument' });

    const memberSnap = await getFirestore()
      .doc('groups/g1/members/bad-name')
      .get();
    expect(memberSnap.exists).toBe(false);
  });

  test('successful join clears previous failed attempt counter', async () => {
    for (let i = 0; i < 4; i += 1) {
      await expect(wrapped({
        data: { inviteCode: 'NOPE99', displayName: 'Bob' },
        auth: { uid: 'bob' },
      } as any)).rejects.toMatchObject({ code: 'not-found' });
    }

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Bob' },
      auth: { uid: 'bob' },
    } as any)).resolves.toEqual({ groupId: 'g1' });

    const counterSnap = await getFirestore().doc('joinAttempts/bob').get();
    expect(counterSnap.exists).toBe(false);

    await expect(wrapped({
      data: { inviteCode: 'NOPE99', displayName: 'Bob' },
      auth: { uid: 'bob' },
    } as any)).rejects.toMatchObject({ code: 'not-found' });
  });

  test('success log omits raw invite code', async () => {
    const infoSpy = jest
      .spyOn(logger, 'info')
      .mockImplementation(() => undefined);

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Carol' },
      auth: { uid: 'carol' },
    } as any)).resolves.toEqual({ groupId: 'g1' });

    expect(infoSpy).toHaveBeenCalledWith('group-join succeeded', {
      uid: 'carol',
      groupId: 'g1',
    });
    expect(JSON.stringify(infoSpy.mock.calls)).not.toContain('ABC123');
  });

  test('already-member join is idempotent', async () => {
    const first = await wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Alice' },
      auth: { uid: 'alice' },
    } as any);
    const second = await wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Alice Again' },
      auth: { uid: 'alice' },
    } as any);

    expect(first).toEqual({ groupId: 'g1' });
    expect(second).toEqual({ groupId: 'g1' });
    const members = await getFirestore().collection('groups/g1/members').listDocuments();
    expect(members.map((doc) => doc.id).sort()).toEqual(['alice', 'owner']);
  });

  test('already-member join heals a missing member document', async () => {
    const db = getFirestore();
    await db.doc('groups/g1').update({ memberIds: ['owner', 'orphan'] });

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Orphan' },
      auth: { uid: 'orphan' },
    } as any)).resolves.toEqual({ groupId: 'g1' });

    const memberSnap = await db.doc('groups/g1/members/orphan').get();
    expect(memberSnap.exists).toBe(true);
    expect(memberSnap.data()).toMatchObject({
      id: 'orphan',
      userId: 'orphan',
      displayName: 'Orphan',
      role: 'MEMBER',
      isShadow: false,
    });
  });

  test('malformed memberIds is rejected before writing membership', async () => {
    const db = getFirestore();
    await db.doc('groups/g1').update({ memberIds: 'owner' });

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Mallory' },
      auth: { uid: 'mallory' },
    } as any)).rejects.toMatchObject({ code: 'failed-precondition' });

    const memberSnap = await db.doc('groups/g1/members/mallory').get();
    expect(memberSnap.exists).toBe(false);
  });
});

describe('joinGroupByInviteCode — display-name collision guard (#279)', () => {
  // seedInviteGroup() (beforeEach) already seeds member "Owner" in g1.

  test('rejects a new join whose name collides (case-insensitive) with a member', async () => {
    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'owner' },
      auth: { uid: 'eve' },
    } as any)).rejects.toMatchObject({ code: 'already-exists' });

    const db = getFirestore();
    // No membership written on rejection.
    expect((await db.doc('groups/g1').get()).data()?.memberIds).toEqual(['owner']);
    expect((await db.doc('groups/g1/members/eve').get()).exists).toBe(false);
  });

  test('rejects on trim + case variants of an existing name', async () => {
    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: '  OWNER  ' },
      auth: { uid: 'eve' },
    } as any)).rejects.toMatchObject({ code: 'already-exists' });
  });

  test('a unique name still joins', async () => {
    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Layla' },
      auth: { uid: 'layla' },
    } as any)).resolves.toEqual({ groupId: 'g1' });
    expect((await getFirestore().doc('groups/g1/members/layla').get())
      .data()?.displayName).toBe('Layla');
  });

  test('collision does NOT burn the join throttle (already-exists is not a lookup failure)', async () => {
    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Owner' },
      auth: { uid: 'eve' },
    } as any)).rejects.toMatchObject({ code: 'already-exists' });
    // joinAttempts/{uid} must be untouched — a collision is a legit user error.
    expect((await getFirestore().doc('joinAttempts/eve').get()).exists).toBe(false);
  });

  test('idempotent re-join with the SAME name is not self-rejected', async () => {
    const db = getFirestore();
    await db.doc('groups/g1').update({ memberIds: ['owner', 'alice'] });
    await db.doc('groups/g1/members/alice').set({
      id: 'alice', userId: 'alice', displayName: 'Alice',
      role: 'MEMBER', joinedAt: new Date(), isShadow: false,
    });

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Alice' },
      auth: { uid: 'alice' },
    } as any)).resolves.toEqual({ groupId: 'g1' });
  });

  test('heal-path re-join (uid in memberIds, member-doc missing) is NOT blocked even if its name collides', async () => {
    // #53 heal path: uid is already in memberIds but its member doc is gone.
    // Restoring it must NOT be uniqueness-checked (the member already "owns"
    // that name) — the guard is gated on `didJoin`, which is false here.
    const db = getFirestore();
    await db.doc('groups/g1').update({ memberIds: ['owner', 'heal'] });
    // No members/heal doc — the doc to be healed. 'heal' wants displayName
    // 'Owner', which collides with the existing owner member doc.

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'Owner' },
      auth: { uid: 'heal' },
    } as any)).resolves.toEqual({ groupId: 'g1' });

    expect((await db.doc('groups/g1/members/heal').get()).exists).toBe(true);
  });

  test('collision is detected against a creator doc keyed by a random uuid (userId-field match)', async () => {
    // createGroup keys the CREATOR's member doc by a random uuid with userId as a
    // FIELD (not by uid). Re-shape the owner doc that way to prove the guard
    // compares displayName across ALL member docs, not by doc id.
    const db = getFirestore();
    await db.doc('groups/g1/members/owner').delete();
    await db.doc('groups/g1/members/2f1c0000-uuid').set({
      id: '2f1c0000-uuid', userId: 'owner', displayName: 'Owner',
      role: 'CREATOR', joinedAt: new Date(), isShadow: false,
    });

    await expect(wrapped({
      data: { inviteCode: 'ABC123', displayName: 'owner' },
      auth: { uid: 'eve' },
    } as any)).rejects.toMatchObject({ code: 'already-exists' });
  });
});

describe('joinGroupByInviteCode — member-join notification (#53)', () => {
  function mockSendEach(): jest.Mock {
    const sendEach = jest.fn().mockResolvedValue({
      successCount: 1,
      failureCount: 0,
      responses: [{ success: true, messageId: 'm' }],
    });
    jest
      .spyOn(messaging, 'getMessaging')
      .mockReturnValue({ sendEach } as unknown as messaging.Messaging);
    return sendEach;
  }

  async function seedToken(uid: string): Promise<void> {
    await getFirestore()
      .doc(`fcm_tokens/${uid}`)
      .set({ user_id: uid, token: `tok-${uid}`, locale: 'en', platform: 'android' });
  }

  beforeEach(async () => {
    const tokens = await getFirestore().collection('fcm_tokens').listDocuments();
    await Promise.all(tokens.map((d) => d.delete()));
  });

  test('first-time join notifies pre-join members minus the joiner', async () => {
    await seedToken('owner');
    const sendEach = mockSendEach();

    await expect(
      wrapped({ data: { inviteCode: 'ABC123', displayName: 'Alice' }, auth: { uid: 'alice' } } as any),
    ).resolves.toEqual({ groupId: 'g1' });

    expect(sendEach).toHaveBeenCalledTimes(1);
    const messages = sendEach.mock.calls[0][0];
    expect(messages).toHaveLength(1);
    expect(messages[0].token).toBe('tok-owner');
    expect(messages[0].data).toEqual({ type: 'member_join', groupId: 'g1' });
    expect(messages[0].notification.body).toContain('Alice');
  });

  test('idempotent re-join sends NO notification (G1 gate)', async () => {
    const db = getFirestore();
    // alice is ALREADY a member with a member doc.
    await db.doc('groups/g1').update({ memberIds: ['owner', 'alice'] });
    await db.doc('groups/g1/members/alice').set({
      id: 'alice', userId: 'alice', displayName: 'Alice',
      role: 'MEMBER', joinedAt: new Date(), isShadow: false,
    });
    await seedToken('owner'); // owner WOULD be a valid target if the gate were absent
    const sendEach = mockSendEach();

    await expect(
      wrapped({ data: { inviteCode: 'ABC123', displayName: 'Alice' }, auth: { uid: 'alice' } } as any),
    ).resolves.toEqual({ groupId: 'g1' });

    expect(sendEach).not.toHaveBeenCalled();
  });

  test('heal-path re-join (in memberIds, member-doc missing) does NOT re-announce', async () => {
    const db = getFirestore();
    // alice is in memberIds but her member doc is MISSING (the heal path).
    await db.doc('groups/g1').update({ memberIds: ['owner', 'alice'] });
    await seedToken('owner');
    const sendEach = mockSendEach();

    await expect(
      wrapped({ data: { inviteCode: 'ABC123', displayName: 'Alice' }, auth: { uid: 'alice' } } as any),
    ).resolves.toEqual({ groupId: 'g1' });

    // the heal still creates the member doc...
    expect((await db.doc('groups/g1/members/alice').get()).exists).toBe(true);
    // ...but it is NOT a brand-new join, so no notification fires.
    expect(sendEach).not.toHaveBeenCalled();
  });

  test('notification failure does NOT fail the committed join', async () => {
    await seedToken('owner');
    jest.spyOn(messaging, 'getMessaging').mockReturnValue({
      sendEach: jest.fn().mockRejectedValue(new Error('fcm down')),
    } as unknown as messaging.Messaging);

    await expect(
      wrapped({ data: { inviteCode: 'ABC123', displayName: 'Alice' }, auth: { uid: 'alice' } } as any),
    ).resolves.toEqual({ groupId: 'g1' });

    const memberSnap = await getFirestore().doc('groups/g1/members/alice').get();
    expect(memberSnap.exists).toBe(true);
  });
});
