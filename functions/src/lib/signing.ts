import { getStorage } from 'firebase-admin/storage';
import '../admin';
import { MAX_FILE_BYTES } from './validation';

const UPLOAD_TTL_MS = 15 * 60 * 1000;   // D-02: 15 min
const DOWNLOAD_TTL_MS = 60 * 60 * 1000; // D-02: 60 min

function isEmulator(): boolean {
  return !!process.env.FUNCTIONS_EMULATOR;
}

function storageEmulatorBaseUrl(): string {
  const host =
    process.env.FIREBASE_STORAGE_EMULATOR_HOST
    ?? process.env.STORAGE_EMULATOR_HOST
    ?? '127.0.0.1:9199';
  return host.startsWith('http://') || host.startsWith('https://')
    ? host
    : `http://${host}`;
}

function emulatorUploadUrl(bucketName: string, storagePath: string): string {
  return `${storageEmulatorBaseUrl()}/upload/storage/v1/b/${encodeURIComponent(
    bucketName,
  )}/o?uploadType=media&name=${encodeURIComponent(storagePath)}`;
}

function emulatorDownloadUrl(bucketName: string, storagePath: string): string {
  return `${storageEmulatorBaseUrl()}/download/storage/v1/b/${encodeURIComponent(
    bucketName,
  )}/o/${encodeURIComponent(storagePath)}?alt=media`;
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
  const bucket = getStorage().bucket();
  const file = bucket.file(storagePath);
  const expiresMs = Date.now() + UPLOAD_TTL_MS;

  if (isEmulator()) {
    // firebase-tools#3400: Storage emulator does not support getSignedUrl.
    // Use the emulator's simple media upload endpoint so E2E tests can still
    // verify the membership gate plus actual object creation.
    return {
      uploadUrl: emulatorUploadUrl(bucket.name, storagePath),
      expiresAt: new Date(expiresMs).toISOString(),
    };
  }

  const [uploadUrl] = await file.getSignedUrl(buildUploadSignOptions(contentType, expiresMs));
  return { uploadUrl, expiresAt: new Date(expiresMs).toISOString() };
}

export async function issueDownloadUrl(storagePath: string): Promise<DownloadUrl> {
  const bucket = getStorage().bucket();
  const file = bucket.file(storagePath);
  const expiresMs = Date.now() + DOWNLOAD_TTL_MS;

  if (isEmulator()) {
    return {
      signedUrl: emulatorDownloadUrl(bucket.name, storagePath),
      expiresAt: new Date(expiresMs).toISOString(),
    };
  }

  const [signedUrl] = await file.getSignedUrl(buildDownloadSignOptions(expiresMs));
  return { signedUrl, expiresAt: new Date(expiresMs).toISOString() };
}
