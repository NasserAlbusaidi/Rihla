import { getFirestore, DocumentData } from 'firebase-admin/firestore';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import '../admin';
import { sendToUids } from '../notifications/fcmSender';
import { eventTitle, eventBody } from '../notifications/strings';

// #179 — buzz an event's participants (minus the creator) when the event is
// created. The fourth and final v1 sender; mirrors settlementNotifier (#53) and
// expenseNotifier (#503). Fires AFTER the client-direct create commits; it only
// reads + sends, NEVER mutates a domain doc.
//
// event.participantIds and createdBy are auth uids (the create path is
// rules-gated: firestore.rules:367 hasOnly(groupMembers()) / :402 auth.uid in
// participantIds), so they map directly to fcm_tokens/{uid}; shadow/unclaimed
// members have no token doc and are silently skipped by sendToUids.
// onDocumentCreated (NOT ...Written), so an open-edit, a soft-delete, or a
// recovery uid-migration update() never re-fires it; and no server path .set()s
// an event doc (recovery/deleteAccount only update, deleteGroup soft-deletes),
// so it never false-buzzes on a cascade.

function asString(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

async function resolveGroupName(gid: string): Promise<string> {
  try {
    const snap = await getFirestore().doc(`groups/${gid}`).get();
    return asString(snap.data()?.name);
  } catch (error) {
    logger.warn('event notify: group name lookup failed', {
      gid,
      error: String(error),
    });
    return '';
  }
}

// Match by the userId FIELD, never the doc id. New client-created member docs
// key by {uid}, but legacy creator docs and server-minted shadows can be
// uuid-keyed (#294/#524). Mirrors expenseNotifier.resolveActorName.
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
    logger.warn('event notify: actor name lookup failed', {
      gid,
      actorUid,
      error: String(error),
    });
  }
  return '';
}

async function notifyEventCreated(
  gid: string,
  eid: string,
  eventId: string,
  snap: { data(): DocumentData } | undefined,
): Promise<void> {
  if (!snap) return;
  const data = snap.data();
  if (data.isDeleted === true) return;

  const createdBy = asString(data.createdBy);
  const participants = Array.isArray(data.participantIds)
    ? data.participantIds.filter((v): v is string => typeof v === 'string')
    : [];

  const targets = [
    ...new Set(participants.filter((uid) => uid.length > 0 && uid !== createdBy)),
  ];
  if (targets.length === 0) return;

  const actorName = await resolveActorName(gid, createdBy);
  const groupName = await resolveGroupName(gid);
  const eventName = asString(data.name);

  await sendToUids(
    targets,
    (locale) => ({
      title: eventTitle(locale, groupName),
      body: eventBody(locale, actorName, eventName),
    }),
    { type: 'event', groupId: gid, eventId: eid },
    { dedupeKey: `event:create:${gid}:${eid}:${eventId}`, requireCurrentMembershipOf: gid },
  );
}

export const eventNotifier = onDocumentCreated(
  'groups/{gid}/events/{eid}',
  (event) => notifyEventCreated(
    event.params.gid,
    event.params.eid,
    event.id,
    event.data,
  ),
);
