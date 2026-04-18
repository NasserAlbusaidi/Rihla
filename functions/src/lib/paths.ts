import { HttpsError } from 'firebase-functions/v2/https';

export type BucketKind = 'documents' | 'memories' | 'receipts';

export interface ParsedPath {
  bucket: BucketKind;
  eventId: string;
  expenseId?: string;
}

export function buildDocumentPath(eventId: string, fileName: string): string {
  return `trip-documents/${eventId}/${Date.now()}-${fileName}`;
}

export function buildMemoryPath(eventId: string, fileName: string): string {
  return `trip-memories/${eventId}/${Date.now()}-${fileName}`;
}

export function buildReceiptPath(eventId: string, expenseId: string, fileName: string): string {
  return `receipts/${eventId}/${expenseId}/${Date.now()}-${fileName}`;
}

export function parseStoragePath(storagePath: string): ParsedPath {
  const docMatch = storagePath.match(/^trip-documents\/([^/]+)\/.+$/);
  if (docMatch) return { bucket: 'documents', eventId: docMatch[1] };
  const memMatch = storagePath.match(/^trip-memories\/([^/]+)\/.+$/);
  if (memMatch) return { bucket: 'memories', eventId: memMatch[1] };
  const rcpMatch = storagePath.match(/^receipts\/([^/]+)\/([^/]+)\/.+$/);
  if (rcpMatch) return { bucket: 'receipts', eventId: rcpMatch[1], expenseId: rcpMatch[2] };
  throw new HttpsError('invalid-argument', `Unrecognized storagePath: ${storagePath}`);
}
