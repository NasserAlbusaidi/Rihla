import functionsTest from 'firebase-functions-test';
import { getStorage } from 'firebase-admin/storage';
import { clearFirestore, seedGroupWithEvent } from '../fixtures';
import { listDocumentsWithUrls } from '../../src/callables/listDocumentsWithUrls';
import { listMemoriesWithUrls } from '../../src/callables/listMemoriesWithUrls';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrappedDocs = testEnv.wrap(listDocumentsWithUrls);
const wrappedMems = testEnv.wrap(listMemoriesWithUrls);

async function seedStorageObject(path: string): Promise<void> {
  await getStorage().bucket().file(path).save(Buffer.from('hello'), {
    contentType: 'text/plain',
  });
}

beforeEach(async () => {
  await clearFirestore();
  await seedGroupWithEvent({
    groupId: 'g1',
    eventId: 'e1',
    memberIds: ['alice'],
  });
});

afterAll(async () => {
  await clearFirestore();
  testEnv.cleanup();
});

describe('list storage with signed URLs', () => {
  test('documents list rejects unauthenticated request', async () => {
    await expect(wrappedDocs({
      data: { groupId: 'g1', eventId: 'e1' },
      auth: undefined,
    } as any)).rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('documents list rejects non-participant', async () => {
    await expect(wrappedDocs({
      data: { groupId: 'g1', eventId: 'e1' },
      auth: { uid: 'eve' },
    } as any)).rejects.toMatchObject({ code: 'permission-denied' });
  });

  test('documents list returns storage objects with signed URLs', async () => {
    await seedStorageObject('trip-documents/e1/123-report.pdf');
    await seedStorageObject('trip-documents/e-other/999-hidden.pdf');

    const res = await wrappedDocs({
      data: { groupId: 'g1', eventId: 'e1' },
      auth: { uid: 'alice' },
    } as any);

    expect(res.documents).toHaveLength(1);
    expect(res.documents[0]).toMatchObject({
      id: 'trip-documents/e1/123-report.pdf',
      fileName: '123-report.pdf',
      storagePath: 'trip-documents/e1/123-report.pdf',
    });
    expect(res.documents[0].signedUrl).toMatch(/^https?:\/\//);
    expect(new Date(res.documents[0].expiresAt).getTime()).toBeGreaterThan(Date.now());
  });

  test('memories list returns storage objects with signed URLs', async () => {
    await seedStorageObject('trip-memories/e1/456-photo.jpg');

    const res = await wrappedMems({
      data: { groupId: 'g1', eventId: 'e1' },
      auth: { uid: 'alice' },
    } as any);

    expect(res.memories).toHaveLength(1);
    expect(res.memories[0]).toMatchObject({
      id: 'trip-memories/e1/456-photo.jpg',
      fileName: '456-photo.jpg',
      storagePath: 'trip-memories/e1/456-photo.jpg',
    });
    expect(res.memories[0].signedUrl).toMatch(/^https?:\/\//);
  });
});
