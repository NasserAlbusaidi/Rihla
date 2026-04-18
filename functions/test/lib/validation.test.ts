import { validateUploadParams, MAX_FILE_BYTES } from '../../src/lib/validation';

describe('validateUploadParams', () => {
  const ok = { fileName: 'a.pdf', contentType: 'application/pdf', sizeBytes: 100 };
  test('valid input passes', () => { expect(() => validateUploadParams(ok)).not.toThrow(); });
  test('path traversal rejected', () => {
    expect(() => validateUploadParams({ ...ok, fileName: '../evil.pdf' })).toThrow(expect.objectContaining({ code: 'invalid-argument' }));
  });
  test('empty fileName rejected', () => {
    expect(() => validateUploadParams({ ...ok, fileName: '' })).toThrow(expect.objectContaining({ code: 'invalid-argument' }));
  });
  test('fileName longer than 128 chars rejected', () => {
    expect(() => validateUploadParams({ ...ok, fileName: 'a'.repeat(129) })).toThrow(expect.objectContaining({ code: 'invalid-argument' }));
  });
  test('oversized sizeBytes rejected', () => {
    expect(() => validateUploadParams({ ...ok, sizeBytes: MAX_FILE_BYTES + 1 })).toThrow(expect.objectContaining({ code: 'invalid-argument' }));
  });
  test('zero sizeBytes rejected', () => {
    expect(() => validateUploadParams({ ...ok, sizeBytes: 0 })).toThrow(expect.objectContaining({ code: 'invalid-argument' }));
  });
  test('empty contentType rejected', () => {
    expect(() => validateUploadParams({ ...ok, contentType: '' })).toThrow(expect.objectContaining({ code: 'invalid-argument' }));
  });
});
