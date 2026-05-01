import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import '../admin';

export async function assertMemberOfEvent(
  uid: string,
  groupId: string,
  eventId: string,
): Promise<void> {
  if (!uid || !groupId || !eventId) {
    throw new HttpsError('invalid-argument', 'uid, groupId, eventId required');
  }
  const db = getFirestore();
  const [groupSnap, eventSnap] = await Promise.all([
    db.doc(`groups/${groupId}`).get(),
    db.doc(`groups/${groupId}/events/${eventId}`).get(),
  ]);
  if (!groupSnap.exists) {
    throw new HttpsError('not-found', 'Group not found.');
  }
  if (!eventSnap.exists) {
    throw new HttpsError('not-found', 'Event not found.');
  }
  const memberIds = (groupSnap.data()?.memberIds ?? []) as string[];
  if (!memberIds.includes(uid)) {
    throw new HttpsError('permission-denied', 'Not a member of this group.');
  }
  const participantIds = (eventSnap.data()?.participantIds ?? []) as string[];
  if (!participantIds.includes(uid)) {
    throw new HttpsError('permission-denied', 'Not a participant in this event.');
  }
}
