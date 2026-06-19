import {
  normalizeLocale,
  settlementTitle,
  settlementBody,
  memberJoinTitle,
  memberJoinBody,
  claimRequestTitle,
  claimRequestBody,
  claimDecideTitle,
  claimDecideBody,
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

  test('claim-request copy interpolates requester + shadow names in both locales', () => {
    expect(claimRequestTitle('en', 'Trip')).toBe('Trip');
    expect(claimRequestTitle('ar', 'رحلة')).toBe('رحلة');

    const en = claimRequestBody('en', 'Sam', 'Dad');
    expect(en).toContain('Sam');
    expect(en).toContain('Dad');

    const ar = claimRequestBody('ar', 'سام', 'بابا');
    expect(ar).toContain('سام');
    expect(ar).toContain('بابا');
    expect(ar).toContain('يريد'); // "wants" — proves Arabic, not English
  });

  test('claim-request empty requester name falls back to a localized default (#483)', () => {
    expect(claimRequestBody('en', '   ', 'Dad')).toContain('Someone');
    expect(claimRequestBody('ar', '', 'بابا')).toContain('شخص ما');
    expect(claimRequestBody('ar', '   ', 'بابا')).not.toContain('Someone');
  });

  test('claim-request empty shadow name avoids a dangling possessive', () => {
    // An empty owner must not splice into "claim 's spot"; a localized stand-in
    // noun ("a member") takes its place.
    const en = claimRequestBody('en', 'Sam', '   ');
    expect(en).toContain('Sam');
    expect(en).toContain('a member');
    expect(en).not.toContain("claim 's"); // no dangling possessive
    expect(en).not.toContain('  '); // no double space from an empty splice

    const ar = claimRequestBody('ar', 'سام', '');
    expect(ar).toContain('سام');
    expect(ar).not.toContain('a member'); // Arabic, not the English stand-in
  });

  test('claim-decide copy reflects the decision + shadow name in both locales (#565)', () => {
    expect(claimDecideTitle('en', 'Trip')).toBe('Trip');
    expect(claimDecideTitle('ar', 'رحلة')).toBe('رحلة');

    const approvedEn = claimDecideBody('en', 'claimed', 'Dad');
    expect(approvedEn).toContain('Dad');
    expect(approvedEn).toContain('approved');

    const declinedEn = claimDecideBody('en', 'declined', 'Dad');
    expect(declinedEn).toContain('Dad');
    expect(declinedEn).toContain('declined');

    const approvedAr = claimDecideBody('ar', 'claimed', 'بابا');
    expect(approvedAr).toContain('بابا');
    expect(approvedAr).toContain('الموافقة'); // "approval" — proves Arabic
    expect(approvedAr).not.toContain('approved');

    const declinedAr = claimDecideBody('ar', 'declined', 'بابا');
    expect(declinedAr).toContain('بابا');
    expect(declinedAr).toContain('رفض'); // "declined" — proves Arabic
  });

  test('claim-decide empty shadow name uses a localized stand-in, no dangling possessive (#565)', () => {
    const approvedEn = claimDecideBody('en', 'claimed', '   ');
    expect(approvedEn).toContain('approved');
    expect(approvedEn).not.toContain("'s spot"); // no dangling possessive
    expect(approvedEn).not.toContain('  '); // no double space from an empty splice

    const declinedAr = claimDecideBody('ar', 'declined', '');
    expect(declinedAr).toContain('رفض');
    expect(declinedAr).not.toContain('member'); // Arabic, not the English stand-in
  });

  test('empty groupName falls back to a localized default', () => {
    expect(settlementTitle('en', '   ')).toBe('your group');
    expect(settlementTitle('ar', '')).toBe('مجموعتك');
    expect(memberJoinTitle('en', '')).toBe('your group');
  });

  // #483: the empty-name fallback must be per-locale, INSIDE the body builder —
  // an Arabic recipient must never get the English literal 'Someone' spliced
  // into an RTL sentence (mirrors the groupLabel fallback).
  test('empty actor/joiner name falls back to a localized default', () => {
    expect(settlementBody('en', '   ', '10.500')).toContain('Someone');
    expect(settlementBody('ar', '', '10.500')).toContain('شخص ما');
    expect(settlementBody('ar', '   ', '10.500')).not.toContain('Someone');

    expect(memberJoinBody('en', '')).toContain('Someone');
    expect(memberJoinBody('ar', '   ')).toContain('شخص ما');
    expect(memberJoinBody('ar', '')).not.toContain('Someone');
  });
});
