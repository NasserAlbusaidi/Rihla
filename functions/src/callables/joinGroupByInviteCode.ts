import { getFirestore, FieldValue } from 'firebase-admin/firestore';
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

  const groupId = await db.runTransaction(async (tx) => {
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

  logger.info('group-join succeeded', { uid, groupId, inviteCode });
  return { groupId };
});
