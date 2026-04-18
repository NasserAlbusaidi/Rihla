import { getFirestore } from 'firebase-admin/firestore';
import './../src/admin';

export interface SeedOptions {
  groupId: string;
  eventId: string;
  memberIds: string[];
}

export async function seedGroupWithEvent(opts: SeedOptions): Promise<void> {
  const db = getFirestore();
  await db.doc(`groups/${opts.groupId}`).set({
    id: opts.groupId,
    name: `TestGroup-${opts.groupId}`,
    memberIds: opts.memberIds,
    createdAt: new Date(),
  });
  await db.doc(`groups/${opts.groupId}/events/${opts.eventId}`).set({
    id: opts.eventId,
    groupId: opts.groupId,
    name: `TestEvent-${opts.eventId}`,
    createdAt: new Date(),
  });
}

export async function clearFirestore(): Promise<void> {
  const db = getFirestore();
  const groups = await db.collection('groups').listDocuments();
  for (const g of groups) {
    const events = await g.collection('events').listDocuments();
    for (const e of events) { await e.delete(); }
    await g.delete();
  }
}
