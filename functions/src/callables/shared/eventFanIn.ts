import {
  DocumentData,
  DocumentReference,
  FieldValue,
  QuerySnapshot,
  Transaction,
} from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

// Fan a member (real joiner or shadow placeholder) into every LIVE event's
// participantIds/participantNames so the ledger can split against them
// immediately. Extracted verbatim from joinGroupByInviteCode (#245 PR1) so
// addShadowMember shares one implementation. Semantics: skip soft-deleted
// events; include closed ones (a closed event rejects new expenses anyway,
// #723); arrayUnion the id; merge the name map; bump updatedAt.

// Firestore caps a transaction at 500 writes; callers guard their fan-in
// event count against this and fail cleanly instead of blowing up mid-tx.
export const MAX_FAN_IN_EVENTS = 400;

export interface EventFanInUpdate {
  ref: DocumentReference;
  addParticipantId: boolean;
  participantNames: Record<string, string>;
}

export function getParticipantIds(eventData: DocumentData, eventId: string): string[] {
  const participantIds = eventData.participantIds;
  if (
    !Array.isArray(participantIds)
    || participantIds.some((participantId) => typeof participantId !== 'string')
  ) {
    throw new HttpsError(
      'failed-precondition',
      `Event ${eventId} participantIds data is malformed.`,
    );
  }
  return participantIds;
}

export function getParticipantNames(
  eventData: DocumentData,
  eventId: string,
): Record<string, string> {
  const participantNames = eventData.participantNames;
  if (
    participantNames == null
    || typeof participantNames !== 'object'
    || Array.isArray(participantNames)
  ) {
    throw new HttpsError(
      'failed-precondition',
      `Event ${eventId} participantNames data is malformed.`,
    );
  }

  const normalized: Record<string, string> = {};
  for (const [participantId, displayName] of Object.entries(participantNames)) {
    if (typeof displayName !== 'string') {
      throw new HttpsError(
        'failed-precondition',
        `Event ${eventId} participantNames data is malformed.`,
      );
    }
    normalized[participantId] = displayName;
  }
  return normalized;
}

export function collectEventFanIn(
  eventsSnap: QuerySnapshot,
  userId: string,
  displayName: string,
): EventFanInUpdate[] {
  const updates: EventFanInUpdate[] = [];
  for (const eventSnap of eventsSnap.docs) {
    const eventData = eventSnap.data() ?? {};
    if (eventData.isDeleted === true) {
      continue;
    }
    const participantIds = getParticipantIds(eventData, eventSnap.id);
    const participantNames = getParticipantNames(eventData, eventSnap.id);
    const addParticipantId = !participantIds.includes(userId);
    const nameChanged = participantNames[userId] !== displayName;
    if (addParticipantId || nameChanged) {
      updates.push({
        ref: eventSnap.ref,
        addParticipantId,
        participantNames: {
          ...participantNames,
          [userId]: displayName,
        },
      });
    }
  }
  return updates;
}

export function applyEventFanIn(
  tx: Transaction,
  updates: EventFanInUpdate[],
  userId: string,
): void {
  for (const eventUpdate of updates) {
    const updateData: Record<string, unknown> = {
      participantNames: eventUpdate.participantNames,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (eventUpdate.addParticipantId) {
      updateData.participantIds = FieldValue.arrayUnion(userId);
    }
    tx.update(eventUpdate.ref, updateData);
  }
}
