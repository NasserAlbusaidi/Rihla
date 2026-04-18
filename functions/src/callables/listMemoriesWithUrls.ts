import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { getFirestore } from 'firebase-admin/firestore';
import '../admin';
import { assertMemberOfEvent } from '../lib/membership';
import { issueDownloadUrl } from '../lib/signing';

export interface ListMemoriesInput {
  groupId: string;
  eventId: string;
}

export interface MemoryWithUrl {
  id: string;
  storagePath: string;
  signedUrl: string;
  expiresAt: string;
  [key: string]: unknown;
}

export interface ListMemoriesOutput {
  memories: MemoryWithUrl[];
}

export const listMemoriesWithUrls = onCall<ListMemoriesInput, Promise<ListMemoriesOutput>>(
  async (request: CallableRequest<ListMemoriesInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }
    const uid = request.auth.uid;
    const { groupId, eventId } = request.data ?? ({} as ListMemoriesInput);

    if (!groupId || !eventId) {
      throw new HttpsError('invalid-argument', 'groupId and eventId required');
    }

    await assertMemberOfEvent(uid, groupId, eventId);

    const db = getFirestore();
    const snap = await db
      .collection(`groups/${groupId}/events/${eventId}/memories`)
      .get();

    // D-03: batch pre-issue — single round-trip, parallel signing.
    const memories = await Promise.all(
      snap.docs.map(async (d) => {
        const data = d.data();
        const { signedUrl, expiresAt } = await issueDownloadUrl(data.storagePath as string);
        return { ...data, id: d.id, signedUrl, expiresAt } as MemoryWithUrl;
      }),
    );

    logger.info('list-memories-with-urls issued', {
      uid,
      groupId,
      eventId,
      count: memories.length,
    });
    return { memories };
  },
);
