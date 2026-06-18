import { getFirestore } from 'firebase-admin/firestore';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import '../admin';
import { sendToUids } from '../notifications/fcmSender';
import { claimRequestTitle, claimRequestBody } from '../notifications/strings';

// #560 — buzz the group CREATOR when a claim request arrives, so approval isn't
// gated on the creator manually polling Group Settings. A real person requests to
// claim a placeholder ("shadow") member via requestClaimShadow, which writes a
// groups/{gid}/claimRequests/{id} doc with status:'pending'.
//
// onDocumentWritten (NOT ...Created): claimRequests is MUTABLE, unlike the
// append-only settlement/event docs the sibling notifiers watch. requestClaimShadow
// uses a deterministic id `${uid}__${shadowMemberId}` + `.set()`, so a
// creator-DECLINED request that is re-requested is an UPDATE (declined→pending),
// which onDocumentCreated would miss — defeating the discoverability goal. The
// guard fires on exactly "a request just became pending":
//     before.status !== 'pending' && after.status === 'pending'
// → NOTIFY on create (∅→pending) and re-open (declined→pending); SKIP every
// decideClaimRequest transition (pending→claimed | pending→declined, incl. the
// already-claimed decline), the no-op pending→pending re-write, and any delete
// (after absent). A claimed doc can never reopen — requestClaimShadow throws
// before .set() if status==='claimed'.
//
// Read-only: reads the request doc + the group doc (createdBy + name) and sends;
// it NEVER mutates a domain doc. createdBy is an auth uid (the creator trust
// anchor in decideClaimRequest), so it maps directly to fcm_tokens/{uid}; an
// anonymous creator with no token doc is silently skipped by sendToUids.

function asString(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

async function resolveGroup(
  gid: string,
): Promise<{ createdBy: string; name: string }> {
  try {
    const snap = await getFirestore().doc(`groups/${gid}`).get();
    const data = snap.data() ?? {};
    return { createdBy: asString(data.createdBy), name: asString(data.name) };
  } catch (error) {
    logger.warn('claim notify: group lookup failed', { gid, error: String(error) });
    return { createdBy: '', name: '' };
  }
}

export const claimRequestNotifier = onDocumentWritten(
  'groups/{gid}/claimRequests/{requestId}',
  async (event) => {
    const change = event.data;
    const before = change?.before.exists ? change.before.data() : undefined;
    const after = change?.after.exists ? change.after.data() : undefined;

    // Fire only when a request ARRIVES at pending (create or declined→re-open);
    // skip decide transitions, no-op re-writes, and deletes.
    if (after?.status !== 'pending') return;
    if (before?.status === 'pending') return;

    const gid = event.params.gid;
    const requesterUid = asString(after.requesterUid);
    const { createdBy, name } = await resolveGroup(gid);

    // The creator can never be the requester (requestClaimShadow rejects existing
    // members; the creator is always a member), but self-skip defensively —
    // mirrors the `uid !== createdBy` filter in the other notifiers.
    if (createdBy.length === 0 || createdBy === requesterUid) return;

    const requesterName = asString(after.requesterDisplayName);
    const shadowName = asString(after.shadowDisplayName);

    await sendToUids(
      [createdBy],
      (locale) => ({
        title: claimRequestTitle(locale, name),
        body: claimRequestBody(locale, requesterName, shadowName),
      }),
      { type: 'claim_request', groupId: gid },
    );
  },
);
