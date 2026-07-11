import { sendToUids } from './fcmSender';
import { memberJoinTitle, memberJoinBody } from './strings';

// #53 — notify existing group members when a NEW member joins via invite code.
// Called from joinGroupByInviteCode AFTER a committed join and ONLY when the
// join actually added a member (G1 gate in the callable) — an idempotent
// re-join must not re-announce. `existingMemberIds` is the PRE-join member
// snapshot; the joiner is filtered out defensively.
export async function notifyMemberJoin(
  gid: string,
  joinerUid: string,
  joinerName: string,
  groupName: string,
  existingMemberIds: string[],
): Promise<void> {
  const targets = existingMemberIds.filter((id) => id !== joinerUid);
  // #483: pass the (possibly empty) joiner name straight through; memberJoinBody
  // localizes the empty-name fallback per recipient locale, so an Arabic
  // recipient never gets the English literal 'Someone'.
  await sendToUids(
    targets,
    (locale) => ({
      title: memberJoinTitle(locale, groupName),
      body: memberJoinBody(locale, joinerName),
    }),
    { type: 'member_join', groupId: gid },
    // #1141 fence: fresh memberIds intersect, fail-closed. This is the one
    // best-effort, lost-row-at-worst notification (no redelivery path — a
    // fire-and-forget call from joinGroupByInviteCode), so a transient lookup
    // failure permanently loses the "X joined" announcement. Accepted: the
    // pre-join snapshot's recipients are guarded by a sub-millisecond window,
    // and fail-closed keeps the fence single-semantics.
    { requireCurrentMembershipOf: gid },
  );
}
