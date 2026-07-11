import { Timestamp } from 'firebase-admin/firestore';
import type { DocumentData } from 'firebase-admin/firestore';

/** Sentinel createdBy for a group whose creator departed with no real survivor. */
export const deletedUserSentinel = 'deleted-user';

// Private on purpose: groupNetBalance.ts exports a timestampMillis with
// DIFFERENT garbage semantics (null vs MAX_SAFE_INTEGER); don't offer importers
// two same-named functions.
function timestampMillis(value: unknown): number {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'string') {
    const millis = Date.parse(value);
    return Number.isNaN(millis) ? Number.MAX_SAFE_INTEGER : millis;
  }
  return Number.MAX_SAFE_INTEGER;
}

/**
 * #1138 successor selection (shared by deleteAccount Phase C + leaveGroup):
 * the oldest-joined member doc that is (a) not the departing uid, (b) not a
 * tombstone, (c) not soft-deleted, (d) NOT an unclaimed shadow, and (e) a
 * CURRENT member (userId ∈ memberIds).
 *
 * (d) is the ONLY conjunct that excludes a production shadow — addShadowMember
 * arrayUnions the shadow uuid INTO memberIds, so (e) never catches it. A shadow
 * as createdBy is admin-less because it never AUTHENTICATES: no request.auth.uid
 * ever equals the uuid, so every createdBy-keyed gate is unsatisfiable.
 * (e) is defense-in-depth for torn/legacy docs whose userId fell out of
 * memberIds — equally admin-less as createdBy under the #1132 membership
 * conjunct, since createdBy ∈ memberIds is required by rules isCreator.
 */
export function oldestRealMemberUid(
  members: Array<{ id: string; data: DocumentData }>,
  departingUid: string,
  memberIds: string[],
): string | null {
  const candidates = members
    .filter(({ data }) =>
      data.userId !== departingUid
      && data.isTombstone !== true
      && data.isDeleted !== true
      && data.isShadow !== true
      && typeof data.userId === 'string'
      && memberIds.includes(data.userId))
    .sort((a, b) => timestampMillis(a.data.joinedAt) - timestampMillis(b.data.joinedAt));
  const first = candidates[0]?.data.userId;
  return typeof first === 'string' && first.length > 0 ? first : null;
}

/**
 * #1132: creator authority requires current membership. leaveGroup/removeMember
 * shrink memberIds but never reassign createdBy, so a `createdBy === uid` check
 * alone grants a DEPARTED creator destructive authority (delete group, remove
 * members, add shadows, decide claims) forever. Callers pair this with the
 * createdBy check — keep BOTH or the gate regresses.
 */
export function isCurrentMember(
  groupData: Record<string, unknown> | undefined,
  uid: string,
): boolean {
  const memberIds = Array.isArray(groupData?.memberIds) ? groupData.memberIds : [];
  return memberIds.includes(uid);
}
