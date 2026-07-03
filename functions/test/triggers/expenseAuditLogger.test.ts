import functionsTest from 'firebase-functions-test';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { clearFirestore } from '../fixtures';
import { expenseAuditLogger, classify } from '../../src/triggers/expenseAuditLogger';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrap = testEnv.wrap(expenseAuditLogger);

const EXP_PATH = 'groups/g1/events/e1/expenses/exp1';
const ACTIVITY = 'groups/g1/events/e1/activity_logs';
const FIRE_TIME = '2026-06-07T00:00:00.000Z';
const params = { gid: 'g1', eid: 'e1', expenseId: 'exp1' };

// firebase-functions-test 3.4.1 v2 contract: testEnv.wrap(fn) returns a fn taking
// a SINGLE CloudEvent-partial { data, params, id, time }. The id field is `id`
// (CloudEvent.id), NOT `eventId`; `time` is an ISO string. The same `id` on two
// calls models an at-least-once retry of one delivery.
function fire(before: unknown, after: unknown, id: string) {
  return wrap({ data: testEnv.makeChange(before, after), params, id, time: FIRE_TIME });
}

function snap(data: Record<string, unknown>) {
  return testEnv.firestore.makeDocumentSnapshot(data, EXP_PATH);
}
function absent() {
  // empty data → makeDocumentSnapshot builds a resource-only proto → .exists === false
  return testEnv.firestore.makeDocumentSnapshot({}, EXP_PATH);
}

function expData(o: Record<string, unknown> = {}) {
  return {
    id: 'exp1',
    eventId: 'e1',
    payerParticipantId: 'owner',
    amountFils: 10500,
    currency: 'OMR',
    scope: 'global',
    customSplitParticipants: [],
    isDeleted: false,
    deletedAt: null,
    createdAt: '2026-06-07T00:00:00.000Z',
    createdBy: 'owner',
    lastEditedBy: 'owner',
    ...o,
  };
}

async function seedMember(userId: string, displayName: string, docId: string) {
  await getFirestore().doc(`groups/g1/members/${docId}`).set({ userId, displayName });
}
async function logs() {
  return getFirestore().collection(ACTIVITY).get();
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

describe('classify (pure)', () => {
  test('create / update / soft-delete / skips', () => {
    expect(classify(undefined, expData())).toBe('CREATE');
    expect(classify(expData(), expData({ amountFils: 9000 }))).toBe('UPDATE');
    expect(classify(expData(), expData({ isDeleted: true }))).toBe('DELETE');
    expect(classify(expData(), expData())).toBeNull(); // no content change
    expect(classify(expData(), expData({ lastEditedBy: 'x' }))).toBeNull(); // identity-only
    expect(classify(expData({ isDeleted: true }), expData({ isDeleted: true, description: 's' }))).toBeNull(); // already-deleted edit
    expect(classify(expData(), undefined)).toBeNull(); // hard delete (N/A on path)
  });
});

describe('expenseAuditLogger', () => {
  test('CREATE logs one MONEY/CREATE entry attributed to the creator', async () => {
    await seedMember('owner', 'Owner', 'member-uuid-not-owner'); // creator keyed by uuid (#294)
    await fire(absent(), snap(expData()), 'evt-create-1');
    const got = await logs();
    expect(got.size).toBe(1);
    const d = got.docs[0].data();
    expect(d.category).toBe('MONEY');
    expect(d.eventType).toBe('CREATE');
    expect(d.actorId).toBe('owner');
    expect(d.actorName).toBe('Owner'); // resolved by userId field, not doc id
    expect(d.metadata.expenseId).toBe('exp1');
    expect(d.metadata.before).toBeNull();
    expect(d.metadata.after.amountFils).toBe(10500);
    expect(d.id).toBe('evt-create-1');
    expect(d.createdAt).toBe(FIRE_TIME);
  });

  test('UPDATE (amount change) logs MONEY/UPDATE with before/after money', async () => {
    await seedMember('owner', 'Owner', 'member-uuid');
    await fire(snap(expData()), snap(expData({ amountFils: 12500 })), 'evt-update-1');
    const got = await logs();
    expect(got.size).toBe(1);
    expect(got.docs[0].data().eventType).toBe('UPDATE');
    expect(got.docs[0].data().metadata.before.amountFils).toBe(10500);
    expect(got.docs[0].data().metadata.after.amountFils).toBe(12500);
  });

  test('soft-DELETE (isDeleted false→true) logs MONEY/DELETE', async () => {
    await fire(
      snap(expData()),
      snap(expData({ isDeleted: true, deletedAt: '2026-06-07T01:00:00.000Z' })),
      'evt-del-1',
    );
    const got = await logs();
    expect(got.size).toBe(1);
    expect(got.docs[0].data().eventType).toBe('DELETE');
  });

  test('#278 [P2]: a claim re-key write (claimRekeyAt newly stamped) is SKIPPED — no phantom audit row', async () => {
    const rekeyAt = Timestamp.fromMillis(1_700_000_000_000);
    // The claimShadow engine stamps a fresh claimRekeyAt while it re-keys
    // CONTENT_KEYS (payerParticipantId/splitDistribution). Without the skip,
    // every re-keyed expense would log a phantom UPDATE misattributed to the
    // shadow's createdBy — spamming the feed for a multi-expense claim.
    await fire(
      snap(expData()),
      snap(expData({ payerParticipantId: 'claimer', claimRekeyAt: rekeyAt })),
      'evt-rekey-1',
    );
    expect((await logs()).size).toBe(0);
  });

  test('#278 [P2]: the skip is SCOPED to the marker — a later real edit (claimRekeyAt unchanged) still logs', async () => {
    const rekeyAt = Timestamp.fromMillis(1_700_000_000_000);
    await seedMember('claimer', 'Ali', 'claimer');
    // claimRekeyAt lingers on the doc after the claim; a subsequent genuine edit
    // does NOT change it, so the skip does NOT fire and the edit logs normally.
    await fire(
      snap(expData({ payerParticipantId: 'claimer', claimRekeyAt: rekeyAt, lastEditedBy: 'claimer' })),
      snap(expData({ payerParticipantId: 'claimer', amountFils: 9000, claimRekeyAt: rekeyAt, lastEditedBy: 'claimer' })),
      'evt-postrekey-edit-1',
    );
    const got = await logs();
    expect(got.size).toBe(1);
    expect(got.docs[0].data().eventType).toBe('UPDATE');
  });

  test('no content change writes nothing (D2 SKIP)', async () => {
    await fire(snap(expData()), snap(expData({ lastEditedBy: 'owner' })), 'evt-noop-1');
    expect((await logs()).size).toBe(0);
  });

  test('edit of an already-deleted expense writes nothing (admin scrub guard, D5)', async () => {
    await fire(
      snap(expData({ isDeleted: true })),
      snap(expData({ isDeleted: true, description: 'scrubbed' })),
      'evt-scrub-1',
    );
    expect((await logs()).size).toBe(0);
  });

  test('actor falls back to createdBy when lastEditedBy empty (legacy doc)', async () => {
    await seedMember('owner', 'Owner', 'm-uuid');
    await fire(
      snap(expData({ lastEditedBy: '' })),
      snap(expData({ lastEditedBy: '', amountFils: 9000 })),
      'evt-legacy-1',
    );
    expect((await logs()).docs[0].data().actorId).toBe('owner');
  });

  test('actorName is null (not "Someone") when no member matches', async () => {
    await fire(absent(), snap(expData()), 'evt-noname-1');
    expect((await logs()).docs[0].data().actorName).toBeNull();
  });

  test('idempotent on retry: same event.id → exactly one entry (D7)', async () => {
    await fire(absent(), snap(expData()), 'evt-dupe');
    await fire(absent(), snap(expData()), 'evt-dupe'); // retry of the same delivery
    expect((await logs()).size).toBe(1);
  });

  test('never mutates the expense doc (detection-only)', async () => {
    await fire(snap(expData()), snap(expData({ amountFils: 12500 })), 'evt-immut-1');
    // the trigger writes activity_logs only; the observed expense doc never existed
    // in the emulator (makeDocumentSnapshot does not persist) and stays absent.
    expect((await getFirestore().doc(EXP_PATH).get()).exists).toBe(false);
  });
});

// #808 PR1 — the same audit event also fans into the GROUP activity feed, in
// the exact GroupActivityLog client shape (group_activity_log_model.dart):
// {id == doc id, type, actorId, actorName, description non-null, metadata map,
// timestamp ISO string}. Description is a VERB PHRASE without the actor name
// (leaveGroup.ts parity — the activity row renders actorName separately).
describe('group activity fan-in (#808 PR1)', () => {
  const GROUP_ACTIVITY = 'groups/g1/activity';
  const groupLogs = () => getFirestore().collection(GROUP_ACTIVITY).get();

  test('CREATE also writes one expense_added group entry in GroupActivityLog shape', async () => {
    await seedMember('owner', 'Owner', 'member-uuid-not-owner');
    await getFirestore().doc('groups/g1/events/e1').set({ name: 'Muscat trip' });
    await fire(absent(), snap(expData({ description: 'Dinner' })), 'evt-fanin-1');
    const group = await groupLogs();
    expect(group.size).toBe(1);
    const d = group.docs[0].data();
    expect(group.docs[0].id).toBe('evt-fanin-1');
    expect(d).toMatchObject({
      id: 'evt-fanin-1',
      type: 'expense_added',
      actorId: 'owner',
      actorName: 'Owner',
      description: 'added Dinner (10.500 OMR)',
      timestamp: FIRE_TIME,
      metadata: {
        expenseId: 'exp1',
        eventId: 'e1',
        eventName: 'Muscat trip',
        amountFils: 10500,
        currency: 'OMR',
      },
    });
  });

  test('UPDATE → expense_edited; DELETE → expense_deleted (label-bearing verb phrases)', async () => {
    await getFirestore().doc('groups/g1/events/e1').set({ name: 'Muscat trip' });
    await fire(snap(expData()), snap(expData({ amountFils: 9000 })), 'evt-fanin-2');
    await fire(
      snap(expData({ description: 'Dinner' })),
      snap(expData({ isDeleted: true, description: 'Dinner' })),
      'evt-fanin-3',
    );
    const group = await groupLogs();
    const byId = Object.fromEntries(group.docs.map((x) => [x.id, x.data()]));
    expect(byId['evt-fanin-2'].type).toBe('expense_edited');
    expect(byId['evt-fanin-2'].description).toBe('edited an expense');
    expect(byId['evt-fanin-3'].type).toBe('expense_deleted');
    expect(byId['evt-fanin-3'].description).toBe('deleted Dinner');
  });

  test('no-op edit and claimRekeyAt re-key write NEITHER entry', async () => {
    const rekeyAt = Timestamp.fromMillis(1_700_000_000_000);
    await fire(snap(expData()), snap(expData({ lastEditedBy: 'owner' })), 'evt-fanin-4');
    await fire(
      snap(expData()),
      snap(expData({ payerParticipantId: 'claimer', claimRekeyAt: rekeyAt })),
      'evt-fanin-5',
    );
    expect((await groupLogs()).size).toBe(0);
    expect((await logs()).size).toBe(0);
  });

  test('at-least-once retry collapses to one group doc (same event.id)', async () => {
    await fire(absent(), snap(expData()), 'evt-fanin-6');
    await fire(absent(), snap(expData()), 'evt-fanin-6');
    expect((await groupLogs()).size).toBe(1);
  });

  test('missing event doc → eventName empty string; unresolved actor → actorName null', async () => {
    await fire(absent(), snap(expData()), 'evt-fanin-7');
    const d = (await groupLogs()).docs[0].data();
    expect(d.metadata.eventName).toBe('');
    expect(d.actorName).toBeNull();
  });
});
