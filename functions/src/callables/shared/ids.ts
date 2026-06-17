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
