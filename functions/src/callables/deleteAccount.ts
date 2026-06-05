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
import { createHash } from 'crypto';
import '../admin';

// Server-side account deletion cascade. Each group is scrubbed in two phases:
// (B) idempotent child-doc scrubs (events/expenses/settlements/activity) staged
// into a per-group BatchWriter, then (C) a transactional identity retirement
// (tombstone member + old-member delete + memberIds/createdBy/orphan update).
// The group stays visible to the `memberIds array-contains uid` retry query
// until C commits, so a torn or interrupted cascade converges on retry (#46).
// Future upload flows should add receipt Storage object deletion here.
const deletedMemberName = 'Deleted member';
const deletedUserSentinel = 'deleted-user';
const defaultBatchLimit = 450;

// #46: test seam — lower via DELETE_ACCOUNT_BATCH_LIMIT to force a mid-group
// auto-flush with a handful of docs instead of 450+. Read at construction (not
// module load) so a test can set it before invoking the callable.
function resolveBatchLimit(): number {
  return Number(process.env.DELETE_ACCOUNT_BATCH_LIMIT) || defaultBatchLimit;
}

// #73: per-UID invocation rate limit (compensating control for soft App Check).
const DELETION_ATTEMPT_LIMIT = 5;
const DELETION_ATTEMPT_WINDOW_MS = 60 * 60 * 1000;

// #76: server-only marker recording an incomplete deletion, so the deletionReaper
// backstop can find and finish abandoned/timed-out deletions. Written while a
// deletion is incomplete, deleted once it converges. `expiresAt` drives a
// Firestore TTL safety net; the reaper normally deletes the marker on success.
const deletionAuditCollection = 'deletionAudit';
const defaultAuditTtlMs = 30 * 24 * 60 * 60 * 1000;

function resolveAuditTtlMs(): number {
  return Number(process.env.DELETE_ACCOUNT_AUDIT_TTL_MS) || defaultAuditTtlMs;
}

export interface DeleteAccountOutput {
  groupsProcessed: number;
  tombstoneIds: string[];
  expensesScrubbed: number;
  settlementsScrubbed: number;
  activityLogsScrubbed: number;
  membersDeleted: number;
  groupsOrphanedAndSoftDeleted: number;
  // #46: group ids (or 'fcm_tokens' / 'joinAttempts') whose scrub failed. While
  // non-empty, the Auth user is preserved and the callable THROWS so the client
  // (which discards the payload and only reacts to throw-vs-resolve) re-prompts.
  cascadeFailed: string[];
  fcmTokenDeleted: boolean;
  joinAttemptsDeleted: boolean;
  authUserDeleted: boolean;
}

interface GroupCascadeResult {
  tombstoneId: string;
  expensesScrubbed: number;
  settlementsScrubbed: number;
  activityLogsScrubbed: number;
  membersDeleted: number;
  groupOrphanedAndSoftDeleted: boolean;
  // True when the group was already scrubbed / no longer contains the uid /
  // vanished — a benign no-op, NOT a cascadeFailed.
  skipped: boolean;
}

class BatchWriter {
  private batch: WriteBatch;
  private writes = 0;
  private readonly limit: number;

  constructor(private readonly db: Firestore) {
    this.batch = db.batch();
    this.limit = resolveBatchLimit();
  }

  async set(ref: DocumentReference, data: DocumentData): Promise<void> {
    this.batch.set(ref, data);
    await this.afterWrite();
  }

  async update(ref: DocumentReference, data: DocumentData): Promise<void> {
    this.batch.update(ref, data);
    await this.afterWrite();
  }

  async delete(ref: DocumentReference): Promise<void> {
    this.batch.delete(ref);
    await this.afterWrite();
  }

  async flush(): Promise<void> {
    if (this.writes === 0) return;
    await this.batch.commit();
    this.batch = this.db.batch();
    this.writes = 0;
  }

  private async afterWrite(): Promise<void> {
    this.writes += 1;
    if (this.writes >= this.limit) {
      await this.flush();
    }
  }
}

function assertNoInput(data: unknown): void {
  if (data == null) return;
  if (typeof data === 'object' && !Array.isArray(data) && Object.keys(data).length === 0) {
    return;
  }
  throw new HttpsError('invalid-argument', 'deleteAccount does not accept input.');
}

function isTimestamp(value: unknown): value is Timestamp {
  return value instanceof Timestamp;
}

// #73: per-UID invocation rate limit. Counts EVERY invocation (success, no-op, or
// failure) and throttles before any cascade work, because a deleted user's
// unexpired ID token can still authenticate (the callable layer does not check
// revocation) — failure-counting would not bound replays. `expiresAt` drives a
// Firestore TTL so the counter doc (a short-lived pseudonymous marker keyed by UID,
// no profile data) self-reaps. The handler never mutates the counter again, so the
// deletion cascade and its error surface stay unchanged.
async function enforceDeletionRateLimit(db: Firestore, uid: string): Promise<void> {
  const ref = db.doc(`deletionAttempts/${uid}`);
  await db.runTransaction(async (tx) => {
    const now = Timestamp.now();
    const data = (await tx.get(ref)).data() ?? {};
    const windowStart = data.windowStart;
    const inWindow = isTimestamp(windowStart)
      && now.toMillis() - windowStart.toMillis() < DELETION_ATTEMPT_WINDOW_MS;
    const count = inWindow && typeof data.count === 'number' ? data.count : 0;
    if (count >= DELETION_ATTEMPT_LIMIT) {
      throw new HttpsError('resource-exhausted', 'Too many deletion attempts. Try again later.');
    }
    const nextWindowStart = inWindow ? (windowStart as Timestamp) : now;
    tx.set(ref, {
      count: count + 1,
      windowStart: nextWindowStart,
      expiresAt: Timestamp.fromMillis(nextWindowStart.toMillis() + DELETION_ATTEMPT_WINDOW_MS),
    }, { merge: true });
  });
}

// #46: deterministic so that re-processing a group on retry reuses the SAME
// tombstone identity (random ids accumulated a fresh "Deleted member" doc per
// retry, and diverged from the id already written into child docs). `taken`
// must include every existing member id (incl. existing tombstones) so we never
// overwrite a real member; on the (unrealistic, generated-UID) collision we add
// a deterministic suffix rather than falling back to randomness.
function deterministicTombstoneId(uid: string, taken: Set<string>): string {
  const base = `deleted-${createHash('sha1').update(uid).digest('hex').slice(0, 8)}`;
  if (!taken.has(base)) return base;
  for (let suffix = 2; ; suffix += 1) {
    const candidate = `${base}-${suffix}`;
    if (!taken.has(candidate)) return candidate;
  }
}

// #46: child name-string scrubbing needs the retiring member's display name. If
// the member doc is gone (corrupted group), fall back to the name embedded in an
// event's participantNames before giving up (uid-keyed scrubs still run either way).
function resolveOriginalName(
  oldMemberData: DocumentData | undefined,
  eventDocs: FirebaseFirestore.QueryDocumentSnapshot[],
  uid: string,
): string | undefined {
  const fromMember = findOriginalName(oldMemberData);
  if (fromMember) return fromMember;
  for (const eventDoc of eventDocs) {
    const names = eventDoc.data()?.participantNames;
    if (
      names && typeof names === 'object' && !Array.isArray(names)
      && typeof names[uid] === 'string' && (names[uid] as string).trim().length > 0
    ) {
      return names[uid] as string;
    }
  }
  return undefined;
}

function asStringArray(value: unknown, path: string): string[] {
  if (!Array.isArray(value) || value.some((entry) => typeof entry !== 'string')) {
    throw new HttpsError('failed-precondition', `${path} is malformed.`);
  }
  return value;
}

function timestampMillis(value: unknown): number {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'string') {
    const millis = Date.parse(value);
    return Number.isNaN(millis) ? Number.MAX_SAFE_INTEGER : millis;
  }
  return Number.MAX_SAFE_INTEGER;
}

function replaceUid(values: string[], uid: string, tombstoneId: string): {
  values: string[];
  changed: boolean;
} {
  let changed = false;
  const next: string[] = [];
  for (const value of values) {
    const replacement = value === uid ? tombstoneId : value;
    if (replacement !== value) changed = true;
    if (!next.includes(replacement)) next.push(replacement);
  }
  return { values: next, changed };
}

function rewriteString(value: unknown, originalName: string | undefined): unknown {
  if (typeof value !== 'string' || !originalName || originalName.length === 0) {
    return value;
  }
  return value.split(originalName).join(deletedMemberName);
}

function rewriteMetadata(value: unknown, uid: string, tombstoneId: string, originalName?: string): unknown {
  if (typeof value === 'string') {
    if (value === uid) return tombstoneId;
    return rewriteString(value, originalName);
  }
  if (Array.isArray(value)) {
    return value.map((entry) => rewriteMetadata(entry, uid, tombstoneId, originalName));
  }
  if (value && typeof value === 'object') {
    const next: Record<string, unknown> = {};
    for (const [key, entryValue] of Object.entries(value)) {
      const nextKey = key === uid ? tombstoneId : key;
      next[nextKey] = rewriteMetadata(entryValue, uid, tombstoneId, originalName);
    }
    return next;
  }
  return value;
}

function hasChanged(before: unknown, after: unknown): boolean {
  return JSON.stringify(before) !== JSON.stringify(after);
}

function renameMapKey(
  value: unknown,
  uid: string,
  tombstoneId: string,
  tombstoneValue: unknown,
): { value: Record<string, unknown>; changed: boolean } | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  const next: Record<string, unknown> = { ...(value as Record<string, unknown>) };
  if (!Object.prototype.hasOwnProperty.call(next, uid)) {
    return { value: next, changed: false };
  }
  next[tombstoneId] = tombstoneValue;
  delete next[uid];
  return { value: next, changed: true };
}

function findOriginalName(memberData: DocumentData | undefined): string | undefined {
  const displayName = memberData?.displayName;
  return typeof displayName === 'string' && displayName.trim().length > 0
    ? displayName
    : undefined;
}

function oldestRealMemberUid(
  members: Array<{ id: string; data: DocumentData }>,
  uid: string,
): string | null {
  const candidates = members
    .filter(({ data }) => data.userId !== uid && data.isTombstone !== true && data.isDeleted !== true)
    .sort((a, b) => timestampMillis(a.data.joinedAt) - timestampMillis(b.data.joinedAt));
  const first = candidates[0]?.data.userId;
  return typeof first === 'string' && first.length > 0 ? first : null;
}

function expenseUpdates(
  data: DocumentData,
  uid: string,
  tombstoneId: string,
): { updates: DocumentData; touched: boolean } {
  const updates: DocumentData = {};
  let touched = false;

  if (data.createdBy === uid) {
    updates.createdBy = deletedUserSentinel;
    touched = true;
  }
  if (data.payerParticipantId === uid) {
    updates.payerParticipantId = tombstoneId;
    touched = true;
  }
  if (Array.isArray(data.customSplitParticipants)) {
    const replaced = replaceUid(data.customSplitParticipants, uid, tombstoneId);
    if (replaced.changed) {
      updates.customSplitParticipants = replaced.values;
      touched = true;
    }
  }
  const distribution = renameMapKey(
    data.splitDistribution,
    uid,
    tombstoneId,
    (data.splitDistribution as Record<string, unknown> | undefined)?.[uid],
  );
  if (distribution?.changed) {
    updates.splitDistribution = distribution.value;
    touched = true;
  }

  if (touched) {
    updates.receiptUrl = null;
    updates.note = null;
    updates.description = null;
  }
  return { updates, touched };
}

function settlementUpdates(
  data: DocumentData,
  uid: string,
  tombstoneId: string,
): { updates: DocumentData; touched: boolean } {
  const updates: DocumentData = {};
  let touched = false;

  if (data.createdBy === uid) {
    updates.createdBy = deletedUserSentinel;
    touched = true;
  }
  if (data.payerParticipantId === uid) {
    updates.payerParticipantId = tombstoneId;
    updates.payerName = deletedMemberName;
    touched = true;
  }
  if (data.recipientParticipantId === uid) {
    updates.recipientParticipantId = tombstoneId;
    updates.recipientName = deletedMemberName;
    touched = true;
  }
  if (touched) {
    updates.note = null;
  }
  return { updates, touched };
}

function activityUpdates(
  data: DocumentData,
  uid: string,
  tombstoneId: string,
  originalName: string | undefined,
  eventScoped: boolean,
): { updates: DocumentData; touched: boolean } {
  const updates: DocumentData = {};
  let touched = false;
  const actorMatched = data.actorId === uid;

  if (actorMatched) {
    updates.actorId = tombstoneId;
    updates.actorName = deletedMemberName;
    touched = true;
  }
  if (eventScoped && data.targetParticipantId === uid) {
    updates.targetParticipantId = tombstoneId;
    touched = true;
  }

  for (const field of eventScoped ? ['logText'] : ['description']) {
    const rewritten = rewriteString(data[field], originalName);
    if (rewritten !== data[field]) {
      updates[field] = rewritten;
      touched = true;
    } else if (actorMatched && typeof data[field] === 'string') {
      updates[field] = `${deletedMemberName} activity`;
    }
  }

  const metadata = rewriteMetadata(data.metadata, uid, tombstoneId, originalName);
  if (hasChanged(data.metadata, metadata)) {
    updates.metadata = metadata;
    touched = true;
  }

  return { updates, touched };
}

async function processSettlementsCollection(
  writer: BatchWriter,
  collectionRef: FirebaseFirestore.CollectionReference,
  uid: string,
  tombstoneId: string,
): Promise<number> {
  const snap = await collectionRef.get();
  let scrubbed = 0;
  for (const doc of snap.docs) {
    const { updates, touched } = settlementUpdates(doc.data(), uid, tombstoneId);
    if (touched) {
      await writer.update(doc.ref, updates);
      scrubbed += 1;
    }
  }
  return scrubbed;
}

function skippedGroup(): GroupCascadeResult {
  return {
    tombstoneId: '',
    expensesScrubbed: 0,
    settlementsScrubbed: 0,
    activityLogsScrubbed: 0,
    membersDeleted: 0,
    groupOrphanedAndSoftDeleted: false,
    skipped: true,
  };
}

// #46: scrub one group in two phases. Phase B stages all child-doc scrubs into a
// per-group batch and flushes; Phase C retires the member identity inside a
// transaction. Critically, NONE of the three identity-visibility writes (tombstone
// member, old-member delete, group memberIds removal) land before Phase B is durable
// — so a torn/interrupted Phase B leaves the group query-visible, the old member doc
// intact (display name still resolvable), and no partial tombstone (retry reuses the
// same deterministic id). On any throw the handler isolates this group into
// cascadeFailed without aborting the others.
async function processGroup(
  db: Firestore,
  groupRef: DocumentReference,
  uid: string,
): Promise<GroupCascadeResult> {
  // ---- Phase A: reads + deterministic identity ----
  const groupSnap = await groupRef.get();
  if (!groupSnap.exists) return skippedGroup();
  const groupData = groupSnap.data() ?? {};
  const memberIds = asStringArray(groupData.memberIds, `groups/${groupRef.id}.memberIds`);
  if (!memberIds.includes(uid)) return skippedGroup();

  const membersSnap = await groupRef.collection('members').get();
  const taken = new Set<string>([...memberIds, ...membersSnap.docs.map((doc) => doc.id)]);
  taken.delete(uid);
  const tombstoneId = deterministicTombstoneId(uid, taken);

  const oldMemberData = membersSnap.docs.find((doc) => doc.id === uid)?.data();
  const eventsSnap = await groupRef.collection('events').get();
  const originalName = resolveOriginalName(oldMemberData, eventsSnap.docs, uid);

  // ---- Phase B: idempotent child scrubs (batched, may span auto-flushes) ----
  const writer = new BatchWriter(db);
  let expensesScrubbed = 0;
  let settlementsScrubbed = 0;
  let activityLogsScrubbed = 0;

  for (const eventDoc of eventsSnap.docs) {
    const eventData = eventDoc.data();
    const eventUpdate: DocumentData = {};
    if (Array.isArray(eventData.participantIds)) {
      const replaced = replaceUid(eventData.participantIds, uid, tombstoneId);
      if (replaced.changed) eventUpdate.participantIds = replaced.values;
    }
    // Full-map rewrite (idempotent on retry). A dotted-key/FieldPath merge would
    // be marginally safer against a concurrent edit to THIS event, but tombstone
    // ids and uids contain hyphens (illegal in dotted field paths without
    // FieldPath escaping), and the concurrent-event-edit race during the owner's
    // own deletion is a low-severity, documented residual (same class as expenses).
    const participantNames = renameMapKey(
      eventData.participantNames,
      uid,
      tombstoneId,
      deletedMemberName,
    );
    if (participantNames?.changed) {
      eventUpdate.participantNames = participantNames.value;
    }
    if (eventData.createdBy === uid) {
      eventUpdate.createdBy = deletedUserSentinel;
    }
    if (Object.keys(eventUpdate).length > 0) {
      eventUpdate.updatedAt = FieldValue.serverTimestamp();
      await writer.update(eventDoc.ref, eventUpdate);
    }

    const expensesSnap = await eventDoc.ref.collection('expenses').get();
    for (const expenseDoc of expensesSnap.docs) {
      const { updates, touched } = expenseUpdates(expenseDoc.data(), uid, tombstoneId);
      if (touched) {
        await writer.update(expenseDoc.ref, updates);
        expensesScrubbed += 1;
      }
    }

    settlementsScrubbed += await processSettlementsCollection(
      writer,
      eventDoc.ref.collection('settlements'),
      uid,
      tombstoneId,
    );

    const eventActivitySnap = await eventDoc.ref.collection('activity_logs').get();
    for (const activityDoc of eventActivitySnap.docs) {
      const { updates, touched } = activityUpdates(
        activityDoc.data(),
        uid,
        tombstoneId,
        originalName,
        true,
      );
      if (touched) {
        await writer.update(activityDoc.ref, updates);
        activityLogsScrubbed += 1;
      }
    }
  }

  settlementsScrubbed += await processSettlementsCollection(
    writer,
    groupRef.collection('settlements'),
    uid,
    tombstoneId,
  );

  const groupActivitySnap = await groupRef.collection('activity').get();
  for (const activityDoc of groupActivitySnap.docs) {
    const { updates, touched } = activityUpdates(
      activityDoc.data(),
      uid,
      tombstoneId,
      originalName,
      false,
    );
    if (touched) {
      await writer.update(activityDoc.ref, updates);
      activityLogsScrubbed += 1;
    }
  }

  await writer.flush();

  // ---- Phase C: transactional identity retirement (after B is durable) ----
  const retired = await db.runTransaction(async (tx) => {
    const gSnap = await tx.get(groupRef);
    if (!gSnap.exists) return { membersDeleted: 0, orphaned: false, applied: false };
    const gData = gSnap.data() ?? {};
    const currentMemberIds = asStringArray(gData.memberIds, `groups/${groupRef.id}.memberIds`);
    if (!currentMemberIds.includes(uid)) {
      return { membersDeleted: 0, orphaned: false, applied: false };
    }

    const membersTxSnap = await tx.get(groupRef.collection('members'));
    const members = membersTxSnap.docs.map((doc) => ({ id: doc.id, data: doc.data() }));
    const tombstoneClash = members.find((m) => m.id === tombstoneId);
    if (tombstoneClash && tombstoneClash.data.isTombstone !== true) {
      throw new HttpsError(
        'failed-precondition',
        `tombstone id ${tombstoneId} collides with a real member of ${groupRef.id}.`,
      );
    }
    const oldTxMember = members.find((m) => m.id === uid)?.data;
    const remainingRealCreator = oldestRealMemberUid(members, uid);
    const hasRealSurvivor = remainingRealCreator != null;

    const groupUpdate: DocumentData = {
      memberIds: replaceUid(currentMemberIds, uid, tombstoneId).values,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (gData.createdBy === uid) {
      groupUpdate.createdBy = remainingRealCreator ?? deletedUserSentinel;
    }
    if (!hasRealSurvivor) {
      groupUpdate.createdBy = deletedUserSentinel;
      groupUpdate.isDeleted = true;
      groupUpdate.deletedAt = FieldValue.serverTimestamp();
    }

    tx.set(groupRef.collection('members').doc(tombstoneId), {
      id: tombstoneId,
      userId: tombstoneId,
      displayName: deletedMemberName,
      role: 'MEMBER',
      joinedAt: oldTxMember?.joinedAt ?? gData.createdAt ?? FieldValue.serverTimestamp(),
      isShadow: oldTxMember?.isShadow === true,
      isTombstone: true,
    });
    tx.delete(groupRef.collection('members').doc(uid));
    tx.update(groupRef, groupUpdate);

    return { membersDeleted: oldTxMember ? 1 : 0, orphaned: !hasRealSurvivor, applied: true };
  });

  return {
    tombstoneId,
    expensesScrubbed,
    settlementsScrubbed,
    activityLogsScrubbed,
    membersDeleted: retired.membersDeleted,
    groupOrphanedAndSoftDeleted: retired.orphaned,
    skipped: !retired.applied,
  };
}

async function deleteDocIfExists(ref: DocumentReference): Promise<boolean> {
  const snap = await ref.get();
  if (!snap.exists) return false;
  await ref.delete();
  return true;
}

// #76: upsert the deletionAudit marker for an incomplete deletion. Preserves
// `firstFailedAt` across attempts, bumps `attemptCount`, refreshes `lastAttemptAt`
// + the TTL `expiresAt`. `attemptCount` is observability-only (best-effort under a
// reaper-vs-client overlap); the reaper does not depend on it or on `cascadeFailed`
// (it re-queries every group still containing the uid).
async function writeDeletionAuditMarker(
  db: Firestore,
  uid: string,
  cascadeFailed: string[],
): Promise<void> {
  const ref = db.doc(`${deletionAuditCollection}/${uid}`);
  await db.runTransaction(async (tx) => {
    const now = Timestamp.now();
    const prev = (await tx.get(ref)).data();
    const firstFailedAt = prev && isTimestamp(prev.firstFailedAt) ? prev.firstFailedAt : now;
    const attemptCount = prev && typeof prev.attemptCount === 'number' ? prev.attemptCount : 0;
    tx.set(ref, {
      uid,
      status: 'failed',
      cascadeFailed,
      firstFailedAt,
      lastAttemptAt: now,
      attemptCount: attemptCount + 1,
      expiresAt: Timestamp.fromMillis(now.toMillis() + resolveAuditTtlMs()),
    });
  });
}

// #76: shared per-uid deletion cascade, called by BOTH the deleteAccount callable
// and the deletionReaper scheduled backstop. Revokes refresh tokens, scrubs every
// group + global identity residue, deletes the Auth user when the scrub is clean,
// and manages the `deletionAudit/{uid}` marker. It does NOT throw for the two
// EXPECTED incomplete outcomes (partialCascade / authDeleteFailed) — it returns
// `complete:false` + `failureKind` so the reaper can inspect the result; the
// onCall wrapper translates those into the #46 client-facing throws.
export interface CascadeRunResult {
  output: DeleteAccountOutput;
  complete: boolean;
  failureKind: 'none' | 'partialCascade' | 'authDeleteFailed';
}

export async function runAccountDeletionCascade(
  db: Firestore,
  uid: string,
): Promise<CascadeRunResult> {
  // #76: revoke refresh tokens up front so a user preserved by a partial failure
  // cannot mint a new ID token. Best-effort — erasure must not be blocked by a
  // hardening step, and `auth/user-not-found` (the reaper re-running an
  // already-gone user) is benign. This BOUNDS the post-partial-failure replay
  // window to one ID-token lifetime (<=1h); it does NOT retroactively invalidate
  // an outstanding ID token (rules/callables do not check revocation — see the
  // enforceDeletionRateLimit comment). The eventual full closure is deleteUser.
  try {
    await getAuth().revokeRefreshTokens(uid);
  } catch (error) {
    logger.warn('deleteAccount revokeRefreshTokens failed (continuing)', {
      uid,
      code: (error as { code?: unknown }).code,
    });
  }

  const cascadeFailed: string[] = [];
  const output: DeleteAccountOutput = {
    groupsProcessed: 0,
    tombstoneIds: [],
    expensesScrubbed: 0,
    settlementsScrubbed: 0,
    activityLogsScrubbed: 0,
    membersDeleted: 0,
    groupsOrphanedAndSoftDeleted: 0,
    cascadeFailed,
    fcmTokenDeleted: false,
    joinAttemptsDeleted: false,
    authUserDeleted: false,
  };

  const groupsSnap = await db.collection('groups')
    .where('memberIds', 'array-contains', uid)
    .get();

  // #46: isolate per group. One group failing (transient Firestore error,
  // a Phase C transaction conflict, malformed data) must NOT abort the others
  // or reach the Auth-delete gate.
  for (const groupDoc of groupsSnap.docs) {
    try {
      const result = await processGroup(db, groupDoc.ref, uid);
      output.groupsProcessed += 1;
      if (result.skipped) {
        // uid raced out of memberIds between the query and Phase A/C re-read.
        logger.info('deleteAccount group skipped (uid no longer a member)', {
          uid,
          groupId: groupDoc.id,
        });
        continue;
      }
      output.tombstoneIds.push(result.tombstoneId);
      output.expensesScrubbed += result.expensesScrubbed;
      output.settlementsScrubbed += result.settlementsScrubbed;
      output.activityLogsScrubbed += result.activityLogsScrubbed;
      output.membersDeleted += result.membersDeleted;
      if (result.groupOrphanedAndSoftDeleted) {
        output.groupsOrphanedAndSoftDeleted += 1;
      }
      logger.info('deleteAccount group scrubbed', {
        uid,
        groupId: groupDoc.id,
        tombstoneId: result.tombstoneId,
      });
    } catch (error) {
      cascadeFailed.push(groupDoc.id);
      logger.error('deleteAccount group failed', {
        uid,
        groupId: groupDoc.id,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  // #46: scrub identity residue before the Auth-delete gate, and fold these
  // failures into cascadeFailed too (mirrors cleanupAnonUidArtifacts).
  try {
    output.fcmTokenDeleted = await deleteDocIfExists(db.doc(`fcm_tokens/${uid}`));
  } catch (error) {
    cascadeFailed.push('fcm_tokens');
    logger.error('deleteAccount fcm token delete failed', {
      uid,
      error: error instanceof Error ? error.message : String(error),
    });
  }
  try {
    output.joinAttemptsDeleted = await deleteDocIfExists(db.doc(`joinAttempts/${uid}`));
  } catch (error) {
    cascadeFailed.push('joinAttempts');
    logger.error('deleteAccount join attempts delete failed', {
      uid,
      error: error instanceof Error ? error.message : String(error),
    });
  }

  // #76: classify the outcome. `auth/user-not-found` is NOT a failure — the
  // user is gone, which is exactly the goal (a prior attempt finished, or the
  // reaper re-ran a completed deletion). Only a REAL auth error is incomplete.
  let failureKind: CascadeRunResult['failureKind'] = 'none';
  if (cascadeFailed.length > 0) {
    // #46: any scrub failed → preserve the Auth user (the still-valid session
    // can retry; the cascade is idempotent + convergent). deleteUser is not
    // attempted.
    failureKind = 'partialCascade';
  } else {
    try {
      await getAuth().deleteUser(uid);
      output.authUserDeleted = true;
    } catch (error) {
      if ((error as { code?: unknown }).code === 'auth/user-not-found') {
        output.authUserDeleted = false;
      } else {
        logger.error('deleteAccount auth delete failed after cascade', {
          uid,
          output,
          error: error instanceof Error ? error.message : String(error),
        });
        failureKind = 'authDeleteFailed';
      }
    }
  }

  // #76: the marker is the reaper's input. Write/refresh it while incomplete;
  // delete it once the deletion converges (incl. a torn prior marker on success).
  const complete = failureKind === 'none';
  if (complete) {
    await deleteDocIfExists(db.doc(`${deletionAuditCollection}/${uid}`));
  } else {
    await writeDeletionAuditMarker(db, uid, cascadeFailed);
  }

  return { output, complete, failureKind };
}

export const deleteAccount = onCall<unknown, Promise<DeleteAccountOutput>>(
  // #46: bump timeout + memory so the per-group cascade has 9 min of
  // headroom on accounts with many groups (default callable timeout is
  // 60s; default memory 256MiB).
  // #73: soft App Check (verify-if-present, do not hard-reject) so deletion — a
  // self-scoped GDPR-erasure action (UID from request.auth only; see assertNoInput)
  // — works on attestation-failing devices (Play Integrity failure / no Play
  // Services / MDM). enforceDeletionRateLimit is the compensating control.
  { enforceAppCheck: false, timeoutSeconds: 540, memory: '1GiB' },
  async (request: CallableRequest<unknown>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }

    const uid = request.auth.uid;
    const db = getFirestore();
    // #73: throttle before assertNoInput + cascade so malformed and replayed
    // authenticated calls are both counted.
    await enforceDeletionRateLimit(db, uid);
    assertNoInput(request.data);

    const { output, failureKind } = await runAccountDeletionCascade(db, uid);

    // #46: the client discards the payload and reacts only to throw-vs-resolve, so
    // an incomplete deletion MUST throw to deny sign-out and re-prompt. Messages +
    // codes are preserved byte-for-byte across the #76 core extraction.
    if (failureKind === 'partialCascade') {
      logger.error('deleteAccount partial cascade; auth user preserved for retry', {
        uid,
        cascadeFailed: output.cascadeFailed,
      });
      throw new HttpsError(
        'internal',
        'Account deletion did not finish; please try again.',
        output,
      );
    }
    if (failureKind === 'authDeleteFailed') {
      throw new HttpsError(
        'internal',
        'Account data was scrubbed, but the Auth user could not be deleted.',
        output,
      );
    }

    return output;
  },
);
