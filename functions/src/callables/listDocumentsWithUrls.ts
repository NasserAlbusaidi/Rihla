import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { getFirestore } from 'firebase-admin/firestore';
import '../admin';
import { assertMemberOfEvent } from '../lib/membership';
import { issueDownloadUrl } from '../lib/signing';

export interface ListDocumentsInput {
  groupId: string;
  eventId: string;
}

export interface DocumentWithUrl {
  id: string;
  fileName: string;
  mimeType: string;
  storagePath: string;
  sizeBytes: number;
  uploadedBy: string;
  signedUrl: string;
  expiresAt: string;
  [key: string]: unknown;
}

export interface ListDocumentsOutput {
  documents: DocumentWithUrl[];
}

export const listDocumentsWithUrls = onCall<ListDocumentsInput, Promise<ListDocumentsOutput>>(
  async (request: CallableRequest<ListDocumentsInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }
    const uid = request.auth.uid;
    const { groupId, eventId } = request.data ?? ({} as ListDocumentsInput);

    if (!groupId || !eventId) {
      throw new HttpsError('invalid-argument', 'groupId and eventId required');
    }

    await assertMemberOfEvent(uid, groupId, eventId);

    const db = getFirestore();
    const snap = await db
      .collection(`groups/${groupId}/events/${eventId}/documents`)
      .where('isDeleted', '==', false)
      .get();

    // D-03: batch pre-issue — single round-trip, parallel signing.
    const documents = await Promise.all(
      snap.docs.map(async (d) => {
        const data = d.data();
        const { signedUrl, expiresAt } = await issueDownloadUrl(data.storagePath as string);
        return { ...data, id: d.id, signedUrl, expiresAt } as DocumentWithUrl;
      }),
    );

    logger.info('list-documents-with-urls issued', {
      uid,
      groupId,
      eventId,
      count: documents.length,
    });
    return { documents };
  },
);
