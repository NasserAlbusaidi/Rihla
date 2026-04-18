import functionsTest from 'firebase-functions-test';
import { getStorage } from 'firebase-admin/storage';
import { seedGroupWithEvent, clearFirestore } from '../fixtures';
import { deleteStorageObject } from '../../src/callables/deleteStorageObject';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(deleteStorageObject);

async function seedStorageObject(path: string): Promise<void> {
  const file = getStorage().bucket().file(path);
  await file.save(Buffer.from('hello world'), { contentType: 'text/plain' });
}

async function storageObjectExists(path: string): Promise<boolean> {
  const [exists] = await getStorage().bucket().file(path).exists();
  return exists;
}

beforeEach(async () => {
  await clearFirestore();
  await seedGroupWithEvent({ groupId: 'g1', eventId: 'e1', memberIds: ['alice'] });
});

afterAll(async () => {
  await clearFirestore();
  testEnv.cleanup();
});

describe('deleteStorageObject', () => {
  test('unauthenticated rejected', async () => {
    await expect(
      wrapped({
        data: { storagePath: 'trip-documents/e1/x.pdf', groupId: 'g1' },
        auth: undefined,
      } as any),
    ).rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('non-member rejected with permission-denied', async () => {
    await expect(
      wrapped({
        data: { storagePath: 'trip-documents/e1/x.pdf', groupId: 'g1' },
        auth: { uid: 'eve' },
      } as any),
    ).rejects.toMatchObject({ code: 'permission-denied' });
  });

  test('malformed storagePath rejected with invalid-argument', async () => {
    await expect(
      wrapped({
        data: { storagePath: 'garbage/x', groupId: 'g1' },
        auth: { uid: 'alice' },
      } as any),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('member deletes trip-documents object successfully', async () => {
    const path = 'trip-documents/e1/123-x.pdf';
    await seedStorageObject(path);
    expect(await storageObjectExists(path)).toBe(true);

    const res = await wrapped({
      data: { storagePath: path, groupId: 'g1' },
      auth: { uid: 'alice' },
    } as any);

    expect(res).toEqual({ deleted: true });
    expect(await storageObjectExists(path)).toBe(false);
  });

  test('member deletes trip-memories object successfully', async () => {
    const path = 'trip-memories/e1/456-y.jpg';
    await seedStorageObject(path);

    const res = await wrapped({
      data: { storagePath: path, groupId: 'g1' },
      auth: { uid: 'alice' },
    } as any);

    expect(res).toEqual({ deleted: true });
    expect(await storageObjectExists(path)).toBe(false);
  });

  test('member deletes receipts object successfully', async () => {
    const path = 'receipts/e1/exp1/789-r.png';
    await seedStorageObject(path);

    const res = await wrapped({
      data: { storagePath: path, groupId: 'g1' },
      auth: { uid: 'alice' },
    } as any);

    expect(res).toEqual({ deleted: true });
    expect(await storageObjectExists(path)).toBe(false);
  });

  test('eventId-mismatch rejected (T-38-06) — path references event not in claimed group', async () => {
    // path says event 'e-other' but 'g1' has only 'e1' — assertMemberOfEvent throws not-found
    await expect(
      wrapped({
        data: { storagePath: 'trip-documents/e-other/x.pdf', groupId: 'g1' },
        auth: { uid: 'alice' },
      } as any),
    ).rejects.toMatchObject({ code: 'not-found' });
  });
});
