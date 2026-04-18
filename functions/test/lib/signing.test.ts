import {
  issueUploadUrl,
  issueDownloadUrl,
  buildUploadSignOptions,
  buildDownloadSignOptions,
} from '../../src/lib/signing';
import { MAX_FILE_BYTES } from '../../src/lib/validation';

// test/setup.ts sets FUNCTIONS_EMULATOR='true', so these integration tests run the emulator branch.

describe('signing helpers (emulator branch)', () => {
  test('issueUploadUrl returns publicUrl and ~15min expiry', async () => {
    const before = Date.now();
    const result = await issueUploadUrl('trip-documents/e1/x.pdf', 'application/pdf');
    const after = Date.now();
    expect(result.uploadUrl).toMatch(/^https?:\/\//);
    const expiresMs = new Date(result.expiresAt).getTime();
    expect(expiresMs).toBeGreaterThanOrEqual(before + 14 * 60 * 1000);
    expect(expiresMs).toBeLessThanOrEqual(after + 16 * 60 * 1000);
  });

  test('issueDownloadUrl returns publicUrl and ~60min expiry', async () => {
    const before = Date.now();
    const result = await issueDownloadUrl('trip-documents/e1/x.pdf');
    const after = Date.now();
    expect(result.signedUrl).toMatch(/^https?:\/\//);
    const expiresMs = new Date(result.expiresAt).getTime();
    expect(expiresMs).toBeGreaterThanOrEqual(before + 59 * 60 * 1000);
    expect(expiresMs).toBeLessThanOrEqual(after + 61 * 60 * 1000);
  });
});

// Pure-function unit tests for the sign-options builders (production path coverage).
// Deviation from plan: replaces the flaky jest.resetModules approach with a testable seam
// exported from signing.ts — the builders are the critical correctness surface.
describe('signing helpers (production sign-options builders)', () => {
  test('buildUploadSignOptions emits x-goog-content-length-range at 25 MB', () => {
    const opts = buildUploadSignOptions('application/pdf', 1_000_000);
    expect(opts.version).toBe('v4');
    expect(opts.action).toBe('write');
    expect(opts.expires).toBe(1_000_000);
    expect(opts.contentType).toBe('application/pdf');
    expect(opts.extensionHeaders).toEqual({ 'x-goog-content-length-range': '0,26214400' });
    expect(opts.extensionHeaders['x-goog-content-length-range']).toBe(`0,${MAX_FILE_BYTES}`);
  });

  test('buildDownloadSignOptions emits v4 read action', () => {
    const opts = buildDownloadSignOptions(2_000_000);
    expect(opts.version).toBe('v4');
    expect(opts.action).toBe('read');
    expect(opts.expires).toBe(2_000_000);
  });
});
