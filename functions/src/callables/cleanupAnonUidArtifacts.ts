import { getAuth } from 'firebase-admin/auth';
import {
  DocumentData,
  DocumentReference,
  FieldValue,
  Timestamp,
  getFirestore,
} from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import '../admin';

export interface CleanupAnonUidArtifactsInput {
  oldUid: string;
  cleanupSecret: string;
}

export interface CleanupAnonUidArtifactsOutput {
  groupsProcessed: number;
  groupsFailed: string[];
  authUserDeleted: boolean;
  fcmTokenDeleted: boolean;
  joinAttemptsDeleted: boolean;
}

const cleanupIntentMaxAgeMs = 15 * 60 * 1000;
const cleanupSecretMinLength = 32;
const cleanupSecretMaxLength = 128;

function parseOldUid(data: CleanupAnonUidArtifactsInput | undefined): string {
  const oldUid = data?.oldUid;
  if (typeof oldUid !== 'string' || oldUid.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'oldUid must be a non-empty string.');
  }
  return oldUid.trim();
}

function parseCleanupSecret(data: CleanupAnonUidArtifactsInput | undefined): string {
  const cleanupSecret = data?.cleanupSecret;
  if (
    typeof cleanupSecret !== 'string'
    || cleanupSecret.length < cleanupSecretMinLength
    || cleanupSecret.length > cleanupSecretMaxLength
  ) {
    throw new HttpsError('invalid-argument', 'cleanupSecret is invalid.');
  }
  return cleanupSecret;
}

function getStringArray(data: DocumentData, field: string, path: string): string[] {
  const value = data[field];
  if (!Array.isArray(value) || value.some((item) => typeof item !== 'string')) {
    throw new HttpsError('failed-precondition', `${path}.${field} is malformed.`);
  }
  return value;
}

function getStringMap(data: DocumentData, field: string, path: string): Record<string, string> {
  const value = data[field];
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    throw new HttpsError('failed-precondition', `${path}.${field} is malformed.`);
  }
  const normalized: Record<string, string> = {};
  for (const [key, entryValue] of Object.entries(value)) {
    if (typeof entryValue !== 'string') {
      throw new HttpsError('failed-precondition', `${path}.${field} is malformed.`);
    }
    normalized[key] = entryValue;
  }
  return normalized;
}

function replaceUid(values: string[], oldUid: string, newUid: string): string[] {
  const next: string[] = [];
  for (const value of values) {
    const replacement = value === oldUid ? newUid : value;
    if (!next.includes(replacement)) {
      next.push(replacement);
    }
  }
  return next;
}

function hasEmailProvider(providerData: Array<{ providerId: string }>): boolean {
  return providerData.some((provider) => (
    provider.providerId === 'password' || provider.providerId === 'emailLink'
  ));
}

async function assertRecoveredUser(newUid: string): Promise<void> {
  try {
    const user = await getAuth().getUser(newUid);
    if (!hasEmailProvider(user.providerData)) {
      throw new HttpsError(
        'failed-precondition',
        'Recovered user must be linked to an email provider.',
      );
    }
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError(
      'failed-precondition',
      'Recovered user must exist before cleanup.',
    );
  }
}

function cleanupIntentError(): HttpsError {
  return new HttpsError('permission-denied', 'Invalid cleanup intent.');
}

async function assertCleanupIntent(
  oldUid: string,
  cleanupSecret: string,
): Promise<DocumentReference> {
  const db = getFirestore();
  const intentRef = db.doc(`recoveryCleanupIntents/${oldUid}`);
  const intentSnap = await intentRef.get();
  if (!intentSnap.exists) {
    throw cleanupIntentError();
  }

  const data = intentSnap.data() ?? {};
  if (data.secret !== cleanupSecret) {
    throw cleanupIntentError();
  }
  const createdAt = data.createdAt;
  if (
    !(createdAt instanceof Timestamp)
    || Timestamp.now().toMillis() - createdAt.toMillis() > cleanupIntentMaxAgeMs
  ) {
    throw cleanupIntentError();
  }
  return intentRef;
}

async function processGroup(
  groupRef: DocumentReference,
  oldUid: string,
  newUid: string,
): Promise<string[]> {
  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const oldMemberRef = groupRef.collection('members').doc(oldUid);
    const newMemberRef = groupRef.collection('members').doc(newUid);
    const [groupSnap, oldMemberSnap, newMemberSnap, eventsSnap] = await Promise.all([
      tx.get(groupRef),
      tx.get(oldMemberRef),
      tx.get(newMemberRef),
      tx.get(groupRef.collection('events')),
    ]);

    if (!groupSnap.exists) {
      return [];
    }

    const groupData = groupSnap.data() ?? {};
    const memberIds = getStringArray(groupData, 'memberIds', `groups/${groupRef.id}`);
    if (!memberIds.includes(oldUid)) {
      return [];
    }

    const activeEventSnaps = eventsSnap.docs.filter(
      (eventSnap) => eventSnap.data().isDeleted !== true,
    );
    const expenseSnaps = await Promise.all(
      activeEventSnaps.map((eventSnap) => tx.get(eventSnap.ref.collection('expenses'))),
    );
    const actions: string[] = [];
    const nextMemberIds = replaceUid(memberIds, oldUid, newUid);
    const groupUpdate: Record<string, unknown> = {
      memberIds: nextMemberIds,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (groupData.createdBy === oldUid) {
      groupUpdate.createdBy = newUid;
      actions.push('group.createdBy');
    }
    tx.update(groupRef, groupUpdate);
    actions.push(
      memberIds.includes(newUid)
        ? 'group.memberIds.removeOldUid'
        : 'group.memberIds.replaceOldUid',
    );

    if (!newMemberSnap.exists && oldMemberSnap.exists) {
      tx.set(newMemberRef, {
        ...(oldMemberSnap.data() ?? {}),
        id: newUid,
        userId: newUid,
      });
      actions.push('members.copyOldToNew');
    }
    if (oldMemberSnap.exists) {
      tx.delete(oldMemberRef);
      actions.push('members.deleteOld');
    }

    for (const eventSnap of eventsSnap.docs) {
      const eventPath = `groups/${groupRef.id}/events/${eventSnap.id}`;
      const eventData = eventSnap.data() ?? {};
      const participantIds = getStringArray(eventData, 'participantIds', eventPath);
      const participantNames = getStringMap(eventData, 'participantNames', eventPath);
      const eventUpdate: Record<string, unknown> = {};

      if (participantIds.includes(oldUid)) {
        eventUpdate.participantIds = replaceUid(participantIds, oldUid, newUid);
      }
      if (Object.prototype.hasOwnProperty.call(participantNames, oldUid)) {
        eventUpdate.participantNames = {
          ...participantNames,
          [newUid]: participantNames[oldUid],
        };
        delete (eventUpdate.participantNames as Record<string, string>)[oldUid];
      }
      if (eventData.isDeleted !== true && eventData.createdBy === oldUid) {
        eventUpdate.createdBy = newUid;
      }
      if (Object.keys(eventUpdate).length > 0) {
        eventUpdate.updatedAt = FieldValue.serverTimestamp();
        tx.update(eventSnap.ref, eventUpdate);
        actions.push(`events.${eventSnap.id}`);
      }
    }

    activeEventSnaps.forEach((eventSnap, index) => {
      for (const expenseSnap of expenseSnaps[index].docs) {
        const expenseData = expenseSnap.data() ?? {};
        if (expenseData.isDeleted !== true && expenseData.createdBy === oldUid) {
          tx.update(expenseSnap.ref, { createdBy: newUid });
          actions.push(`expenses.${eventSnap.id}.${expenseSnap.id}.createdBy`);
        }
      }
    });

    return actions;
  });
}

export const cleanupAnonUidArtifacts = onCall<
  CleanupAnonUidArtifactsInput,
  Promise<CleanupAnonUidArtifactsOutput>
>(
  { enforceAppCheck: true },
  async (request: CallableRequest<CleanupAnonUidArtifactsInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }

    const newUid = request.auth.uid;
    const oldUid = parseOldUid(request.data);
    const cleanupSecret = parseCleanupSecret(request.data);
    if (newUid === oldUid) {
      throw new HttpsError('invalid-argument', 'oldUid must differ from caller uid.');
    }

    await assertRecoveredUser(newUid);
    const cleanupIntentRef = await assertCleanupIntent(oldUid, cleanupSecret);

    const db = getFirestore();
    const groupSnaps = await db
      .collection('groups')
      .where('memberIds', 'array-contains', oldUid)
      .get();
    const groupsFailed: string[] = [];
    let groupsProcessed = 0;

    for (const groupSnap of groupSnaps.docs) {
      try {
        const actions = await processGroup(groupSnap.ref, oldUid, newUid);
        groupsProcessed += 1;
        if (actions.length > 0) {
          logger.info('cleanupAnonUidArtifacts group write', {
            oldUid,
            newUid,
            groupId: groupSnap.id,
            actions,
          });
        }
      } catch (error) {
        groupsFailed.push(groupSnap.id);
        logger.error('cleanupAnonUidArtifacts group failed', {
          oldUid,
          newUid,
          groupId: groupSnap.id,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    let authUserDeleted = false;
    try {
      await getAuth().deleteUser(oldUid);
      authUserDeleted = true;
    } catch (error) {
      if ((error as { code?: unknown }).code !== 'auth/user-not-found') {
        throw error;
      }
    }

    const fcmTokenRef = db.doc(`fcm_tokens/${oldUid}`);
    const fcmTokenSnap = await fcmTokenRef.get();
    const fcmTokenDeleted = fcmTokenSnap.exists;
    if (fcmTokenDeleted) {
      await fcmTokenRef.delete();
      logger.info('cleanupAnonUidArtifacts fcm token deleted', {
        oldUid,
        newUid,
      });
    }

    const joinAttemptsRef = db.doc(`joinAttempts/${oldUid}`);
    const joinAttemptsSnap = await joinAttemptsRef.get();
    const joinAttemptsDeleted = joinAttemptsSnap.exists;
    if (joinAttemptsDeleted) {
      await joinAttemptsRef.delete();
      logger.info('cleanupAnonUidArtifacts join attempts deleted', {
        oldUid,
        newUid,
      });
    }

    if (groupsFailed.length === 0) {
      await cleanupIntentRef.delete();
    }

    return {
      groupsProcessed,
      groupsFailed,
      authUserDeleted,
      fcmTokenDeleted,
      joinAttemptsDeleted,
    };
  },
);
