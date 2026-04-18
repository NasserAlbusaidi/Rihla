import { HttpsError } from 'firebase-functions/v2/https';

export const MAX_FILE_BYTES = 25 * 1024 * 1024;  // 25 MB
const FILENAME_REGEX = /^[\w\-. ]{1,128}$/;  // no slashes, no dot-dot

export interface UploadParamsInput {
  fileName: string;
  contentType: string;
  sizeBytes: number;
}

export function validateUploadParams(input: UploadParamsInput): void {
  const { fileName, contentType, sizeBytes } = input;
  if (!fileName || !FILENAME_REGEX.test(fileName)) {
    throw new HttpsError('invalid-argument', `Invalid fileName: ${fileName}`);
  }
  if (!contentType || contentType.length < 3 || contentType.length > 127) {
    throw new HttpsError('invalid-argument', 'contentType required');
  }
  if (typeof sizeBytes !== 'number' || sizeBytes <= 0) {
    throw new HttpsError('invalid-argument', 'sizeBytes must be > 0');
  }
  if (sizeBytes > MAX_FILE_BYTES) {
    throw new HttpsError('invalid-argument', `sizeBytes exceeds 25 MB cap (${sizeBytes})`);
  }
}
