import functionsTest from 'firebase-functions-test';
import { seedGroupWithEvent, seedMemories, clearFirestore } from '../fixtures';
import { listMemoriesWithUrls } from '../../src/callables/listMemoriesWithUrls';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(listMemoriesWithUrls);

beforeEach(async () => {
  await clearFirestore();
  await seedGroupWithEvent({ groupId: 'g1', eventId: 'e1', memberIds: ['alice'] });
});

afterAll(async () => {
  await clearFirestore();
  testEnv.cleanup();
});

describe('listMemoriesWithUrls', () => {
  test('unauthenticated request rejected', async () => {
    await expect(
      wrapped({ data: { groupId: 'g1', eventId: 'e1' }, auth: undefined } as any),
    ).rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('non-member rejected with permission-denied', async () => {
    await expect(
      wrapped({ data: { groupId: 'g1', eventId: 'e1' }, auth: { uid: 'eve' } } as any),
    ).rejects.toMatchObject({ code: 'permission-denied' });
  });

  test('member with zero memories returns empty array', async () => {
    const res = await wrapped({
      data: { groupId: 'g1', eventId: 'e1' },
      auth: { uid: 'alice' },
    } as any);
    expect(res.memories).toEqual([]);
  });

  test('member with 2 memories returns array with signedUrls (batch pre-issue)', async () => {
    await seedMemories('g1', 'e1', [
      { id: 'm1', storagePath: 'trip-memories/e1/1-a.jpg' },
      { id: 'm2', storagePath: 'trip-memories/e1/2-b.jpg' },
    ]);
    const res = await wrapped({
      data: { groupId: 'g1', eventId: 'e1' },
      auth: { uid: 'alice' },
    } as any);
    expect(res.memories).toHaveLength(2);
    expect(res.memories[0].signedUrl).toMatch(/^https?:\/\//);
    expect(res.memories[1].signedUrl).toMatch(/^https?:\/\//);
    for (const m of res.memories) {
      expect(m.storagePath).toMatch(/^trip-memories\/e1\//);
      expect(new Date(m.expiresAt).getTime()).toBeGreaterThan(Date.now());
    }
  });
});
