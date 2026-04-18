import functionsTest from 'firebase-functions-test';
import { seedGroupWithEvent, clearFirestore } from '../fixtures';
import { getSignedUploadUrl } from '../../src/callables/getSignedUploadUrl';

const testEnv = functionsTest({ projectId: 'rihla-safar-test' });
const wrapped = testEnv.wrap(getSignedUploadUrl);

beforeEach(async () => {
  await clearFirestore();
  await seedGroupWithEvent({ groupId: 'g1', eventId: 'e1', memberIds: ['alice'] });
});

afterAll(async () => {
  await clearFirestore();
  testEnv.cleanup();
});

const baseData = {
  bucket: 'documents' as const,
  groupId: 'g1',
  eventId: 'e1',
  fileName: 'report.pdf',
  contentType: 'application/pdf',
  sizeBytes: 1024,
};

describe('getSignedUploadUrl', () => {
  test('unauthenticated request rejected', async () => {
    await expect(wrapped({ data: baseData, auth: undefined } as any))
      .rejects.toMatchObject({ code: 'unauthenticated' });
  });

  test('non-member rejected with permission-denied', async () => {
    await expect(wrapped({ data: baseData, auth: { uid: 'eve' } } as any))
      .rejects.toMatchObject({ code: 'permission-denied' });
  });

  test('invalid bucket rejected', async () => {
    await expect(wrapped({ data: { ...baseData, bucket: 'bogus' as any }, auth: { uid: 'alice' } } as any))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('path-traversal fileName rejected', async () => {
    await expect(wrapped({ data: { ...baseData, fileName: '../../evil.pdf' }, auth: { uid: 'alice' } } as any))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('oversized sizeBytes rejected', async () => {
    await expect(wrapped({ data: { ...baseData, sizeBytes: 26 * 1024 * 1024 }, auth: { uid: 'alice' } } as any))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('member happy path — documents', async () => {
    const res = await wrapped({ data: baseData, auth: { uid: 'alice' } } as any);
    expect(res.uploadUrl).toMatch(/^https?:\/\//);
    expect(res.storagePath).toMatch(/^trip-documents\/e1\/\d+-report\.pdf$/);
    expect(new Date(res.expiresAt).getTime()).toBeGreaterThan(Date.now());
  });

  test('member happy path — memories', async () => {
    const res = await wrapped({
      data: { ...baseData, bucket: 'memories', fileName: 'photo.jpg', contentType: 'image/jpeg' },
      auth: { uid: 'alice' },
    } as any);
    expect(res.storagePath).toMatch(/^trip-memories\/e1\/\d+-photo\.jpg$/);
  });

  test('member happy path — receipts with expenseId', async () => {
    const res = await wrapped({
      data: { ...baseData, bucket: 'receipts', expenseId: 'exp1', fileName: 'r.png', contentType: 'image/png' },
      auth: { uid: 'alice' },
    } as any);
    expect(res.storagePath).toMatch(/^receipts\/e1\/exp1\/\d+-r\.png$/);
  });

  test('receipts without expenseId rejected', async () => {
    await expect(wrapped({
      data: { ...baseData, bucket: 'receipts' },
      auth: { uid: 'alice' },
    } as any)).rejects.toMatchObject({ code: 'invalid-argument' });
  });
});
