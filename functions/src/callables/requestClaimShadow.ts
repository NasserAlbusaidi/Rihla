import { getFirestore, FieldValue, DocumentData } from 'firebase-admin/firestore';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import '../admin';
import { normalizeInviteCode, resolveGroupIdByInviteCode } from './shared/inviteCode';
import { validId } from './shared/ids';
import { normalizeRequiredDisplayName } from './shared/displayName';

// #278 claim/merge PR8 (D1 + D8). A real (durable) person REQUESTS to claim a
// placeholder ("shadow") member BEFORE joining the group. The request is a
// server-written `claimRequests` doc; only the group creator, via
// decideClaimRequest, can approve it and trigger the re-key. The requester is
// NOT yet a member (D8) — so this resolves the group from the INVITE CODE
// (mirroring joinGroupByInviteCode), not a groupId the requester wouldn't hold.
//
// This callable writes ONLY a claimRequests doc — never memberIds or any money
// doc. No re-key happens here.

export interface RequestClaimShadowInput {
  inviteCode: string;
  shadowMemberId: string;
  displayName?: string;
}

export interface RequestClaimShadowOutput {
  requestId: string;
  status: string;
  groupId: string;
}

// The requester's "who is asking" name (creator-facing only). NOT the adopted
// name — D7: a claim KEEPS the shadow's typed name. Optional; defaults to
// 'Anonymous' (the requester provides their own real name at the PR9 join screen).
function normalizeRequesterName(value: unknown): string {
  if (value == null) return 'Anonymous';
  return normalizeRequiredDisplayName(value);
}

function getMemberIds(groupData: DocumentData): string[] {
  return Array.isArray(groupData.memberIds)
    ? groupData.memberIds.filter((m): m is string => typeof m === 'string')
    : [];
}

export const requestClaimShadow = onCall<RequestClaimShadowInput, Promise<RequestClaimShadowOutput>>(
  { enforceAppCheck: true },
  async (request: CallableRequest<RequestClaimShadowInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }
    // D6: claiming adopts a real identity → a durable account is required.
    // Thrown BEFORE any lookup (mirrors joinGroupByInviteCode:236).
    if (request.auth.token?.firebase?.sign_in_provider === 'anonymous') {
      throw new HttpsError(
        'permission-denied',
        'A linked (non-anonymous) account is required to claim a member.',
      );
    }

    const uid = request.auth.uid;
    const code = normalizeInviteCode(request.data?.inviteCode);
    const shadowMemberId = validId(request.data?.shadowMemberId, 'shadowMemberId');
    const requesterDisplayName = normalizeRequesterName(request.data?.displayName);

    const db = getFirestore();
    const groupId = await resolveGroupIdByInviteCode(db, code); // not-found / failed-precondition
    const groupRef = db.doc(`groups/${groupId}`);
    const groupSnap = await groupRef.get();
    if (!groupSnap.exists) {
      throw new HttpsError('not-found', 'Group not found.');
    }
    const groupData = groupSnap.data() ?? {};
    // Honor the same write-lock as firestore.rules (Admin bypasses rules),
    // mirroring joinGroupByInviteCode:286 / addShadowMember:74.
    if (
      groupData.isDeleted === true
      || groupData.deletingInProgress === true
      || groupData.claimingInProgress === true
      || groupData.accountDeletionInProgress === true
    ) {
      throw new HttpsError('not-found', 'Group not found.');
    }

    const memberIds = getMemberIds(groupData);
    // D8: the requester must NOT already be a member (the engine enforces the full
    // financial-universe pre-scan at approve time; this is the early, clear gate).
    if (memberIds.includes(uid)) {
      throw new HttpsError(
        'failed-precondition',
        "You're already a member of this group.",
      );
    }

    // Validate the shadow is a LIVE placeholder. Match by the userId FIELD (#294)
    // — shadows are uuid-keyed by addShadowMember, but match by field for
    // consistency. Same claimable predicate as the engine Phase A.
    const shadowSnap = await groupRef
      .collection('members')
      .where('userId', '==', shadowMemberId)
      .get();
    const shadow = shadowSnap.docs[0]?.data();
    const claimable =
      shadow != null
      && shadow.isShadow === true
      && shadow.isTombstone !== true
      && memberIds.includes(shadowMemberId);
    if (!claimable) {
      throw new HttpsError(
        'failed-precondition',
        "That member can't be claimed.",
      );
    }
    const shadowDisplayName =
      typeof shadow.displayName === 'string' ? shadow.displayName : 'Member';

    // Deterministic id ⇒ one request per (requester, shadow); idempotent upsert.
    const requestId = `${uid}__${shadowMemberId}`;
    const requestRef = groupRef.collection('claimRequests').doc(requestId);
    const existing = await requestRef.get();
    if (existing.exists) {
      const existingStatus = existing.data()?.status;
      if (existingStatus === 'claimed' || existingStatus === 'claiming') {
        throw new HttpsError('failed-precondition', 'This member has already been claimed.');
      }
      if (existingStatus === 'pending') {
        logger.info('claim request already pending', { uid, groupId, shadowMemberId });
        return { requestId, status: 'pending', groupId };
      }
      if (existingStatus === 'declined') {
        await requestRef.update({
          requesterDisplayName,
          shadowDisplayName,
          status: 'pending',
          decidedBy: null,
          decidedAt: null,
        });
        logger.info('claim request re-opened', { uid, groupId, shadowMemberId });
        return { requestId, status: 'pending', groupId };
      }
      throw new HttpsError('failed-precondition', 'This member has already been claimed.');
    }

    // Open a pending request. A prior 'declined' is re-opened above with a partial
    // update so immutable request identity and createdAt survive the cycle.
    await requestRef.set({
      requesterUid: uid,
      requesterDisplayName,
      shadowMemberId,
      shadowDisplayName,
      status: 'pending',
      createdAt: FieldValue.serverTimestamp(),
      decidedBy: null,
      decidedAt: null,
    });

    logger.info('claim request opened', { uid, groupId, shadowMemberId });
    return { requestId, status: 'pending', groupId };
  },
);
