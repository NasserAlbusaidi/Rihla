import { createHash } from 'crypto';
import { HttpsError } from 'firebase-functions/v2/https';

// A valid Firestore document id reference: a non-empty string with no path
// separator. Extracted from claimShadow.ts's de-exported onCall wrapper so the
// #278 claim/merge callables (requestClaimShadow / decideClaimRequest /
// listGroupClaimRequests) share one id guard.
export function validId(value: unknown, label: string): string {
  if (typeof value !== 'string' || value.length === 0 || value.includes('/')) {
    throw new HttpsError('invalid-argument', `${label} must be a valid id.`);
  }
  return value;
}

// #889: a deterministic, path-safe, bounded doc-id fragment derived from an
// arbitrary string (a settlement doc path, or a groupSettleUpId). 16 hex chars
// (64 bits) keeps intra-group collisions negligible, and a collision is
// fail-closed anyway — the correction callables treat a non-validating
// existing doc at the deterministic id as a hard failure, never silent
// overwrite. Never feed a raw id/path directly into a document id; always
// route it through this hash first.
export function shortHash(input: string): string {
  return createHash('sha256').update(input).digest('hex').slice(0, 16);
}
