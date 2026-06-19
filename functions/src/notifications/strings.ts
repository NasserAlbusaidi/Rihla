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

export function eventTitle(locale: Locale, groupName: string): string {
  return groupLabel(locale, groupName);
}

// #179 event-created push. The empty-name fallback is localized internally via
// actorLabel (#483 pattern). `eventName` is user free-text in any language, so it
// is appended after a `·` separator (never grammatically embedded) to stay correct
// in both locales — the same convention as expenseBody's description; an empty
// name is dropped.
export function eventBody(
  locale: Locale,
  actorName: string,
  eventName: string,
): string {
  const actor = actorLabel(locale, actorName);
  const label = eventName.trim();
  const tail = label.length > 0 ? ` · ${label}` : '';
  return locale === 'ar'
    ? `أنشأ ${actor} حدثًا جديدًا${tail}.`
    : `${actor} created a new event${tail}.`;
}

export function claimRequestTitle(locale: Locale, groupName: string): string {
  return groupLabel(locale, groupName);
}

// #560 — push the group creator when someone REQUESTS to claim a placeholder
// ("shadow") member (requestClaimShadow). Both names are stored on the
// claimRequests doc with non-empty defaults ('Anonymous' / 'Member'), but we
// still localize the empty fallbacks (#483 pattern): an empty requester →
// actorLabel ('Someone' / 'شخص ما'); an empty shadow → a localized stand-in noun
// so we never splice a dangling possessive ("claim 's spot").
export function claimRequestBody(
  locale: Locale,
  requesterName: string,
  shadowName: string,
): string {
  const requester = actorLabel(locale, requesterName);
  const shadow = shadowName.trim();
  if (shadow.length === 0) {
    return locale === 'ar'
      ? `يريد ${requester} أخذ مكان أحد الأعضاء.`
      : `${requester} wants to claim a member's spot.`;
  }
  return locale === 'ar'
    ? `يريد ${requester} أخذ مكان ${shadow}.`
    : `${requester} wants to claim ${shadow}'s spot.`;
}

export type ClaimDecision = 'claimed' | 'declined';

export function claimDecideTitle(locale: Locale, groupName: string): string {
  return groupLabel(locale, groupName);
}

// #565 — notify the REQUESTER when the creator decides their claim
// (pending→claimed | pending→declined). Same empty-shadow fallback discipline as
// claimRequestBody (#483 pattern): when the shadow name is empty we localize a
// whole stand-in sentence rather than splicing a dangling possessive.
export function claimDecideBody(
  locale: Locale,
  decision: ClaimDecision,
  shadowName: string,
): string {
  const shadow = shadowName.trim();
  if (decision === 'claimed') {
    if (shadow.length === 0) {
      return locale === 'ar'
        ? 'تمت الموافقة على طلب العضوية الخاص بك.'
        : 'Your member claim was approved.';
    }
    return locale === 'ar'
      ? `تمت الموافقة على طلبك لأخذ مكان ${shadow}.`
      : `Your claim for ${shadow}'s spot was approved.`;
  }
  if (shadow.length === 0) {
    return locale === 'ar'
      ? 'تم رفض طلب العضوية الخاص بك.'
      : 'Your member claim was declined.';
  }
  return locale === 'ar'
    ? `تم رفض طلبك لأخذ مكان ${shadow}.`
    : `Your claim for ${shadow}'s spot was declined.`;
}
