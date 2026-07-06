import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import '../admin';
import { validId } from './shared/ids';

// #278 claim/merge PR8 (D1). The group CREATOR polls the pending claim requests
// to approve/decline (claimRequests is `allow read: if false`, so no client
// doc-listen). Creator-gated (mirrors removeMember.ts:90).

export interface ListGroupClaimRequestsInput {
  groupId: string;
}

export interface GroupClaimRequest {
  requestId: string;
  requesterUid: string;
  requesterDisplayName: string;
  shadowMemberId: string;
  shadowDisplayName: string;
  status: string;
  createdAtMillis: number | null;
}

export interface ListGroupClaimRequestsOutput {
  requests: GroupClaimRequest[];
}

function asString(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback;
}

function toMillis(value: unknown): number | null {
  return value instanceof Timestamp ? value.toMillis() : null;
}

export const listGroupClaimRequests = onCall<
  ListGroupClaimRequestsInput,
  Promise<ListGroupClaimRequestsOutput>
>(
  { enforceAppCheck: true },
  async (request: CallableRequest<ListGroupClaimRequestsInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }
    // D6-R (2026-07-06): anonymous creators may LIST claim requests — the
    // pending request is the link nudge. Read-only + creator-scoped below;
    // the DECISION stays durable-gated in decideClaimRequest.
    const uid = request.auth.uid;
    const groupId = validId(request.data?.groupId, 'groupId');
    const db = getFirestore();
    const groupRef = db.doc(`groups/${groupId}`);
    const groupSnap = await groupRef.get();
    if (!groupSnap.exists) {
      throw new HttpsError('not-found', 'Group not found.');
    }
    // D1 trust anchor: only the group creator may list claim requests.
    if ((groupSnap.data() ?? {}).createdBy !== uid) {
      throw new HttpsError('permission-denied', 'Only the group creator can view claim requests.');
    }

    const snap = await groupRef
      .collection('claimRequests')
      .where('status', '==', 'pending')
      .get();

    const requests: GroupClaimRequest[] = snap.docs.map((doc) => {
      const data = doc.data();
      return {
        requestId: doc.id,
        requesterUid: asString(data.requesterUid),
        requesterDisplayName: asString(data.requesterDisplayName),
        shadowMemberId: asString(data.shadowMemberId),
        shadowDisplayName: asString(data.shadowDisplayName),
        status: asString(data.status),
        createdAtMillis: toMillis(data.createdAt),
      };
    });

    return { requests };
  },
);
