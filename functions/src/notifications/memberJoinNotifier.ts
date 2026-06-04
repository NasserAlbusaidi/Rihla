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
  const name = joinerName.trim().length > 0 ? joinerName : 'Someone';
  await sendToUids(
    targets,
    (locale) => ({
      title: memberJoinTitle(locale, groupName),
      body: memberJoinBody(locale, name),
    }),
    { type: 'member_join', groupId: gid },
  );
}
