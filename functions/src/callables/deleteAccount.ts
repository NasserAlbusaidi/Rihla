import { getAuth } from 'firebase-admin/auth';
import {
  DocumentData,
  DocumentReference,
  FieldValue,
  Firestore,
  Timestamp,
  getFirestore,
} from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import { createHash } from 'crypto';
import '../admin';
import { BatchWriter } from './shared/batchWriter';
import { mergeUidMapKey, replaceUid, renameMapKey } from './shared/mapReKey';

// Server-side account deletion cascade. Each group is scrubbed in two phases:
// (B) idempotent child-doc scrubs (events/expenses/settlements/activity) staged
// into a per-group BatchWriter, then (C) a transactional identity retirement
// (tombstone member + old-member delete + memberIds/createdBy/orphan update).
// The group stays visible to the `memberIds array-contains uid` retry query
// until C commits, so a torn or interrupted cascade converges on retry (#46).
// Future upload flows should add receipt Storage object deletion here.
const deletedMemberName = 'Deleted member';
const deletedUserSentinel = 'deleted-user';

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
function tombstoneBaseId(uid: string): string {
  return `deleted-${createHash('sha1').update(uid).digest('hex').slice(0, 8)}`;
}

function deterministicTombstoneId(uid: string, taken: Set<string>): string {
  const base = tombstoneBaseId(uid);
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

function rewriteString(value: unknown, originalName: string | undefined): unknown {
  if (typeof value !== 'string' || !originalName || originalName.length === 0) {
    return value;
  }
  return value.split(originalName).join(deletedMemberName);
}

function rewriteMetadata(value: unknown, uid: string, tombstoneId: string, originalName?: string): unknown {
  if (typeof value === 'string') {
    return rewriteString(value.split(uid).join(tombstoneId), originalName);
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
  originalName?: string,
): { updates: DocumentData; touched: boolean } {
  const updates: DocumentData = {};
  let touched = false;

  if (data.createdBy === uid) {
    updates.createdBy = deletedUserSentinel;
    touched = true;
  }
  if (data.lastEditedBy === uid) {
    updates.lastEditedBy = deletedUserSentinel;
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
  // #1099: SUM on collision, never OVERWRITE. On a re-scrub of a re-joined member,
  // one expense can hold BOTH the prior-pass tombstone T and the re-added uid U in
  // splitDistribution; renameMapKey would set T=U's value and DROP T's slice
  // (conservation broken). mergeUidMapKey sums to T=T+U. With an absent target key
  // it behaves identically to renameMapKey, so first scrubs are unchanged (#710).
  // Scope: splitDistribution ONLY — settlement scalar fields and participantNames
  // (a NAME map, re-keyed by renameMapKey below) stay on their existing re-keyers.
  const distribution = mergeUidMapKey(data.splitDistribution, uid, tombstoneId);
  if (distribution?.changed) {
    updates.splitDistribution = distribution.value;
    touched = true;
  }
  const splitExplanation = rewriteMetadata(data.splitExplanation, uid, tombstoneId, originalName);
  if (hasChanged(data.splitExplanation, splitExplanation)) {
    updates.splitExplanation = splitExplanation;
    touched = true;
  }

  if (touched) {
    updates.receiptUrl = null;
    updates.note = null;
    updates.description = null;
    updates.deleteAccountScrubAt = FieldValue.serverTimestamp();
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

async function acquireAccountDeletionGroupMarker(
  db: Firestore,
  groupRef: DocumentReference,
  uid: string,
): Promise<boolean> {
  const auditRef = db.doc(`${deletionAuditCollection}/${uid}`);
  return db.runTransaction(async (tx) => {
    const now = Timestamp.now();
    const groupSnap = await tx.get(groupRef);
    const auditSnap = await tx.get(auditRef);
    if (!groupSnap.exists) return false;
    const groupData = groupSnap.data() ?? {};
    const memberIds = asStringArray(groupData.memberIds, `groups/${groupRef.id}.memberIds`);
    if (!memberIds.includes(uid)) return false;
    if (
      groupData.deletingInProgress === true
      || groupData.claimingInProgress === true
      // #1144: the tombstone re-key rewrites oracle inputs — mutually
      // exclusive with a departure's recompute window.
      || groupData.departureInProgress === true
      || (
        groupData.accountDeletionInProgress === true
        && groupData.accountDeletionUid !== uid
      )
    ) {
      throw new HttpsError('aborted', 'Group is temporarily locked.');
    }
    const auditData = auditSnap.data() ?? {};
    const firstFailedAt = auditData.firstFailedAt instanceof Timestamp
      ? auditData.firstFailedAt
      : now;
    const attemptCount = typeof auditData.attemptCount === 'number'
      ? auditData.attemptCount
      : 0;
    tx.set(auditRef, {
      uid,
      status: 'failed',
      cascadeFailed: FieldValue.arrayUnion(groupRef.id),
      firstFailedAt,
      lastAttemptAt: now,
      attemptCount: attemptCount + 1,
      expiresAt: Timestamp.fromMillis(now.toMillis() + resolveAuditTtlMs()),
    }, { merge: true });
    tx.update(groupRef, {
      accountDeletionInProgress: true,
      accountDeletionUid: uid,
      accountDeletionLockedAt: now,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

// #714 P1 #4: clear the accountDeletion freeze this uid acquired. Guarded on
// accountDeletionUid===uid so it never clears a different uid's deletion (or a
// re-acquired marker for a different run); a same-uid deletionReaper overlap is
// benign (both converge). Phase C clears the freeze itself on the applied happy
// path — this covers every OTHER exit (Phase A/B/C throw, Phase A skip, Phase C
// no-op) so an interrupted cascade never leaves the group write-frozen.
async function releaseAccountDeletionGroupMarker(
  db: Firestore,
  groupRef: DocumentReference,
  uid: string,
): Promise<void> {
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(groupRef);
    if (!snap.exists) return;
    const data = snap.data() ?? {};
    if (data.accountDeletionInProgress === true && data.accountDeletionUid === uid) {
      tx.update(groupRef, {
        accountDeletionInProgress: FieldValue.delete(),
        accountDeletionUid: FieldValue.delete(),
        accountDeletionLockedAt: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  });
}

// #46: scrub one group in two phases. Phase B stages all child-doc scrubs into a
// per-group batch and flushes; Phase C retires the member identity inside a
// transaction. Critically, NONE of the three identity-visibility writes (tombstone
// member, old-member delete, group memberIds removal) land before Phase B is durable
// — so a torn/interrupted Phase B leaves the group query-visible, the old member doc
// intact (display name still resolvable), and no partial tombstone (retry reuses the
// same deterministic id). On any throw the handler isolates this group into
// cascadeFailed without aborting the others.
//
// #714 P1 #4: `processGroup` wraps this so the accountDeletion freeze is released on
// every failure/skip exit; this inner body runs AFTER the marker is acquired.
async function cascadeGroupAfterMarker(
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
  // #1099: on a re-scrub of a re-joined group, the base deterministic tombstone id is
  // already occupied by THIS uid's tombstone from a prior pass/run — REUSE it (drop it
  // from `taken`) instead of minting deleted-<hash>-2. A genuine collision with a REAL
  // member (occupant not a tombstone) still advances the suffix (pinned by the
  // deterministic-id collision test). Ownership caveat (inherited, ~2^-32): a same-group
  // sha1-prefix collision between two DIFFERENT deleted uids would merge their anonymized
  // "Deleted member" ledgers under reuse — the class already accepted by this hash.
  const baseTombstoneId = tombstoneBaseId(uid);
  const baseOccupant = membersSnap.docs.find((doc) => doc.id === baseTombstoneId);
  if (baseOccupant?.data().isTombstone === true) {
    taken.delete(baseTombstoneId);
  }
  const tombstoneId = deterministicTombstoneId(uid, taken);

  // #294/#524: match the deleted user's member doc by the `userId` FIELD,
  // never the doc id. New client-created creator docs are uid-keyed, but
  // legacy creator docs may still be uuid-keyed, so doc.id===uid is not enough.
  const oldMemberData = membersSnap.docs.find((doc) => doc.data().userId === uid)?.data();
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
      const { updates, touched } = expenseUpdates(
        expenseDoc.data(),
        uid,
        tombstoneId,
        originalName,
      );
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
    // #294/#524: match by the `userId` FIELD. Delete ALL matched docs (mirrors
    // leaveGroup); realistically one per userId, but legacy duplicates are
    // cleaned up too.
    const oldTxMembers = members.filter((m) => m.data.userId === uid);
    const oldTxMember = oldTxMembers[0]?.data;
    const remainingRealCreator = oldestRealMemberUid(members, uid);
    const hasRealSurvivor = remainingRealCreator != null;

    const groupUpdate: DocumentData = {
      memberIds: replaceUid(currentMemberIds, uid, tombstoneId).values,
      accountDeletionInProgress: FieldValue.delete(),
      accountDeletionUid: FieldValue.delete(),
      accountDeletionLockedAt: FieldValue.delete(),
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
    for (const m of oldTxMembers) {
      tx.delete(groupRef.collection('members').doc(m.id));
    }
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

// #714 P1 #4: acquire the accountDeletion freeze, run the cascade, and GUARANTEE the
// freeze is released on every exit. Phase C clears it on the applied happy path; a
// throw (Phase B torn batch, Phase C conflict) or a skip (group vanished / uid raced
// out / Phase C no-op) would otherwise leave the group write-frozen for innocent
// co-members until the same uid's deletionReaper converges (24h) — so we release here.
async function processGroup(
  db: Firestore,
  groupRef: DocumentReference,
  uid: string,
): Promise<GroupCascadeResult> {
  const acquired = await acquireAccountDeletionGroupMarker(db, groupRef, uid);
  if (!acquired) return skippedGroup();

  let result: GroupCascadeResult;
  try {
    result = await cascadeGroupAfterMarker(db, groupRef, uid);
  } catch (error) {
    await releaseAccountDeletionGroupMarker(db, groupRef, uid).catch((releaseError) => {
      logger.error('deleteAccount: accountDeletion freeze release after group failure also failed', {
        uid,
        groupId: groupRef.id,
        error: releaseError instanceof Error ? releaseError.message : String(releaseError),
      });
    });
    throw error;
  }
  if (result.skipped) {
    await releaseAccountDeletionGroupMarker(db, groupRef, uid);
  }
  return result;
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
    const prevCascadeFailed = Array.isArray(prev?.cascadeFailed)
      ? prev.cascadeFailed.filter((entry): entry is string => typeof entry === 'string')
      : [];
    const alreadyMarkedThisAttempt =
      cascadeFailed.length > 0
      && cascadeFailed.some((entry) => prevCascadeFailed.includes(entry));
    tx.set(ref, {
      uid,
      status: 'failed',
      cascadeFailed,
      firstFailedAt,
      lastAttemptAt: alreadyMarkedThisAttempt && isTimestamp(prev?.lastAttemptAt)
        ? prev.lastAttemptAt
        : now,
      attemptCount: alreadyMarkedThisAttempt ? attemptCount : attemptCount + 1,
      expiresAt: Timestamp.fromMillis(now.toMillis() + resolveAuditTtlMs()),
    });
  });
}

function addCascadeFailure(cascadeFailed: string[], id: string): void {
  if (!cascadeFailed.includes(id)) cascadeFailed.push(id);
}

async function scrubClaimStateForDeletingUid(
  db: Firestore,
  uid: string,
  cascadeFailed: string[],
): Promise<void> {
  const requests = await db.collectionGroup('claimRequests')
    .where('requesterUid', '==', uid)
    .get();
  for (const doc of requests.docs) {
    const groupId = doc.ref.parent.parent?.id ?? 'claimRequests';
    const data = doc.data();
    if (data.status === 'claiming') {
      addCascadeFailure(cascadeFailed, groupId);
      continue;
    }
    try {
      await doc.ref.delete();
    } catch (error) {
      addCascadeFailure(cascadeFailed, groupId);
      logger.error('deleteAccount claim request delete failed', {
        uid,
        groupId,
        requestId: doc.id,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  const locks = await db.collectionGroup('claimShadowLocks')
    .where('claimerUid', '==', uid)
    .get();
  for (const doc of locks.docs) {
    addCascadeFailure(cascadeFailed, doc.ref.parent.parent?.id ?? 'claimShadowLocks');
  }
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

  // #714 P1 #1: scrubClaimStateForDeletingUid runs two collectionGroup queries that
  // need COLLECTION_GROUP indexes (added in firestore.indexes.json). Wrap it like the
  // fcm_tokens/joinAttempts deletes below so a query failure (missing index, transient)
  // degrades to partialCascade — auth user preserved, retryable — instead of aborting
  // the whole cascade BEFORE the Auth-delete gate for every user (incl. zero-claim ones).
  try {
    await scrubClaimStateForDeletingUid(db, uid, cascadeFailed);
  } catch (error) {
    if (!cascadeFailed.includes('claimState')) cascadeFailed.push('claimState');
    logger.error('deleteAccount claim-state scrub failed', {
      uid,
      error: error instanceof Error ? error.message : String(error),
    });
  }

  // #46: scrub identity residue before the Auth-delete gate, and fold these
  // failures into cascadeFailed too.
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

  // #1099: a membership created concurrently DURING this cascade — a join
  // (joinGroupByInviteCode is re-enabled the moment Phase C clears the accountDeletion
  // freeze) or a creator-approved claim (claimShadow re-adds requesterUid to memberIds)
  // landing after the S0 snapshot at the top of this function — would otherwise be a
  // permanent ghost: the S0 loop never saw it, and a clean run writes NO deletionAudit
  // marker, so the reaper never revisits it. Re-query the same arrayContains set and
  // (re-)process anything still holding a live membership, bounded to 3 passes.
  //
  // Placed LAST — after the claim/fcm/joinAttempts scrubs above — ON PURPOSE: those
  // scrubs take several round-trips, and a claim/join committing during THAT window
  // must be caught by the final check below, not slip behind an early-placed gate.
  // The re-query is AUTHORITATIVE (no exclude-set): a successfully-scrubbed group drops
  // out of the arrayContains result by construction (Phase C removes the uid), so any
  // group it returns currently holds a live membership; a monotonic processed-set would
  // wrongly skip a RE-joined group. Groups already in cascadeFailed this run stay the
  // reaper's job (they already block the gate) — re-processing them would self-heal the
  // bounded failure injections the partial-cascade tests rely on.
  for (let pass = 0; pass < 3; pass += 1) {
    let requery: FirebaseFirestore.QuerySnapshot;
    try {
      requery = await db.collection('groups')
        .where('memberIds', 'array-contains', uid)
        .get();
    } catch (error) {
      // Degrade like the claim/fcm/joinAttempts blocks: block the gate + write the
      // marker rather than throw out markerless (the reaper would never converge).
      addCascadeFailure(cascadeFailed, 'requeryUnavailable');
      logger.error('deleteAccount membership re-query failed', {
        uid,
        pass,
        error: error instanceof Error ? error.message : String(error),
      });
      break;
    }
    const fresh = requery.docs.filter((groupDoc) => !cascadeFailed.includes(groupDoc.id));
    if (fresh.length === 0) break;
    for (const groupDoc of fresh) {
      try {
        const result = await processGroup(db, groupDoc.ref, uid);
        output.groupsProcessed += 1;
        if (result.skipped) {
          logger.info('deleteAccount re-query group skipped (uid no longer a member)', {
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
        logger.info('deleteAccount re-query group scrubbed', {
          uid,
          groupId: groupDoc.id,
          tombstoneId: result.tombstoneId,
        });
      } catch (error) {
        addCascadeFailure(cascadeFailed, groupDoc.id);
        logger.error('deleteAccount re-query group failed', {
          uid,
          groupId: groupDoc.id,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }
  }

  // #1099: FINAL authoritative check. Anything STILL holding a live membership and not
  // already in cascadeFailed goes to cascadeFailed — the gate then preserves the auth
  // user, the marker is written, and the 24h deletionReaper re-runs this cascade to
  // convergence (its marker's group list is observability-only). Wrapped so a transient
  // query failure degrades (blocks the gate) rather than throwing out markerless.
  try {
    const finalCheck = await db.collection('groups')
      .where('memberIds', 'array-contains', uid)
      .get();
    for (const groupDoc of finalCheck.docs) addCascadeFailure(cascadeFailed, groupDoc.id);
  } catch (error) {
    addCascadeFailure(cascadeFailed, 'requeryUnavailable');
    logger.error('deleteAccount final membership check failed', {
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
