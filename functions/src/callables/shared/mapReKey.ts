// SUM-on-collision map re-keyer — restored for #278 claim/merge (PR6).
//
// This is the SUM sibling of deleteAccount.ts's `renameMapKey` (which
// OVERWRITES on collision). It existed inside cleanupAnonUidArtifacts.ts (the
// #216 anon-recovery migrator) and was deleted in #441 PR5 (c009b700) when the
// cross-UID merge engine was removed. PR7 (`claimShadow`) re-introduces it for
// `splitDistribution` ONLY — a participant-keyed money map where, when a claim
// re-keys a shadow uuid to the claimer's uid and BOTH already hold a slice for
// the same expense, the stored integers must SUM rather than clobber.
//
// Why summing the opaque stored integers is always valid: both keys live in ONE
// expense's `splitDistribution`, which carries that expense's single split mode,
// so the two values share an encoding (two `exact` subunit slices sum to a
// combined subunit slice; two `shares` weights sum to a combined weight; two
// `percent`×1000 values sum to combined percent). The helper is therefore mode-
// AND currency-agnostic by design — it must NOT try to interpret the integers.
//
// Arrays (`participantIds`, `customSplitParticipants`) use `replaceUid` (which
// already dedups) — never this helper. Display-string maps (`participantNames`)
// use `renameMapKey` (overwrite-safe) — never this helper.

/**
 * Coerces a value to a finite number, zeroing anything else (forged
 * non-numeric, NaN, Infinity) so a SUM never emits NaN. Legitimate split data
 * is always a finite number.
 */
export function toFiniteNumber(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

/**
 * Re-keys `oldUid` to `newUid` in a map, SUMMING the two values on collision.
 *
 * - Non-map input (null / array / non-object) → `null` (mirrors the
 *   `renameMapKey` null guard so callers can skip uniformly).
 * - `oldUid === newUid` → defensive no-op (`changed:false`). A claim never
 *   re-keys an id onto itself, but if it did, the SUM-on-collision branch below
 *   would compute `source[uid] + oldValue` = 2× the value. Early-return guards
 *   that doubling. (This guard is new in the #278 restore; the #441-era original
 *   lacked it.)
 * - `oldUid` absent → unchanged copy (`changed:false`).
 * - `oldUid` present, `newUid` absent → plain rename (`changed:true`).
 * - both present → `newUid` value becomes the SUM (`changed:true`), money kept.
 *
 * Always returns a NEW object — the input map is never mutated.
 */
export function mergeUidMapKey(
  value: unknown,
  oldUid: string,
  newUid: string,
): { value: Record<string, unknown>; changed: boolean } | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  const source = value as Record<string, unknown>;
  if (oldUid === newUid) {
    return { value: { ...source }, changed: false };
  }
  if (!Object.prototype.hasOwnProperty.call(source, oldUid)) {
    return { value: { ...source }, changed: false };
  }
  const next: Record<string, unknown> = { ...source };
  const oldValue = next[oldUid];
  delete next[oldUid];
  if (Object.prototype.hasOwnProperty.call(source, newUid)) {
    // Collision: SUM. toFiniteNumber zeroes a forged non-numeric value rather
    // than emit NaN — legitimate data is always a number.
    next[newUid] = toFiniteNumber(source[newUid]) + toFiniteNumber(oldValue);
  } else {
    next[newUid] = oldValue;
  }
  return { value: next, changed: true };
}
