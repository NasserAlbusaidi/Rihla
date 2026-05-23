import { createHash } from "node:crypto";
import { getAuth } from "firebase-admin/auth";
import {
  DocumentData,
  DocumentReference,
  FieldPath,
  FieldValue,
  Firestore,
  Timestamp,
  WriteBatch,
  getFirestore,
} from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import {
  CallableRequest,
  HttpsError,
  onCall,
} from "firebase-functions/v2/https";
import {
  AccountJobStatusOutput,
  RecoveryCleanupCounters,
} from "../accountJobs/types";
import {
  renameMapKey,
  replaceUidInArray,
  rewriteRecoveryMetadataUidReferences,
} from "../accountJobs/identityRewrite";
import "../admin";

interface RecoveryCleanupJobInput {
  oldUid: string;
  cleanupSecret: string;
}

interface RecoveryCleanupJobIdInput {
  jobId: string;
}

interface RecoveryCleanupJobDoc {
  kind: "recoveryCleanup";
  oldUid: string;
  newUid?: string;
  secretHash: string;
  status: "blocked" | "running" | "failed" | "complete";
  phase: string;
  groupIds: string[];
  cursorIndex: number;
  retryable: boolean;
  errorCode?: string;
  counters: RecoveryCleanupCounters;
  createdAt: Timestamp | FieldValue;
  updatedAt: Timestamp | FieldValue;
}

interface GroupRewriteResult {
  membersRewritten: number;
  eventsRewritten: number;
  expensesRewritten: number;
  settlementsRewritten: number;
  activityLogsRewritten: number;
}

const recoveryJobCollection = "recoveryCleanupJobs";
const recoveryIntentCollection = "recoveryCleanupIntents";
const cleanupIntentMaxAgeMs = 15 * 60 * 1000;
const cleanupSecretMinLength = 32;
const cleanupSecretMaxLength = 128;
const batchLimit = 450;
const collectionPageLimit = 200;

class BatchWriter {
  private batch: WriteBatch;
  private writes = 0;

  constructor(private readonly db: Firestore) {
    this.batch = db.batch();
  }

  async enqueueSet(ref: DocumentReference, data: DocumentData): Promise<void> {
    this.batch.set(ref, data);
    await this.afterWrite();
  }

  async enqueueUpdate(
    ref: DocumentReference,
    data: DocumentData,
  ): Promise<void> {
    this.batch.update(ref, data);
    await this.afterWrite();
  }

  async enqueueDelete(ref: DocumentReference): Promise<void> {
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

function parseOldUid(data: RecoveryCleanupJobInput | undefined): string {
  const oldUid = data?.oldUid;
  if (typeof oldUid !== "string" || oldUid.trim().length === 0) {
    throw new HttpsError(
      "invalid-argument",
      "oldUid must be a non-empty string.",
    );
  }
  return oldUid.trim();
}

function parseCleanupSecret(data: RecoveryCleanupJobInput | undefined): string {
  const cleanupSecret = data?.cleanupSecret;
  if (
    typeof cleanupSecret !== "string" ||
    cleanupSecret.length < cleanupSecretMinLength ||
    cleanupSecret.length > cleanupSecretMaxLength
  ) {
    throw new HttpsError("invalid-argument", "cleanupSecret is invalid.");
  }
  return cleanupSecret;
}

function parseJobId(data: RecoveryCleanupJobIdInput | undefined): string {
  const jobId = data?.jobId;
  if (typeof jobId !== "string" || jobId.trim().length === 0) {
    throw new HttpsError(
      "invalid-argument",
      "jobId must be a non-empty string.",
    );
  }
  return jobId.trim();
}

function secretHash(secret: string): string {
  return createHash("sha256").update(secret).digest("hex");
}

function emptyCounters(): RecoveryCleanupCounters {
  return {
    groupsProcessed: 0,
    groupsFailed: 0,
    membersRewritten: 0,
    eventsRewritten: 0,
    expensesRewritten: 0,
    settlementsRewritten: 0,
    activityLogsRewritten: 0,
  };
}

function statusFromJob(
  jobId: string,
  data: RecoveryCleanupJobDoc,
): AccountJobStatusOutput {
  return {
    jobId,
    kind: "recoveryCleanup",
    status: data.status,
    phase: data.phase,
    current: data.cursorIndex,
    total: data.groupIds.length,
    retryable: data.retryable,
    errorCode: data.errorCode,
    counters: { ...data.counters },
  };
}

function withoutErrorCode(data: RecoveryCleanupJobDoc): RecoveryCleanupJobDoc {
  const next = { ...data };
  delete next.errorCode;
  return next;
}

function asStringArray(value: unknown, path: string): string[] {
  if (
    !Array.isArray(value) ||
    value.some((entry) => typeof entry !== "string")
  ) {
    throw new HttpsError("failed-precondition", `${path} is malformed.`);
  }
  return value;
}

function optionalStringArray(value: unknown, path: string): string[] | null {
  if (value == null) return null;
  return asStringArray(value, path);
}

async function forEachCollectionDoc(
  collectionRef: FirebaseFirestore.CollectionReference,
  onDoc: (doc: FirebaseFirestore.QueryDocumentSnapshot) => Promise<void>,
): Promise<void> {
  let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  while (true) {
    let query: FirebaseFirestore.Query = collectionRef
      .orderBy(FieldPath.documentId())
      .limit(collectionPageLimit);
    if (lastDoc != null) query = query.startAfter(lastDoc);
    const page = await query.get();
    if (page.empty) return;
    for (const doc of page.docs) {
      await onDoc(doc);
    }
    lastDoc = page.docs[page.docs.length - 1];
    if (page.size < collectionPageLimit) return;
  }
}

function cleanupIntentError(): HttpsError {
  return new HttpsError("permission-denied", "Invalid cleanup intent.");
}

function hasEmailProvider(
  providerData: Array<{ providerId: string }>,
): boolean {
  return providerData.some(
    (provider) =>
      provider.providerId === "password" || provider.providerId === "emailLink",
  );
}

async function assertRecoveredUser(newUid: string): Promise<void> {
  try {
    const user = await getAuth().getUser(newUid);
    if (!hasEmailProvider(user.providerData)) {
      throw new HttpsError(
        "failed-precondition",
        "Recovered user must be linked to an email provider.",
      );
    }
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError(
      "failed-precondition",
      "Recovered user must exist before cleanup.",
    );
  }
}

async function assertCleanupIntent(
  oldUid: string,
  cleanupSecret: string,
): Promise<DocumentReference> {
  const db = getFirestore();
  const intentRef = db.doc(`${recoveryIntentCollection}/${oldUid}`);
  const intentSnap = await intentRef.get();
  if (!intentSnap.exists) throw cleanupIntentError();

  const data = intentSnap.data() ?? {};
  if (data.secret !== cleanupSecret) throw cleanupIntentError();
  const createdAt = data.createdAt;
  if (
    !(createdAt instanceof Timestamp) ||
    Timestamp.now().toMillis() - createdAt.toMillis() > cleanupIntentMaxAgeMs
  ) {
    throw cleanupIntentError();
  }
  return intentRef;
}

async function loadAuthorizedJob(
  request: CallableRequest<RecoveryCleanupJobIdInput>,
): Promise<{ ref: DocumentReference; data: RecoveryCleanupJobDoc }> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }
  const jobId = parseJobId(request.data);
  const ref = getFirestore().doc(`${recoveryJobCollection}/${jobId}`);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Recovery cleanup job not found.");
  }
  const data = snap.data() as RecoveryCleanupJobDoc;
  if (data.newUid !== request.auth.uid) {
    throw new HttpsError(
      "permission-denied",
      "Recovery cleanup job belongs to another user.",
    );
  }
  return { ref, data };
}

async function createOrLoadPreClaimJob(
  oldUid: string,
  cleanupSecret: string,
): Promise<{
  ref: DocumentReference;
  data: RecoveryCleanupJobDoc;
  intentRef?: DocumentReference;
}> {
  const db = getFirestore();
  const ref = db.doc(`${recoveryJobCollection}/${oldUid}`);
  const existing = await ref.get();
  if (existing.exists) {
    const data = existing.data() as RecoveryCleanupJobDoc;
    if (
      data.oldUid !== oldUid ||
      data.secretHash !== secretHash(cleanupSecret)
    ) {
      throw cleanupIntentError();
    }
    return { ref, data };
  }

  const intentRef = await assertCleanupIntent(oldUid, cleanupSecret);
  const groupsSnap = await db
    .collection("groups")
    .where("memberIds", "array-contains", oldUid)
    .get();
  const groupIds = groupsSnap.docs.map((doc) => doc.id);
  const data: RecoveryCleanupJobDoc = {
    kind: "recoveryCleanup",
    oldUid,
    secretHash: secretHash(cleanupSecret),
    status: "blocked",
    phase: "Waiting for recovered account",
    groupIds,
    cursorIndex: 0,
    retryable: true,
    counters: emptyCounters(),
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  await ref.set(data);
  return { ref, data, intentRef };
}

function expenseUpdates(
  data: DocumentData,
  oldUid: string,
  newUid: string,
  path = "expense",
): DocumentData | null {
  const updates: DocumentData = {};
  if (data.createdBy === oldUid) updates.createdBy = newUid;
  if (data.payerParticipantId === oldUid) updates.payerParticipantId = newUid;
  const customSplitParticipants = optionalStringArray(
    data.customSplitParticipants,
    `${path}.customSplitParticipants`,
  );
  if (customSplitParticipants != null) {
    const replaced = replaceUidInArray(customSplitParticipants, oldUid, newUid);
    if (replaced.changed) updates.customSplitParticipants = replaced.value;
  }
  const distribution = renameMapKey(data.splitDistribution, oldUid, newUid, {
    preserveExistingDestination: true,
  });
  if (distribution?.changed) updates.splitDistribution = distribution.value;
  return Object.keys(updates).length > 0 ? updates : null;
}

function settlementUpdates(
  data: DocumentData,
  oldUid: string,
  newUid: string,
): DocumentData | null {
  const updates: DocumentData = {};
  if (data.createdBy === oldUid) updates.createdBy = newUid;
  if (data.payerParticipantId === oldUid) updates.payerParticipantId = newUid;
  if (data.recipientParticipantId === oldUid)
    updates.recipientParticipantId = newUid;
  return Object.keys(updates).length > 0 ? updates : null;
}

function activityUpdates(
  data: DocumentData,
  oldUid: string,
  newUid: string,
  path = "activity",
): DocumentData | null {
  const updates: DocumentData = {};
  if (data.actorId === oldUid) updates.actorId = newUid;
  if (data.targetParticipantId === oldUid) updates.targetParticipantId = newUid;
  const metadata = rewriteRecoveryMetadataUidReferences(
    data.metadata,
    oldUid,
    newUid,
    `${path}.metadata`,
  );
  if (metadata.changed) updates.metadata = metadata.value;
  return Object.keys(updates).length > 0 ? updates : null;
}

async function processSettlementsCollection(
  writer: BatchWriter,
  collectionRef: FirebaseFirestore.CollectionReference,
  oldUid: string,
  newUid: string,
): Promise<number> {
  let rewritten = 0;
  await forEachCollectionDoc(collectionRef, async (doc) => {
    const updates = settlementUpdates(doc.data(), oldUid, newUid);
    if (updates != null) {
      await writer.enqueueUpdate(doc.ref, updates);
      rewritten += 1;
    }
  });
  return rewritten;
}

async function processActivityCollection(
  writer: BatchWriter,
  collectionRef: FirebaseFirestore.CollectionReference,
  oldUid: string,
  newUid: string,
): Promise<number> {
  let rewritten = 0;
  await forEachCollectionDoc(collectionRef, async (doc) => {
    const updates = activityUpdates(doc.data(), oldUid, newUid, doc.ref.path);
    if (updates != null) {
      await writer.enqueueUpdate(doc.ref, updates);
      rewritten += 1;
    }
  });
  return rewritten;
}

async function processGroup(
  writer: BatchWriter,
  groupRef: DocumentReference,
  oldUid: string,
  newUid: string,
): Promise<GroupRewriteResult> {
  const result: GroupRewriteResult = {
    membersRewritten: 0,
    eventsRewritten: 0,
    expensesRewritten: 0,
    settlementsRewritten: 0,
    activityLogsRewritten: 0,
  };
  const groupSnap = await groupRef.get();
  if (!groupSnap.exists) return result;

  const groupData = groupSnap.data() ?? {};
  const memberIds = asStringArray(
    groupData.memberIds,
    `groups/${groupRef.id}.memberIds`,
  );
  const hasOldMemberId = memberIds.includes(oldUid);
  const hasNewMemberId = memberIds.includes(newUid);
  if (!hasOldMemberId && !hasNewMemberId) return result;

  const oldMemberRef = groupRef.collection("members").doc(oldUid);
  const newMemberRef = groupRef.collection("members").doc(newUid);
  const [oldMemberSnap, newMemberSnap] = await Promise.all([
    oldMemberRef.get(),
    newMemberRef.get(),
  ]);

  await forEachCollectionDoc(groupRef.collection("events"), async (eventDoc) => {
    const eventData = eventDoc.data();
    const eventUpdate: DocumentData = {};
    const participantIds = optionalStringArray(
      eventData.participantIds,
      `${eventDoc.ref.path}.participantIds`,
    );
    if (participantIds != null) {
      const replaced = replaceUidInArray(participantIds, oldUid, newUid);
      if (replaced.changed) eventUpdate.participantIds = replaced.value;
    }
    const participantNames = renameMapKey(
      eventData.participantNames,
      oldUid,
      newUid,
      {
        preserveExistingDestination: true,
      },
    );
    if (participantNames?.changed)
      eventUpdate.participantNames = participantNames.value;
    if (eventData.createdBy === oldUid) eventUpdate.createdBy = newUid;
    if (Object.keys(eventUpdate).length > 0) {
      eventUpdate.updatedAt = FieldValue.serverTimestamp();
      await writer.enqueueUpdate(eventDoc.ref, eventUpdate);
      result.eventsRewritten += 1;
    }

    await forEachCollectionDoc(eventDoc.ref.collection("expenses"), async (
      expenseDoc,
    ) => {
      const updates = expenseUpdates(
        expenseDoc.data(),
        oldUid,
        newUid,
        expenseDoc.ref.path,
      );
      if (updates != null) {
        await writer.enqueueUpdate(expenseDoc.ref, updates);
        result.expensesRewritten += 1;
      }
    });

    result.settlementsRewritten += await processSettlementsCollection(
      writer,
      eventDoc.ref.collection("settlements"),
      oldUid,
      newUid,
    );
    result.activityLogsRewritten += await processActivityCollection(
      writer,
      eventDoc.ref.collection("activity_logs"),
      oldUid,
      newUid,
    );
  });

  result.settlementsRewritten += await processSettlementsCollection(
    writer,
    groupRef.collection("settlements"),
    oldUid,
    newUid,
  );
  result.activityLogsRewritten += await processActivityCollection(
    writer,
    groupRef.collection("activity"),
    oldUid,
    newUid,
  );

  await writer.flush();

  const replacedMemberIds = replaceUidInArray(memberIds, oldUid, newUid);
  const groupUpdate: DocumentData = {
    memberIds: replacedMemberIds.value,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (groupData.createdBy === oldUid) groupUpdate.createdBy = newUid;
  await writer.enqueueUpdate(groupRef, groupUpdate);

  if (!newMemberSnap.exists && oldMemberSnap.exists) {
    await writer.enqueueSet(newMemberRef, {
      ...(oldMemberSnap.data() ?? {}),
      id: newUid,
      userId: newUid,
    });
    result.membersRewritten += 1;
  }
  if (oldMemberSnap.exists) {
    await writer.enqueueDelete(oldMemberRef);
    result.membersRewritten += 1;
  }

  await writer.flush();
  return result;
}

export const claimRecoveryCleanupJob = onCall<
  RecoveryCleanupJobInput,
  Promise<AccountJobStatusOutput>
>(
  { enforceAppCheck: true },
  async (request: CallableRequest<RecoveryCleanupJobInput>) => {
    if (!request.auth)
      throw new HttpsError("unauthenticated", "Sign-in required.");
    const oldUid = parseOldUid(request.data);
    const cleanupSecret = parseCleanupSecret(request.data);
    const { ref, data, intentRef } = await createOrLoadPreClaimJob(
      oldUid,
      cleanupSecret,
    );

    if (request.auth.uid === oldUid) {
      return statusFromJob(ref.id, data);
    }

    if (data.secretHash !== secretHash(cleanupSecret))
      throw cleanupIntentError();
    await assertRecoveredUser(request.auth.uid);
    const next: RecoveryCleanupJobDoc = {
      ...data,
      newUid: request.auth.uid,
      status: data.status === "complete" ? "complete" : "running",
      phase: data.status === "complete" ? "Complete" : "Migrating groups",
      retryable: true,
      updatedAt: FieldValue.serverTimestamp(),
    };
    await ref.set({ ...next, errorCode: FieldValue.delete() }, { merge: true });
    if (intentRef != null) await intentRef.delete();
    return statusFromJob(ref.id, next);
  },
);

export const getRecoveryCleanupJobStatus = onCall<
  RecoveryCleanupJobIdInput,
  Promise<AccountJobStatusOutput>
>(
  { enforceAppCheck: true },
  async (request: CallableRequest<RecoveryCleanupJobIdInput>) => {
    const { ref, data } = await loadAuthorizedJob(request);
    return statusFromJob(ref.id, data);
  },
);

export const advanceRecoveryCleanupJob = onCall<
  RecoveryCleanupJobIdInput,
  Promise<AccountJobStatusOutput>
>(
  { enforceAppCheck: true },
  async (request: CallableRequest<RecoveryCleanupJobIdInput>) => {
    const { ref, data: loadedData } = await loadAuthorizedJob(request);
    if (loadedData.status === "complete")
      return statusFromJob(ref.id, loadedData);
    if (
      loadedData.status !== "running" &&
      !(loadedData.status === "failed" && loadedData.retryable)
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Recovery cleanup job is not running.",
      );
    }
    const data: RecoveryCleanupJobDoc =
      loadedData.status === "failed"
        ? {
            ...withoutErrorCode(loadedData),
            status: "running",
            phase: "Retrying group migration",
            updatedAt: FieldValue.serverTimestamp(),
          }
        : loadedData;
    const newUid = data.newUid;
    if (newUid == null || newUid.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "Recovery cleanup job is not claimed.",
      );
    }

    const db = getFirestore();
    const groupId = data.groupIds[data.cursorIndex];
    if (groupId == null) {
      try {
        await getAuth().deleteUser(data.oldUid);
      } catch (error) {
        if ((error as { code?: unknown }).code !== "auth/user-not-found")
          throw error;
      }
      await Promise.all([
        db
          .doc(`fcm_tokens/${data.oldUid}`)
          .delete()
          .catch(() => undefined),
        db
          .doc(`joinAttempts/${data.oldUid}`)
          .delete()
          .catch(() => undefined),
      ]);
      const complete = {
        ...data,
        status: "complete" as const,
        phase: "Complete",
        retryable: false,
        updatedAt: FieldValue.serverTimestamp(),
      };
      await ref.set(complete, { merge: true });
      logger.info("advanceRecoveryCleanupJob complete", {
        oldUid: data.oldUid,
        newUid,
        jobId: ref.id,
      });
      return statusFromJob(ref.id, complete);
    }

    try {
      const writer = new BatchWriter(db);
      const result = await processGroup(
        writer,
        db.doc(`groups/${groupId}`),
        data.oldUid,
        newUid,
      );
      const counters: RecoveryCleanupCounters = {
        groupsProcessed: data.counters.groupsProcessed + 1,
        groupsFailed: data.counters.groupsFailed,
        membersRewritten:
          data.counters.membersRewritten + result.membersRewritten,
        eventsRewritten: data.counters.eventsRewritten + result.eventsRewritten,
        expensesRewritten:
          data.counters.expensesRewritten + result.expensesRewritten,
        settlementsRewritten:
          data.counters.settlementsRewritten + result.settlementsRewritten,
        activityLogsRewritten:
          data.counters.activityLogsRewritten + result.activityLogsRewritten,
      };
      const next: RecoveryCleanupJobDoc = {
        ...data,
        cursorIndex: data.cursorIndex + 1,
        counters,
        phase: "Migrating groups",
        retryable: true,
        updatedAt: FieldValue.serverTimestamp(),
      };
      await ref.set(
        { ...next, errorCode: FieldValue.delete() },
        { merge: true },
      );
      return statusFromJob(ref.id, next);
    } catch (error) {
      const failed: RecoveryCleanupJobDoc = {
        ...data,
        status: "failed",
        phase: `Group ${groupId} failed`,
        retryable: true,
        errorCode: error instanceof Error ? error.name : "unknown",
        counters: {
          ...data.counters,
          groupsFailed: data.counters.groupsFailed + 1,
        },
        updatedAt: FieldValue.serverTimestamp(),
      };
      await ref.set(failed, { merge: true });
      logger.error("advanceRecoveryCleanupJob group failed", {
        oldUid: data.oldUid,
        newUid,
        groupId,
        error: error instanceof Error ? error.message : String(error),
      });
      return statusFromJob(ref.id, failed);
    }
  },
);
