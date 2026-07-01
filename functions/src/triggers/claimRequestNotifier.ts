import { getFirestore } from 'firebase-admin/firestore';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import '../admin';
import { sendToUids } from '../notifications/fcmSender';
import {
  claimRequestTitle,
  claimRequestBody,
  claimDecideTitle,
  claimDecideBody,
} from '../notifications/strings';

// Claim-request notifier — fires in BOTH directions of the claim handshake:
//
// #560 — buzz the group CREATOR when a claim request ARRIVES at pending, so
// approval isn't gated on the creator manually polling Group Settings. A real
// person requests to claim a placeholder ("shadow") member via requestClaimShadow,
// which writes a groups/{gid}/claimRequests/{id} doc with status:'pending'.
//
// #565 — buzz the REQUESTER when the creator DECIDES (pending→claimed |
// pending→declined), so the joiner isn't left polling for an answer.
//
// onDocumentWritten (NOT ...Created): claimRequests is MUTABLE, unlike the
// append-only settlement/event docs the sibling notifiers watch. requestClaimShadow
// uses a deterministic id `${uid}__${shadowMemberId}` + `.set()`, so a
// creator-DECLINED request that is re-requested is an UPDATE (declined→pending),
// which onDocumentCreated would miss — defeating the discoverability goal.
//
// Two branches, mutually exclusive:
//   A (creator)   before.status ∉ {pending, claiming} && after.status === 'pending'
//                 → NOTIFY creator. Fires on create (∅→pending) and re-open
//                   (declined→pending).
//   B (requester) before.status ∈ {pending, claiming} && after ∈ {claimed, declined}
//                 → NOTIFY requester with the decision copy.
// Everything else — the no-op pending→pending re-write, any delete (after absent),
// and re-writes that touch neither edge — returns. A claimed doc can never reopen
// (requestClaimShadow throws before .set() if status==='claimed').
//
// Read-only: reads the request doc + the group doc (createdBy + name) and sends;
// it NEVER mutates a domain doc. createdBy / requesterUid are auth uids, so each
// maps directly to fcm_tokens/{uid}; a recipient with no token doc is silently
// skipped by sendToUids.

function asString(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

function asStringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === 'string')
    : [];
}

async function resolveGroup(
  gid: string,
): Promise<{ createdBy: string; name: string; inviteCode: string; memberIds: string[] }> {
  try {
    const snap = await getFirestore().doc(`groups/${gid}`).get();
    const data = snap.data() ?? {};
    return {
      createdBy: asString(data.createdBy),
      name: asString(data.name),
      inviteCode: asString(data.inviteCode),
      memberIds: asStringArray(data.memberIds),
    };
  } catch (error) {
    logger.warn('claim notify: group lookup failed', { gid, error: String(error) });
    return { createdBy: '', name: '', inviteCode: '', memberIds: [] };
  }
}

export const claimRequestNotifier = onDocumentWritten(
  'groups/{gid}/claimRequests/{requestId}',
  async (event) => {
    const change = event.data;
    const before = change?.before.exists ? change.before.data() : undefined;
    const after = change?.after.exists ? change.after.data() : undefined;

    const gid = event.params.gid;
    const dedupeKey = `claim:${gid}:${event.params.requestId}:${event.id}`;
    const afterStatus = asString(after?.status);
    const beforeStatus = asString(before?.status);
    const beforeWasPending = beforeStatus === 'pending';
    const beforeWasClaiming = beforeStatus === 'claiming';

    // Branch A (#560) — request ARRIVES at pending (create or declined→re-open):
    // notify the CREATOR.
    if (afterStatus === 'pending' && !beforeWasPending && !beforeWasClaiming) {
      const requesterUid = asString(after?.requesterUid);
      const { createdBy, name } = await resolveGroup(gid);

      // The creator can never be the requester (requestClaimShadow rejects existing
      // members; the creator is always a member), but self-skip defensively —
      // mirrors the `uid !== createdBy` filter in the other notifiers.
      if (createdBy.length === 0 || createdBy === requesterUid) return;

      const requesterName = asString(after?.requesterDisplayName);
      const shadowName = asString(after?.shadowDisplayName);

      await sendToUids(
        [createdBy],
        (locale) => ({
          title: claimRequestTitle(locale, name),
          body: claimRequestBody(locale, requesterName, shadowName),
        }),
        { type: 'claim_request', groupId: gid },
        { dedupeKey },
      );
      return;
    }

    // Branch B (#565) — creator DECIDES a pending request: notify the REQUESTER.
    if (
      (beforeWasPending || beforeWasClaiming)
      && (afterStatus === 'claimed' || afterStatus === 'declined')
    ) {
      const requesterUid = asString(after?.requesterUid);
      if (requesterUid.length === 0) return;

      const { name, inviteCode, memberIds } = await resolveGroup(gid);
      const shadowName = asString(after?.shadowDisplayName);
      const routeability = memberIds.includes(requesterUid) ? 'member' : 'pre_join';

      await sendToUids(
        [requesterUid],
        (locale) => ({
          title: claimDecideTitle(locale, name),
          body: claimDecideBody(locale, afterStatus, shadowName),
        }),
        {
          type: 'claim_decided',
          groupId: gid,
          decision: afterStatus,
          inviteCode,
          routeability,
        },
        { dedupeKey },
      );
      return;
    }

    // Everything else (no-op pending→pending, deletes, unrelated re-writes): skip.
  },
);
