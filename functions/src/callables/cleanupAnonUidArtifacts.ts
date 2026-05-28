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
  // String identifiers of the steps that failed during the cascade.
  // Group failures push the groupId; fcm/joinAttempts failures push the
  // literal sentinels 'fcm_tokens' / 'joinAttempts'. While this array
  // is non-empty, the callable refuses to delete the old anon Auth user
  // or consume the cleanup intent (#46).
  cascadeFailed: string[];
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
  // #46: bump timeout + memory so the per-group cascade has 9 min of
  // headroom on accounts with many groups (default callable timeout is
  // 60s; default memory 256MiB).
  { enforceAppCheck: true, timeoutSeconds: 540, memory: '1GiB' },
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
    const cascadeFailed: string[] = [];
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
        cascadeFailed.push(groupSnap.id);
        logger.error('cleanupAnonUidArtifacts group failed', {
          oldUid,
          newUid,
          groupId: groupSnap.id,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    // #46: fcm/joinAttempts deletes MUST run before the Auth-delete gate so
    // identity residue is scrubbed even when a partial-cascade retry is
    // expected, and so failures of those steps participate in the gate.
    const fcmTokenRef = db.doc(`fcm_tokens/${oldUid}`);
    const fcmTokenSnap = await fcmTokenRef.get();
    let fcmTokenDeleted = false;
    if (fcmTokenSnap.exists) {
      try {
        await fcmTokenRef.delete();
        fcmTokenDeleted = true;
        logger.info('cleanupAnonUidArtifacts fcm token deleted', {
          oldUid,
          newUid,
        });
      } catch (error) {
        cascadeFailed.push('fcm_tokens');
        logger.error('cleanupAnonUidArtifacts fcm token delete failed', {
          oldUid,
          newUid,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    const joinAttemptsRef = db.doc(`joinAttempts/${oldUid}`);
    const joinAttemptsSnap = await joinAttemptsRef.get();
    let joinAttemptsDeleted = false;
    if (joinAttemptsSnap.exists) {
      try {
        await joinAttemptsRef.delete();
        joinAttemptsDeleted = true;
        logger.info('cleanupAnonUidArtifacts join attempts deleted', {
          oldUid,
          newUid,
        });
      } catch (error) {
        cascadeFailed.push('joinAttempts');
        logger.error('cleanupAnonUidArtifacts join attempts delete failed', {
          oldUid,
          newUid,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    // #46 P0 fix: while ANY cascade step failed, the old anon Auth user
    // MUST remain so the client can retry within the 15-min intent
    // window. Today's pre-fix code unconditionally deleted the Auth
    // user, stranding Firestore references to a now-non-existent UID.
    let authUserDeleted = false;
    if (cascadeFailed.length === 0) {
      try {
        await getAuth().deleteUser(oldUid);
        authUserDeleted = true;
      } catch (error) {
        if ((error as { code?: unknown }).code !== 'auth/user-not-found') {
          throw error;
        }
      }
      // Intent is consumed only on full success; on partial failure the
      // client retains the bearer secret for retry until the 15-min
      // code-side expiry (and 1h gcloud TTL backstop).
      await cleanupIntentRef.delete();
    }

    return {
      groupsProcessed,
      cascadeFailed,
      authUserDeleted,
      fcmTokenDeleted,
      joinAttemptsDeleted,
    };
  },
);
