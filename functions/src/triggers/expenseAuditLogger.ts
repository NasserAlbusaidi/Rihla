import { getFirestore, DocumentData } from 'firebase-admin/firestore';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import '../admin';
import { formatAmount } from '../notifications/formatAmount';

// #248 PR 2 — tamper-proof expense audit log. Fires AFTER an expense write
// commits and writes ONE entry to the event activity_logs subcollection. Runs as
// Admin (no request.auth), so the actor lives IN the document: lastEditedBy
// (rule-pinned to the writer in PR 1), falling back to createdBy. It NEVER
// mutates the expense doc, and watches expenses/{id} only — its activity_logs
// write is on a disjoint path, so it cannot re-fire itself (the _writeCounters
// loop-safety pattern, writeRateMonitor.ts:39-43). Clients can no longer create
// activity_logs entries (validActivityCreate removed from firestore.rules), so
// this trigger is the sole writer — a client cannot forge an audit entry.

export type AuditType = 'CREATE' | 'UPDATE' | 'DELETE';

// The persisted expense keys whose change is a user-meaningful edit worth logging.
// Excludes isDeleted/deletedAt (the DELETE branch owns those), lastEditedBy/
// createdBy/id/eventId/createdAt (identity/immutable), and receiptUrl (no edit
// path touches it) — so a lastEditedBy-only or metadata-only write never logs a
// phantom "edited" entry.
const CONTENT_KEYS = [
  'amountFils',
  'currency',
  'payerParticipantId',
  'description',
  'note',
  'scope',
  'subGroupId',
  'categoryId',
  'splitMode',
  'splitDistribution',
  'customSplitParticipants',
] as const;

function asString(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

function deepEqual(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (a === null || b === null || a === undefined || b === undefined) return a === b;
  if (Array.isArray(a) && Array.isArray(b)) {
    return a.length === b.length && a.every((v, i) => deepEqual(v, b[i]));
  }
  if (typeof a === 'object' && typeof b === 'object') {
    const ak = Object.keys(a as Record<string, unknown>);
    const bk = Object.keys(b as Record<string, unknown>);
    return (
      ak.length === bk.length &&
      ak.every((k) =>
        deepEqual(
          (a as Record<string, unknown>)[k],
          (b as Record<string, unknown>)[k],
        ),
      )
    );
  }
  return false;
}

function contentChanged(before: DocumentData, after: DocumentData): boolean {
  return CONTENT_KEYS.some((k) => !deepEqual(before[k], after[k]));
}

// Returns the eventType to log, or null to SKIP. Everything on the expense path
// is soft-delete (no hard doc delete), so a "delete" is an isDeleted false→true
// UPDATE, never an absent `after`. See spec D2.
export function classify(
  before: DocumentData | undefined,
  after: DocumentData | undefined,
): AuditType | null {
  if (!after) return null; // hard delete — does not happen on the expense path
  const isDeleted = after.isDeleted === true;
  if (!before) return isDeleted ? null : 'CREATE';
  const wasDeleted = before.isDeleted === true;
  if (wasDeleted) return null; // edit of an already-deleted doc (admin scrub/migration) — SKIP (D5)
  if (isDeleted) return 'DELETE'; // soft-delete (false → true)
  return contentChanged(before, after) ? 'UPDATE' : null; // real edit vs no-op
}

// The money fields the audit row records for PR 3's before/after rendering.
function moneySnap(d: DocumentData): Record<string, unknown> {
  return {
    amountFils: typeof d.amountFils === 'number' ? d.amountFils : 0,
    currency: asString(d.currency) || 'OMR',
    payerParticipantId: asString(d.payerParticipantId) || null,
    description: asString(d.description) || null,
    isDeleted: d.isDeleted === true,
  };
}

// Resolve the actor's display name from the group's members, matched by the
// `userId` FIELD — never the doc id: joiners key by {uid} but the creator's doc
// is keyed by a random uuid with `userId:uid` (#294), so .doc(uid) misses it.
// Mirrors leaveGroup.ts:66-99. Returns null (NOT 'Someone') when unresolved —
// the event activity feed localizes a null actor to l10n.activitySomeone at
// render (activity_feed_screen.dart); a literal 'Someone' would break Arabic/RTL.
async function resolveActorName(
  gid: string,
  actorUid: string,
): Promise<string | null> {
  if (!actorUid) return null;
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
    logger.warn('expenseAuditLogger: actor name lookup failed', {
      gid,
      actorUid,
      error: String(error),
    });
  }
  return null;
}

// Non-localized fallback string. The feed derives the displayed verb from
// (category, eventType) → l10n; logText is only the `_` fallback in
// activity_display.dart, but fromFirestore requires it non-null.
function buildLogText(
  type: AuditType,
  name: string | null,
  d: DocumentData,
): string {
  const who = name ?? 'Someone';
  const currency = asString(d.currency) || 'OMR';
  const money = formatAmount(
    typeof d.amountFils === 'number' ? d.amountFils : 0,
    currency,
  );
  const label =
    asString(d.description).trim().length > 0
      ? asString(d.description).trim()
      : 'an expense';
  if (type === 'CREATE') return `${who} added ${label} for ${money} ${currency}`;
  if (type === 'DELETE') return `${who} deleted ${label}`;
  return `${who} edited ${label}`;
}

export const expenseAuditLogger = onDocumentWritten(
  'groups/{gid}/events/{eid}/expenses/{expenseId}',
  async (event) => {
    const change = event.data;
    const before = change?.before.exists ? change.before.data() : undefined;
    const after = change?.after.exists ? change.after.data() : undefined;

    const type = classify(before, after);
    if (!type) return;

    const { gid, eid, expenseId } = event.params;
    const afterData = after as DocumentData; // type !== null ⇒ after exists
    const actorUid = asString(afterData.lastEditedBy) || asString(afterData.createdBy);
    const actorName = await resolveActorName(gid, actorUid);

    const entry = {
      id: event.id, // stable across at-least-once retries → idempotent .set (D7)
      eventId: eid,
      category: 'MONEY',
      eventType: type,
      logText: buildLogText(type, actorName, afterData),
      actorId: actorUid,
      actorName,
      metadata: {
        expenseId,
        before: before ? moneySnap(before) : null,
        after: moneySnap(afterData),
      },
      createdAt: event.time, // CloudEvent.time is already an ISO string
    };

    await getFirestore()
      .doc(`groups/${gid}/events/${eid}/activity_logs/${event.id}`)
      .set(entry);

    logger.info('expenseAuditLogger logged', {
      gid,
      eid,
      expenseId,
      type,
      actorUid,
    });
  },
);
