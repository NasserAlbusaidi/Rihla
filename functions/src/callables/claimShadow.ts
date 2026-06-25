import {
  CollectionReference,
  DocumentData,
  DocumentReference,
  FieldValue,
  Firestore,
} from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import type Decimal from 'decimal.js';
import '../admin';
import { BatchWriter } from './shared/batchWriter';
import { replaceUid, renameMapKey, mergeUidMapKey } from './shared/mapReKey';
import {
  recomputeNet,
  computeNetFromSnapshot,
  loadGroupBalanceSnapshot,
  Money,
  type GroupBalanceSnapshot,
} from './groupNetBalance';

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
// converges on retry).
//
// CORRECTNESS MODEL (the divisor-shift class defeated 3 single-agent guards):
// a clean claim is a PURE RELABEL — the claimer occupies NO divisor-driving slot,
// so re-keying shadow→claimer cannot dedup an equal-split divisor (participantIds
// or customSplitParticipants 3→2) nor flip the claimer's liveness-gated universe
// membership. Pure-relabel is a STRUCTURAL property, checked PRE-COMMIT and
// COMPLETELY by a 3-term footprint pre-scan (Part 2) — claimer ∈ members ∪
// priorNet-by-presence ∪ any live event's participantIds/customSplit/
// splitDistribution-keys. That set is EXACTLY the identity-field set the oracle
// reads (groupNetBalance.ts computeNetFromSnapshot — the two move in lock-step;
// see the ⚠️ there). A net-comparison gate CANNOT express it cleanly: the
// alphabetically-last-absorbs-remainder rule means a legitimate brand-new claim
// can legally relocate a remainder subunit to a third party (correct money
// movement), which any additive net diff would false-reject — so the OLD
// claimer-only `postNet[claimer] == priorShadow + priorClaimer` assert was itself
// buggy. The backstop (Part 3) is instead an EXACT simNet == actualNet check: we
// SIMULATE the re-key in memory over the loaded snapshot (computeNetFromSnapshot),
// commit, then recompute and assert value-equality. simNet already bakes in the
// remainder-hop, so a mismatch means a concurrent write landed between snapshot
// and commit (TOCTOU) → loud P0 + `internal` (idempotent-retryable). D7: KEY-ONLY
// — the claimed doc KEEPS the creator-typed shadow name, so NO denormalized name
// value is ever rewritten. D8: no real-identity merge (the pre-scan refuses it).
// splitDistribution re-keys via mergeUidMapKey (SUM-on-collision, mapReKey.test.ts)
// — defensive only; the pre-scan makes a live claim-time collision unreachable.

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

// Pure event-/group-scope settlement re-key: id swaps only. payerName/
// recipientName are NOT rewritten (D7 — the denormalized name stays the shadow's
// = the claimer's adopted name). Returns the changed field map (a PARTIAL — only
// the swapped keys) or null. SHARED by the in-memory simulation and the
// committing rekeySettlements so they re-key identically (sim-fidelity).
function settlementRekey(
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
  if (data.recipientParticipantId === shadowId) {
    updates.recipientParticipantId = claimerUid;
    touched = true;
  }
  if (data.createdBy === shadowId) {
    updates.createdBy = claimerUid; // defensive
    touched = true;
  }
  return touched ? updates : null;
}

// Commit the settlement re-key across a collection (event- or group-scope). Admin
// update bypasses the append-only `allow update: if false`.
async function rekeySettlements(
  writer: BatchWriter,
  collection: CollectionReference,
  shadowId: string,
  claimerUid: string,
): Promise<void> {
  const snap = await collection.get();
  for (const doc of snap.docs) {
    const updates = settlementRekey(doc.data(), shadowId, claimerUid);
    if (updates) await writer.update(doc.ref, updates);
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

type Net = Map<string, Map<string, Decimal>>;

// Part 2, term 3: does the claimer occupy a divisor-driving slot the oracle DROPS
// from priorNet when out-of-universe? Any LIVE event's participantIds (always
// also a priorNet zero-row → redundant with term 2, kept so the guard is
// self-contained), OR a LIVE expense's customSplitParticipants (custom scope) /
// splitDistribution keys (non-equally mode). Gated on isDeleted === false EXACTLY
// as the oracle (computeNetFromSnapshot) scopes its reads — the claim path
// forbids a delete lock, so this equals the oracle's event/expense scope. The
// custom/weighted split fields are point-in-time, NOT standing (F1: an admin can
// shrink participantIds with no child re-validation → customSplit/
// splitDistribution ⊋ participantIds, an out-of-universe key the oracle drops).
function claimerInLiveEventSlot(
  snapshot: GroupBalanceSnapshot,
  claimerUid: string,
): boolean {
  for (const ev of snapshot.events) {
    if (ev.data.isDeleted !== false) continue;
    if (asStringArray(ev.data.participantIds).includes(claimerUid)) return true;
    for (const e of ev.expenses) {
      if (e.isDeleted !== false) continue;
      if (e.scope === 'custom' && asStringArray(e.customSplitParticipants).includes(claimerUid)) {
        return true;
      }
      const nonEqually =
        e.splitMode === 'shares' || e.splitMode === 'exact' || e.splitMode === 'percent';
      const dist = e.splitDistribution;
      if (
        nonEqually
        && dist != null
        && typeof dist === 'object'
        && !Array.isArray(dist)
        && Object.prototype.hasOwnProperty.call(dist, claimerUid)
      ) {
        return true;
      }
    }
  }
  return false;
}

// Part 3 pre-commit: build the simulated post-claim snapshot by re-keying EXACTLY
// the oracle-read identity fields on copies. The event participantIds re-key
// mirrors Phase B's inline replaceUid (the single most divisor-driving field —
// omit it and the shadow stays in the sim's universe while the commit moved it →
// simNet diverges from actualNet on every legitimate claim). expense/settlement
// re-keys are spread-merged PARTIALS (expenseRekey/settlementRekey return only
// the changed keys, or null — treating a partial as the whole doc would zero
// amountFils/scope/currency). The member set drops the shadow and appends ONE
// LIVE claimer (no isTombstone → the oracle treats it as live, matching Phase C);
// term 1's member-doc arm guarantees no pre-existing claimer doc on an accepted
// path, so this mirrors Phase C exactly. Oracle-inert fields (participantNames,
// createdBy, activity logs, the claimRekeyAt/updatedAt sentinels) are not read by
// computeNetFromSnapshot, so leaving them un-re-keyed is safe.
function simulateClaim(
  snapshot: GroupBalanceSnapshot,
  shadowId: string,
  claimerUid: string,
): GroupBalanceSnapshot {
  const events = snapshot.events.map((ev) => ({
    ...ev,
    data: {
      ...ev.data,
      participantIds: replaceUid(asStringArray(ev.data.participantIds), shadowId, claimerUid).values,
    },
    expenses: ev.expenses.map((e) => ({ ...e, ...(expenseRekey(e, shadowId, claimerUid) ?? {}) })),
    settlements: ev.settlements.map((s) => ({ ...s, ...(settlementRekey(s, shadowId, claimerUid) ?? {}) })),
  }));
  const groupSettlements = snapshot.groupSettlements.map((s) => ({
    ...s,
    ...(settlementRekey(s, shadowId, claimerUid) ?? {}),
  }));
  const members = snapshot.members
    .filter((m) => m.data.userId !== shadowId)
    .concat([{ docId: claimerUid, data: { userId: claimerUid, isShadow: false } }]);
  const groupData = {
    ...snapshot.groupData,
    memberIds: replaceUid(asStringArray(snapshot.groupData.memberIds), shadowId, claimerUid).values,
  };
  return { groupExists: snapshot.groupExists, groupData, members, events, groupSettlements };
}

// True if `uid` is a key in ANY currency bucket of `net` (a balance position,
// even a zero-row).
function netHasUid(net: Net, uid: string): boolean {
  return [...net.values()].some((bucket) => bucket.has(uid));
}

// Value-equality of two nets over the UNION of currencies and, per currency, the
// UNION of uids (so a uid present in one but absent from the other — exactly the
// TOCTOU the backstop guards — is compared, not skipped; mirror HEAD's union
// iteration). Decimals are compared by VALUE (.minus().isZero()), NEVER `===`
// (two Money objects are never reference-equal). Returns a mismatch description,
// or null when equal — NO tolerance / NO remainder fuzz (simNet already bakes in
// the legitimate remainder-hop).
function netMismatch(expected: Net, actual: Net): string | null {
  const zero = new Money(0);
  const currencies = new Set<string>([...expected.keys(), ...actual.keys()]);
  for (const currency of currencies) {
    const eBucket = expected.get(currency);
    const aBucket = actual.get(currency);
    const uids = new Set<string>([...(eBucket?.keys() ?? []), ...(aBucket?.keys() ?? [])]);
    for (const uid of uids) {
      const e = eBucket?.get(uid) ?? zero;
      const a = aBucket?.get(uid) ?? zero;
      if (!e.minus(a).isZero()) {
        return `${currency}/${uid}: sim=${e.toString()} actual=${a.toString()}`;
      }
    }
  }
  return null;
}

// Part 3 post-commit backstop (replaces the buggy claimer-only additive assert):
// recompute the live net and assert it EXACTLY equals the pre-commit simulation
// AND the shadow is gone. simNet already bakes in the legitimate remainder-hop,
// so absent a concurrent write actualNet == simNet by construction (both are
// computeNetFromSnapshot over the same relabeled docs). A mismatch ⇒ a write
// landed between the snapshot read and the commit (TOCTOU) → loud P0 + `internal`
// (idempotent so the next attempt re-snapshots).
async function assertExactParity(
  db: Firestore,
  groupRef: DocumentReference,
  simNet: Net,
  shadowId: string,
  claimerUid: string,
): Promise<void> {
  const { net: actualNet } = await recomputeNet(db, groupRef);
  const mismatch = netMismatch(simNet, actualNet);
  const shadowSurvived = netHasUid(actualNet, shadowId);
  if (mismatch != null || shadowSurvived) {
    logger.error('claimShadow parity MISMATCH (TOCTOU?) — claim NOT finalized', {
      groupId: groupRef.id,
      shadowId,
      claimerUid,
      mismatch: mismatch ?? 'none',
      shadowSurvived,
    });
    throw new HttpsError(
      'internal',
      'Claim produced an inconsistent balance and was not finalized.',
    );
  }
}

// The engine. Reachable ONLY via an approved decideClaimRequest (#278 PR8): the
// raw onCall wrapper was de-exported so a re-key cannot be triggered except by the
// group creator approving a pending claim request. decideClaimRequest calls this
// in-process under the creator-auth context with the claimerUid read from the
// persisted request doc (the requester's auth.uid) — the creator never supplies a
// claimerUid. The engine is fully self-protecting (eligibility + 3-term D8
// pre-scan + Phase-C TOCTOU re-check + post-commit simNet==actualNet parity), so
// it does not trust its caller's gate.
export async function claimShadowEngine(
  db: Firestore,
  groupRef: DocumentReference,
  shadowMemberId: string,
  claimerUid: string,
): Promise<ClaimShadowOutput> {
  const groupId = groupRef.id;

  // ---- Phase A: eligibility, over a full balance snapshot loaded ONCE. The same
  // snapshot feeds priorNet, the 3-term pre-scan, AND the in-memory simulation, so
  // there is NO second-read seam between them (Phase C re-checks in a tx). ----
  const snapshot = await loadGroupBalanceSnapshot(db, groupRef);
  if (!snapshot.groupExists) throw new HttpsError('not-found', 'Group not found.');
  const groupData = snapshot.groupData;
  if (groupData.isDeleted === true || groupData.deletingInProgress === true) {
    throw new HttpsError('not-found', 'Group not found.');
  }

  // Match the shadow by the userId FIELD. Server-minted shadow docs are
  // uuid-keyed (doc.id === userId), and field matching keeps this path aligned
  // with the rest of the member-doc keying code.
  const shadowMembers = snapshot.members.filter((m) => m.data.userId === shadowMemberId);
  if (shadowMembers.length === 0) {
    // The placeholder doc is gone — a prior claim retired it (or it never
    // existed). Idempotent no-op (convergence): nothing to re-key. This check runs
    // BEFORE the pre-scan, so a re-claim by an already-member claimer (test 6/16)
    // returns alreadyClaimed rather than failed-precondition.
    return { groupId, shadowMemberId, claimerUid, alreadyClaimed: true };
  }
  // Claimable predicate: a LIVE placeholder. A tombstoned shadow (Part 4) is NOT
  // claimable — no honest path tombstones a shadow (it has no auth account to call
  // deleteAccount), so {isShadow:true, isTombstone:true} is forged/defensive.
  const shadowData = shadowMembers[0].data;
  if (shadowData.isShadow !== true || shadowData.isTombstone === true) {
    throw new HttpsError('failed-precondition', 'Only a placeholder member can be claimed.');
  }

  // ---- Prior net BEFORE any writes, from the snapshot (FULL recompute so
  // group-scope settlements are included — never reconstruct from per-event). ----
  const { net: priorNet } = computeNetFromSnapshot(snapshot);

  // ---- Part 2: complete divisor-driving footprint pre-scan (PRECISE,
  // pre-commit, NO writes on reject). A clean claim is a PURE RELABEL — the
  // claimer occupies no divisor-driving slot, so re-keying shadow→claimer cannot
  // dedup an equal-split divisor nor flip the claimer's liveness-gated universe
  // membership. Reject if the claimer is financially visible by ANY of 3 terms —
  // EXACTLY the identity-field set the oracle reads (lock-step with
  // computeNetFromSnapshot). This admits exactly pure-relabel claims (a brand-new
  // invisible claimer passes; the legitimate remainder-hop is allowed because it
  // is not a collision) and rejects exactly the divisor-collapse class
  // (rounds 1/2/3 + FLAW A). PR8's approve flow guarantees a pre-join non-member
  // claimer; the engine self-protects regardless of caller.
  const claimerIsMember =
    asStringArray(groupData.memberIds).includes(claimerUid)
    || snapshot.members.some((m) => m.data.userId === claimerUid); // term 1 (#53 array-vs-doc)
  const claimerInPriorNet = netHasUid(priorNet, claimerUid); // term 2 — presence incl. netted-to-0 (F4)
  const claimerInSlot = claimerInLiveEventSlot(snapshot, claimerUid); // term 3 — dropped divisor key (F3)
  if (claimerIsMember || claimerInPriorNet || claimerInSlot) {
    throw new HttpsError(
      'failed-precondition',
      'The claimer is already a member or participant of this group.',
    );
  }

  // ---- Part 3 pre-commit: SIMULATE the re-key over the snapshot, capturing the
  // expected post-claim net. Sanity: the shadow MUST be gone from simNet (else the
  // simulation itself is buggy — caught before any write). ----
  const { net: simNet } =
    computeNetFromSnapshot(simulateClaim(snapshot, shadowMemberId, claimerUid));
  if (netHasUid(simNet, shadowMemberId)) {
    logger.error('claimShadow simulation retained the shadow — aborted pre-commit', {
      groupId,
      shadowMemberId,
      claimerUid,
    });
    throw new HttpsError('internal', 'Claim simulation was inconsistent and was not attempted.');
  }

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
    if (
      shadowTx.length === 0
      || shadowTx[0].data.isShadow !== true
      || shadowTx[0].data.isTombstone === true
    ) return false;
    // TOCTOU re-check of the D8 guard: the claimer must not have joined as a real
    // member between Phase A and this tx (PR8 serializes; defense-in-depth). Abort
    // the identity swap loudly rather than commit a divergent merge. memberIds
    // gains claimerUid only in this tx's own update below, so a normal flow never
    // trips this. (The rarer race — the claimer added to an event's participantIds
    // mid-claim — is left to the POST-commit B4 verifyParity backstop; re-folding
    // the universe inside the tx would exceed its read budget.)
    if (currentMemberIds.includes(claimerUid)) {
      throw new HttpsError(
        'failed-precondition',
        'The claimer is already a member or participant of this group.',
      );
    }
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

  // ---- Part 3 post-commit: exact simNet == actualNet (TOCTOU backstop). ----
  await assertExactParity(db, groupRef, simNet, shadowMemberId, claimerUid);

  logger.info('claimShadow re-keyed', { groupId, shadowMemberId, claimerUid });
  return { groupId, shadowMemberId, claimerUid, alreadyClaimed: false };
}
