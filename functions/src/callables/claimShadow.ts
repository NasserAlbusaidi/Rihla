import {
  CollectionReference,
  DocumentData,
  DocumentReference,
  FieldValue,
  Firestore,
  getFirestore,
} from 'firebase-admin/firestore';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import type Decimal from 'decimal.js';
import '../admin';
import { BatchWriter } from './shared/batchWriter';
import { replaceUid, renameMapKey, mergeUidMapKey } from './shared/mapReKey';
import { recomputeNet, Money } from './groupNetBalance';

// #278 claim/merge (PR7). The Admin-SDK uuid→uid re-key that lets a real joiner
// CLAIM a placeholder ("shadow") member: the shadow's uuid identity is re-keyed
// to the claimer's auth uid across every money doc, so the joiner inherits the
// shadow's balance. The mirror image of deleteAccount.ts's uid→tombstone re-key.
// It MUST be an Admin callable (memberIds is server-authoritative and #524 binds
// a client member-doc to auth.uid; the balance oracle is identity-blind so the
// re-key is a key rename across docs).
//
// Two-phase, idempotent, convergent (deleteAccount precedent): Phase B batched
// child-doc re-keys, Phase C transactional identity retirement with memberIds
// rewritten LAST (so a torn cascade stays query-visible under the shadow id and
// converges on retry). D2: splitDistribution SUMS on collision (mergeUidMapKey,
// never overwrite — money loss). D7: KEY-ONLY — the claimed doc KEEPS the
// creator-typed shadow name, so NO denormalized name value is ever rewritten.
// D9: a POST-commit recomputeNet parity assert (priorShadow + priorClaimer per
// currency) catches a forged-doc divergence and refuses to finalize.

export interface ClaimShadowInput {
  groupId: string;
  shadowMemberId: string;
  claimerUid: string;
}

export interface ClaimShadowOutput {
  groupId: string;
  shadowMemberId: string;
  claimerUid: string;
  alreadyClaimed: boolean;
}

// Stamped on every re-keyed expense so expenseAuditLogger skips the phantom
// UPDATE (it re-keys CONTENT_KEYS). Admin-only by construction — deliberately
// absent from validExpenseUpdate's hasOnly allow-list, so a client can never
// write it. Inert to balances + display (absent from EXPENSE_BALANCE_KEYS /
// CONTENT_KEYS); the field persists harmlessly after the claim.
const CLAIM_REKEY_FIELD = 'claimRekeyAt';

function validId(value: unknown, label: string): string {
  if (typeof value !== 'string' || value.length === 0 || value.includes('/')) {
    throw new HttpsError('invalid-argument', `${label} must be a valid id.`);
  }
  return value;
}

function asStringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((v): v is string => typeof v === 'string') : [];
}

// Per-expense re-key. Returns the field updates (incl. the audit-skip sentinel)
// or null when the shadow is not referenced. NEVER nulls note/description/
// receiptUrl — a claim preserves data; it is not a deletion.
function expenseRekey(
  data: DocumentData,
  shadowId: string,
  claimerUid: string,
): DocumentData | null {
  const updates: DocumentData = {};
  let touched = false;
  if (data.payerParticipantId === shadowId) {
    updates.payerParticipantId = claimerUid;
    touched = true;
  }
  if (Array.isArray(data.customSplitParticipants)) {
    const replaced = replaceUid(data.customSplitParticipants, shadowId, claimerUid);
    if (replaced.changed) {
      updates.customSplitParticipants = replaced.values;
      touched = true;
    }
  }
  // ★ The money-critical step — SUM on collision (D2), never overwrite.
  const distribution = mergeUidMapKey(data.splitDistribution, shadowId, claimerUid);
  if (distribution?.changed) {
    updates.splitDistribution = distribution.value;
    touched = true;
  }
  // Defensive (legacy/Admin docs only — a shadow has no client and is never an
  // expense's createdBy under any normal path; see spec §"Re-key items NOT
  // grounded"). Kept for convergence symmetry with the settlement/group swaps.
  if (data.createdBy === shadowId) {
    updates.createdBy = claimerUid;
    touched = true;
  }
  if (!touched) return null;
  updates[CLAIM_REKEY_FIELD] = FieldValue.serverTimestamp();
  return updates;
}

// Event- AND group-scope settlements: id swaps only. payerName/recipientName are
// NOT rewritten (D7 — the denormalized name stays the shadow's = the claimer's
// adopted name). Admin update bypasses the append-only `allow update: if false`.
async function rekeySettlements(
  writer: BatchWriter,
  collection: CollectionReference,
  shadowId: string,
  claimerUid: string,
): Promise<void> {
  const snap = await collection.get();
  for (const doc of snap.docs) {
    const data = doc.data();
    const updates: DocumentData = {};
    let touched = false;
    if (data.payerParticipantId === shadowId) {
      updates.payerParticipantId = claimerUid;
      touched = true;
    }
    if (data.recipientParticipantId === shadowId) {
      updates.recipientParticipantId = claimerUid;
      touched = true;
    }
    if (data.createdBy === shadowId) {
      updates.createdBy = claimerUid; // defensive
      touched = true;
    }
    if (touched) await writer.update(doc.ref, updates);
  }
}

// Activity logs: best-effort id swap (does NOT feed balances). actorName is
// untouched (D7). A malformed doc simply yields no updates.
async function rekeyActivityLogs(
  writer: BatchWriter,
  collection: CollectionReference,
  shadowId: string,
  claimerUid: string,
): Promise<void> {
  const snap = await collection.get();
  for (const doc of snap.docs) {
    const data = doc.data();
    const updates: DocumentData = {};
    let touched = false;
    if (data.actorId === shadowId) {
      updates.actorId = claimerUid;
      touched = true;
    }
    if (data.targetParticipantId === shadowId) {
      updates.targetParticipantId = claimerUid;
      touched = true;
    }
    if (touched) await writer.update(doc.ref, updates);
  }
}

// B4 (D9): re-run the oracle after the cascade commits and assert, per currency,
// post[claimer] == priorShadow + priorClaimer AND the shadow is gone. On
// mismatch the claim is NOT finalized — a loud P0 + an `internal` error (the
// operation is idempotent so a retry converges; a forged-doc divergence stays
// loud rather than silently corrupting the net).
async function verifyParity(
  db: Firestore,
  groupRef: DocumentReference,
  priorNet: Map<string, Map<string, Decimal>>,
  shadowId: string,
  claimerUid: string,
): Promise<void> {
  const { net: postNet } = await recomputeNet(db, groupRef);
  const zero = new Money(0);
  const currencies = new Set<string>([...priorNet.keys(), ...postNet.keys()]);
  for (const currency of currencies) {
    const priorShadow = priorNet.get(currency)?.get(shadowId) ?? zero;
    const priorClaimer = priorNet.get(currency)?.get(claimerUid) ?? zero;
    const expected = priorShadow.plus(priorClaimer);
    const actual = postNet.get(currency)?.get(claimerUid) ?? zero;
    const shadowPost = postNet.get(currency)?.get(shadowId);
    const claimerOk = actual.minus(expected).isZero();
    const shadowGone = shadowPost == null || shadowPost.isZero();
    if (!claimerOk || !shadowGone) {
      logger.error('claimShadow B4 parity MISMATCH — claim NOT finalized', {
        groupId: groupRef.id,
        shadowId,
        claimerUid,
        currency,
        priorShadow: priorShadow.toString(),
        priorClaimer: priorClaimer.toString(),
        expectedClaimer: expected.toString(),
        actualClaimer: actual.toString(),
        shadowPost: shadowPost?.toString() ?? 'absent',
      });
      throw new HttpsError(
        'internal',
        'Claim produced an inconsistent balance and was not finalized.',
      );
    }
  }
}

// The engine. PR8 calls this directly from an approved decideClaimRequest; PR7's
// onCall wrapper gates it on the group creator (the D1 trust anchor).
export async function claimShadowEngine(
  db: Firestore,
  groupRef: DocumentReference,
  shadowMemberId: string,
  claimerUid: string,
): Promise<ClaimShadowOutput> {
  const groupId = groupRef.id;

  // ---- Phase A: eligibility (fast pre-check; Phase C re-checks in a tx) ----
  const groupSnap = await groupRef.get();
  if (!groupSnap.exists) throw new HttpsError('not-found', 'Group not found.');
  const groupData = groupSnap.data() ?? {};
  if (groupData.isDeleted === true || groupData.deletingInProgress === true) {
    throw new HttpsError('not-found', 'Group not found.');
  }

  // Match the shadow by the userId FIELD (uuid-keyed; #294 trap).
  const shadowDocs = await groupRef
    .collection('members')
    .where('userId', '==', shadowMemberId)
    .get();
  if (shadowDocs.empty) {
    // The placeholder doc is gone — a prior claim retired it (or it never
    // existed). Idempotent no-op (D9 convergence): nothing to re-key.
    return { groupId, shadowMemberId, claimerUid, alreadyClaimed: true };
  }
  if (shadowDocs.docs[0].data().isShadow !== true) {
    throw new HttpsError('failed-precondition', 'Only a placeholder member can be claimed.');
  }

  // ---- B4 capture: prior nets BEFORE any writes (D9; FULL recomputeNet so
  // group-scope settlements are included — never reconstruct from per-event) ----
  const { net: priorNet } = await recomputeNet(db, groupRef);

  // ---- Phase B: idempotent batched child re-keys ----
  const writer = new BatchWriter(db);
  const eventsSnap = await groupRef.collection('events').get();
  for (const eventDoc of eventsSnap.docs) {
    const eventData = eventDoc.data();
    const eventUpdate: DocumentData = {};
    const replaced = replaceUid(asStringArray(eventData.participantIds), shadowMemberId, claimerUid);
    if (replaced.changed) eventUpdate.participantIds = replaced.values;
    // KEY-ONLY (D7): rename the key, KEEP the shadow's name as the value.
    const names = renameMapKey(
      eventData.participantNames,
      shadowMemberId,
      claimerUid,
      (eventData.participantNames as Record<string, unknown> | undefined)?.[shadowMemberId],
    );
    if (names?.changed) eventUpdate.participantNames = names.value;
    if (eventData.createdBy === shadowMemberId) eventUpdate.createdBy = claimerUid; // defensive
    if (Object.keys(eventUpdate).length > 0) {
      eventUpdate.updatedAt = FieldValue.serverTimestamp();
      await writer.update(eventDoc.ref, eventUpdate);
    }

    const expensesSnap = await eventDoc.ref.collection('expenses').get();
    for (const expenseDoc of expensesSnap.docs) {
      const updates = expenseRekey(expenseDoc.data(), shadowMemberId, claimerUid);
      if (updates) await writer.update(expenseDoc.ref, updates);
    }

    await rekeySettlements(writer, eventDoc.ref.collection('settlements'), shadowMemberId, claimerUid);
    await rekeyActivityLogs(writer, eventDoc.ref.collection('activity_logs'), shadowMemberId, claimerUid);
  }

  await rekeySettlements(writer, groupRef.collection('settlements'), shadowMemberId, claimerUid);
  await rekeyActivityLogs(writer, groupRef.collection('activity'), shadowMemberId, claimerUid);

  await writer.flush();

  // ---- Phase C: transactional identity retirement (memberIds LAST) ----
  const retired = await db.runTransaction(async (tx) => {
    const gSnap = await tx.get(groupRef);
    if (!gSnap.exists) return false;
    const gData = gSnap.data() ?? {};
    const currentMemberIds = asStringArray(gData.memberIds);
    if (!currentMemberIds.includes(shadowMemberId)) return false; // already retired

    const membersTxSnap = await tx.get(groupRef.collection('members'));
    const members = membersTxSnap.docs.map((doc) => ({ id: doc.id, data: doc.data() }));
    const shadowTx = members.filter((m) => m.data.userId === shadowMemberId);
    if (shadowTx.length === 0 || shadowTx[0].data.isShadow !== true) return false;
    const sData = shadowTx[0].data;

    const groupUpdate: DocumentData = {
      memberIds: replaceUid(currentMemberIds, shadowMemberId, claimerUid).values,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (gData.createdBy === shadowMemberId) groupUpdate.createdBy = claimerUid; // defensive

    // D4 + D7: write the LIVE claimer identity keyed by {claimerUid}, KEEPING the
    // shadow's name. Overwrites any pre-existing claimer doc (the D2 forged path).
    tx.set(groupRef.collection('members').doc(claimerUid), {
      id: claimerUid,
      userId: claimerUid,
      displayName: typeof sData.displayName === 'string' ? sData.displayName : 'Member',
      role: 'MEMBER',
      joinedAt: sData.joinedAt ?? FieldValue.serverTimestamp(),
      isShadow: false,
    });
    // Delete the shadow doc(s) + any stray non-canonical claimer doc (a uuid-keyed
    // claimer doc would otherwise duplicate the canonical {claimerUid} doc).
    for (const m of members) {
      if (m.data.userId === shadowMemberId) {
        tx.delete(groupRef.collection('members').doc(m.id));
      } else if (m.data.userId === claimerUid && m.id !== claimerUid) {
        tx.delete(groupRef.collection('members').doc(m.id));
      }
    }
    tx.update(groupRef, groupUpdate); // 🔴 memberIds LAST (atomic within the tx)
    return true;
  });

  if (!retired) {
    return { groupId, shadowMemberId, claimerUid, alreadyClaimed: true };
  }

  // ---- B4 verify: POST-commit parity (D9) ----
  await verifyParity(db, groupRef, priorNet, shadowMemberId, claimerUid);

  logger.info('claimShadow re-keyed', { groupId, shadowMemberId, claimerUid });
  return { groupId, shadowMemberId, claimerUid, alreadyClaimed: false };
}

export const claimShadow = onCall<ClaimShadowInput, Promise<ClaimShadowOutput>>(
  { enforceAppCheck: true },
  async (request: CallableRequest<ClaimShadowInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }
    // D6: a durable account is required (the claimer adopts a real identity).
    if (request.auth.token?.firebase?.sign_in_provider === 'anonymous') {
      throw new HttpsError(
        'permission-denied',
        'A linked (non-anonymous) account is required to claim a member.',
      );
    }
    const groupId = validId(request.data?.groupId, 'groupId');
    const shadowMemberId = validId(request.data?.shadowMemberId, 'shadowMemberId');
    const claimerUid = validId(request.data?.claimerUid, 'claimerUid');

    const db = getFirestore();
    const groupRef = db.doc(`groups/${groupId}`);
    const groupSnap = await groupRef.get();
    if (!groupSnap.exists) throw new HttpsError('not-found', 'Group not found.');
    const groupData = groupSnap.data() ?? {};
    if (groupData.isDeleted === true || groupData.deletingInProgress === true) {
      throw new HttpsError('not-found', 'Group not found.');
    }
    // D1 trust anchor (removeMember.ts precedent): only the group creator may
    // trigger a re-key. PR8 wraps this with the request/approve flow and
    // de-exports this raw callable so the engine is reachable ONLY via an
    // approved decideClaimRequest.
    if (groupData.createdBy !== request.auth.uid) {
      throw new HttpsError('permission-denied', 'Only the group creator can approve a claim.');
    }

    return claimShadowEngine(db, groupRef, shadowMemberId, claimerUid);
  },
);
