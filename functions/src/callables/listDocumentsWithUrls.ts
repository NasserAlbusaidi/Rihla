import { getStorage } from 'firebase-admin/storage';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { posix as path } from 'node:path';
import '../admin';
import { assertMemberOfEvent } from '../lib/membership';
import { issueDownloadUrl } from '../lib/signing';

export interface ListDocumentsWithUrlsInput {
  groupId: string;
  eventId: string;
}

export interface DocumentWithUrlOutput {
  id: string;
  fileName: string;
  storagePath: string;
  signedUrl: string;
  expiresAt: string;
}

export interface ListDocumentsWithUrlsOutput {
  documents: DocumentWithUrlOutput[];
}

function validateInput(data: Partial<ListDocumentsWithUrlsInput>): ListDocumentsWithUrlsInput {
  const { groupId, eventId } = data;
  if (typeof groupId !== 'string' || groupId.length === 0) {
    throw new HttpsError('invalid-argument', 'groupId required.');
  }
  if (typeof eventId !== 'string' || eventId.length === 0) {
    throw new HttpsError('invalid-argument', 'eventId required.');
  }
  return { groupId, eventId };
}

export const listDocumentsWithUrls = onCall<
  ListDocumentsWithUrlsInput,
  Promise<ListDocumentsWithUrlsOutput>
>(async (request: CallableRequest<ListDocumentsWithUrlsInput>) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign-in required.');
  }

  const { groupId, eventId } = validateInput(request.data ?? {});
  await assertMemberOfEvent(request.auth.uid, groupId, eventId);

  const prefix = `trip-documents/${eventId}/`;
  const [files] = await getStorage().bucket().getFiles({ prefix });
  const documents = await Promise.all(
    files
      .filter((file) => file.name !== prefix && !file.name.endsWith('/'))
      .map(async (file): Promise<DocumentWithUrlOutput> => {
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

  return { documents };
});
