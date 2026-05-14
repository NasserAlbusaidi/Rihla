import {
  getFirestore,
  FieldValue,
  Firestore,
  Timestamp,
  Transaction,
} from 'firebase-admin/firestore';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import '../admin';

export interface JoinGroupByInviteCodeInput {
  inviteCode: string;
  displayName?: string;
}

export interface JoinGroupByInviteCodeOutput {
  groupId: string;
}

const JOIN_ATTEMPT_WINDOW_MS = 60 * 60 * 1000;
const JOIN_ATTEMPT_LOCK_MS = 60 * 60 * 1000;
const JOIN_ATTEMPT_LIMIT = 5;

function normalizeInviteCode(inviteCode: unknown): string {
  if (typeof inviteCode !== 'string') {
    throw new HttpsError('invalid-argument', 'inviteCode must be a string.');
  }
  const normalized = inviteCode.trim().toUpperCase();
  if (!/^[A-Z0-9]{6}$/.test(normalized)) {
    throw new HttpsError('invalid-argument', 'Invalid invite code.');
  }
  return normalized;
}

function normalizeDisplayName(displayName: unknown): string {
  if (typeof displayName !== 'string') return 'Anonymous';
  const trimmed = displayName.trim();
  return trimmed.length > 0 ? trimmed.substring(0, 80) : 'Anonymous';
}

function isTimestamp(value: unknown): value is Timestamp {
  return value instanceof Timestamp;
}

function isLookupFailure(error: unknown): boolean {
  const code = (error as { code?: unknown }).code;
  return code === 'not-found' || code === 'failed-precondition';
}

function tooManyAttemptsError(): HttpsError {
  return new HttpsError('resource-exhausted', 'Too many attempts. Try again later.');
}

async function assertJoinNotLocked(db: Firestore, uid: string): Promise<void> {
  const attemptRef = db.doc(`joinAttempts/${uid}`);

  await db.runTransaction(async (tx) => {
    const attemptSnap = await tx.get(attemptRef);
    const lockedUntil = attemptSnap.get('lockedUntil');
    if (
      isTimestamp(lockedUntil)
      && lockedUntil.toMillis() > Timestamp.now().toMillis()
    ) {
      throw tooManyAttemptsError();
    }
  });
}

async function recordFailedJoinAttempt(db: Firestore, uid: string): Promise<boolean> {
  const attemptRef = db.doc(`joinAttempts/${uid}`);

  return db.runTransaction(async (tx: Transaction) => {
    const now = Timestamp.now();
    const attemptSnap = await tx.get(attemptRef);
    const data = attemptSnap.data() ?? {};
    const firstFailAt = data.firstFailAt;
    const insideWindow =
      isTimestamp(firstFailAt)
      && now.toMillis() - firstFailAt.toMillis() < JOIN_ATTEMPT_WINDOW_MS;
    const currentFailCount =
      insideWindow && typeof data.failCount === 'number' ? data.failCount : 0;
    const effectiveFirstFailAt = insideWindow ? firstFailAt : now;

    if (currentFailCount >= JOIN_ATTEMPT_LIMIT) {
      tx.set(
        attemptRef,
        {
          failCount: currentFailCount,
          firstFailAt: effectiveFirstFailAt,
          lockedUntil: Timestamp.fromMillis(now.toMillis() + JOIN_ATTEMPT_LOCK_MS),
        },
        { merge: true },
      );
      return true;
    }

    const nextFailCount = currentFailCount + 1;
    tx.set(
      attemptRef,
      {
        failCount: nextFailCount,
        firstFailAt: effectiveFirstFailAt,
        lockedUntil:
          nextFailCount >= JOIN_ATTEMPT_LIMIT
            ? Timestamp.fromMillis(now.toMillis() + JOIN_ATTEMPT_LOCK_MS)
            : null,
      },
      { merge: true },
    );
    return false;
  });
}

export const joinGroupByInviteCode = onCall<
  JoinGroupByInviteCodeInput,
  Promise<JoinGroupByInviteCodeOutput>
>(async (request: CallableRequest<JoinGroupByInviteCodeInput>) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign-in required.');
  }

  const uid = request.auth.uid;
  const inviteCode = normalizeInviteCode(request.data?.inviteCode);
  const displayName = normalizeDisplayName(request.data?.displayName);
  const db = getFirestore();
  const inviteRef = db.doc(`inviteCodes/${inviteCode}`);

  // TODO: enforce App Check tokens (request.app != null) before public launch — requires Firebase Console enrolment.
  await assertJoinNotLocked(db, uid);

  let groupId: string;
  try {
    groupId = await db.runTransaction(async (tx) => {
      const inviteSnap = await tx.get(inviteRef);
      if (!inviteSnap.exists) {
        throw new HttpsError('not-found', 'Invalid invite code.');
      }

      const inviteData = inviteSnap.data() ?? {};
      const resolvedGroupId = inviteData.groupId;
      if (typeof resolvedGroupId !== 'string' || resolvedGroupId.length === 0) {
        throw new HttpsError('failed-precondition', 'Invite code is malformed.');
      }

      const groupRef = db.doc(`groups/${resolvedGroupId}`);
      const memberRef = groupRef.collection('members').doc(uid);
      const [groupSnap, memberSnap] = await Promise.all([
        tx.get(groupRef),
        tx.get(memberRef),
      ]);

      if (!groupSnap.exists) {
        throw new HttpsError('not-found', 'Group not found.');
      }

      const groupData = groupSnap.data() ?? {};
      const memberIds = (groupData.memberIds ?? []) as string[];
      if (memberIds.includes(uid)) {
        return resolvedGroupId;
      }

      tx.update(groupRef, {
        memberIds: FieldValue.arrayUnion(uid),
        updatedAt: FieldValue.serverTimestamp(),
      });

      if (!memberSnap.exists) {
        tx.set(memberRef, {
          id: uid,
          userId: uid,
          displayName,
          role: 'MEMBER',
          joinedAt: FieldValue.serverTimestamp(),
          isShadow: false,
        });
      }

      return resolvedGroupId;
    });
  } catch (error) {
    if (isLookupFailure(error)) {
      const throttled = await recordFailedJoinAttempt(db, uid);
      if (throttled) {
        throw tooManyAttemptsError();
      }
    }
    throw error;
  }

  await db.doc(`joinAttempts/${uid}`).delete();
  logger.info('group-join succeeded', { uid, groupId });
  return { groupId };
});
