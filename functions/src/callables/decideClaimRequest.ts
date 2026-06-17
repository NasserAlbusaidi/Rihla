import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import '../admin';
import { validId } from './shared/ids';
import { claimShadowEngine } from './claimShadow';

// #278 claim/merge PR8 (D1). The group CREATOR approves or declines a pending
// claim request. This is the impersonation gate: the raw claimShadow onCall was
// de-exported, so the re-key engine is reachable ONLY here, and ONLY by the
// creator. On approve, the engine re-keys the shadow onto the requester whose
// auth.uid is read FROM THE PERSISTED REQUEST DOC — there is no claimerUid in the
// input, so a creator cannot redirect a claim onto an attacker-supplied uid.
//
// Status machine: pending → claimed (engine success, incl. idempotent
// alreadyClaimed) | declined (creator declines). There is NO persisted
// intermediate 'approved' — the multi-batch engine runs outside the CAS tx, and
// the status flips to 'claimed' only after it returns. If the engine THROWS, the
// request stays 'pending': a transient internal/TOCTOU is retryable by
// re-approving; a terminal failed-precondition (the requester already has a
// position) is declinable, and the requester joins as new (PR9).

export interface DecideClaimRequestInput {
  groupId: string;
  requestId: string;
  approve: boolean;
}

export interface DecideClaimRequestOutput {
  requestId: string;
  status: string;
  alreadyClaimed: boolean;
}

export const decideClaimRequest = onCall<DecideClaimRequestInput, Promise<DecideClaimRequestOutput>>(
  { enforceAppCheck: true },
  async (request: CallableRequest<DecideClaimRequestInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }
    if (request.auth.token?.firebase?.sign_in_provider === 'anonymous') {
      throw new HttpsError(
        'permission-denied',
        'A linked (non-anonymous) account is required to approve a claim.',
      );
    }

    const uid = request.auth.uid;
    const groupId = validId(request.data?.groupId, 'groupId');
    const requestId = validId(request.data?.requestId, 'requestId');
    const approve = request.data?.approve;
    if (typeof approve !== 'boolean') {
      throw new HttpsError('invalid-argument', 'approve must be a boolean.');
    }

    const db = getFirestore();
    const groupRef = db.doc(`groups/${groupId}`);
    const groupSnap = await groupRef.get();
    if (!groupSnap.exists) {
      throw new HttpsError('not-found', 'Group not found.');
    }
    const groupData = groupSnap.data() ?? {};
    if (groupData.isDeleted === true || groupData.deletingInProgress === true) {
      throw new HttpsError('not-found', 'Group not found.');
    }
    // D1 trust anchor (removeMember.ts:90): only the group creator decides.
    if (groupData.createdBy !== uid) {
      throw new HttpsError('permission-denied', 'Only the group creator can approve a claim.');
    }

    const requestRef = groupRef.collection('claimRequests').doc(requestId);

    // CAS the pending transition. The claim target (requesterUid + shadowMemberId)
    // is read FROM THE DOC — requestId is an opaque handle, never parsed, and no
    // uid crosses this boundary (impersonation seal). On decline, flip in-tx.
    const decision = await db.runTransaction(async (tx) => {
      const snap = await tx.get(requestRef);
      if (!snap.exists) {
        throw new HttpsError('not-found', 'Claim request not found.');
      }
      const data = snap.data() ?? {};
      if (data.status !== 'pending') {
        throw new HttpsError(
          'failed-precondition',
          'This claim request has already been decided.',
        );
      }
      const requesterUid = data.requesterUid;
      const shadowMemberId = data.shadowMemberId;
      if (typeof requesterUid !== 'string' || typeof shadowMemberId !== 'string') {
        throw new HttpsError('failed-precondition', 'Claim request is malformed.');
      }
      if (!approve) {
        tx.update(requestRef, {
          status: 'declined',
          decidedBy: uid,
          decidedAt: FieldValue.serverTimestamp(),
        });
      }
      return { requesterUid, shadowMemberId };
    });

    if (!approve) {
      logger.info('claim request declined', { uid, groupId, requestId });
      return { requestId, status: 'declined', alreadyClaimed: false };
    }

    // Approve: run the engine OUTSIDE the tx (it is multi-batch). It is fully
    // self-protecting (eligibility + D8 pre-scan + post-commit parity). If it
    // THROWS, propagate unchanged and leave the request 'pending' (do NOT mark
    // claimed) — retryable for internal/TOCTOU, declinable for terminal.
    const result = await claimShadowEngine(
      db,
      groupRef,
      decision.shadowMemberId,
      decision.requesterUid,
    );

    // alreadyClaimed:true means the shadow is GONE — but the engine is
    // identity-blind to WHO retired it. Two distinct requesters can each hold a
    // pending request for the SAME shadow (a duplicate-name group), so approving
    // requester B (who inherits it) and THEN approving requester A's still-pending
    // request yields alreadyClaimed:true for A even though A claimed NOTHING.
    // Marking A 'claimed' would be a phantom success. So when the shadow was
    // already gone, confirm THIS requester actually holds the membership the
    // claim promised; if not, they lost the race → decline (not claimed). The
    // same-requester crash-retry (the legitimate alreadyClaimed path) passes this
    // check because that requester IS in memberIds. A fresh re-key
    // (alreadyClaimed:false) always lands the requester in memberIds, so no extra
    // read is paid on the hot path.
    if (result.alreadyClaimed) {
      const afterMemberIds = (await groupRef.get()).data()?.memberIds;
      const requesterIsMember =
        Array.isArray(afterMemberIds) && afterMemberIds.includes(decision.requesterUid);
      if (!requesterIsMember) {
        await requestRef.update({
          status: 'declined',
          decidedBy: uid,
          decidedAt: FieldValue.serverTimestamp(),
        });
        logger.warn('claim approval lost the race (shadow claimed by another) — declined', {
          uid,
          groupId,
          requestId,
          requesterUid: decision.requesterUid,
        });
        throw new HttpsError(
          'failed-precondition',
          'This member has already been claimed by someone else.',
        );
      }
    }

    await requestRef.update({
      status: 'claimed',
      decidedBy: uid,
      decidedAt: FieldValue.serverTimestamp(),
    });

    logger.info('claim request approved', {
      uid,
      groupId,
      requestId,
      alreadyClaimed: result.alreadyClaimed,
    });
    return { requestId, status: 'claimed', alreadyClaimed: result.alreadyClaimed };
  },
);
