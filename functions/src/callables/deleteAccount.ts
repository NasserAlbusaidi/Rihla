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

const deletedMemberName = 'Deleted member';
const deletedUserSentinel = 'deleted-user';
const batchLimit = 450;

export interface DeleteAccountOutput {
  groupsProcessed: number;
  tombstoneIds: string[];
  expensesScrubbed: number;
  settlementsScrubbed: number;
  activityLogsScrubbed: number;
  membersDeleted: number;
  groupsOrphanedAndSoftDeleted: number;
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
}

class BatchWriter {
  private batch: WriteBatch;
  private writes = 0;

  constructor(private readonly db: Firestore) {
    this.batch = db.batch();
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
    if (this.writes >= batchLimit) {
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

function generateTombstoneId(): string {
  const value = Math.floor(Math.random() * 36 ** 8)
    .toString(36)
    .padStart(8, '0');
  return `deleted-${value}`;
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
      updates[field] = eventScoped ? `${deletedMemberName} activity` : `${deletedMemberName} activity`;
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

async function processGroup(
  db: Firestore,
  writer: BatchWriter,
  groupRef: DocumentReference,
  uid: string,
): Promise<GroupCascadeResult> {
  const groupSnap = await groupRef.get();
  if (!groupSnap.exists) {
    throw new HttpsError('not-found', `Group ${groupRef.id} no longer exists.`);
  }

  const groupData = groupSnap.data() ?? {};
  const memberIds = asStringArray(groupData.memberIds, `groups/${groupRef.id}.memberIds`);
  if (!memberIds.includes(uid)) {
    throw new HttpsError('failed-precondition', `groups/${groupRef.id} no longer contains uid.`);
  }

  let tombstoneId = generateTombstoneId();
  while (memberIds.includes(tombstoneId)) {
    tombstoneId = generateTombstoneId();
  }

  const membersSnap = await groupRef.collection('members').get();
  const members = membersSnap.docs.map((doc) => ({ id: doc.id, data: doc.data() }));
  const oldMemberRef = groupRef.collection('members').doc(uid);
  const oldMemberSnap = membersSnap.docs.find((doc) => doc.id === uid);
  const oldMemberData = oldMemberSnap?.data();
  const originalName = findOriginalName(oldMemberData);
  const remainingRealCreator = oldestRealMemberUid(members, uid);
  const hasRealSurvivor = remainingRealCreator != null;
  const replacedMemberIds = replaceUid(memberIds, uid, tombstoneId).values;
  const groupUpdate: DocumentData = {
    memberIds: replacedMemberIds,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (groupData.createdBy === uid) {
    groupUpdate.createdBy = remainingRealCreator ?? deletedUserSentinel;
  }
  if (!hasRealSurvivor) {
    groupUpdate.createdBy = deletedUserSentinel;
    groupUpdate.isDeleted = true;
    groupUpdate.deletedAt = FieldValue.serverTimestamp();
  }

  await writer.set(groupRef.collection('members').doc(tombstoneId), {
    id: tombstoneId,
    userId: tombstoneId,
    displayName: deletedMemberName,
    role: 'MEMBER',
    joinedAt: oldMemberData?.joinedAt ?? groupData.createdAt ?? FieldValue.serverTimestamp(),
    isShadow: oldMemberData?.isShadow === true,
    isTombstone: true,
  });
  await writer.delete(oldMemberRef);
  await writer.update(groupRef, groupUpdate);

  let expensesScrubbed = 0;
  let settlementsScrubbed = 0;
  let activityLogsScrubbed = 0;

  const eventsSnap = await groupRef.collection('events').get();
  for (const eventDoc of eventsSnap.docs) {
    const eventData = eventDoc.data();
    const eventUpdate: DocumentData = {};
    if (Array.isArray(eventData.participantIds)) {
      const replaced = replaceUid(eventData.participantIds, uid, tombstoneId);
      if (replaced.changed) eventUpdate.participantIds = replaced.values;
    }
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

  return {
    tombstoneId,
    expensesScrubbed,
    settlementsScrubbed,
    activityLogsScrubbed,
    membersDeleted: oldMemberSnap?.exists ? 1 : 0,
    groupOrphanedAndSoftDeleted: !hasRealSurvivor,
  };
}

async function deleteDocIfExists(ref: DocumentReference): Promise<boolean> {
  const snap = await ref.get();
  if (!snap.exists) return false;
  await ref.delete();
  return true;
}

export const deleteAccount = onCall<unknown, Promise<DeleteAccountOutput>>(
  { enforceAppCheck: true },
  async (request: CallableRequest<unknown>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }
    assertNoInput(request.data);

    const uid = request.auth.uid;
    const db = getFirestore();
    const output: DeleteAccountOutput = {
      groupsProcessed: 0,
      tombstoneIds: [],
      expensesScrubbed: 0,
      settlementsScrubbed: 0,
      activityLogsScrubbed: 0,
      membersDeleted: 0,
      groupsOrphanedAndSoftDeleted: 0,
      fcmTokenDeleted: false,
      joinAttemptsDeleted: false,
      authUserDeleted: false,
    };

    const groupsSnap = await db.collection('groups')
      .where('memberIds', 'array-contains', uid)
      .get();
    const writer = new BatchWriter(db);

    for (const groupDoc of groupsSnap.docs) {
      const result = await processGroup(db, writer, groupDoc.ref, uid);
      output.groupsProcessed += 1;
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
    }

    await writer.flush();

    output.fcmTokenDeleted = await deleteDocIfExists(db.doc(`fcm_tokens/${uid}`));
    output.joinAttemptsDeleted = await deleteDocIfExists(db.doc(`joinAttempts/${uid}`));

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
        throw new HttpsError(
          'internal',
          'Account data was scrubbed, but the Auth user could not be deleted.',
          output,
        );
      }
    }

    return output;
  },
);
