import { HttpsError } from 'firebase-functions/v2/https';

const DISPLAY_NAME_MAX_LENGTH = 32;
// Matches control characters AND the #1216 bidi-control / zero-width format
// reject-set K (U+00AD, U+200B, U+200E, U+200F, U+202A-202E, U+2060-2064,
// U+2066-2069, U+FEFF) to REJECT them — server counterpart to isValidDisplayName,
// kept aligned with firestore.rules. ZWNJ/ZWJ (U+200C/U+200D) are DELIBERATELY
// NOT rejected (Persian/Kurdish orthography + emoji ZWJ sequences). (Mirror of
// the joinGroupByInviteCode validator; de-dup of that copy is a tracked
// follow-up.)
// eslint-disable-next-line no-control-regex
const CONTROL_CHARACTER_PATTERN = /[\x00-\x1F\x7F\u00ad\u200b\u200e\u200f\u202a-\u202e\u2060-\u2064\u2066-\u2069\ufeff]/u;
// #1216 visible-char floor: a valid name has at least one char that is not
// whitespace and not a ZWNJ/ZWJ joiner (escapes, never raw joiners in source).
const VISIBLE_CHAR_PATTERN = /[^\s\u200c\u200d]/u;
// firestore.rules:50 isValidDisplayName ALSO rejects a name ending in
// " (former member)" — and the SAME suffix is rejected per-value in
// displayNameMapValuesAreValid (rules:65), which validEventBase enforces on
// participantNames (rules:369). A shadow's name is COPIED into an event's
// participantNames when the creator adds the shadow to an event, so a shadow
// named "Bob (former member)" would persist via the Admin SDK but then make the
// CLIENT event-create/update fail PERMISSION_DENIED. Reject it up front here.
const FORMER_MEMBER_SUFFIX_PATTERN = / \(former member\)$/u;

/**
 * Validate a REQUIRED display name, mirroring firestore.rules:44-51
 * isValidDisplayName (1–32 chars, no control chars, no "(former member)"
 * suffix). Unlike joinGroupByInviteCode's normalizeDisplayName, a missing name
 * is an ERROR (a nameless shadow is meaningless) — there is no 'Anonymous'
 * default. Returns the trimmed name.
 */
export function normalizeRequiredDisplayName(value: unknown): string {
  if (typeof value !== 'string') {
    throw new HttpsError('invalid-argument', 'displayName must be a string.');
  }
  const trimmed = value.trim();
  if (trimmed.length < 1 || trimmed.length > DISPLAY_NAME_MAX_LENGTH) {
    throw new HttpsError(
      'invalid-argument',
      `displayName must be between 1 and ${DISPLAY_NAME_MAX_LENGTH} characters.`,
    );
  }
  // #1216: reject control + bidi/zero-width format chars on the RAW value (JS
  // trim() strips U+FEFF, so a trailing-BOM name would slip a trimmed check).
  if (CONTROL_CHARACTER_PATTERN.test(value)) {
    throw new HttpsError('invalid-argument', 'displayName contains invalid characters.');
  }
  // #1216 visible-char floor: reject a name that is only whitespace + joiners.
  if (!VISIBLE_CHAR_PATTERN.test(trimmed)) {
    throw new HttpsError('invalid-argument', 'displayName contains invalid characters.');
  }
  if (FORMER_MEMBER_SUFFIX_PATTERN.test(trimmed)) {
    throw new HttpsError('invalid-argument', 'displayName is not allowed.');
  }
  return trimmed;
}
