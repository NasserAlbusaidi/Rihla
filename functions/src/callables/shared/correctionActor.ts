import { DocumentData } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

// Correction actor policy: a correction may be performed only by the group
// creator or a party (payer/recipient) to EVERY settlement being reversed.
// Party matching is exact uid equality against the settlement's own
// participant-id fields, type-guarded so a null/absent field never matches —
// and a shadow participant's id (a randomUUID, never an auth uid) can never
// satisfy the party branch. Runs AFTER the membership gate and AFTER the
// settlement doc(s) are loaded; needs no extra reads.

function isParty(uid: string, data: DocumentData): boolean {
  const payer = data.payerParticipantId;
  const recipient = data.recipientParticipantId;
  return (typeof payer === 'string' && payer === uid)
    || (typeof recipient === 'string' && recipient === uid);
}

export function assertCorrectionActor(
  uid: string,
  createdBy: unknown,
  originals: ReadonlyArray<DocumentData>,
): void {
  if (typeof createdBy === 'string' && createdBy === uid) {
    return;
  }
  if (originals.length > 0 && originals.every((data) => isParty(uid, data))) {
    return;
  }
  throw new HttpsError(
    'permission-denied',
    'Only the group creator or a party to this settlement can correct it.',
  );
}
