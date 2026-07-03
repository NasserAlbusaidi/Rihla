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
// `userId` FIELD — never the doc id. New client-created member docs key by
// {uid}, but legacy creator docs and server-minted shadows can be uuid-keyed
// (#294/#524), so doc-id lookup is not enough.
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

// #808 PR1 — group-feed fan-in vocabulary. These types are SERVER-ONLY:
// validGroupActivityCreate's allow-list (firestore.rules) rejects them from
// clients, which is also what makes the writeRateMonitor expense_* skip safe.
export type GroupExpenseActivityType =
  | 'expense_added'
  | 'expense_edited'
  | 'expense_deleted';

const GROUP_TYPE: Record<AuditType, GroupExpenseActivityType> = {
  CREATE: 'expense_added',
  UPDATE: 'expense_edited',
  DELETE: 'expense_deleted',
};

// Group-feed description is a VERB PHRASE without the actor name — the
// activity row renders actorName separately (leaveGroup.ts parity: 'left the
// group'); embedding "who" here would double-print the name. English-only
// fallback: current clients render unknown types via activity_display.dart's
// `_ => log.description`; PR2 localizes by type.
export function buildGroupDescription(
  type: AuditType,
  d: DocumentData,
): string {
  const label =
    asString(d.description).trim().length > 0
      ? asString(d.description).trim()
      : 'an expense';
  if (type === 'CREATE') {
    const currency = asString(d.currency) || 'OMR';
    const money = formatAmount(
      typeof d.amountFils === 'number' ? d.amountFils : 0,
      currency,
    );
    return `added ${label} (${money} ${currency})`;
  }
  if (type === 'DELETE') return `deleted ${label}`;
  return `edited ${label}`;
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
    // #278 [P2]: suppress a claimShadow re-key write. The claim engine stamps a
    // fresh claimRekeyAt while swapping CONTENT_KEYS (payerParticipantId/
    // splitDistribution/customSplitParticipants), so without this skip every
    // re-keyed expense would log a phantom UPDATE misattributed to the shadow's
    // createdBy. deepEqual (NOT !==) so serverTimestamp's distinct-but-equal
    // deserialized Timestamp objects compare correctly: a later GENUINE edit
    // leaves claimRekeyAt unchanged and still logs.
    if (!deepEqual(afterData.claimRekeyAt, before?.claimRekeyAt)) return;
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

    // #808 PR1 — fan the same audit event into the group activity feed, in
    // the exact GroupActivityLog client shape (group_activity_log_model.dart):
    // description non-null, timestamp ISO string (sorts lexicographically with
    // the client's toIso8601String), doc id == data.id == event.id (idempotent
    // .set across at-least-once retries; distinct collection from the event
    // log, so the shared id cannot collide). Metadata carries ids + money
    // scalars only — no uid-keyed maps — so the claimShadow rekey (actorId)
    // and the deleteAccount scrub cover it unchanged. The claimRekeyAt
    // early-return above gates this write too: a shadow-claim re-key produces
    // NEITHER entry.
    let eventName = '';
    try {
      const eventSnap = await getFirestore()
        .doc(`groups/${gid}/events/${eid}`)
        .get();
      const rawName = eventSnap.data()?.name;
      if (typeof rawName === 'string') eventName = rawName;
    } catch (error) {
      logger.warn('expenseAuditLogger: event name lookup failed', {
        gid,
        eid,
        error: String(error),
      });
    }

    await getFirestore()
      .doc(`groups/${gid}/activity/${event.id}`)
      .set({
        id: event.id,
        type: GROUP_TYPE[type],
        actorId: actorUid,
        actorName,
        description: buildGroupDescription(type, afterData),
        metadata: {
          expenseId,
          eventId: eid,
          eventName,
          amountFils:
            typeof afterData.amountFils === 'number' ? afterData.amountFils : 0,
          currency: asString(afterData.currency) || 'OMR',
        },
        timestamp: event.time,
      });

    logger.info('expenseAuditLogger logged', {
      gid,
      eid,
      expenseId,
      type,
      actorUid,
    });
  },
);
