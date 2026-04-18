import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import '../admin';
import { assertMemberOfEvent } from '../lib/membership';
import { issueUploadUrl } from '../lib/signing';
import { buildDocumentPath, buildMemoryPath, buildReceiptPath } from '../lib/paths';
import { validateUploadParams } from '../lib/validation';

export interface GetSignedUploadUrlInput {
  bucket: 'documents' | 'memories' | 'receipts';
  groupId: string;
  eventId: string;
  fileName: string;
  contentType: string;
  sizeBytes: number;
  expenseId?: string;
}

export interface GetSignedUploadUrlOutput {
  uploadUrl: string;
  storagePath: string;
  expiresAt: string;
}

export const getSignedUploadUrl = onCall<GetSignedUploadUrlInput, Promise<GetSignedUploadUrlOutput>>(
  async (request: CallableRequest<GetSignedUploadUrlInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }
    const uid = request.auth.uid;
    const { bucket, groupId, eventId, fileName, contentType, sizeBytes, expenseId } =
      request.data ?? ({} as GetSignedUploadUrlInput);

    if (!['documents', 'memories', 'receipts'].includes(bucket)) {
      throw new HttpsError(
        'invalid-argument',
        `bucket must be one of documents|memories|receipts, got: ${bucket}`,
      );
    }
    validateUploadParams({ fileName, contentType, sizeBytes });
    await assertMemberOfEvent(uid, groupId, eventId);

    let storagePath: string;
    if (bucket === 'documents') {
      storagePath = buildDocumentPath(eventId, fileName);
    } else if (bucket === 'memories') {
      storagePath = buildMemoryPath(eventId, fileName);
    } else {
      if (!expenseId) {
        throw new HttpsError('invalid-argument', 'expenseId required for receipts bucket');
      }
      storagePath = buildReceiptPath(eventId, expenseId, fileName);
    }

    const { uploadUrl, expiresAt } = await issueUploadUrl(storagePath, contentType);

    logger.info('signed-upload-url issued', { uid, groupId, eventId, bucket, storagePath });
    return { uploadUrl, storagePath, expiresAt };
  },
);
