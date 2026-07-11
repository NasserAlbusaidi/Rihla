import {
  DocumentData,
  DocumentReference,
  FieldValue,
  Firestore,
  Timestamp,
  getFirestore,
} from 'firebase-admin/firestore';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import '../admin';
import { validId } from './shared/ids';
import { claimShadowEngine, finalizeClaimAndRelease } from './claimShadow';
import { refreshGroupBalanceAggregate } from '../triggers/balanceAggregator';
import { isCurrentMember } from './shared/membership';

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

interface ClaimReservationToken {
  refPath: string;
  groupId: string;
  shadowMemberId: string;
  claimerUid: string;
  requestId: string;
  lockedBy: string;
  lockedAtMs: number;
}

function timestampMillis(value: unknown): number | null {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return null;
}

function lockMatches(data: DocumentData | undefined, token: ClaimReservationToken): boolean {
  return data?.groupId === token.groupId
    && data?.shadowMemberId === token.shadowMemberId
    && data?.claimerUid === token.claimerUid
    && data?.requestId === token.requestId
    && data?.lockedBy === token.lockedBy
    && timestampMillis(data?.lockedAt) === token.lockedAtMs;
}

async function compareReleaseClaimReservation(
  db: Firestore,
  groupRef: DocumentReference,
  token: ClaimReservationToken,
): Promise<void> {
  const lockRef = db.doc(token.refPath);
  await db.runTransaction(async (tx) => {
    const groupSnap = await tx.get(groupRef);
    const lockSnap = await tx.get(lockRef);
    if (lockSnap.exists && lockMatches(lockSnap.data(), token)) {
      tx.delete(lockRef);
    }
    const groupData = groupSnap.data() ?? {};
    if (
      groupSnap.exists
      && groupData.claimingInProgress === true
      && timestampMillis(groupData.claimLockedAt) === token.lockedAtMs
    ) {
      tx.update(groupRef, {
        claimingInProgress: FieldValue.delete(),
        claimLockedAt: FieldValue.delete(),
        claimMutationStartedAt: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  });
}

async function resetPreMutationClaimReservation(
  db: Firestore,
  groupRef: DocumentReference,
  requestRef: DocumentReference,
  token: ClaimReservationToken,
): Promise<void> {
  const lockRef = db.doc(token.refPath);
  await db.runTransaction(async (tx) => {
    const requestSnap = await tx.get(requestRef);
    const groupSnap = await tx.get(groupRef);
    const lockSnap = await tx.get(lockRef);
    const requestData = requestSnap.data() ?? {};
    if (
      requestSnap.exists
      && requestData.status === 'claiming'
      && requestData.requesterUid === token.claimerUid
      && requestData.shadowMemberId === token.shadowMemberId
      && timestampMillis(requestData.claimingAt) === token.lockedAtMs
    ) {
      tx.update(requestRef, {
        status: 'pending',
        claimingBy: FieldValue.delete(),
        claimingAt: FieldValue.delete(),
        claimMutationStartedAt: FieldValue.delete(),
      });
    }
    if (lockSnap.exists && lockMatches(lockSnap.data(), token)) {
      tx.delete(lockRef);
    }
    const groupData = groupSnap.data() ?? {};
    if (
      groupSnap.exists
      && groupData.claimingInProgress === true
      && timestampMillis(groupData.claimLockedAt) === token.lockedAtMs
    ) {
      tx.update(groupRef, {
        claimingInProgress: FieldValue.delete(),
        claimLockedAt: FieldValue.delete(),
        claimMutationStartedAt: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  });
}

async function reservationHasMutationMarker(
  db: Firestore,
  groupRef: DocumentReference,
  requestRef: DocumentReference,
  token: ClaimReservationToken,
): Promise<boolean> {
  const lockRef = db.doc(token.refPath);
  const [requestSnap, lockSnap, groupSnap] = await Promise.all([
    requestRef.get(),
    lockRef.get(),
    groupRef.get(),
  ]);
  const requestData = requestSnap.data() ?? {};
  const lockData = lockSnap.data() ?? {};
  const groupData = groupSnap.data() ?? {};
  return requestData.claimMutationStartedAt instanceof Timestamp
    || lockData.mutationStartedAt instanceof Timestamp
    || groupData.claimMutationStartedAt instanceof Timestamp;
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
    if (
      groupData.claimingInProgress === true
      || groupData.accountDeletionInProgress === true
      // #1144: the claim re-key rewrites oracle inputs — mutually exclusive
      // with a departure's recompute window.
      || groupData.departureInProgress === true
    ) {
      throw new HttpsError('failed-precondition', 'Group is temporarily locked.');
    }
    // D1 trust anchor (removeMember.ts:90): only the CURRENT-member group creator
    // decides. #1132: createdBy alone is membership-blind — a departed creator
    // must not retain claim-approval (identity re-key) authority.
    if (groupData.createdBy !== uid || !isCurrentMember(groupData, uid)) {
      throw new HttpsError('permission-denied', 'Only the group creator can approve a claim.');
    }

    const requestRef = groupRef.collection('claimRequests').doc(requestId);

    // CAS the pending transition. The claim target (requesterUid + shadowMemberId)
    // is read FROM THE DOC — requestId is an opaque handle, never parsed, and no
    // uid crosses this boundary (impersonation seal). On approve, reserve the
    // per-shadow lock before any money mutation so two requests for one shadow
    // cannot run two engines concurrently.
    const lockedAt = Timestamp.now();
    const decision = await db.runTransaction(async (tx) => {
      const lockedGroupSnap = await tx.get(groupRef);
      if (!lockedGroupSnap.exists) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      const lockedGroupData = lockedGroupSnap.data() ?? {};
      if (lockedGroupData.isDeleted === true || lockedGroupData.deletingInProgress === true) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      if (
        lockedGroupData.claimingInProgress === true
        || lockedGroupData.accountDeletionInProgress === true
        || lockedGroupData.departureInProgress === true // #1144
      ) {
        throw new HttpsError('failed-precondition', 'Group is temporarily locked.');
      }
      // #1132: re-check membership in the tx too — a leave can commit between
      // the first check and here.
      if (lockedGroupData.createdBy !== uid || !isCurrentMember(lockedGroupData, uid)) {
        throw new HttpsError('permission-denied', 'Only the group creator can approve a claim.');
      }

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
      const lockRef = groupRef.collection('claimShadowLocks').doc(shadowMemberId);
      const lockSnap = await tx.get(lockRef);
      if (lockSnap.exists) {
        throw new HttpsError('aborted', 'A claim for this member is already in progress.');
      }
      if (!approve) {
        tx.update(requestRef, {
          status: 'declined',
          decidedBy: uid,
          decidedAt: FieldValue.serverTimestamp(),
        });
        return { requesterUid, shadowMemberId, token: undefined };
      }
      tx.update(requestRef, {
        status: 'claiming',
        claimingBy: uid,
        claimingAt: lockedAt,
      });
      tx.set(lockRef, {
        groupId,
        shadowMemberId,
        claimerUid: requesterUid,
        requestId,
        lockedBy: uid,
        lockedAt,
        updatedAt: lockedAt,
      });
      tx.update(groupRef, {
        claimingInProgress: true,
        claimLockedAt: lockedAt,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {
        requesterUid,
        shadowMemberId,
        token: {
          refPath: lockRef.path,
          groupId,
          shadowMemberId,
          claimerUid: requesterUid,
          requestId,
          lockedBy: uid,
          lockedAtMs: lockedAt.toMillis(),
        } satisfies ClaimReservationToken,
      };
    });

    if (!approve) {
      logger.info('claim request declined', { uid, groupId, requestId });
      return { requestId, status: 'declined', alreadyClaimed: false };
    }

    // Approve: run the engine OUTSIDE the tx (it is multi-batch). It is fully
    // self-protecting (eligibility + D8 pre-scan + post-commit parity). If it
    // THROWS, propagate unchanged and leave the request 'pending' (do NOT mark
    // claimed) — retryable for internal/TOCTOU, declinable for terminal.
    const token = decision.token;
    if (!token) {
      throw new HttpsError('internal', 'Claim reservation was not created.');
    }
    let result;
    try {
      result = await claimShadowEngine(
        db,
        groupRef,
        decision.shadowMemberId,
        decision.requesterUid,
        { lock: token },
      );
    } catch (error) {
      if (await reservationHasMutationMarker(db, groupRef, requestRef, token)) {
        logger.error('claim approval failed after mutation marker; leaving reservation for recovery', {
          uid,
          groupId,
          requestId,
          shadowMemberId: decision.shadowMemberId,
          requesterUid: decision.requesterUid,
          error: error instanceof Error ? error.message : String(error),
        });
        throw error;
      }
      await resetPreMutationClaimReservation(db, groupRef, requestRef, token);
      throw error;
    }

    // status:'claimed' is written ONLY when the engine actually re-keyed THIS
    // approval — i.e. alreadyClaimed === false, which holds iff the shadow EXISTED
    // and this requester just inherited it (engine Phase C added requesterUid to
    // memberIds + parity passed). alreadyClaimed === true means the shadow was
    // ALREADY GONE, and the engine is IDENTITY-BLIND to who retired it: it cannot
    // mean THIS requester succeeded. Two requesters can each hold a pending request
    // for one shadow (a duplicate-name group); a requester can hold a stale request
    // for a shadow a third party took, or for one they didn't claim while joining
    // by a different path. In every such case this approval claimed nothing, so it
    // must DECLINE — never phantom-mark 'claimed' (that would tell a non-inheritor
    // their claim succeeded). The one inverse cost: a crash between a successful
    // re-key and this status write leaves the request 'pending'; a re-approve then
    // DECLINES it even though that requester did inherit the shadow in the crashed
    // run — but their membership + balance are already correct, so only the
    // advisory label lags (a self-correcting false-negative; money is never wrong).
    if (result.alreadyClaimed) {
      // #714: this two-step (decline-then-release) stays NON-atomic on purpose — the
      // alreadyClaimed path returns from the engine BEFORE markClaimMutationStarted, so a
      // crash here leaves an UN-mutation-marked lock the reaper's resetPreMutationReservation
      // clears regardless of request status. (The engine's `!retired` mutation-marked
      // alreadyClaimed return is UNREACHABLE while this lock holds — every shadow-retiring
      // callable gates on claimingInProgress — so it can't reach this block mutation-marked.)
      await requestRef.update({
        status: 'declined',
        decidedBy: uid,
        decidedAt: FieldValue.serverTimestamp(),
      });
      await compareReleaseClaimReservation(db, groupRef, token);
      logger.warn('claim approval found the shadow already gone — declined', {
        uid,
        groupId,
        requestId,
        requesterUid: decision.requesterUid,
      });
      throw new HttpsError(
        'failed-precondition',
        'This member has already been claimed.',
      );
    }

    // #714 P1 #3: ATOMIC finalize (request status + lock delete + freeze clear in ONE
    // tx). The prior two-step `update`-then-`compareRelease` could crash between and
    // strand a 'claimed' request with a live lock + claimingInProgress freeze — which
    // the reaper's status==='claiming' resume guard cannot recover (group-wide outage).
    await finalizeClaimAndRelease(db, groupRef, requestRef, token, uid);
    // #714 P2-1: every claim-time write hit the balanceAggregator freeze early-return,
    // so the home-hero cache is pre-claim until refreshed. Best-effort now that the
    // freeze is cleared — the claim already converged; a stale cache self-heals.
    try {
      await refreshGroupBalanceAggregate(db, groupId, Date.now());
    } catch (error) {
      logger.warn('decideClaimRequest aggregate refresh after claim failed (continuing)', {
        groupId,
        requestId,
        error: error instanceof Error ? error.message : String(error),
      });
    }

    logger.info('claim request approved', { uid, groupId, requestId });
    return { requestId, status: 'claimed', alreadyClaimed: false };
  },
);
