import {
  DocumentData,
  DocumentReference,
  QueryDocumentSnapshot,
  getFirestore,
} from 'firebase-admin/firestore';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import '../admin';
import { assertCorrectionActor } from './shared/correctionActor';
import { validId } from './shared/ids';
import {
  buildEventReverseData,
  buildGroupReverseData,
  hasLiveLegacyCorrectionOf,
  isExpectedReverse,
  isItselfLegacyCorrection,
  isMarkedCorrection,
  logicalReverseId,
  normalizeCorrectionNote,
} from './shared/settlementCorrection';
import { CorrectSettlementOutput } from './correctSettlement';

// #889: server-authoritative logical (decomposed group settle-up) correction
// (#283/#753 track). Replaces the client WriteBatch
// (SettlementCorrectionService.reverseLogicalSettleUp) so every reverse row —
// event-scope slices AND the group-scope residual — carries the un-forgeable
// `correctionOfSettlementId` marker. Validates the FULL logical set
// server-side (a large logical settle-up can exceed 20 event slices, past
// what rules-side get() validation on a client batch could afford). Append-
// only (B3); all-or-nothing per invocation.

const MAX_GROUP_SETTLE_UP_ID_LENGTH = 200;

function validGroupSettleUpId(value: unknown): string {
  if (
    typeof value !== 'string'
    || value.trim().length === 0
    || value.includes('/')
    || value.length > MAX_GROUP_SETTLE_UP_ID_LENGTH
  ) {
    throw new HttpsError('invalid-argument', 'groupSettleUpId must be a valid id.');
  }
  return value;
}

export interface CorrectLogicalSettleUpInput {
  groupId: string;
  groupSettleUpId: string;
  correctionNote: string;
}

export type CorrectLogicalSettleUpOutput = CorrectSettlementOutput;

interface TaggedOriginal {
  scope: 'event' | 'group';
  eventId?: string;
  ref: DocumentReference;
  id: string;
  data: DocumentData;
}

function taggedLiveDocs(
  docs: QueryDocumentSnapshot[],
  groupSettleUpId: string,
): QueryDocumentSnapshot[] {
  return docs.filter((doc) => {
    const data = doc.data();
    return data.isDeleted === false && data.groupSettleUpId === groupSettleUpId;
  });
}

export const correctLogicalSettleUp = onCall<
  CorrectLogicalSettleUpInput,
  Promise<CorrectLogicalSettleUpOutput>
>(
  { enforceAppCheck: true },
  async (request: CallableRequest<CorrectLogicalSettleUpInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }
    const uid = request.auth.uid;
    const groupId = validId(request.data?.groupId, 'groupId');
    const groupSettleUpId = validGroupSettleUpId(request.data?.groupSettleUpId);
    const correctionNote = normalizeCorrectionNote(request.data?.correctionNote);

    const db = getFirestore();
    const groupRef = db.doc(`groups/${groupId}`);

    return db.runTransaction(async (tx) => {
      const groupSnap = await tx.get(groupRef);
      if (!groupSnap.exists) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      const groupData = groupSnap.data() ?? {};
      if (
        groupData.isDeleted === true
        || groupData.deletingInProgress === true
        || groupData.claimingInProgress === true
        || groupData.accountDeletionInProgress === true
        // #1144: correction rows are balance-input writes.
        || groupData.departureInProgress === true
      ) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      const memberIds = groupData.memberIds;
      if (!Array.isArray(memberIds) || !memberIds.includes(uid)) {
        throw new HttpsError('permission-denied', 'You are not a member of this group.');
      }

      // Live events ONLY (mirrors watchGroupEvents/event_service.dart:40 and
      // the oracle's soft-deleted-event skip, groupNetBalance.ts:627-633). A
      // slice under a soft-deleted event is out of the balance universe on
      // both client and server — it is IGNORED (never enumerated, never a
      // failure reason), not fetched via an unscoped collectionGroup scan.
      const eventsSnap = await tx.get(groupRef.collection('events'));
      const liveEventDocs = eventsSnap.docs.filter((doc) => doc.data().isDeleted === false);

      const groupSettlementsSnap = await tx.get(groupRef.collection('settlements'));
      const eventSettlementsSnaps = await Promise.all(
        liveEventDocs.map((eventDoc) => tx.get(eventDoc.ref.collection('settlements'))),
      );

      const taggedOriginals: TaggedOriginal[] = [];
      for (const doc of taggedLiveDocs(groupSettlementsSnap.docs, groupSettleUpId)) {
        taggedOriginals.push({ scope: 'group', ref: doc.ref, id: doc.id, data: doc.data() });
      }
      liveEventDocs.forEach((eventDoc, index) => {
        const snap = eventSettlementsSnaps[index];
        for (const doc of taggedLiveDocs(snap.docs, groupSettleUpId)) {
          taggedOriginals.push({
            scope: 'event',
            eventId: eventDoc.id,
            ref: doc.ref,
            id: doc.id,
            data: doc.data(),
          });
        }
      });

      if (taggedOriginals.length === 0) {
        throw new HttpsError('not-found', 'No settlements found for this group settle-up.');
      }

      // Per-scope participant checks (mirrors eventAllowsClientWrites'
      // participant gate for event slices; current group members for the
      // residual). Live events are already guaranteed by the query above.
      for (const orig of taggedOriginals) {
        const payer = orig.data.payerParticipantId;
        const recipient = orig.data.recipientParticipantId;
        if (typeof payer !== 'string' || typeof recipient !== 'string') {
          throw new HttpsError('failed-precondition', 'Settlement data is malformed.');
        }
        if (orig.scope === 'event') {
          const eventDoc = liveEventDocs.find((doc) => doc.id === orig.eventId)!;
          const participantIds = Array.isArray(eventDoc.data().participantIds)
            ? eventDoc.data().participantIds
            : [];
          if (!participantIds.includes(payer) || !participantIds.includes(recipient)) {
            throw new HttpsError(
              'failed-precondition',
              'Settlement parties are not event participants.',
            );
          }
        } else if (!memberIds.includes(payer) || !memberIds.includes(recipient)) {
          throw new HttpsError(
            'failed-precondition',
            'Settlement parties are not current group members.',
          );
        }
      }

      // Actor policy: membership alone is not enough — only the group creator,
      // or a caller who is a party on EVERY live tagged original, may reverse
      // the set (party-on-some-but-not-all is denied). Evaluated over the full
      // tagged set, deny-biased.
      assertCorrectionActor(uid, groupData.createdBy, taggedOriginals.map((orig) => orig.data));

      // Use only unmarked, non-legacy-correction source rows as originals.
      // The legacy-pairing pool is the tagged set itself (a legacy reverse of
      // a logical original carries the SAME groupSettleUpId, mirroring the
      // old client SettlementCorrectionService.reverseLogicalSettleUp shape).
      const correctableOriginals = taggedOriginals.filter((orig) => {
        if (isMarkedCorrection(orig.data)) return false;
        const others = taggedOriginals
          .filter((other) => other.id !== orig.id)
          .map((other) => other.data);
        return !isItselfLegacyCorrection(orig.data, others);
      });

      const originalsNeedingReverse = correctableOriginals.filter((orig) => {
        const others = taggedOriginals
          .filter((other) => other.id !== orig.id)
          .map((other) => other.data);
        return !hasLiveLegacyCorrectionOf(orig.data, others);
      });

      const nowIso = new Date().toISOString();
      const reverseChecks = await Promise.all(
        originalsNeedingReverse.map(async (orig) => {
          const reverseId = logicalReverseId(groupSettleUpId, orig.ref.path);
          const reverseRef = orig.scope === 'event'
            ? groupRef.collection('events').doc(orig.eventId!).collection('settlements').doc(reverseId)
            : groupRef.collection('settlements').doc(reverseId);
          const reverseSnap = await tx.get(reverseRef);
          return { orig, reverseId, reverseRef, reverseSnap };
        }),
      );

      let anyExistingValid = false;
      let eventScopeTouched = false;
      const toWrite: Array<{ ref: DocumentReference; data: DocumentData; scope: 'event' | 'group' }> = [];

      for (const { orig, reverseId, reverseRef, reverseSnap } of reverseChecks) {
        if (reverseSnap.exists) {
          const reverseData = reverseSnap.data() ?? {};
          if (isExpectedReverse(reverseData, orig.id, orig.data)) {
            anyExistingValid = true;
            if (orig.scope === 'event') eventScopeTouched = true;
            continue;
          }
          throw new HttpsError(
            'already-exists',
            'A conflicting correction already exists for this group settle-up.',
          );
        }

        const reverseData = orig.scope === 'event'
          ? buildEventReverseData(orig.eventId!, {
            newId: reverseId,
            originalId: orig.id,
            originalData: orig.data,
            correctionNote,
            callerUid: uid,
            nowIso,
          })
          : buildGroupReverseData(groupId, {
            newId: reverseId,
            originalId: orig.id,
            originalData: orig.data,
            correctionNote,
            callerUid: uid,
            nowIso,
          });
        toWrite.push({ ref: reverseRef, data: reverseData, scope: orig.scope });
        if (orig.scope === 'event') eventScopeTouched = true;
      }

      let eventScopeWrites = 0;
      let groupScopeWrites = 0;
      for (const w of toWrite) {
        tx.create(w.ref, w.data);
        if (w.scope === 'event') eventScopeWrites += 1;
        else groupScopeWrites += 1;
      }

      return {
        eventScopeWrites,
        groupScopeWrites,
        repaired: toWrite.length > 0 && anyExistingValid,
        noop: toWrite.length === 0,
        shouldBumpLedgerRevision: eventScopeTouched,
      };
    });
  },
);
