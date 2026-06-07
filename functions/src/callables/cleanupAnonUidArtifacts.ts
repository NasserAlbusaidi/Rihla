import { getAuth } from 'firebase-admin/auth';
import {
  DocumentData,
  DocumentReference,
  FieldValue,
  Firestore,
  Timestamp,
  WriteBatch,
  getFirestore,
} from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import '../admin';

// #275: chunked batch writer (≤450-op auto-flush) so the per-group recovery
// cascade no longer rides Firestore's 500-write-per-transaction cliff. Local to
// this callable with its OWN test seam (CLEANUP_BATCH_LIMIT) so the deleteAccount
// / deleteGroup cascades stay untouched — mirrors deleteGroup.ts's deliberate
// per-callable copy. Only `update` is needed (Phase B never set/deletes; the
// member copy/delete is the Phase C transaction).
// LIMIT GUARD: only event updates here carry a serverTimestamp transform (which
// counts as +1 against the 500-write commit cap); expense/settlement/activity
// updates carry none, so 450 (matching deleteAccount/deleteGroup) is safe. If a
// transform is ever added to a high-volume write, halve this to <=250.
const DEFAULT_BATCH_LIMIT = 450;

function resolveBatchLimit(): number {
  return Number(process.env.CLEANUP_BATCH_LIMIT) || DEFAULT_BATCH_LIMIT;
}

class BatchWriter {
  private batch: WriteBatch;
  private writes = 0;
  private readonly limit: number;

  constructor(private readonly db: Firestore) {
    this.batch = db.batch();
    this.limit = resolveBatchLimit();
  }

  async update(ref: DocumentReference, data: DocumentData): Promise<void> {
    this.batch.update(ref, data);
    this.writes += 1;
    if (this.writes >= this.limit) {
      await this.flush();
    }
  }

  async flush(): Promise<void> {
    if (this.writes === 0) return;
    await this.batch.commit();
    this.batch = this.db.batch();
    this.writes = 0;
  }
}

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

// #275: the per-group cascade is chunked into three phases to escape the
// 500-write-per-transaction cliff (#216 financial + #217 activity writes both
// rode it). MIGRATION SEMANTICS ARE UNCHANGED from the prior single transaction
// — only the execution mechanism changes:
//   Phase A — non-transactional reads + membership guard.
//   Phase B — idempotent child scrubs (events + expenses + settlements +
//             activity) staged into a BatchWriter that auto-flushes at <=450.
//   Phase C — a bounded transaction retires the member identity (member doc
//             copy/delete + memberIds/createdBy update).
// CONVERGENCE CONTRACT (#46): the BatchWriter is non-atomic across flushes, so
// this relies on every op being idempotent + convergent-on-retry (which
// cleanupAnonUidArtifacts already is — splitDistribution's sum-merge is gated on
// the oldUid key still being present, so a torn-batch retry never double-sums).
// Phase C's memberIds removal — the write that drops the group from the handler's
// `memberIds array-contains oldUid` retry query — MUST land only AFTER Phase B is
// durable (writer.flush), so a torn Phase B keeps the group query-visible and the
// retry converges. This mirrors deleteAccount's Phase B -> Phase C ordering.
async function processGroup(
  groupRef: DocumentReference,
  oldUid: string,
  newUid: string,
): Promise<string[]> {
  const db = getFirestore();
  const newMemberRef = groupRef.collection('members').doc(newUid);

  // ---- Phase A: reads + membership guard (non-transactional) ----
  const [groupSnap, eventsSnap] = await Promise.all([
    groupRef.get(),
    groupRef.collection('events').get(),
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

  // #275: pre-fetch every child collection in parallel (reads need not share the
  // writer's flush cadence — only writes do; keeps the dense-account read
  // latency the 540s budget assumes). Active-events-only for
  // expenses/settlements/activity, mirroring the pre-rewrite policy; participant
  // migration below still covers ALL events.
  const [expenseSnaps, eventSettlementSnaps, eventActivitySnaps] = await Promise.all([
    Promise.all(activeEventSnaps.map((e) => e.ref.collection('expenses').get())),
    Promise.all(activeEventSnaps.map((e) => e.ref.collection('settlements').get())),
    Promise.all(activeEventSnaps.map((e) => e.ref.collection('activity_logs').get())),
  ]);
  const groupSettlementsSnap = await groupRef.collection('settlements').get();
  const groupActivitySnap = await groupRef.collection('activity').get();

  // ---- Phase B: idempotent child scrubs (batched, may span auto-flushes) ----
  // #275: for...of / index loops, NEVER Array.forEach — writer.update is async
  // (it awaits the auto-flush at the limit); a forEach callback swallows that
  // promise so the <=450 gate would silently no-op and writes would race.
  const writer = new BatchWriter(db);
  const actions: string[] = [];

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
      await writer.update(eventSnap.ref, eventUpdate);
      actions.push(`events.${eventSnap.id}`);
    }
  }

  // #216: migrate the FINANCIAL attribution of each active expense in each active
  // event — createdBy (ownership), payerParticipantId (feeds totalPaid +
  // eventFinancialUids), customSplitParticipants (custom-scope head set, dedup on
  // collision via replaceUid), and splitDistribution keys (owed allocation,
  // sum-merge on collision). Soft-deleted expenses are skipped: they never feed
  // balances, so their oldUid refs are an inert residual.
  for (let index = 0; index < activeEventSnaps.length; index += 1) {
    const eventSnap = activeEventSnaps[index];
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
        await writer.update(expenseSnap.ref, expenseUpdate);
        actions.push(`expenses.${eventSnap.id}.${expenseSnap.id}`);
      }
    }
  }

  // #216: migrate event-level settlements (per active event) and group-level
  // settlements. Settlements are append-only live financial records read by the
  // balance engine; an un-migrated payer/recipient id strands the recovered
  // user's money under the about-to-be-deleted oldUid. These writes go THROUGH
  // the `allow update: if false` append-only rule via the Admin SDK
  // (rules-bypassing) — clients still cannot mutate settlements.
  for (let index = 0; index < activeEventSnaps.length; index += 1) {
    const eventSnap = activeEventSnaps[index];
    for (const settlementSnap of eventSettlementSnaps[index].docs) {
      const update = settlementMigrationUpdate(settlementSnap.data() ?? {}, oldUid, newUid);
      if (update) {
        await writer.update(settlementSnap.ref, update);
        actions.push(`settlements.${eventSnap.id}.${settlementSnap.id}`);
      }
    }
  }
  for (const settlementSnap of groupSettlementsSnap.docs) {
    const update = settlementMigrationUpdate(settlementSnap.data() ?? {}, oldUid, newUid);
    if (update) {
      await writer.update(settlementSnap.ref, update);
      actions.push(`settlements.group.${settlementSnap.id}`);
    }
  }

  // #217: migrate the ACTIVITY surface — event activity_logs (per active event)
  // and group activity. MIGRATE semantics: repoint actorId/targetParticipantId +
  // UID-bearing metadata VALUES; leave actorName/logText/description (same
  // person). Activity is non-financial, so an un-migrated ref is an inert orphan;
  // we migrate it for completeness. These writes go THROUGH the activity
  // `allow update: if false` rule via the Admin SDK.
  for (let index = 0; index < activeEventSnaps.length; index += 1) {
    const eventSnap = activeEventSnaps[index];
    for (const activitySnap of eventActivitySnaps[index].docs) {
      const update = activityMigrationUpdate(activitySnap.data() ?? {}, oldUid, newUid, true);
      if (update) {
        await writer.update(activitySnap.ref, update);
        actions.push(`activity_logs.${eventSnap.id}.${activitySnap.id}`);
      }
    }
  }
  for (const activitySnap of groupActivitySnap.docs) {
    const update = activityMigrationUpdate(activitySnap.data() ?? {}, oldUid, newUid, false);
    if (update) {
      await writer.update(activitySnap.ref, update);
      actions.push(`activity.${activitySnap.id}`);
    }
  }

  await writer.flush();

  // ---- Phase C: transactional identity retirement (after B is durable) ----
  // Bounded writes (1 group update + <=1 member copy + N member deletes), so it
  // cannot itself hit the cliff. Re-reads memberIds: a clean skip if oldUid raced
  // out between Phase A and here (double-invocation), else atomic retirement.
  // #294: match the member doc by the `userId` FIELD (a creator's doc is keyed by
  // a random uuid), copy from the deterministic first, delete ALL matches.
  const retired = await db.runTransaction(async (tx) => {
    const gSnap = await tx.get(groupRef);
    if (!gSnap.exists) {
      return { applied: false, createdByMigrated: false, copied: false, deleted: 0, removed: false };
    }
    const gData = gSnap.data() ?? {};
    const currentMemberIds = getStringArray(gData, 'memberIds', `groups/${groupRef.id}`);
    if (!currentMemberIds.includes(oldUid)) {
      return { applied: false, createdByMigrated: false, copied: false, deleted: 0, removed: false };
    }
    const membersSnap = await tx.get(groupRef.collection('members'));
    const oldMemberDocs = membersSnap.docs.filter((d) => d.data().userId === oldUid);
    const newMemberExists = membersSnap.docs.some((d) => d.data().userId === newUid);

    const groupUpdate: Record<string, unknown> = {
      memberIds: replaceUid(currentMemberIds, oldUid, newUid),
      updatedAt: FieldValue.serverTimestamp(),
    };
    const createdByMigrated = gData.createdBy === oldUid;
    if (createdByMigrated) {
      groupUpdate.createdBy = newUid;
    }

    let copied = false;
    if (!newMemberExists && oldMemberDocs.length > 0) {
      tx.set(newMemberRef, {
        ...(oldMemberDocs[0].data() ?? {}),
        id: newUid,
        userId: newUid,
      });
      copied = true;
    }
    for (const d of oldMemberDocs) {
      tx.delete(d.ref);
    }
    tx.update(groupRef, groupUpdate);
    return {
      applied: true,
      createdByMigrated,
      copied,
      deleted: oldMemberDocs.length,
      removed: currentMemberIds.includes(newUid),
    };
  });

  // Observability-equivalent action strings (set preserved; order is now
  // child-first then identity, since Phase C runs last — no consumer reads order).
  if (retired.applied) {
    if (retired.createdByMigrated) {
      actions.push('group.createdBy');
    }
    actions.push(
      retired.removed
        ? 'group.memberIds.removeOldUid'
        : 'group.memberIds.replaceOldUid',
    );
    if (retired.copied) {
      actions.push('members.copyOldToNew');
    }
    for (let i = 0; i < retired.deleted; i += 1) {
      actions.push('members.deleteOld');
    }
  }

  return actions;
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
