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

function toFiniteNumber(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

// #216: rename the `oldUid` key of a splitDistribution map to `newUid`.
// Unlike deleteAccount's renameMapKey (which renames uid -> a FRESH tombstone
// id that never collides), recovery renames oldUid -> newUid, and newUid may
// ALREADY be a key (the "both UIDs are members" case). On collision we SUM the
// persisted integer subunits — provably conservation-safe: the calculator reads
// splitDistribution only for exact/shares/percent (all additive, equally is
// excluded) and the from-persisted reconstruction is linear, so the merged
// person's combined share and the denominator total are both preserved. A plain
// overwrite (renameMapKey) would silently DROP newUid's share — a money bug.
// Returns a new map (immutable); null when the input is not a plain object.
function mergeUidMapKey(
  value: unknown,
  oldUid: string,
  newUid: string,
): { value: Record<string, unknown>; changed: boolean } | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  const source = value as Record<string, unknown>;
  if (!Object.prototype.hasOwnProperty.call(source, oldUid)) {
    return { value: { ...source }, changed: false };
  }
  const next: Record<string, unknown> = { ...source };
  const oldValue = next[oldUid];
  delete next[oldUid];
  if (Object.prototype.hasOwnProperty.call(source, newUid)) {
    // Collision: sum subunits. toFiniteNumber zeroes a forged non-numeric value
    // rather than emit NaN — legitimate data is always a number.
    next[newUid] = toFiniteNumber(source[newUid]) + toFiniteNumber(oldValue);
  } else {
    next[newUid] = oldValue;
  }
  return { value: next, changed: true };
}

// #216: migrate the UID-keyed attribution fields of a settlement doc oldUid ->
// newUid. MIGRATE semantics (repoint ids only) — payerName/recipientName are
// denormalized display strings for the SAME recovered person and are left
// untouched (contrast deleteAccount, which scrubs them to "Deleted member"
// because the person is gone). Returns null when nothing matches.
function settlementMigrationUpdate(
  data: DocumentData,
  oldUid: string,
  newUid: string,
): Record<string, unknown> | null {
  const update: Record<string, unknown> = {};
  if (data.payerParticipantId === oldUid) {
    update.payerParticipantId = newUid;
  }
  if (data.recipientParticipantId === oldUid) {
    update.recipientParticipantId = newUid;
  }
  if (data.createdBy === oldUid) {
    update.createdBy = newUid;
  }
  return Object.keys(update).length > 0 ? update : null;
}

// #217: recursively repoint oldUid -> newUid inside an activity-log `metadata`
// blob — string VALUES that equal oldUid (metadata.payerParticipantId /
// recipientId), array entries (metadata.customSplitParticipants), and
// (defensively) map KEYS that equal oldUid. Mirrors deleteAccount's
// rewriteMetadata MINUS the name-scrubbing (recovery keeps the person's name).
// PURE substitution — does NOT sum (contrast mergeUidMapKey for
// splitDistribution, which sums because those values are money subunits;
// metadata values are display-only and never aggregated, so on the both-members
// collision an array duplicates rather than merges — inert). Returns a new value
// (immutable); passes non-UID content through unchanged.
function migrateMetadataValue(value: unknown, oldUid: string, newUid: string): unknown {
  if (typeof value === 'string') {
    return value === oldUid ? newUid : value;
  }
  if (Array.isArray(value)) {
    return value.map((entry) => migrateMetadataValue(entry, oldUid, newUid));
  }
  if (value && typeof value === 'object') {
    const next: Record<string, unknown> = {};
    for (const [key, entryValue] of Object.entries(value)) {
      next[key === oldUid ? newUid : key] = migrateMetadataValue(entryValue, oldUid, newUid);
    }
    return next;
  }
  return value;
}

// #217: migrate the UID-bearing attribution of one activity-log doc oldUid ->
// newUid. MIGRATE semantics (repoint ids only) — actorName / logText /
// description are denormalized display strings for the SAME recovered person and
// are LEFT untouched (contrast deleteAccount's activityUpdates, which scrubs them
// because the person is gone). eventScoped=true also migrates targetParticipantId
// (group activity has no such field; note: no LIVE writer emits it — defensive
// parity with the scrub). Returns null when nothing matched (so an unchanged doc
// is never written).
function activityMigrationUpdate(
  data: DocumentData,
  oldUid: string,
  newUid: string,
  eventScoped: boolean,
): Record<string, unknown> | null {
  const update: Record<string, unknown> = {};
  if (data.actorId === oldUid) {
    update.actorId = newUid;
  }
  if (eventScoped && data.targetParticipantId === oldUid) {
    update.targetParticipantId = newUid;
  }
  if (data.metadata !== undefined) {
    const migrated = migrateMetadataValue(data.metadata, oldUid, newUid);
    if (JSON.stringify(migrated) !== JSON.stringify(data.metadata)) {
      update.metadata = migrated;
    }
  }
  return Object.keys(update).length > 0 ? update : null;
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
    // #216: settlement reads MUST stay in the read phase — every tx.get below
    // precedes the first write (tx.update(groupRef)), per Firestore's
    // all-reads-before-writes transaction rule.
    const eventSettlementSnaps = await Promise.all(
      activeEventSnaps.map((eventSnap) => tx.get(eventSnap.ref.collection('settlements'))),
    );
    const groupSettlementsSnap = await tx.get(groupRef.collection('settlements'));
    // #217: activity reads MUST also stay in the read phase (all-reads-before-
    // writes). Event activity_logs is migrated active-events-only, mirroring the
    // expense/settlement active-only policy above.
    const eventActivitySnaps = await Promise.all(
      activeEventSnaps.map((eventSnap) => tx.get(eventSnap.ref.collection('activity_logs'))),
    );
    const groupActivitySnap = await tx.get(groupRef.collection('activity'));
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

    // #216: migrate the FINANCIAL attribution of each active expense in each
    // active event — createdBy (ownership), payerParticipantId (feeds totalPaid
    // + eventFinancialUids), customSplitParticipants (custom-scope head set,
    // dedup on collision via replaceUid), and splitDistribution keys (owed
    // allocation, sum-merge on collision). Soft-deleted expenses are skipped:
    // they never feed balances (the read path filters isDeleted=false), so their
    // oldUid refs are an inert residual — same active-only policy as createdBy.
    activeEventSnaps.forEach((eventSnap, index) => {
      for (const expenseSnap of expenseSnaps[index].docs) {
        const expenseData = expenseSnap.data() ?? {};
        if (expenseData.isDeleted === true) {
          continue;
        }
        const expenseUpdate: Record<string, unknown> = {};
        if (expenseData.createdBy === oldUid) {
          expenseUpdate.createdBy = newUid;
        }
        if (expenseData.payerParticipantId === oldUid) {
          expenseUpdate.payerParticipantId = newUid;
        }
        if (
          Array.isArray(expenseData.customSplitParticipants)
          && (expenseData.customSplitParticipants as unknown[]).includes(oldUid)
        ) {
          expenseUpdate.customSplitParticipants = replaceUid(
            expenseData.customSplitParticipants as string[],
            oldUid,
            newUid,
          );
        }
        const mergedDistribution = mergeUidMapKey(
          expenseData.splitDistribution,
          oldUid,
          newUid,
        );
        if (mergedDistribution?.changed) {
          expenseUpdate.splitDistribution = mergedDistribution.value;
        }
        if (Object.keys(expenseUpdate).length > 0) {
          tx.update(expenseSnap.ref, expenseUpdate);
          actions.push(`expenses.${eventSnap.id}.${expenseSnap.id}`);
        }
      }
    });

    // #216: migrate event-level settlements (per active event) and group-level
    // settlements. Settlements are append-only live financial records read by
    // the balance engine; an un-migrated payer/recipient id strands the
    // recovered user's money under the about-to-be-deleted oldUid. The whole
    // collection is read (settlement docs' own isDeleted is not gated — they are
    // append-only, so none are effectively deleted, matching deleteAccount).
    // This tx.update writes THROUGH the `allow update: if false` append-only
    // rule via the Admin SDK (rules-bypassing) — clients still cannot mutate
    // settlements; only this server identity-migration can.
    activeEventSnaps.forEach((eventSnap, index) => {
      for (const settlementSnap of eventSettlementSnaps[index].docs) {
        const update = settlementMigrationUpdate(
          settlementSnap.data() ?? {},
          oldUid,
          newUid,
        );
        if (update) {
          tx.update(settlementSnap.ref, update);
          actions.push(`settlements.${eventSnap.id}.${settlementSnap.id}`);
        }
      }
    });
    for (const settlementSnap of groupSettlementsSnap.docs) {
      const update = settlementMigrationUpdate(
        settlementSnap.data() ?? {},
        oldUid,
        newUid,
      );
      if (update) {
        tx.update(settlementSnap.ref, update);
        actions.push(`settlements.group.${settlementSnap.id}`);
      }
    }

    // #217: migrate the ACTIVITY surface — event activity_logs (per active event)
    // and group activity. MIGRATE semantics: repoint actorId/targetParticipantId
    // + UID-bearing metadata VALUES; leave actorName/logText/description (same
    // person). Activity is non-financial (the balance engine never reads it), so
    // an un-migrated ref is an inert orphan, not a money bug — but we migrate it
    // for completeness (same defect class as #216). Like the settlement loops,
    // these tx.update calls write THROUGH the activity `allow update: if false`
    // rule via the Admin SDK; clients still cannot mutate activity.
    activeEventSnaps.forEach((eventSnap, index) => {
      for (const activitySnap of eventActivitySnaps[index].docs) {
        const update = activityMigrationUpdate(
          activitySnap.data() ?? {},
          oldUid,
          newUid,
          true,
        );
        if (update) {
          tx.update(activitySnap.ref, update);
          actions.push(`activity_logs.${eventSnap.id}.${activitySnap.id}`);
        }
      }
    });
    for (const activitySnap of groupActivitySnap.docs) {
      const update = activityMigrationUpdate(
        activitySnap.data() ?? {},
        oldUid,
        newUid,
        false,
      );
      if (update) {
        tx.update(activitySnap.ref, update);
        actions.push(`activity.${activitySnap.id}`);
      }
    }

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
