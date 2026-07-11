import { getFirestore, DocumentData } from 'firebase-admin/firestore';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import '../admin';
import { sendToUids } from '../notifications/fcmSender';
import { formatAmount } from '../notifications/formatAmount';
import { expenseTitle, expenseBody } from '../notifications/strings';

// #179 — buzz the people an expense is split onto (minus the actor) when an
// expense is created. Fires AFTER the client-direct create commits; it only
// reads + sends, NEVER mutates the financial doc. Mirrors settlementNotifier (#53).
//
// Expense split participants (payerParticipantId, splitDistribution keys,
// customSplitParticipants) and event.participantIds are auth uids — the CREATE
// path is rules-gated to participant uids (firestore.rules:477/548/554/367) — so
// they map directly to fcm_tokens/{uid}; shadow/unclaimed members have no token
// doc and are silently skipped by sendToUids. onDocumentCreated (NOT ...Written),
// so a recovery uid-migration update() or an open-edit (#248) never re-fires it,
// and it cannot collide with the onDocumentWritten expenseAuditLogger.

function asString(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

async function resolveGroupName(gid: string): Promise<string> {
  try {
    const snap = await getFirestore().doc(`groups/${gid}`).get();
    return asString(snap.data()?.name);
  } catch (error) {
    logger.warn('expense notify: group name lookup failed', {
      gid,
      error: String(error),
    });
    return '';
  }
}

// Match by the userId FIELD, never the doc id. New client-created member docs
// key by {uid}, but legacy creator docs and server-minted shadows can be
// uuid-keyed (#294/#524). Mirrors expenseAuditLogger.resolveActorName.
// Returns '' when unresolved; strings.ts actorLabel localizes the fallback.
async function resolveActorName(gid: string, actorUid: string): Promise<string> {
  if (!actorUid) return '';
  try {
    const snap = await getFirestore()
      .collection(`groups/${gid}/members`)
      .where('userId', '==', actorUid)
      .get();
    for (const doc of snap.docs) {
      const name = doc.data().displayName;
      if (typeof name === 'string' && name.length > 0) return name;
    }
  } catch (error) {
    logger.warn('expense notify: actor name lookup failed', {
      gid,
      actorUid,
      error: String(error),
    });
  }
  return '';
}

async function eventParticipantIds(gid: string, eid: string): Promise<string[]> {
  try {
    const snap = await getFirestore().doc(`groups/${gid}/events/${eid}`).get();
    const ids = snap.data()?.participantIds;
    return Array.isArray(ids)
      ? ids.filter((v): v is string => typeof v === 'string')
      : [];
  } catch (error) {
    logger.warn('expense notify: event participants lookup failed', {
      gid,
      eid,
      error: String(error),
    });
    return [];
  }
}

// Who shares the cost: splitDistribution keys (NON-ZERO only — the editor persists
// 0-value rows that owe nothing, #179 Gate R1) when present, else the custom subset
// (custom + equally), else nobody (personal), else all event participants (global /
// equally-with-no-distribution). See docs/plans/2026-06-13-expense-notifier-179.md.
async function shareSet(
  gid: string,
  eid: string,
  data: DocumentData,
): Promise<string[]> {
  const dist = data.splitDistribution;
  if (
    dist &&
    typeof dist === 'object' &&
    !Array.isArray(dist) &&
    Object.keys(dist).length > 0
  ) {
    return Object.entries(dist as Record<string, unknown>)
      .filter(([, v]) => typeof v === 'number' && v > 0)
      .map(([k]) => k);
  }
  const custom = data.customSplitParticipants;
  if (Array.isArray(custom) && custom.length > 0) {
    return custom.filter((v): v is string => typeof v === 'string');
  }
  if (asString(data.scope) === 'personal') return [];
  return eventParticipantIds(gid, eid);
}

async function notifyExpenseCreated(
  gid: string,
  eid: string,
  expenseId: string,
  eventId: string,
  snap: { data(): DocumentData } | undefined,
): Promise<void> {
  if (!snap) return;
  const data = snap.data();
  if (data.isDeleted === true) return;

  const amountFils = data.amountFils;
  if (typeof amountFils !== 'number') return;

  const createdBy = asString(data.createdBy);
  const payer = asString(data.payerParticipantId);

  const base = await shareSet(gid, eid, data);
  const targets = [
    ...new Set(
      [...base, payer].filter((uid) => uid.length > 0 && uid !== createdBy),
    ),
  ];
  if (targets.length === 0) return;

  const actorName = await resolveActorName(gid, createdBy);
  const amountText = formatAmount(amountFils, asString(data.currency) || 'OMR');
  const groupName = await resolveGroupName(gid);
  const description = asString(data.description);

  await sendToUids(
    targets,
    (locale) => ({
      title: expenseTitle(locale, groupName),
      body: expenseBody(locale, actorName, amountText, description),
    }),
    { type: 'expense', groupId: gid, eventId: eid },
    { dedupeKey: `expense:create:${gid}:${eid}:${expenseId}:${eventId}`, requireCurrentMembershipOf: gid },
  );
}

export const expenseNotifier = onDocumentCreated(
  'groups/{gid}/events/{eid}/expenses/{expenseId}',
  (event) => notifyExpenseCreated(
    event.params.gid,
    event.params.eid,
    event.params.expenseId,
    event.id,
    event.data,
  ),
);
