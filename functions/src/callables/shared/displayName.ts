import { HttpsError } from 'firebase-functions/v2/https';

const DISPLAY_NAME_MAX_LENGTH = 32;
// Matches control characters to REJECT them — server counterpart to
// isValidDisplayName, kept aligned with firestore.rules. (Mirror of the
// joinGroupByInviteCode validator; de-dup of that copy is a tracked follow-up.)
// eslint-disable-next-line no-control-regex
const CONTROL_CHARACTER_PATTERN = /[\x00-\x1F\x7F]/u;
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
  if (CONTROL_CHARACTER_PATTERN.test(value)) {
    throw new HttpsError('invalid-argument', 'displayName contains invalid characters.');
  }
  if (FORMER_MEMBER_SUFFIX_PATTERN.test(trimmed)) {
    throw new HttpsError('invalid-argument', 'displayName is not allowed.');
  }
  return trimmed;
}
