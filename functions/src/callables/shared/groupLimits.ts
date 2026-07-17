// Generous cap: bounds roster spam + per-write recompute cost. The persona
// is small friend groups; 50 is far above any real Rihla group. Enforced on
// BOTH roster-growth paths (addShadowMember, joinGroupByInviteCode) against
// raw memberIds.length — which counts unclaimed shadows and deleteAccount
// tombstones; one basis, no drift (#1282).
export const MAX_GROUP_MEMBERS = 50;
