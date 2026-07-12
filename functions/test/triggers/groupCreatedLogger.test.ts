import functionsTest from 'firebase-functions-test';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { clearFirestore } from '../fixtures';
import { groupCreatedLogger } from '../../src/triggers/groupCreatedLogger';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrap = testEnv.wrap(groupCreatedLogger);

const FIRE_TIME = '2026-07-12T00:00:00.000Z';

function groupPath(gid: string): string {
  return `groups/${gid}`;
}

// onDocumentCreated v2 contract: testEnv.wrap(fn) takes a single CloudEvent-
// partial { data, params, id, time }. Same `id` on two calls models an
// at-least-once retry of one delivery (mirrors expenseAuditLogger.test.ts).
function groupCreated(
  data: Record<string, unknown>,
  gid: string,
  id = 'evt-group-1',
) {
  return {
    data: testEnv.firestore.makeDocumentSnapshot(data, groupPath(gid)),
    params: { gid },
    id,
    time: FIRE_TIME,
  };
}

function groupData(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: 'g1',
    name: 'Muscat Trip',
    createdBy: 'owner',
    memberIds: ['owner'],
    currency: 'OMR',
    isDeleted: false,
    ...overrides,
  };
}

async function seedMember(
  gid: string,
  userId: string,
  displayName: string,
  docId: string,
): Promise<void> {
  await getFirestore().doc(`groups/${gid}/members/${docId}`).set({ userId, displayName });
}

function activity(gid: string) {
  return getFirestore().collection(`groups/${gid}/activity`).get();
}

beforeEach(async () => {
  await clearFirestore();
});
afterEach(() => {
  jest.restoreAllMocks();
});
afterAll(async () => {
  await clearFirestore();
  testEnv.cleanup();
});

describe('groupCreatedLogger', () => {
  test('writes one group_created activity entry attributed to the creator', async () => {
    await seedMember('g1', 'owner', 'Owner', 'member-uuid-not-owner'); // #294 uuid-keyed doc, field-matched
    const createdAt = Timestamp.fromDate(new Date('2026-07-11T10:00:00.000Z'));
    await wrap(groupCreated(groupData({ createdAt }), 'g1', 'evt-create-1'));

    const got = await activity('g1');
    expect(got.size).toBe(1);
    expect(got.docs[0].id).toBe('evt-create-1');
    expect(got.docs[0].data()).toEqual({
      id: 'evt-create-1',
      type: 'group_created',
      actorId: 'owner',
      actorName: 'Owner',
      description: 'created the group',
      metadata: {},
      timestamp: '2026-07-11T10:00:00.000Z',
    });
  });

  test('createdAt Timestamp is converted to its exact ISO instant, not event.time', async () => {
    await seedMember('g1', 'owner', 'Owner', 'm1');
    const createdAt = Timestamp.fromDate(new Date('2026-01-05T08:30:00.000Z'));
    await wrap(groupCreated(groupData({ createdAt }), 'g1', 'evt-ts-1'));
    const d = (await activity('g1')).docs[0].data();
    expect(d.timestamp).toBe('2026-01-05T08:30:00.000Z');
    expect(d.timestamp).not.toBe(FIRE_TIME);
  });

  test('missing createdAt falls back to the CloudEvent time', async () => {
    await seedMember('g1', 'owner', 'Owner', 'm1');
    await wrap(groupCreated(groupData(), 'g1', 'evt-fallback-1')); // no createdAt key
    const d = (await activity('g1')).docs[0].data();
    expect(d.timestamp).toBe(FIRE_TIME);
  });

  test('non-Timestamp createdAt (mistyped) falls back to the CloudEvent time', async () => {
    await seedMember('g1', 'owner', 'Owner', 'm1');
    await wrap(
      groupCreated(groupData({ createdAt: '2026-01-01T00:00:00.000Z' }), 'g1', 'evt-fallback-2'),
    );
    const d = (await activity('g1')).docs[0].data();
    expect(d.timestamp).toBe(FIRE_TIME);
  });

  test('createdBy missing → no activity doc written', async () => {
    const data = groupData();
    delete data.createdBy;
    await wrap(groupCreated(data, 'g1', 'evt-nocreator-1'));
    expect((await activity('g1')).size).toBe(0);
  });

  test('createdBy non-string → no activity doc written', async () => {
    await wrap(groupCreated(groupData({ createdBy: 12345 }), 'g1', 'evt-badcreator-1'));
    expect((await activity('g1')).size).toBe(0);
  });

  test('metadata is the empty map, not omitted or populated', async () => {
    await seedMember('g1', 'owner', 'Owner', 'm1');
    await wrap(groupCreated(groupData(), 'g1', 'evt-meta-1'));
    const d = (await activity('g1')).docs[0].data();
    expect(d.metadata).toEqual({});
  });

  test('unresolved actor (no member doc) still writes; actorName is unresolved (null)', async () => {
    await wrap(groupCreated(groupData(), 'g1', 'evt-noname-1'));
    const d = (await activity('g1')).docs[0].data();
    expect(d.actorId).toBe('owner');
    expect(d.actorName).toBeNull();
  });

  test('actorName resolved by the userId FIELD, not the doc id (#294/#524 mixed keying)', async () => {
    await seedMember('g1', 'owner', 'Owner', 'totally-unrelated-uuid-doc-id');
    await wrap(groupCreated(groupData(), 'g1', 'evt-fieldmatch-1'));
    const d = (await activity('g1')).docs[0].data();
    expect(d.actorName).toBe('Owner');
  });

  test('idempotent on retry: same event.id → exactly one activity doc (D7)', async () => {
    await seedMember('g1', 'owner', 'Owner', 'm1');
    const event = groupCreated(groupData(), 'g1', 'evt-dupe-1');
    await wrap(event);
    await wrap(event);
    expect((await activity('g1')).size).toBe(1);
  });

  test('description is a verb phrase without the actor name (#808 lesson)', async () => {
    await seedMember('g1', 'owner', 'Owner', 'm1');
    await wrap(groupCreated(groupData(), 'g1', 'evt-desc-1'));
    const d = (await activity('g1')).docs[0].data();
    expect(d.description).toBe('created the group');
    expect(d.description).not.toContain('Owner');
  });

  test('does not seed an event_created row for the #245 auto-seeded event', async () => {
    await seedMember('g1', 'owner', 'Owner', 'm1');
    await wrap(groupCreated(groupData(), 'g1', 'evt-noeventrow-1'));
    const got = await activity('g1');
    expect(got.size).toBe(1);
    expect(got.docs[0].data().type).toBe('group_created');
  });
});
