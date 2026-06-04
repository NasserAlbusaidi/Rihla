// Server-side bilingual (en/ar) push-notification copy (#53). The recipient's
// locale is read from fcm_tokens/{uid}.locale (stored by the client). We
// localize SERVER-SIDE because a `notification` payload is rendered by the OS
// when the app is terminated/backgrounded — the client cannot build the text.

export type Locale = 'en' | 'ar';

/**
 * Coerces an arbitrary stored `locale` value to a supported [Locale]. Anything
 * starting with `ar` (case-insensitive) -> 'ar'; everything else (incl. null /
 * legacy docs with no locale field) -> 'en', matching AppSettings' 'en' default.
 */
export function normalizeLocale(raw: unknown): Locale {
  if (typeof raw === 'string' && raw.trim().toLowerCase().startsWith('ar')) {
    return 'ar';
  }
  return 'en';
}

function groupLabel(locale: Locale, groupName: string): string {
  const trimmed = groupName.trim();
  if (trimmed.length > 0) return trimmed;
  return locale === 'ar' ? 'مجموعتك' : 'your group';
}

export function settlementTitle(locale: Locale, groupName: string): string {
  return groupLabel(locale, groupName);
}

export function settlementBody(
  locale: Locale,
  actorName: string,
  amountText: string,
): string {
  return locale === 'ar'
    ? `سجّل ${actorName} تسوية بقيمة ${amountText}.`
    : `${actorName} recorded a ${amountText} settlement.`;
}

export function memberJoinTitle(locale: Locale, groupName: string): string {
  return groupLabel(locale, groupName);
}

export function memberJoinBody(locale: Locale, joinerName: string): string {
  return locale === 'ar'
    ? `انضم ${joinerName} إلى المجموعة.`
    : `${joinerName} joined the group.`;
}
