import { buildDocumentPath, buildMemoryPath, buildReceiptPath, parseStoragePath } from '../../src/lib/paths';

describe('path builders', () => {
  test('buildDocumentPath includes timestamp prefix', () => {
    expect(buildDocumentPath('e1', 'report.pdf')).toMatch(/^trip-documents\/e1\/\d+-report\.pdf$/);
  });
  test('buildMemoryPath includes timestamp prefix', () => {
    expect(buildMemoryPath('e1', 'photo.jpg')).toMatch(/^trip-memories\/e1\/\d+-photo\.jpg$/);
  });
  test('buildReceiptPath includes expenseId and timestamp', () => {
    expect(buildReceiptPath('e1', 'exp1', 'r.png')).toMatch(/^receipts\/e1\/exp1\/\d+-r\.png$/);
  });
});

describe('parseStoragePath', () => {
  test('parses trip-documents', () => {
    expect(parseStoragePath('trip-documents/e1/123-x.pdf')).toEqual({ bucket: 'documents', eventId: 'e1' });
  });
  test('parses trip-memories', () => {
    expect(parseStoragePath('trip-memories/e1/456-y.jpg')).toEqual({ bucket: 'memories', eventId: 'e1' });
  });
  test('parses receipts with expenseId', () => {
    expect(parseStoragePath('receipts/e1/exp1/789-r.png')).toEqual({ bucket: 'receipts', eventId: 'e1', expenseId: 'exp1' });
  });
  test('throws invalid-argument on garbage', () => {
    expect(() => parseStoragePath('garbage/x')).toThrow(expect.objectContaining({ code: 'invalid-argument' }));
  });
});
