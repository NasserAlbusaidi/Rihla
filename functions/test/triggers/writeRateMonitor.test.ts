import functionsTest from 'firebase-functions-test';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { clearFirestore } from '../fixtures';
import {
  eventWriteRateMonitor,
  groupSettlementWriteRateMonitor,
  groupActivityWriteRateMonitor,
} from '../../src/triggers/writeRateMonitor';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapEvent = testEnv.wrap(eventWriteRateMonitor);
const wrapGroupSettlement = testEnv.wrap(groupSettlementWriteRateMonitor);
const wrapGroupActivity = testEnv.wrap(groupActivityWriteRateMonitor);

function eventCreate(
  data: Record<string, unknown>,
  params: { gid: string; eid: string; module: string; docId: string },
): { data: unknown; params: typeof params } {
  const path = `groups/${params.gid}/events/${params.eid}/${params.module}/${params.docId}`;
  return { data: testEnv.firestore.makeDocumentSnapshot(data, path), params };
}

function groupSettlementCreate(
  data: Record<string, unknown>,
  params: { gid: string; settlementId: string },
): { data: unknown; params: typeof params } {
  const path = `groups/${params.gid}/settlements/${params.settlementId}`;
  return { data: testEnv.firestore.makeDocumentSnapshot(data, path), params };
}

function groupActivityCreate(
  data: Record<string, unknown>,
  params: { gid: string; activityId: string },
): { data: unknown; params: typeof params } {
  const path = `groups/${params.gid}/activity/${params.activityId}`;
  return { data: testEnv.firestore.makeDocumentSnapshot(data, path), params };
}

async function counter(gid: string, uid: string) {
  return (await getFirestore().doc(`groups/${gid}/_writeCounters/${uid}`).get()).data();
}

beforeEach(async () => {
  await clearFirestore();
  delete process.env.WRITE_RATE_LIMIT;
});

afterEach(() => {
  jest.restoreAllMocks();
  delete process.env.WRITE_RATE_LIMIT;
});

afterAll(async () => {
  await clearFirestore();
  testEnv.cleanup();
});

describe('writeRateMonitor', () => {
  test('event expense create increments the per-UID counter', async () => {
    await wrapEvent(eventCreate(
      { createdBy: 'eve', amountFils: 1000 },
      { gid: 'g1', eid: 'e1', module: 'expenses', docId: 'x1' },
    ));

    const c = await counter('g1', 'eve');
    expect(c?.count).toBe(1);
    expect(c?.windowStart).toBeInstanceOf(Timestamp);
    const start = (c?.windowStart as Timestamp).toMillis();
    expect((c?.expiresAt as Timestamp).toMillis()).toBe(start + 60_000 + 60_000);
  });

  test('event settlement (createdBy) and activity_log (actorId) both count to the right uid', async () => {
    await wrapEvent(eventCreate(
      { createdBy: 'payer', amountFils: 500 },
      { gid: 'g1', eid: 'e1', module: 'settlements', docId: 's1' },
    ));
    await wrapEvent(eventCreate(
      { actorId: 'logger-uid', logText: 'did a thing' },
      { gid: 'g1', eid: 'e1', module: 'activity_logs', docId: 'a1' },
    ));

    expect((await counter('g1', 'payer'))?.count).toBe(1);
    expect((await counter('g1', 'logger-uid'))?.count).toBe(1);
  });

  test('group-level settlement (T2) and activity (T3) are counted', async () => {
    await wrapGroupSettlement(groupSettlementCreate(
      { createdBy: 'gs-uid', amountFils: 700 },
      { gid: 'g1', settlementId: 'gs1' },
    ));
    await wrapGroupActivity(groupActivityCreate(
      { actorId: 'ga-uid', description: 'group event' },
      { gid: 'g1', activityId: 'ga1' },
    ));

    expect((await counter('g1', 'gs-uid'))?.count).toBe(1);
    expect((await counter('g1', 'ga-uid'))?.count).toBe(1);
  });

  test('crossing the limit logs warn exactly once and sets lastFlaggedAt', async () => {
    process.env.WRITE_RATE_LIMIT = '2';
    const warn = jest.spyOn(logger, 'warn').mockImplementation(() => undefined);

    const fire = (docId: string) => wrapEvent(eventCreate(
      { createdBy: 'spammer', amountFils: 1 },
      { gid: 'g1', eid: 'e1', module: 'expenses', docId },
    ));

    await fire('x1'); // count 1
    await fire('x2'); // count 2 (== limit, not exceeded)
    expect((await counter('g1', 'spammer'))?.lastFlaggedAt).toBeUndefined();
    expect(warn).not.toHaveBeenCalled();

    await fire('x3'); // count 3 (> limit) -> crossing
    await fire('x4'); // count 4 (still over, must NOT re-flag)

    const c = await counter('g1', 'spammer');
    expect(c?.count).toBe(4);
    expect(c?.lastFlaggedAt).toBeInstanceOf(Timestamp);
    const burstCalls = warn.mock.calls.filter((args) => args[0] === 'write-rate burst flagged');
    expect(burstCalls).toHaveLength(1);
    expect(burstCalls[0][1]).toMatchObject({ gid: 'g1', uid: 'spammer', count: 3, limit: 2 });
  });

  test('a create after the window elapses resets count to 1 and advances windowStart', async () => {
    const staleStart = Timestamp.fromMillis(Timestamp.now().toMillis() - 5 * 60_000);
    await getFirestore().doc('groups/g1/_writeCounters/eve').set({
      count: 999,
      windowStart: staleStart,
      expiresAt: Timestamp.fromMillis(staleStart.toMillis() + 120_000),
    });

    await wrapEvent(eventCreate(
      { createdBy: 'eve', amountFils: 1000 },
      { gid: 'g1', eid: 'e1', module: 'expenses', docId: 'x1' },
    ));

    const c = await counter('g1', 'eve');
    expect(c?.count).toBe(1);
    expect((c?.windowStart as Timestamp).toMillis()).toBeGreaterThan(staleStart.toMillis());
  });

  test('a doc with neither createdBy nor actorId is not counted and warns', async () => {
    const warn = jest.spyOn(logger, 'warn').mockImplementation(() => undefined);

    await wrapEvent(eventCreate(
      { amountFils: 1000 },
      { gid: 'g1', eid: 'e1', module: 'expenses', docId: 'x1' },
    ));

    expect(await counter('g1', 'eve')).toBeUndefined();
    const counters = await getFirestore().collection('groups/g1/_writeCounters').listDocuments();
    expect(counters).toHaveLength(0);
    expect(warn).toHaveBeenCalledWith(
      'write-rate monitor: create missing actor uid',
      expect.objectContaining({ path: expect.stringContaining('expenses/x1') }),
    );
  });

  test('an unmonitored event sub-collection (params.module) is ignored', async () => {
    await wrapEvent(eventCreate(
      { createdBy: 'eve', foo: 'bar' },
      { gid: 'g1', eid: 'e1', module: 'somethingElse', docId: 'z1' },
    ));

    const counters = await getFirestore().collection('groups/g1/_writeCounters').listDocuments();
    expect(counters).toHaveLength(0);
  });

  test('the same uid writing in two groups keeps separate per-group counters', async () => {
    await wrapEvent(eventCreate(
      { createdBy: 'eve', amountFils: 1 },
      { gid: 'g1', eid: 'e1', module: 'expenses', docId: 'x1' },
    ));
    await wrapEvent(eventCreate(
      { createdBy: 'eve', amountFils: 1 },
      { gid: 'g2', eid: 'e9', module: 'expenses', docId: 'x9' },
    ));

    expect((await counter('g1', 'eve'))?.count).toBe(1);
    expect((await counter('g2', 'eve'))?.count).toBe(1);
  });

  test('detection-only: the trigger never writes to the financial doc path', async () => {
    await wrapEvent(eventCreate(
      { createdBy: 'eve', amountFils: 1000 },
      { gid: 'g1', eid: 'e1', module: 'expenses', docId: 'x1' },
    ));

    // The monitor wrote ONLY the counter; the expense path it observed is untouched
    // (it never existed — makeDocumentSnapshot does not persist — proving the trigger
    // does not create/mutate money docs).
    const expense = await getFirestore().doc('groups/g1/events/e1/expenses/x1').get();
    expect(expense.exists).toBe(false);
    expect((await counter('g1', 'eve'))?.count).toBe(1);
  });
});
