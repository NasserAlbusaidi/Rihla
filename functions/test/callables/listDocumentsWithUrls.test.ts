import functionsTest from 'firebase-functions-test';
import { seedGroupWithEvent, seedDocuments, clearFirestore } from '../fixtures';
import { listDocumentsWithUrls } from '../../src/callables/listDocumentsWithUrls';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(listDocumentsWithUrls);

beforeEach(async () => {
  await clearFirestore();
  await seedGroupWithEvent({ groupId: 'g1', eventId: 'e1', memberIds: ['alice'] });
});

afterAll(async () => {
  await clearFirestore();
  testEnv.cleanup();
});

describe('listDocumentsWithUrls', () => {
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

  test('member with zero documents returns empty array', async () => {
    const res = await wrapped({
      data: { groupId: 'g1', eventId: 'e1' },
      auth: { uid: 'alice' },
    } as any);
    expect(res.documents).toEqual([]);
  });

  test('member with 3 documents returns array with signedUrls', async () => {
    await seedDocuments('g1', 'e1', [
      {
        id: 'd1',
        fileName: 'a.pdf',
        mimeType: 'application/pdf',
        storagePath: 'trip-documents/e1/1-a.pdf',
        sizeBytes: 100,
      },
      {
        id: 'd2',
        fileName: 'b.pdf',
        mimeType: 'application/pdf',
        storagePath: 'trip-documents/e1/2-b.pdf',
        sizeBytes: 200,
      },
      {
        id: 'd3',
        fileName: 'c.pdf',
        mimeType: 'application/pdf',
        storagePath: 'trip-documents/e1/3-c.pdf',
        sizeBytes: 300,
      },
    ]);
    const res = await wrapped({
      data: { groupId: 'g1', eventId: 'e1' },
      auth: { uid: 'alice' },
    } as any);
    expect(res.documents).toHaveLength(3);
    for (const d of res.documents) {
      expect(d.signedUrl).toMatch(/^https?:\/\//);
      expect(d.fileName).toMatch(/\.pdf$/);
      expect(d.storagePath).toMatch(/^trip-documents\/e1\//);
      expect(new Date(d.expiresAt).getTime()).toBeGreaterThan(Date.now());
    }
  });

  test('isDeleted documents are filtered out', async () => {
    await seedDocuments('g1', 'e1', [
      {
        id: 'd1',
        fileName: 'live.pdf',
        mimeType: 'application/pdf',
        storagePath: 'trip-documents/e1/1-live.pdf',
        sizeBytes: 100,
      },
      {
        id: 'd2',
        fileName: 'gone.pdf',
        mimeType: 'application/pdf',
        storagePath: 'trip-documents/e1/2-gone.pdf',
        sizeBytes: 100,
        isDeleted: true,
      },
    ]);
    const res = await wrapped({
      data: { groupId: 'g1', eventId: 'e1' },
      auth: { uid: 'alice' },
    } as any);
    expect(res.documents).toHaveLength(1);
    expect(res.documents[0].fileName).toBe('live.pdf');
  });
});
