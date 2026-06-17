import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import '../admin';
import { normalizeInviteCode, resolveGroupIdByInviteCode } from './shared/inviteCode';

// #278 claim/merge PR8 (D8 read-predicate). The requester polls THEIR OWN claim
// requests' status. claimRequests is `allow read: if false`, and the requester is
// pre-join (not a member), so no client doc-listen is possible — this callable
// (durable-gated, group resolved from the invite code) returns only the caller's
// own requests for that group.

export interface ListMyClaimRequestsInput {
  inviteCode: string;
}

export interface MyClaimRequest {
  requestId: string;
  shadowMemberId: string;
  shadowDisplayName: string;
  status: string;
  createdAtMillis: number | null;
}

export interface ListMyClaimRequestsOutput {
  requests: MyClaimRequest[];
}

function asString(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback;
}

function toMillis(value: unknown): number | null {
  return value instanceof Timestamp ? value.toMillis() : null;
}

export const listMyClaimRequests = onCall<ListMyClaimRequestsInput, Promise<ListMyClaimRequestsOutput>>(
  { enforceAppCheck: true },
  async (request: CallableRequest<ListMyClaimRequestsInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }
    if (request.auth.token?.firebase?.sign_in_provider === 'anonymous') {
      throw new HttpsError(
        'permission-denied',
        'A linked (non-anonymous) account is required.',
      );
    }

    const uid = request.auth.uid;
    const code = normalizeInviteCode(request.data?.inviteCode);
    const db = getFirestore();
    const groupId = await resolveGroupIdByInviteCode(db, code); // not-found for a bad code

    // No membership gate (D8 — the requester is pre-join). Return ONLY the
    // caller's own requests.
    const snap = await db
      .collection(`groups/${groupId}/claimRequests`)
      .where('requesterUid', '==', uid)
      .get();

    const requests: MyClaimRequest[] = snap.docs.map((doc) => {
      const data = doc.data();
      return {
        requestId: doc.id,
        shadowMemberId: asString(data.shadowMemberId),
        shadowDisplayName: asString(data.shadowDisplayName),
        status: asString(data.status),
        createdAtMillis: toMillis(data.createdAt),
      };
    });

    return { requests };
  },
);
