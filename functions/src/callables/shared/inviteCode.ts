import { Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

// Shared invite-code resolution. `normalizeInviteCode` is moved verbatim from
// joinGroupByInviteCode.ts (which now imports it here — behavior-preserving, the
// join test suite is the proof). `resolveGroupIdByInviteCode` is the NON-tx
// sibling used by the #278 pre-join claim callables (requestClaimShadow /
// listMyClaimRequests / listUnclaimedShadows): the requester is not yet a member
// and may not hold the group id, so the group is resolved server-side from the
// code. join's own resolution stays INSIDE its transaction (it reads inviteRef in
// the tx for join-consistency) — this helper is the standalone read; the partial
// duplication is intentional.

export function normalizeInviteCode(inviteCode: unknown): string {
  if (typeof inviteCode !== 'string') {
    throw new HttpsError('invalid-argument', 'inviteCode must be a string.');
  }
  const normalized = inviteCode.trim().toUpperCase();
  if (!/^[A-Z0-9]{6}$/.test(normalized)) {
    throw new HttpsError('invalid-argument', 'Invalid invite code.');
  }
  return normalized;
}

// Resolve a NORMALIZED invite code to its group id via inviteCodes/{code}. Throws
// not-found for an unknown code and failed-precondition for a malformed mapping —
// the same codes joinGroupByInviteCode.ts:262-270 raises in its tx. So only a
// holder of a VALID invite code can resolve a group (a stranger can't fabricate a
// claim against an arbitrary group id).
export async function resolveGroupIdByInviteCode(
  db: Firestore,
  normalizedCode: string,
): Promise<string> {
  const inviteSnap = await db.doc(`inviteCodes/${normalizedCode}`).get();
  if (!inviteSnap.exists) {
    throw new HttpsError('not-found', 'Invalid invite code.');
  }
  const resolvedGroupId = inviteSnap.data()?.groupId;
  if (typeof resolvedGroupId !== 'string' || resolvedGroupId.length === 0) {
    throw new HttpsError('failed-precondition', 'Invite code is malformed.');
  }
  return resolvedGroupId;
}
