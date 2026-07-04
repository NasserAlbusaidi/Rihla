import { CollectionReference, DocumentData, getFirestore } from 'firebase-admin/firestore';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import '../admin';
import { validId } from './shared/ids';
import {
  buildEventReverseData,
  buildGroupReverseData,
  directReverseId,
  hasLiveLegacyCorrectionOf,
  isExpectedReverse,
  isItselfLegacyCorrection,
  isMarkedCorrection,
  normalizeCorrectionNote,
  normalizedGroupSettleUpId,
} from './shared/settlementCorrection';

// #889: server-authoritative direct settlement correction (#283/#753 track).
// Replaces the client-direct reverse write on the solo `onCorrect` sites
// (settle_up_screen.dart / group_settle_up_screen.dart) so the reverse row
// carries an un-forgeable `correctionOfSettlementId` marker (rules deny it on
// client creates — see firestore.rules validEventSettlementBase/
// validGroupSettlementBase hasOnly() key lists). Append-only (B3): originals
// are never mutated, only a new offsetting row is written.

export type CorrectSettlementScope = 'event' | 'group';

export interface CorrectSettlementInput {
  groupId: string;
  scope: CorrectSettlementScope;
  eventId?: string;
  settlementId: string;
  correctionNote: string;
}

export interface CorrectSettlementOutput {
  eventScopeWrites: number;
  groupScopeWrites: number;
  repaired: boolean;
  noop: boolean;
  shouldBumpLedgerRevision: boolean;
}

function noopResult(): CorrectSettlementOutput {
  return {
    eventScopeWrites: 0,
    groupScopeWrites: 0,
    repaired: false,
    noop: true,
    shouldBumpLedgerRevision: false,
  };
}

export const correctSettlement = onCall<
  CorrectSettlementInput,
  Promise<CorrectSettlementOutput>
>(
  { enforceAppCheck: true },
  async (request: CallableRequest<CorrectSettlementInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }
    const uid = request.auth.uid;
    const groupId = validId(request.data?.groupId, 'groupId');
    const scope = request.data?.scope;
    if (scope !== 'event' && scope !== 'group') {
      throw new HttpsError('invalid-argument', 'scope must be "event" or "group".');
    }
    const settlementId = validId(request.data?.settlementId, 'settlementId');
    const eventId = scope === 'event' ? validId(request.data?.eventId, 'eventId') : undefined;
    const correctionNote = normalizeCorrectionNote(request.data?.correctionNote);

    const db = getFirestore();
    const groupRef = db.doc(`groups/${groupId}`);

    return db.runTransaction(async (tx) => {
      const groupSnap = await tx.get(groupRef);
      if (!groupSnap.exists) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      const groupData = groupSnap.data() ?? {};
      // Mirror the rules write-lock groupAllowsClientWrites (firestore.rules:134)
      // server-side — the Admin SDK bypasses rules. Same four flags as
      // addShadowMember.ts:79-82 / joinGroupByInviteCode.ts:231-238.
      if (
        groupData.isDeleted === true
        || groupData.deletingInProgress === true
        || groupData.claimingInProgress === true
        || groupData.accountDeletionInProgress === true
      ) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      const memberIds = groupData.memberIds;
      if (!Array.isArray(memberIds) || !memberIds.includes(uid)) {
        throw new HttpsError('permission-denied', 'You are not a member of this group.');
      }

      let collectionRef: CollectionReference;
      let eventParticipantIds: string[] | null = null;
      if (scope === 'event') {
        const eventRef = groupRef.collection('events').doc(eventId!);
        const eventSnap = await tx.get(eventRef);
        if (!eventSnap.exists) {
          throw new HttpsError('not-found', 'Event not found.');
        }
        const eventData = eventSnap.data() ?? {};
        // Mirror eventAllowsClientWrites (firestore.rules:188) — NOT
        // eventAcceptsExpenseWrites (:206, expense-only close gate).
        // Settlements stay writable after event close.
        if (eventData.isDeleted === true) {
          throw new HttpsError('not-found', 'Event not found.');
        }
        eventParticipantIds = Array.isArray(eventData.participantIds)
          ? eventData.participantIds
          : [];
        collectionRef = eventRef.collection('settlements');
      } else {
        collectionRef = groupRef.collection('settlements');
      }

      const originalRef = collectionRef.doc(settlementId);
      const [originalSnap, collectionSnap] = await Promise.all([
        tx.get(originalRef),
        tx.get(collectionRef),
      ]);

      if (!originalSnap.exists) {
        throw new HttpsError('not-found', 'Settlement not found.');
      }
      const originalData = originalSnap.data() ?? {};
      if (originalData.isDeleted !== false) {
        throw new HttpsError('failed-precondition', 'Settlement has been deleted.');
      }
      const payerParticipantId = originalData.payerParticipantId;
      const recipientParticipantId = originalData.recipientParticipantId;
      if (typeof payerParticipantId !== 'string' || typeof recipientParticipantId !== 'string') {
        throw new HttpsError('failed-precondition', 'Settlement data is malformed.');
      }

      if (scope === 'event') {
        if (
          !eventParticipantIds!.includes(payerParticipantId)
          || !eventParticipantIds!.includes(recipientParticipantId)
        ) {
          throw new HttpsError(
            'failed-precondition',
            'Settlement parties are not event participants.',
          );
        }
      } else if (
        !memberIds.includes(payerParticipantId)
        || !memberIds.includes(recipientParticipantId)
      ) {
        throw new HttpsError(
          'failed-precondition',
          'Settlement parties are not current group members.',
        );
      }

      if (isMarkedCorrection(originalData)) {
        throw new HttpsError('failed-precondition', 'Settlement is already a correction.');
      }
      // Tagged originals belong to one logical group-settle and are corrected
      // only via correctLogicalSettleUp, never piecemeal (mirrors the
      // client-side hidden correct button on tagged rows, #752).
      if (normalizedGroupSettleUpId(originalData) != null) {
        throw new HttpsError(
          'failed-precondition',
          'This settlement is part of a group settle-up and must be corrected as a set.',
        );
      }

      const otherDocs: DocumentData[] = collectionSnap.docs
        .filter((doc) => doc.id !== originalSnap.id)
        .map((doc) => doc.data());

      if (isItselfLegacyCorrection(originalData, otherDocs)) {
        throw new HttpsError('failed-precondition', 'Settlement is already a correction.');
      }
      if (hasLiveLegacyCorrectionOf(originalData, otherDocs)) {
        return noopResult();
      }

      const reverseId = directReverseId(originalRef.path);
      const reverseRef = collectionRef.doc(reverseId);
      const reverseSnap = await tx.get(reverseRef);
      const nowIso = new Date().toISOString();

      if (reverseSnap.exists) {
        const reverseData = reverseSnap.data() ?? {};
        if (isExpectedReverse(reverseData, originalSnap.id, originalData)) {
          return {
            eventScopeWrites: scope === 'event' ? 1 : 0,
            groupScopeWrites: scope === 'group' ? 1 : 0,
            repaired: false,
            noop: true,
            shouldBumpLedgerRevision: scope === 'event',
          };
        }
        throw new HttpsError(
          'already-exists',
          'A conflicting correction already exists for this settlement.',
        );
      }

      const reverseData = scope === 'event'
        ? buildEventReverseData(eventId!, {
          newId: reverseId,
          originalId: originalSnap.id,
          originalData,
          correctionNote,
          callerUid: uid,
          nowIso,
        })
        : buildGroupReverseData(groupId, {
          newId: reverseId,
          originalId: originalSnap.id,
          originalData,
          correctionNote,
          callerUid: uid,
          nowIso,
        });

      tx.create(reverseRef, reverseData);

      return {
        eventScopeWrites: scope === 'event' ? 1 : 0,
        groupScopeWrites: scope === 'group' ? 1 : 0,
        repaired: false,
        noop: false,
        shouldBumpLedgerRevision: scope === 'event',
      };
    });
  },
);
