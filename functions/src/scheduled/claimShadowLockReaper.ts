import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import '../admin';
import {
  claimShadowEngine,
  finalizeClaimAndRelease,
  type ClaimShadowLockToken,
} from '../callables/claimShadow';
import { timestampMillis } from '../callables/groupNetBalance';
import { refreshGroupBalanceAggregate } from '../triggers/balanceAggregator';

const DEFAULT_GRACE_MS = 60 * 60 * 1000;
const DEFAULT_BATCH = 50;

const resolveGraceMs = (): number =>
  Number(process.env.CLAIM_SHADOW_LOCK_REAPER_GRACE_MS) || DEFAULT_GRACE_MS;
const resolveBatch = (): number =>
  Number(process.env.CLAIM_SHADOW_LOCK_REAPER_BATCH) || DEFAULT_BATCH;

function hasMutationMarker(...values: unknown[]): boolean {
  return values.some((value) => value instanceof Timestamp);
}

function lockTokenFromDoc(
  doc: FirebaseFirestore.QueryDocumentSnapshot,
): ClaimShadowLockToken | null {
  const data = doc.data();
  const groupRef = doc.ref.parent.parent;
  if (!groupRef) return null;
  const lockedAtMs = timestampMillis(data.lockedAt);
  if (
    groupRef.id !== data.groupId
    || doc.id !== data.shadowMemberId
    || typeof data.groupId !== 'string'
    || typeof data.shadowMemberId !== 'string'
    || typeof data.claimerUid !== 'string'
    || typeof data.requestId !== 'string'
    || typeof data.lockedBy !== 'string'
    || lockedAtMs == null
  ) {
    return null;
  }
  return {
    refPath: doc.ref.path,
    groupId: data.groupId,
    shadowMemberId: data.shadowMemberId,
    claimerUid: data.claimerUid,
    requestId: data.requestId,
    lockedBy: data.lockedBy,
    lockedAtMs,
  };
}

function lockMatches(data: FirebaseFirestore.DocumentData | undefined, token: ClaimShadowLockToken): boolean {
  return data?.groupId === token.groupId
    && data?.shadowMemberId === token.shadowMemberId
    && data?.claimerUid === token.claimerUid
    && data?.requestId === token.requestId
    && data?.lockedBy === token.lockedBy
    && timestampMillis(data?.lockedAt) === token.lockedAtMs;
}

async function resetPreMutationReservation(
  groupRef: FirebaseFirestore.DocumentReference,
  token: ClaimShadowLockToken,
): Promise<boolean> {
  const db = groupRef.firestore;
  const lockRef = db.doc(token.refPath);
  const requestRef = groupRef.collection('claimRequests').doc(token.requestId);
  return db.runTransaction(async (tx) => {
    const requestSnap = await tx.get(requestRef);
    const groupSnap = await tx.get(groupRef);
    const lockSnap = await tx.get(lockRef);
    const requestData = requestSnap.data() ?? {};
    const lockData = lockSnap.data() ?? {};
    const groupData = groupSnap.data() ?? {};
    if (
      hasMutationMarker(
        requestData.claimMutationStartedAt,
        lockData.mutationStartedAt,
        groupData.claimMutationStartedAt,
      )
    ) {
      return false;
    }
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
    if (lockSnap.exists && lockMatches(lockData, token)) {
      tx.delete(lockRef);
    }
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
    return true;
  });
}

async function processLock(doc: FirebaseFirestore.QueryDocumentSnapshot): Promise<'fresh' | 'reset' | 'resumed' | 'left'> {
  const token = lockTokenFromDoc(doc);
  if (!token) {
    logger.error('claimShadowLockReaper malformed lock left frozen', { path: doc.ref.path });
    return 'left';
  }
  const cutoffMs = Date.now() - resolveGraceMs();
  if (token.lockedAtMs >= cutoffMs) return 'fresh';

  const groupRef = doc.ref.parent.parent!;
  const requestRef = groupRef.collection('claimRequests').doc(token.requestId);
  const [requestSnap, groupSnap] = await Promise.all([requestRef.get(), groupRef.get()]);
  const requestData = requestSnap.data() ?? {};
  const groupData = groupSnap.data() ?? {};
  const mutationMarked = hasMutationMarker(
    requestData.claimMutationStartedAt,
    doc.data().mutationStartedAt,
    groupData.claimMutationStartedAt,
  );

  if (!mutationMarked) {
    return await resetPreMutationReservation(groupRef, token) ? 'reset' : 'left';
  }
  if (
    !requestSnap.exists
    || requestData.status !== 'claiming'
    || requestData.requesterUid !== token.claimerUid
    || requestData.shadowMemberId !== token.shadowMemberId
  ) {
    logger.error('claimShadowLockReaper mutation-marked lock has no matching claiming request', {
      groupId: token.groupId,
      requestId: token.requestId,
    });
    return 'left';
  }

  const result = await claimShadowEngine(
    groupRef.firestore,
    groupRef,
    token.shadowMemberId,
    token.claimerUid,
    { lock: token, resumeExistingLock: true },
  );
  if (result.alreadyClaimed && !result.completedByThisLock) {
    logger.error('claimShadowLockReaper found ambiguous already-claimed state; leaving frozen', {
      groupId: token.groupId,
      requestId: token.requestId,
    });
    return 'left';
  }
  // #714 P1 #3: ATOMIC finalize (status + lock delete + freeze clear in one tx) so a
  // crash here can never leave a 'claimed' request with a live lock + group freeze.
  await finalizeClaimAndRelease(groupRef.firestore, groupRef, requestRef, token, token.lockedBy);
  // #714 P2-1: the display aggregate is stale (every claim-time write hit the
  // balanceAggregator freeze early-return); refresh it now that the freeze is cleared.
  // Best-effort — the claim already converged and a stale cache self-heals via the reconciler.
  try {
    await refreshGroupBalanceAggregate(groupRef.firestore, token.groupId, Date.now());
  } catch (error) {
    logger.warn('claimShadowLockReaper aggregate refresh after resume failed (continuing)', {
      groupId: token.groupId,
      error: error instanceof Error ? error.message : String(error),
    });
  }
  return 'resumed';
}

export const claimShadowLockReaper = onSchedule(
  { schedule: 'every 1 hours', timeoutSeconds: 540, memory: '1GiB' },
  async () => {
    const db = getFirestore();
    const locks = await db.collectionGroup('claimShadowLocks').limit(resolveBatch()).get();
    let fresh = 0;
    let reset = 0;
    let resumed = 0;
    let left = 0;
    for (const doc of locks.docs) {
      try {
        const result = await processLock(doc);
        if (result === 'fresh') fresh += 1;
        if (result === 'reset') reset += 1;
        if (result === 'resumed') resumed += 1;
        if (result === 'left') left += 1;
      } catch (error) {
        left += 1;
        logger.error('claimShadowLockReaper lock processing failed', {
          path: doc.ref.path,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }
    if (locks.size === resolveBatch()) {
      logger.warn('claimShadowLockReaper batch cap hit — stale locks may remain for next pass', {
        batch: resolveBatch(),
      });
    }
    logger.info('claimShadowLockReaper run', {
      scanned: locks.size,
      fresh,
      reset,
      resumed,
      left,
    });
  },
);
