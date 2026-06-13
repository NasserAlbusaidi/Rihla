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

// #483: empty-name fallback for an actor/joiner, localized PER LOCALE. Keeping
// it inside the body builder (like groupLabel) ensures an Arabic recipient
// never gets the English literal 'Someone' spliced into an RTL sentence.
function actorLabel(locale: Locale, name: string): string {
  const trimmed = name.trim();
  if (trimmed.length > 0) return trimmed;
  return locale === 'ar' ? 'شخص ما' : 'Someone';
}

export function settlementTitle(locale: Locale, groupName: string): string {
  return groupLabel(locale, groupName);
}

export function settlementBody(
  locale: Locale,
  actorName: string,
  amountText: string,
): string {
  const actor = actorLabel(locale, actorName);
  return locale === 'ar'
    ? `سجّل ${actor} تسوية بقيمة ${amountText}.`
    : `${actor} recorded a ${amountText} settlement.`;
}

export function memberJoinTitle(locale: Locale, groupName: string): string {
  return groupLabel(locale, groupName);
}

export function memberJoinBody(locale: Locale, joinerName: string): string {
  const joiner = actorLabel(locale, joinerName);
  return locale === 'ar'
    ? `انضم ${joiner} إلى المجموعة.`
    : `${joiner} joined the group.`;
}

export function expenseTitle(locale: Locale, groupName: string): string {
  return groupLabel(locale, groupName);
}

// #179 expense-created push. The empty-name fallback is localized internally via
// actorLabel (#483 pattern). `description` is user free-text in any language, so
// it is appended after a `·` separator (never grammatically embedded) to stay
// correct in both locales; an empty description is dropped.
export function expenseBody(
  locale: Locale,
  actorName: string,
  amountText: string,
  description: string,
): string {
  const actor = actorLabel(locale, actorName);
  const label = description.trim();
  const tail = label.length > 0 ? ` · ${label}` : '';
  return locale === 'ar'
    ? `أضاف ${actor} مصروفًا${tail} بقيمة ${amountText}.`
    : `${actor} added an expense${tail} (${amountText}).`;
}
