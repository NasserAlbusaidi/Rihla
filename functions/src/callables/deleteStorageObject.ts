import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { getStorage } from 'firebase-admin/storage';
import '../admin';
import { assertMemberOfEvent } from '../lib/membership';
import { parseStoragePath } from '../lib/paths';

export interface DeleteStorageObjectInput {
  storagePath: string;
  groupId: string;
}

export interface DeleteStorageObjectOutput {
  deleted: true;
}

export const deleteStorageObject = onCall<DeleteStorageObjectInput, Promise<DeleteStorageObjectOutput>>(
  async (request: CallableRequest<DeleteStorageObjectInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }
    const uid = request.auth.uid;
    const { storagePath, groupId } = request.data ?? ({} as DeleteStorageObjectInput);

    if (!storagePath || !groupId) {
      throw new HttpsError('invalid-argument', 'storagePath and groupId required');
    }

    // T-38-06 mitigation: parse path to recover eventId; throws invalid-argument on garbage.
    const parsed = parseStoragePath(storagePath);

    // Re-check membership against claimed groupId + parsed eventId.
    // If eventId is not in the claimed group, assertMemberOfEvent throws not-found.
    await assertMemberOfEvent(uid, groupId, parsed.eventId);

    const file = getStorage().bucket().file(storagePath);
    try {
      await file.delete({ ignoreNotFound: true });
    } catch (err) {
      logger.error('delete-storage-object failed', {
        uid,
        groupId,
        storagePath,
        err: (err as Error).message,
      });
      throw new HttpsError('internal', 'Failed to delete object');
    }

    logger.info('delete-storage-object succeeded', {
      uid,
      groupId,
      storagePath,
      bucket: parsed.bucket,
    });
    return { deleted: true };
  },
);
