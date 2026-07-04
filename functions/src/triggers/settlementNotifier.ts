import { getFirestore, DocumentData } from 'firebase-admin/firestore';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import '../admin';
import { sendToUids } from '../notifications/fcmSender';
import { formatAmount } from '../notifications/formatAmount';
import { settlementTitle, settlementBody } from '../notifications/strings';

// #53 — notify the counterparty when a settlement is recorded. Fires AFTER the
// write commits (the create is client-direct; see writeRateMonitor.ts) and only
// reads + sends — it NEVER mutates the financial doc. Settlement parties
// (payer/recipient ParticipantId) and createdBy are auth uids (verified:
// group_settle_up_screen.dart:402-403, settlement_service.dart:90-105), so they
// map directly to fcm_tokens/{uid}; shadow/unclaimed members have no token doc
// and are silently skipped by sendToUids.

function asString(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

async function resolveGroupName(gid: string): Promise<string> {
  try {
    const snap = await getFirestore().doc(`groups/${gid}`).get();
    return asString(snap.data()?.name);
  } catch (error) {
    logger.warn('settlement notify: group name lookup failed', {
      gid,
      error: String(error),
    });
    return '';
  }
}

async function notifySettlement(
  gid: string,
  eid: string | null,
  settlementId: string,
  eventId: string,
  snap: { data(): DocumentData } | undefined,
): Promise<void> {
  if (!snap) return;
  const data = snap.data();
  if (data.isDeleted === true) return;
  // #889: a marked correction reverse is a server-written offsetting row, not
  // a fresh payment — skip its push. Presence-only (no read): rules deny a
  // client-created `correctionOfSettlementId`
  // (firestore.rules validEventSettlementBase/validGroupSettlementBase
  // hasOnly() key lists), so presence alone proves an Admin SDK write. If a
  // future rules edit ever admits a client-written marker, this skip becomes
  // forgeable.
  if (typeof data.correctionOfSettlementId === 'string' && data.correctionOfSettlementId.trim().length > 0) {
    return;
  }

  const amountFils = data.amountFils;
  if (typeof amountFils !== 'number') return;

  const payer = asString(data.payerParticipantId);
  const recipient = asString(data.recipientParticipantId);
  const createdBy = asString(data.createdBy);

  const targets = [
    ...new Set(
      [payer, recipient].filter((uid) => uid.length > 0 && uid !== createdBy),
    ),
  ];
  if (targets.length === 0) return;

  // Third-party recorder (createdBy is neither party) resolves to an empty name;
  // settlementBody localizes the empty-name fallback per recipient locale (#483)
  // — never mislabel the actor as the recipient (Gate P2 #53).
  const actorName =
    createdBy === payer
      ? asString(data.payerName)
      : createdBy === recipient
        ? asString(data.recipientName)
        : '';

  const amountText = formatAmount(amountFils, asString(data.currency) || 'OMR');
  const groupName = await resolveGroupName(gid);

  const payload: Record<string, string> = { type: 'settlement', groupId: gid };
  if (eid) payload.eventId = eid;
  const dedupeKey = eid
    ? `settlement:event:${gid}:${eid}:${settlementId}:${eventId}`
    : `settlement:group:${gid}:${settlementId}:${eventId}`;

  await sendToUids(
    targets,
    (locale) => ({
      title: settlementTitle(locale, groupName),
      body: settlementBody(locale, actorName, amountText),
    }),
    payload,
    { dedupeKey },
  );
}

export const eventSettlementNotifier = onDocumentCreated(
  'groups/{gid}/events/{eid}/settlements/{settlementId}',
  (event) => notifySettlement(
    event.params.gid,
    event.params.eid,
    event.params.settlementId,
    event.id,
    event.data,
  ),
);

export const groupSettlementNotifier = onDocumentCreated(
  'groups/{gid}/settlements/{settlementId}',
  (event) => notifySettlement(
    event.params.gid,
    null,
    event.params.settlementId,
    event.id,
    event.data,
  ),
);
