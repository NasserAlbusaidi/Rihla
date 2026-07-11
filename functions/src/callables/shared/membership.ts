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
