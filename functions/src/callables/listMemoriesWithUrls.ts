import { getStorage } from 'firebase-admin/storage';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { posix as path } from 'node:path';
import '../admin';
import { assertMemberOfEvent } from '../lib/membership';
import { issueDownloadUrl } from '../lib/signing';

export interface ListMemoriesWithUrlsInput {
  groupId: string;
  eventId: string;
}

export interface MemoryWithUrlOutput {
  id: string;
  fileName: string;
  storagePath: string;
  signedUrl: string;
  expiresAt: string;
}

export interface ListMemoriesWithUrlsOutput {
  memories: MemoryWithUrlOutput[];
}

function validateInput(data: Partial<ListMemoriesWithUrlsInput>): ListMemoriesWithUrlsInput {
  const { groupId, eventId } = data;
  if (typeof groupId !== 'string' || groupId.length === 0) {
    throw new HttpsError('invalid-argument', 'groupId required.');
  }
  if (typeof eventId !== 'string' || eventId.length === 0) {
    throw new HttpsError('invalid-argument', 'eventId required.');
  }
  return { groupId, eventId };
}

export const listMemoriesWithUrls = onCall<
  ListMemoriesWithUrlsInput,
  Promise<ListMemoriesWithUrlsOutput>
>(async (request: CallableRequest<ListMemoriesWithUrlsInput>) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign-in required.');
  }

  const { groupId, eventId } = validateInput(request.data ?? {});
  await assertMemberOfEvent(request.auth.uid, groupId, eventId);

  const prefix = `trip-memories/${eventId}/`;
  const [files] = await getStorage().bucket().getFiles({ prefix });
  const memories = await Promise.all(
    files
      .filter((file) => file.name !== prefix && !file.name.endsWith('/'))
      .map(async (file): Promise<MemoryWithUrlOutput> => {
        const { signedUrl, expiresAt } = await issueDownloadUrl(file.name);
        return {
          id: file.name,
          fileName: path.basename(file.name),
          storagePath: file.name,
          signedUrl,
          expiresAt,
        };
      }),
  );

  return { memories };
});
