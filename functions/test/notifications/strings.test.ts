import {
  normalizeLocale,
  settlementTitle,
  settlementBody,
  memberJoinTitle,
  memberJoinBody,
} from '../../src/notifications/strings';

describe('normalizeLocale', () => {
  test.each([
    ['ar', 'ar'],
    ['AR', 'ar'],
    ['ar-OM', 'ar'],
    ['arabic', 'ar'],
    ['en', 'en'],
    ['en-US', 'en'],
    ['fr', 'en'],
    ['', 'en'],
  ])('normalizeLocale(%s) -> %s', (raw, expected) => {
    expect(normalizeLocale(raw)).toBe(expected);
  });

  test('non-string / null / legacy-missing -> en', () => {
    expect(normalizeLocale(undefined)).toBe('en');
    expect(normalizeLocale(null)).toBe('en');
    expect(normalizeLocale(42)).toBe('en');
  });
});

describe('notification copy', () => {
  test('settlement copy is non-empty in both locales and interpolates params', () => {
    expect(settlementTitle('en', 'Trip to Salalah')).toBe('Trip to Salalah');
    expect(settlementTitle('ar', 'رحلة')).toBe('رحلة');
    expect(settlementBody('en', 'Ahmed', '10.500')).toContain('Ahmed');
    expect(settlementBody('en', 'Ahmed', '10.500')).toContain('10.500');
    expect(settlementBody('ar', 'أحمد', '10.500')).toContain('أحمد');
    expect(settlementBody('ar', 'أحمد', '10.500')).toContain('10.500');
  });

  test('member-join copy is non-empty in both locales', () => {
    expect(memberJoinTitle('en', 'Trip')).toBe('Trip');
    expect(memberJoinBody('en', 'Sara')).toContain('Sara');
    expect(memberJoinBody('ar', 'سارة')).toContain('سارة');
  });

  test('empty groupName falls back to a localized default', () => {
    expect(settlementTitle('en', '   ')).toBe('your group');
    expect(settlementTitle('ar', '')).toBe('مجموعتك');
    expect(memberJoinTitle('en', '')).toBe('your group');
  });
});
