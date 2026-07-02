import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';

// RED → GREEN: #278 add-by-name. A group creator seeds placeholder ("shadow")
// members BY NAME so a brand-new group is usable on the first session. A shadow
// MUST be in groups/{gid}.memberIds to participate (event expenses gate
// participantIds ⊆ memberIds, firestore.rules:367) and memberIds is fully
// server-authoritative (rules:308; #524 rules:782-783 blocks a client member-doc
// create whose id ≠ auth.uid). So shadow create is this Admin-SDK callable: it
// mints a placeholder uuid (BOTH doc id and userId, since the balance oracle
// keys on userId), writes a members/{uuid} doc with isShadow:true, and
// arrayUnions the uuid into memberIds. The oracle is identity-blind (0 isShadow
// in groupNetBalance.ts), so a placeholder uuid is just another member id —
// tests 13a-c prove it is counted in balances as debtor / payer / settled, and
// test 14 proves the existing removeMember callable removes a zero-balance
// shadow unchanged but refuses a non-zero one.
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/addShadowMember.test.ts" npm run test:emulator`

import { addShadowMember } from '../../src/callables/addShadowMember';
import { removeMember } from '../../src/callables/removeMember';
import { recomputeNet } from '../../src/callables/groupNetBalance';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(addShadowMember);
const wrappedRemove = testEnv.wrap(removeMember);

const OWNER = 'owner';
const OUTSIDER = 'outsider';

async function seedGroup(
  groupId: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore().doc(`groups/${groupId}`).set({
    id: groupId,
    name: groupId,
    inviteCode: 'ABC123',
    createdBy: OWNER,
    memberIds: [OWNER],
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
  docId?: string,
): Promise<void> {
  await getFirestore().doc(`groups/${groupId}/members/${docId ?? uid}`).set({
    id: docId ?? uid,
    userId: uid,
    displayName: uid === OWNER ? 'Owner' : uid,
    role: uid === OWNER ? 'CREATOR' : 'MEMBER',
    joinedAt: new Date('2026-01-01T00:00:00.000Z'),
    isShadow: false,
    ...data,
  });
}

async function seedEvent(
  groupId: string,
  eventId: string,
  participantIds: string[],
  participantNames: Record<string, string>,
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore().doc(`groups/${groupId}/events/${eventId}`).set({
    id: eventId,
    groupId,
    name: eventId,
    type: 'trip',
    createdBy: OWNER,
    participantIds,
    participantNames,
    modules: { ledger: true },
    isDeleted: false,
    deletedAt: null,
    createdAt: new Date('2026-01-04T00:00:00.000Z'),
    ...data,
  });
}

const eventData = async (groupId: string, eventId: string) =>
  (await getFirestore().doc(`groups/${groupId}/events/${eventId}`).get()).data() ?? {};

async function seedExpense(
  path: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore().doc(path).set({
    id: path.split('/').pop(),
    eventId: path.split('/')[3],
    createdBy: OWNER,
    payerParticipantId: OWNER,
    amountFils: 12000,
    currency: 'OMR',
    description: 'expense',
    scope: 'global',
    customSplitParticipants: [],
    splitMode: 'equally',
    splitDistribution: {},
    isDeleted: false,
    deletedAt: null,
    createdAt: '2026-01-06T00:00:00.000Z',
    ...data,
  });
}

async function seedEventSettlement(
  path: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore().doc(path).set({
    id: path.split('/').pop(),
    eventId: path.split('/')[3],
    createdBy: OWNER,
    payerParticipantId: OWNER,
    recipientParticipantId: OWNER,
    payerName: 'Owner',
    recipientName: 'Owner',
    amountFils: 6000,
    currency: 'OMR',
    note: null,
    isDeleted: false,
    deletedAt: null,
    settledAt: '2026-01-08T00:00:00.000Z',
    scope: 'event',
    ...data,
  });
}

const groupData = async (groupId: string) =>
  (await getFirestore().doc(`groups/${groupId}`).get()).data() ?? {};

const memberDoc = async (groupId: string, memberId: string) =>
  (await getFirestore().doc(`groups/${groupId}/members/${memberId}`).get()).data();

async function memberDocCount(groupId: string): Promise<number> {
  return (await getFirestore().collection(`groups/${groupId}/members`).get()).size;
}

async function omrNet(groupId: string, uid: string): Promise<string> {
  const { net } = await recomputeNet(getFirestore(), getFirestore().doc(`groups/${groupId}`));
  return net.get('OMR')!.get(uid)!.toFixed(3);
}

beforeEach(async () => {
  await clearFirestore();
  jest.restoreAllMocks();
  jest.spyOn(logger, 'info').mockImplementation(() => undefined);
  jest.spyOn(logger, 'warn').mockImplementation(() => undefined);
  jest.spyOn(logger, 'error').mockImplementation(() => undefined);
});

afterAll(async () => {
  await clearFirestore();
  testEnv.cleanup();
});

describe('addShadowMember callable — creator adds placeholder members by name (#278)', () => {
  test('1. missing auth → unauthenticated', async () => {
    await expect(
      wrapped({ data: { groupId: 'g', displayName: 'Sara' }, auth: undefined } as any),
    ).rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('2. anonymous caller → permission-denied; memberIds unchanged', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await expect(
      wrapped({
        data: { groupId: 'g', displayName: 'Sara' },
        auth: { uid: OWNER, token: { firebase: { sign_in_provider: 'anonymous' } } },
      } as any),
    ).rejects.toMatchObject({ code: 'permission-denied' });
    expect((await groupData('g')).memberIds).toEqual([OWNER]);
    expect(await memberDocCount('g')).toBe(1);
  });

  test('3. invalid groupId ("" and "a/b") → invalid-argument', async () => {
    await expect(
      wrapped({ data: { groupId: '', displayName: 'Sara' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(
      wrapped({ data: { groupId: 'a/b', displayName: 'Sara' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('4. invalid displayName (null, "", "   ", 33 chars, control char, "(former member)" suffix) → invalid-argument', async () => {
    const bad = [
      null,
      '',
      '   ',
      'x'.repeat(33),
      'Bad\x01Name',
      'Bob (former member)',
    ];
    for (const displayName of bad) {
      await expect(
        wrapped({ data: { groupId: 'g', displayName }, auth: { uid: OWNER } } as any),
      ).rejects.toMatchObject({ code: 'invalid-argument' });
    }
  });

  test('5. missing group → not-found', async () => {
    await expect(
      wrapped({ data: { groupId: 'ghost', displayName: 'Sara' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'not-found' });
  });

  test('6. soft-deleted OR deletingInProgress group → not-found; no member created', async () => {
    await seedGroup('g1', { isDeleted: true });
    await seedMember('g1', OWNER);
    await expect(
      wrapped({ data: { groupId: 'g1', displayName: 'Sara' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'not-found' });

    await seedGroup('g2', { deletingInProgress: true });
    await seedMember('g2', OWNER);
    await expect(
      wrapped({ data: { groupId: 'g2', displayName: 'Sara' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'not-found' });

    expect(await memberDocCount('g1')).toBe(1);
    expect(await memberDocCount('g2')).toBe(1);
  });

  test('7. non-creator member caller → permission-denied; no write', async () => {
    await seedGroup('g', { memberIds: [OWNER, OUTSIDER] });
    await seedMember('g', OWNER);
    await seedMember('g', OUTSIDER);
    await expect(
      wrapped({ data: { groupId: 'g', displayName: 'Sara' }, auth: { uid: OUTSIDER } } as any),
    ).rejects.toMatchObject({ code: 'permission-denied' });
    expect((await groupData('g')).memberIds).toEqual([OWNER, OUTSIDER]);
    expect(await memberDocCount('g')).toBe(2);
  });

  test('8. HAPPY: creator adds "Sara" → shadow member doc + memberIds grows by 1', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    const res = await wrapped({
      data: { groupId: 'g', displayName: 'Sara' },
      auth: { uid: OWNER },
    } as any);

    const memberId = (res as { memberId: string }).memberId;
    expect(typeof memberId).toBe('string');
    expect(memberId.length).toBeGreaterThan(0);

    const doc = await memberDoc('g', memberId);
    expect(doc).toMatchObject({
      id: memberId,
      userId: memberId,
      displayName: 'Sara',
      role: 'MEMBER',
      isShadow: true,
    });
    const ids = (await groupData('g')).memberIds as string[];
    expect(ids).toContain(memberId);
    expect(ids).toHaveLength(2);
  });

  test('9. name collides (case-insensitive, trimmed) with a REAL member → already-exists; no write', async () => {
    await seedGroup('g', { memberIds: [OWNER, OUTSIDER] });
    await seedMember('g', OWNER);
    await seedMember('g', OUTSIDER, { displayName: 'Sara' });
    await expect(
      wrapped({ data: { groupId: 'g', displayName: '  sara ' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'already-exists' });
    expect(await memberDocCount('g')).toBe(2);
    expect((await groupData('g')).memberIds).toHaveLength(2);
  });

  test('10. name collides with an existing SHADOW → already-exists; no write', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await wrapped({ data: { groupId: 'g', displayName: 'Sara' }, auth: { uid: OWNER } } as any);
    await expect(
      wrapped({ data: { groupId: 'g', displayName: 'SARA' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'already-exists' });
    expect(await memberDocCount('g')).toBe(2);
  });

  test('11. two distinct names → two shadow docs, both in memberIds, distinct uuids', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    const a = await wrapped({ data: { groupId: 'g', displayName: 'Sara' }, auth: { uid: OWNER } } as any);
    const b = await wrapped({ data: { groupId: 'g', displayName: 'Khalid' }, auth: { uid: OWNER } } as any);
    const idA = (a as { memberId: string }).memberId;
    const idB = (b as { memberId: string }).memberId;
    expect(idA).not.toBe(idB);
    const ids = (await groupData('g')).memberIds as string[];
    expect(ids).toEqual(expect.arrayContaining([OWNER, idA, idB]));
    expect(ids).toHaveLength(3);
    expect(await memberDocCount('g')).toBe(3);
  });

  test('12. member cap: memberIds at MAX → failed-precondition; no write', async () => {
    const fifty = Array.from({ length: 50 }, (_, i) => (i === 0 ? OWNER : `m${i}`));
    await seedGroup('g', { memberIds: fifty });
    await seedMember('g', OWNER);
    await expect(
      wrapped({ data: { groupId: 'g', displayName: 'Sara' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    expect((await groupData('g')).memberIds).toHaveLength(50);
  });

  // #245 PR1: a shadow must be fanned into LIVE events exactly like a joiner
  // (joinGroupByInviteCode's event fan-in) — the expense editor's split roster
  // reads event.participantIds, and no client path grows it, so a shadow left
  // out of an event can never be split against there.
  test('15a. FAN-IN: new shadow lands in a live event participantIds + participantNames', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedEvent('g', 'e1', [OWNER], { [OWNER]: 'Owner' });
    await seedEvent('g', 'e2', [OWNER], { [OWNER]: 'Owner' });

    const res = await wrapped({
      data: { groupId: 'g', displayName: 'Sara' },
      auth: { uid: OWNER },
    } as any);
    const sara = (res as { memberId: string }).memberId;

    for (const eventId of ['e1', 'e2']) {
      const event = await eventData('g', eventId);
      expect(event.participantIds).toEqual(expect.arrayContaining([OWNER, sara]));
      expect(event.participantIds).toHaveLength(2);
      expect(event.participantNames).toEqual({ [OWNER]: 'Owner', [sara]: 'Sara' });
      expect(event.updatedAt).toBeTruthy();
    }
  });

  test('15b. FAN-IN skips soft-deleted events', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedEvent('g', 'dead', [OWNER], { [OWNER]: 'Owner' }, {
      isDeleted: true,
      deletedAt: new Date('2026-01-05T00:00:00.000Z'),
    });

    const res = await wrapped({
      data: { groupId: 'g', displayName: 'Sara' },
      auth: { uid: OWNER },
    } as any);
    const sara = (res as { memberId: string }).memberId;

    const event = await eventData('g', 'dead');
    expect(event.participantIds).toEqual([OWNER]);
    expect(event.participantNames).toEqual({ [OWNER]: 'Owner' });
    expect(event.participantIds).not.toContain(sara);
    expect(event.updatedAt).toBeUndefined();
  });

  test('15c. FAN-IN includes CLOSED events (mirrors join — closed rejects new expenses anyway)', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedEvent('g', 'closed', [OWNER], { [OWNER]: 'Owner' }, {
      isClosed: true,
      closedAt: new Date('2026-01-05T00:00:00.000Z'),
      closedBy: OWNER,
    });

    const res = await wrapped({
      data: { groupId: 'g', displayName: 'Sara' },
      auth: { uid: OWNER },
    } as any);
    const sara = (res as { memberId: string }).memberId;

    const event = await eventData('g', 'closed');
    expect(event.participantIds).toEqual(expect.arrayContaining([OWNER, sara]));
    expect(event.participantNames[sara]).toBe('Sara');
  });

  test('13a. PARITY shadow-as-DEBTOR: split-against → oracle nets the shadow negative', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    const res = await wrapped({ data: { groupId: 'g', displayName: 'Sara' }, auth: { uid: OWNER } } as any);
    const sara = (res as { memberId: string }).memberId;
    await seedEvent('g', 'e1', [OWNER, sara], { [OWNER]: 'Owner', [sara]: 'Sara' });
    await seedExpense('groups/g/events/e1/expenses/x1'); // OWNER pays 12.000 equally

    expect(await omrNet('g', sara)).toBe('-6.000');
    expect(await omrNet('g', OWNER)).toBe('6.000');
  });

  test('13b. PARITY shadow-as-PAYER: shadow paid → oracle nets the shadow positive', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    const res = await wrapped({ data: { groupId: 'g', displayName: 'Sara' }, auth: { uid: OWNER } } as any);
    const sara = (res as { memberId: string }).memberId;
    await seedEvent('g', 'e1', [OWNER, sara], { [OWNER]: 'Owner', [sara]: 'Sara' });
    await seedExpense('groups/g/events/e1/expenses/x1', {
      payerParticipantId: sara,
      createdBy: OWNER,
    });

    expect(await omrNet('g', sara)).toBe('6.000');
    expect(await omrNet('g', OWNER)).toBe('-6.000');
  });

  test('13c. PARITY shadow CASH-SETTLED: settlement to shadow → oracle nets the shadow zero', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    const res = await wrapped({ data: { groupId: 'g', displayName: 'Sara' }, auth: { uid: OWNER } } as any);
    const sara = (res as { memberId: string }).memberId;
    await seedEvent('g', 'e1', [OWNER, sara], { [OWNER]: 'Owner', [sara]: 'Sara' });
    await seedExpense('groups/g/events/e1/expenses/x1'); // sara owes 6.000
    // sara pays 6.000 back to OWNER → sara nets 0.
    await seedEventSettlement('groups/g/events/e1/settlements/s1', {
      payerParticipantId: sara,
      recipientParticipantId: OWNER,
      payerName: 'Sara',
      recipientName: 'Owner',
      amountFils: 6000,
    });

    expect(await omrNet('g', sara)).toBe('0.000');
  });

  test('14. REMOVAL via existing removeMember: non-zero shadow refused, zero-balance shadow removed', async () => {
    await seedGroup('g');
    await seedMember('g', OWNER);
    // Zero-balance brand-new shadow → removable by creator.
    const fresh = await wrapped({ data: { groupId: 'g', displayName: 'Khalid' }, auth: { uid: OWNER } } as any);
    const khalid = (fresh as { memberId: string }).memberId;
    await wrappedRemove({ data: { groupId: 'g', targetUserId: khalid }, auth: { uid: OWNER } } as any);
    expect((await groupData('g')).memberIds).not.toContain(khalid);
    expect(await memberDoc('g', khalid)).toBeUndefined();

    // Non-zero shadow → refused (settle up first).
    const debt = await wrapped({ data: { groupId: 'g', displayName: 'Sara' }, auth: { uid: OWNER } } as any);
    const sara = (debt as { memberId: string }).memberId;
    await seedEvent('g', 'e1', [OWNER, sara], { [OWNER]: 'Owner', [sara]: 'Sara' });
    await seedExpense('groups/g/events/e1/expenses/x1'); // sara owes 6.000
    await expect(
      wrappedRemove({ data: { groupId: 'g', targetUserId: sara }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    expect((await groupData('g')).memberIds).toContain(sara);
  });
});
