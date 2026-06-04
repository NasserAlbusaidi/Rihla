import { formatAmount } from '../../src/notifications/formatAmount';

describe('formatAmount (money surface — mirrors MoneySerializer scale)', () => {
  // [amountFils, currency, expected]
  const cases: ReadonlyArray<[number, string, string]> = [
    // 3-dp currencies (scale 1000)
    [10500, 'OMR', '10.500'],
    [1000, 'KWD', '1.000'],
    [1, 'BHD', '0.001'],
    // 2-dp currencies (scale 100)
    [999, 'USD', '9.99'],
    [100, 'EUR', '1.00'],
    [12345, 'GBP', '123.45'],
    [50, 'SAR', '0.50'],
    [7, 'AED', '0.07'],
    [2500, 'QAR', '25.00'],
    // 0-dp currency (scale 1) — easy to forget
    [1000, 'JPY', '1000'],
    [0, 'JPY', '0'],
    // boundaries
    [0, 'OMR', '0.000'],
    [1, 'OMR', '0.001'],
    [999999999, 'USD', '9999999.99'],
  ];

  test.each(cases)('formatAmount(%i, %s) -> %s', (fils, currency, expected) => {
    expect(formatAmount(fils, currency)).toBe(expected);
  });

  test('lookup is case-insensitive (lowercase currency)', () => {
    expect(formatAmount(999, 'usd')).toBe('9.99'); // NOT the OMR-fallback 0.999
    expect(formatAmount(10500, 'omr')).toBe('10.500');
    expect(formatAmount(1000, 'jpy')).toBe('1000');
  });

  test('unknown currency falls back to OMR scale (3dp)', () => {
    expect(formatAmount(10500, 'XYZ')).toBe('10.500');
    expect(formatAmount(500, 'ZZZ')).toBe('0.500');
  });
});
