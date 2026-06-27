import functionsTest from 'firebase-functions-test';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';
import { claimShadowLockReaper } from '../../src/scheduled/claimShadowLockReaper';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(claimShadowLockReaper as any);

const OWNER = 'owner';
const CLAIMER = 'claimer';
const SHADOW = 'shadow-7f3a9c';
const LOCKED_AT = Timestamp.fromDate(new Date('2026-02-01T00:00:00.000Z'));

const reqId = (requester: string, shadow: string) => `${requester}__${shadow}`;

async function seedGroup(data: Record<string, unknown> = {}): Promise<void> {
  await getFirestore().doc('groups/g').set({
    id: 'g',
    name: 'g',
    inviteCode: 'ABC123',
    createdBy: OWNER,
    memberIds: [OWNER, SHADOW],
    currency: 'OMR',
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    updatedAt: new Date('2026-01-02T00:00:00.000Z'),
    isDeleted: false,
    deletedAt: null,
    claimingInProgress: true,
    claimLockedAt: LOCKED_AT,
    ...data,
  });
}

async function seedMember(uid: string, data: Record<string, unknown> = {}): Promise<void> {
  await getFirestore().doc(`groups/g/members/${uid}`).set({
    id: uid,
    userId: uid,
    displayName: uid === SHADOW ? 'Ali' : uid,
    role: uid === OWNER ? 'CREATOR' : 'MEMBER',
    joinedAt: new Date('2026-01-01T00:00:00.000Z'),
    isShadow: uid === SHADOW,
    ...data,
  });
}

async function seedEvent(): Promise<void> {
  await getFirestore().doc('groups/g/events/e1').set({
    id: 'e1',
    groupId: 'g',
    name: 'e1',
    type: 'trip',
    createdBy: OWNER,
    participantIds: [OWNER, SHADOW],
    participantNames: { [OWNER]: 'Owner', [SHADOW]: 'Ali' },
    modules: { ledger: true },
    isDeleted: false,
    deletedAt: null,
    createdAt: new Date('2026-01-04T00:00:00.000Z'),
  });
  await getFirestore().doc('groups/g/events/e1/expenses/x1').set({
    id: 'x1',
    eventId: 'e1',
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
  });
}

async function seedClaimReservation(mutationStartedAt?: Timestamp): Promise<string> {
  const rid = reqId(CLAIMER, SHADOW);
  await getFirestore().doc(`groups/g/claimRequests/${rid}`).set({
    requesterUid: CLAIMER,
    requesterDisplayName: 'Khalid',
    shadowMemberId: SHADOW,
    shadowDisplayName: 'Ali',
    status: 'claiming',
    createdAt: FieldValue.serverTimestamp(),
    decidedBy: null,
    decidedAt: null,
    claimingBy: OWNER,
    claimingAt: LOCKED_AT,
    ...(mutationStartedAt ? { claimMutationStartedAt: mutationStartedAt } : {}),
  });
  await getFirestore().doc(`groups/g/claimShadowLocks/${SHADOW}`).set({
    groupId: 'g',
    shadowMemberId: SHADOW,
    claimerUid: CLAIMER,
    requestId: rid,
    lockedBy: OWNER,
    lockedAt: LOCKED_AT,
    updatedAt: LOCKED_AT,
    ...(mutationStartedAt ? { mutationStartedAt } : {}),
  });
  if (mutationStartedAt) {
    await getFirestore().doc('groups/g').update({ claimMutationStartedAt: mutationStartedAt });
  }
  return rid;
}

const groupDoc = async () => (await getFirestore().doc('groups/g').get()).data() ?? {};
const requestDoc = async (rid: string) =>
  (await getFirestore().doc(`groups/g/claimRequests/${rid}`).get()).data() ?? {};
const lockExists = async () =>
  (await getFirestore().doc(`groups/g/claimShadowLocks/${SHADOW}`).get()).exists;

beforeEach(async () => {
  process.env.CLAIM_SHADOW_LOCK_REAPER_GRACE_MS = '0';
  await clearFirestore();
  jest.restoreAllMocks();
  jest.spyOn(logger, 'info').mockImplementation(() => undefined);
  jest.spyOn(logger, 'warn').mockImplementation(() => undefined);
  jest.spyOn(logger, 'error').mockImplementation(() => undefined);
});

afterAll(async () => {
  delete process.env.CLAIM_SHADOW_LOCK_REAPER_GRACE_MS;
  await clearFirestore();
  testEnv.cleanup();
});

describe('claimShadowLockReaper (#710)', () => {
  test('stale pre-mutation reservation resets the request and clears the freeze', async () => {
    await seedGroup();
    await seedMember(OWNER);
    await seedMember(SHADOW);
    await seedEvent();
    const rid = await seedClaimReservation();

    await wrapped({});

    expect((await requestDoc(rid)).status).toBe('pending');
    expect(await lockExists()).toBe(false);
    const group = await groupDoc();
    expect(group.claimingInProgress).toBeUndefined();
    expect(group.claimLockedAt).toBeUndefined();
    expect((await getFirestore().doc('groups/g/members/claimer').get()).exists).toBe(false);
  });

  test('stale mutation-marked reservation resumes the locked claim and releases the freeze', async () => {
    const mutationStartedAt = Timestamp.fromDate(new Date('2026-02-01T00:01:00.000Z'));
    await seedGroup();
    await seedMember(OWNER);
    await seedMember(SHADOW);
    await seedEvent();
    const rid = await seedClaimReservation(mutationStartedAt);

    await wrapped({});

    expect((await requestDoc(rid)).status).toBe('claimed');
    expect(await lockExists()).toBe(false);
    const group = await groupDoc();
    expect(group.memberIds).toEqual([OWNER, CLAIMER]);
    expect(group.claimingInProgress).toBeUndefined();
    expect(group.claimLockedAt).toBeUndefined();
    expect((await getFirestore().doc(`groups/g/members/${SHADOW}`).get()).exists).toBe(false);
    expect((await getFirestore().doc(`groups/g/members/${CLAIMER}`).get()).data()).toMatchObject({
      userId: CLAIMER,
      displayName: 'Ali',
      isShadow: false,
    });
  });

  // #714 P1 #2/#3: the claim COMMITTED (Phase C retired the shadow, balance correct)
  // but the instance died before decideClaimRequest's finalize ran — so the lock +
  // claimingInProgress freeze persist while the shadow is already gone. The reaper's
  // engine resume hits the idempotent already-gone path; it must recognize THIS lock
  // completed the claim (completedByThisLock) and finalize+release, NOT log "ambiguous"
  // and leave the whole group frozen forever.
  test('mutation-marked reservation whose claim already committed (shadow gone) finalizes and clears the freeze', async () => {
    const mutationStartedAt = Timestamp.fromDate(new Date('2026-02-01T00:01:00.000Z'));
    // Post-Phase-C state: memberIds already swapped, shadow member doc deleted,
    // CLAIMER live, event re-keyed — i.e. no shadow reference survives anywhere.
    await seedGroup({ memberIds: [OWNER, CLAIMER] });
    await seedMember(OWNER);
    await seedMember(CLAIMER, { displayName: 'Ali', isShadow: false });
    await getFirestore().doc('groups/g/events/e1').set({
      id: 'e1', groupId: 'g', name: 'e1', type: 'trip', createdBy: OWNER,
      participantIds: [OWNER, CLAIMER],
      participantNames: { [OWNER]: 'Owner', [CLAIMER]: 'Ali' },
      modules: { ledger: true }, isDeleted: false, deletedAt: null,
      createdAt: new Date('2026-01-04T00:00:00.000Z'),
    });
    await getFirestore().doc('groups/g/events/e1/expenses/x1').set({
      id: 'x1', eventId: 'e1', createdBy: OWNER, payerParticipantId: OWNER,
      amountFils: 12000, currency: 'OMR', description: 'expense', scope: 'global',
      customSplitParticipants: [], splitMode: 'equally', splitDistribution: {},
      isDeleted: false, deletedAt: null, createdAt: '2026-01-06T00:00:00.000Z',
    });
    const rid = await seedClaimReservation(mutationStartedAt);

    await wrapped({});

    expect((await requestDoc(rid)).status).toBe('claimed');
    expect(await lockExists()).toBe(false);
    const group = await groupDoc();
    expect(group.claimingInProgress).toBeUndefined();
    expect(group.claimLockedAt).toBeUndefined();
    expect(group.claimMutationStartedAt).toBeUndefined();
    expect(group.memberIds).toEqual([OWNER, CLAIMER]);
    // The committed claim is untouched — no double re-key, claimer stays live.
    expect((await getFirestore().doc(`groups/g/members/${SHADOW}`).get()).exists).toBe(false);
    expect((await getFirestore().doc(`groups/g/members/${CLAIMER}`).get()).data()).toMatchObject({
      userId: CLAIMER,
      isShadow: false,
    });
  });
});
