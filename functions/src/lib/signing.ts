import { getStorage } from 'firebase-admin/storage';
import '../admin';
import { MAX_FILE_BYTES } from './validation';

const UPLOAD_TTL_MS = 15 * 60 * 1000;   // D-02: 15 min
const DOWNLOAD_TTL_MS = 60 * 60 * 1000; // D-02: 60 min

function isEmulator(): boolean {
  return !!process.env.FUNCTIONS_EMULATOR;
}

// Exported for unit-testable seam (plan fallback: avoid flaky jest.resetModules mocking).
export interface SignUploadOptions {
  version: 'v4';
  action: 'write';
  expires: number;
  contentType: string;
  extensionHeaders: { 'x-goog-content-length-range': string };
}

export interface SignDownloadOptions {
  version: 'v4';
  action: 'read';
  expires: number;
}

export function buildUploadSignOptions(
  contentType: string,
  expiresMs: number,
): SignUploadOptions {
  return {
    version: 'v4',
    action: 'write',
    expires: expiresMs,
    contentType,
    extensionHeaders: {
      'x-goog-content-length-range': `0,${MAX_FILE_BYTES}`,
    },
  };
}

export function buildDownloadSignOptions(expiresMs: number): SignDownloadOptions {
  return {
    version: 'v4',
    action: 'read',
    expires: expiresMs,
  };
}

export interface UploadUrl {
  uploadUrl: string;
  expiresAt: string;
}

export interface DownloadUrl {
  signedUrl: string;
  expiresAt: string;
}

export async function issueUploadUrl(
  storagePath: string,
  contentType: string,
): Promise<UploadUrl> {
  const file = getStorage().bucket().file(storagePath);
  const expiresMs = Date.now() + UPLOAD_TTL_MS;

  if (isEmulator()) {
    // firebase-tools#3400: Storage emulator does not support getSignedUrl.
    // Fall back to publicUrl() — tests validate the membership gate, not signature correctness.
    return { uploadUrl: file.publicUrl(), expiresAt: new Date(expiresMs).toISOString() };
  }

  const [uploadUrl] = await file.getSignedUrl(buildUploadSignOptions(contentType, expiresMs));
  return { uploadUrl, expiresAt: new Date(expiresMs).toISOString() };
}

export async function issueDownloadUrl(storagePath: string): Promise<DownloadUrl> {
  const file = getStorage().bucket().file(storagePath);
  const expiresMs = Date.now() + DOWNLOAD_TTL_MS;

  if (isEmulator()) {
    return { signedUrl: file.publicUrl(), expiresAt: new Date(expiresMs).toISOString() };
  }

  const [signedUrl] = await file.getSignedUrl(buildDownloadSignOptions(expiresMs));
  return { signedUrl, expiresAt: new Date(expiresMs).toISOString() };
}
