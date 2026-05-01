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
    createdBy: opts.memberIds[0],
    currency: 'OMR',
    inviteCode: 'ABC123',
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  await db.doc(`groups/${opts.groupId}/events/${opts.eventId}`).set({
    id: opts.eventId,
    groupId: opts.groupId,
    name: `TestEvent-${opts.eventId}`,
    type: 'trip',
    createdBy: opts.memberIds[0],
    participantIds: opts.memberIds,
    participantNames: Object.fromEntries(opts.memberIds.map((id) => [id, id])),
    modules: { ledger: true },
    isDeleted: false,
    createdAt: new Date(),
  });
}

export async function clearFirestore(): Promise<void> {
  const db = getFirestore();
  const groups = await db.collection('groups').listDocuments();
  for (const g of groups) {
    await db.recursiveDelete(g);
  }
  const inviteCodes = await db.collection('inviteCodes').listDocuments();
  for (const code of inviteCodes) {
    await code.delete();
  }
}

export interface DocSeed {
  id: string;
  fileName: string;
  mimeType: string;
  storagePath: string;
  sizeBytes: number;
  isDeleted?: boolean;
}

export interface MemorySeed {
  id: string;
  storagePath: string;
}

export async function seedDocuments(
  groupId: string,
  eventId: string,
  docs: DocSeed[],
): Promise<void> {
  const db = getFirestore();
  for (const d of docs) {
    await db.doc(`groups/${groupId}/events/${eventId}/documents/${d.id}`).set({
      id: d.id,
      fileName: d.fileName,
      mimeType: d.mimeType,
      storagePath: d.storagePath,
      sizeBytes: d.sizeBytes,
      uploadedBy: 'alice',
      uploadedAt: new Date(),
      isDeleted: d.isDeleted ?? false,
    });
  }
}

export async function seedMemories(
  groupId: string,
  eventId: string,
  mems: MemorySeed[],
): Promise<void> {
  const db = getFirestore();
  for (const m of mems) {
    await db.doc(`groups/${groupId}/events/${eventId}/memories/${m.id}`).set({
      id: m.id,
      storagePath: m.storagePath,
      uploadedBy: 'alice',
      createdAt: new Date(),
    });
  }
}
