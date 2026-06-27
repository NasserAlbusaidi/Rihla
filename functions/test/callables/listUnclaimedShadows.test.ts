import functionsTest from 'firebase-functions-test';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';

// RED → GREEN: #278 claim/merge PR9 — listUnclaimedShadows pre-join discovery.
// A real (durable) joiner, BEFORE joining, lists the group's claimable placeholder
// ("shadow") members so the join screen can offer "is one of these you?". The
// members subcollection is read-gated (firestore.rules), so this MUST be a
// callable (durable-gated, group resolved from the invite code, NO membership
// gate — the caller is pre-join, D8). Returns ONLY {shadowMemberId, displayName}
// for genuinely claimable shadows (matching requestClaimShadow's predicate); no
// real-member identity, no balances.
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/listUnclaimedShadows.test.ts" npm run test:emulator`

import { listUnclaimedShadows } from '../../src/callables/listUnclaimedShadows';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(listUnclaimedShadows);

const OWNER = 'owner';
const MEMBER2 = 'member2';
const OUTSIDER = 'outsider'; // a durable real uid, NOT yet a member (pre-join)
const SHADOW = 'shadow-7f3a9c';
const SHADOW2 = 'shadow-22bb01';
const SHADOW_TOMB = 'shadow-tomb01';
const SHADOW_ORPHAN = 'shadow-orph01';
const CODE = 'ABC123';

type Auth = { uid: string; token: { firebase: { sign_in_provider: string } } };
function authOf(uid: string, provider = 'password'): Auth {
  return { uid, token: { firebase: { sign_in_provider: provider } } };
}
const call = (data: Record<string, unknown>, auth: Auth | undefined = authOf(OUTSIDER)) =>
  wrapped({ data, auth } as never);

type Shadow = { shadowMemberId: string; displayName: string };
const namesOf = (out: { shadows: Shadow[] }) =>
  out.shadows.map((s) => s.displayName).sort();
const idsOf = (out: { shadows: Shadow[] }) =>
  out.shadows.map((s) => s.shadowMemberId).sort();

async function seedGroup(
  groupId: string,
  memberIds: string[],
  data: Record<string, unknown> = {},
): Promise<void> {
  await getFirestore().doc(`groups/${groupId}`).set({
    id: groupId,
    name: groupId,
    inviteCode: CODE,
    createdBy: OWNER,
    memberIds,
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
  await getFirestore().doc(`groups/${groupId}/members/${uid}`).set({
    id: uid,
    userId: uid,
    displayName: uid === OWNER ? 'Owner' : uid,
    role: uid === OWNER ? 'CREATOR' : 'MEMBER',
    joinedAt: new Date('2026-01-01T00:00:00.000Z'),
    isShadow: false,
    ...data,
  });
}

async function seedShadow(
  groupId: string,
  shadowId: string,
  displayName: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  await seedMember(groupId, shadowId, {
    displayName,
    role: 'MEMBER',
    isShadow: true,
    joinedAt: new Date('2026-01-03T00:00:00.000Z'),
    ...data,
  });
}

async function seedInviteCode(code: string, groupId: string): Promise<void> {
  await getFirestore().doc(`inviteCodes/${code}`).set({
    code,
    groupId,
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
  });
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

describe('listUnclaimedShadows (#278 PR9)', () => {
  test('U1. missing auth → unauthenticated; anonymous → permission-denied (D6); no leak', async () => {
    await seedGroup('g', [OWNER, SHADOW]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW, 'Ali');
    await seedInviteCode(CODE, 'g');
    await expect(
      wrapped({ data: { inviteCode: CODE }, auth: undefined } as never),
    ).rejects.toMatchObject({ code: 'unauthenticated' });
    await expect(
      call({ inviteCode: CODE }, authOf(OUTSIDER, 'anonymous')),
    ).rejects.toMatchObject({ code: 'permission-denied' });
  });

  test('U2. malformed invite code → invalid-argument; unknown code → not-found', async () => {
    await expect(call({ inviteCode: 'bad' })).rejects.toMatchObject({
      code: 'invalid-argument',
    });
    await expect(call({ inviteCode: 'ZZ9999' })).rejects.toMatchObject({
      code: 'not-found',
    });
  });

  test('U3. soft-deleted / deletingInProgress group → not-found', async () => {
    await seedGroup('gdel', [OWNER, SHADOW], { isDeleted: true });
    await seedInviteCode(CODE, 'gdel');
    await expect(call({ inviteCode: CODE })).rejects.toMatchObject({ code: 'not-found' });

    await clearFirestore();
    await seedGroup('gdip', [OWNER, SHADOW], { deletingInProgress: true });
    await seedInviteCode(CODE, 'gdip');
    await expect(call({ inviteCode: CODE })).rejects.toMatchObject({ code: 'not-found' });
  });

  test('#710 claim/account deletion freeze returns no claimable shadows', async () => {
    await seedGroup('gclaim', [OWNER, SHADOW], { claimingInProgress: true });
    await seedMember('gclaim', OWNER);
    await seedShadow('gclaim', SHADOW, 'Ali');
    await seedInviteCode(CODE, 'gclaim');
    expect((await call({ inviteCode: CODE })).shadows).toEqual([]);

    await clearFirestore();
    await seedGroup('gdelete', [OWNER, SHADOW], { accountDeletionInProgress: true });
    await seedMember('gdelete', OWNER);
    await seedShadow('gdelete', SHADOW, 'Ali');
    await seedInviteCode(CODE, 'gdelete');
    expect((await call({ inviteCode: CODE })).shadows).toEqual([]);
  });

  test('U4. non-member caller: returns EXACTLY the claimable shadows, real members ABSENT (P9-4)', async () => {
    await seedGroup('g', [OWNER, MEMBER2, SHADOW, SHADOW2]);
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER2);
    await seedShadow('g', SHADOW, 'Ali');
    await seedShadow('g', SHADOW2, 'Sara');
    await seedInviteCode(CODE, 'g');

    const out = await call({ inviteCode: CODE });
    expect(namesOf(out)).toEqual(['Ali', 'Sara']);
    expect(idsOf(out)).toEqual([SHADOW, SHADOW2].sort());
    // no real-member identity leaks
    expect(idsOf(out)).not.toContain(OWNER);
    expect(idsOf(out)).not.toContain(MEMBER2);
  });

  test('U5. tombstoned shadow AND shadow whose userId ∉ memberIds are BOTH excluded', async () => {
    await seedGroup('g', [OWNER, SHADOW, SHADOW_TOMB]); // SHADOW_ORPHAN intentionally NOT in memberIds
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW, 'Ali');
    await seedShadow('g', SHADOW_TOMB, 'Tomb', { isTombstone: true });
    await seedShadow('g', SHADOW_ORPHAN, 'Orphan'); // isShadow:true but ∉ memberIds
    await seedInviteCode(CODE, 'g');

    const out = await call({ inviteCode: CODE });
    expect(namesOf(out)).toEqual(['Ali']);
    expect(idsOf(out)).toEqual([SHADOW]);
  });

  test('U6. group with no shadows → { shadows: [] }', async () => {
    await seedGroup('g', [OWNER, MEMBER2]);
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER2);
    await seedInviteCode(CODE, 'g');

    const out = await call({ inviteCode: CODE });
    expect(out.shadows).toEqual([]);
  });

  test('U7. member caller (already joined) still gets the shadows — no membership gate (P9-4)', async () => {
    await seedGroup('g', [OWNER, SHADOW, SHADOW2]);
    await seedMember('g', OWNER);
    await seedShadow('g', SHADOW, 'Ali');
    await seedShadow('g', SHADOW2, 'Sara');
    await seedInviteCode(CODE, 'g');

    const out = await call({ inviteCode: CODE }, authOf(OWNER));
    expect(namesOf(out)).toEqual(['Ali', 'Sara']);
  });
});
