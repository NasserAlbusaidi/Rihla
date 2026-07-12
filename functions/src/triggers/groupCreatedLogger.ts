import { getFirestore, DocumentData, Timestamp } from 'firebase-admin/firestore';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import '../admin';

// #1018 — genesis row for the group activity feed. Fires AFTER the
// client-direct founding batch commits (group + inviteCode + creator member +
// seeded event, atomic per #874 — so the creator's member doc exists when
// resolveActorName runs; rules gate the create — this trigger only reads +
// fans in, it never mutates the group doc). Mirrors the expenseAuditLogger
// (#808 PR1) group fan-in shape exactly: groups/{gid}/activity/{event.id}
// with {id,type,actorId,actorName,description,metadata,timestamp}. `metadata`
// is deliberately {} — cross-group History resolves the group name from
// userGroupsProvider, not from this row. `type: 'group_created'` is NOT in
// validGroupActivityCreate's client allow-list (firestore.rules), so this
// Admin-SDK write is the sole source — a client cannot forge it.

// Match by the userId FIELD, never the doc id — mirrors expenseAuditLogger.ts/
// eventNotifier.ts (each trigger file carries its own copy by convention).
// New client-created member docs key by {uid}, but legacy creator docs and
// server-minted shadows can be uuid-keyed (#294/#524).
async function resolveActorName(gid: string, actorUid: string): Promise<string | null> {
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
    logger.warn('groupCreatedLogger: actor name lookup failed', {
      gid,
      actorUid,
      error: String(error),
    });
  }
  return null;
}

async function logGroupCreated(
  gid: string,
  eventId: string,
  eventTime: string,
  data: DocumentData | undefined,
): Promise<void> {
  if (!data) return;

  const createdBy = data.createdBy;
  if (typeof createdBy !== 'string' || createdBy.length === 0) {
    logger.warn('groupCreatedLogger: group missing createdBy, skipping', { gid });
    return;
  }

  const actorName = await resolveActorName(gid, createdBy);
  const timestamp =
    data.createdAt instanceof Timestamp ? data.createdAt.toDate().toISOString() : eventTime;

  // Doc id == event.id: stable across at-least-once Eventarc retries, so this
  // .set is idempotent (same convention as expenseAuditLogger D7).
  await getFirestore()
    .doc(`groups/${gid}/activity/${eventId}`)
    .set({
      id: eventId,
      type: 'group_created',
      actorId: createdBy,
      actorName,
      description: 'created the group',
      metadata: {},
      timestamp,
    });

  logger.info('groupCreatedLogger logged', { gid, actorId: createdBy });
}

export const groupCreatedLogger = onDocumentCreated('groups/{gid}', (event) =>
  logGroupCreated(event.params.gid, event.id, event.time, event.data?.data()),
);
