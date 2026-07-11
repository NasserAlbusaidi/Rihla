import {
  DocumentData,
  DocumentReference,
  QueryDocumentSnapshot,
  getFirestore,
} from 'firebase-admin/firestore';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import '../admin';
import {
  GroupBalanceSnapshot,
  computeNetFromSnapshot,
  currencyScale,
  isSupportedCurrency,
} from './groupNetBalance';
import { MAX_FAN_IN_EVENTS } from './shared/eventFanIn';
import { normalizeRequiredDisplayName } from './shared/displayName';
import { validId } from './shared/ids';
import { outstandingForPairFils } from './shared/outstanding';
import {
  decomposeLegSettlementId,
  decomposeResidualSettlementId,
  deterministicSettlementId,
} from './shared/settlementIds';

// #1129: the transactional settlement CREATE. Settlement creates are
// CALLABLE-ONLY (firestore.rules denies client direct writes in both scopes) —
// this callable recomputes the pair's outstanding on the settle's scope basis
// INSIDE the transaction via the shared oracle, caps amountFils at it (the
// #1093-residual over-settle/forged-amount closure), derives the sd1 dedup id
// from the client's observed pair-epoch (network retries are idempotent), and
// writes the settlement doc(s) + the ONE #1140 activity row atomically.
//
// Concurrency: one db.runTransaction (the correctSettlement /
// correctLogicalSettleUp idiom, NOT the #1144 3-phase departure lock) —
// settle-vs-settle races serialize on the settlements read-set, and expense
// writes racing the transaction invalidate it into a retry with fresh reads.
//
// Spec: docs/plans/2026-07-11-1129-transactional-settlement-callable.md

export type RecordSettlementMode = 'event' | 'group' | 'groupSettleUp';

export interface RecordSettlementLeg {
  eventId: string;
  amountFils: number;
}

export interface RecordSettlementInput {
  groupId: string;
  mode: RecordSettlementMode;
  eventId?: string;
  payerParticipantId: string;
  recipientParticipantId: string;
  amountFils: number; // positive int subunits; the TOTAL for groupSettleUp
  currency: string;
  note?: string | null;
  payerName?: string | null;
  recipientName?: string | null;
  observedPairEpoch: number;
  legs?: RecordSettlementLeg[];
}

export interface RecordSettlementOutput {
  alreadyRecorded: boolean;
  eventScopeWrites: number;
  groupScopeWrites: number;
  shouldBumpLedgerRevision: boolean;
  settledAt: string;
}

const MAX_OBSERVED_EPOCH = 10_000_000;

function positiveInt(value: unknown, label: string): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value <= 0) {
    throw new HttpsError('invalid-argument', `${label} must be a positive integer.`);
  }
  return value;
}

// Mirror firestore.rules validFreeText (null | string ≤ 280, no control chars).
function nullableFreeText(value: unknown, label: string): string | null {
  if (value == null) return null;
  if (
    typeof value !== 'string'
    || value.length > 280
    // eslint-disable-next-line no-control-regex
    || /[\x00-\x1f\x7f]/.test(value)
  ) {
    throw new HttpsError('invalid-argument', `${label} is not valid free text.`);
  }
  return value;
}

// Mirror firestore.rules isValidNullableDisplayName via the shared validator.
function nullableDisplayName(value: unknown, label: string): string | null {
  if (value == null) return null;
  try {
    return normalizeRequiredDisplayName(value);
  } catch (_) {
    throw new HttpsError('invalid-argument', `${label} is not a valid display name.`);
  }
}

function decimalsFor(currency: string): number {
  const scale = currencyScale(currency);
  return scale === 1000 ? 3 : scale === 100 ? 2 : 0;
}

// AppFormatters.formatCurrency mirror ('OMR 3.000' / 'JPY 250') — integer-only
// math so no float ever touches money. Golden-pinned by the description
// assertions in recordSettlement.event.test.ts.
function formatCurrencyFixed(amountFils: number, currency: string): string {
  const scale = currencyScale(currency);
  const decimals = decimalsFor(currency);
  const whole = Math.floor(amountFils / scale);
  if (decimals === 0) return `${currency} ${whole}`;
  return `${currency} ${whole}.${`${amountFils % scale}`.padStart(decimals, '0')}`;
}

// Dart Decimal.toString() mirror for the group-shape activity metadata
// `amount` STRING (trailing zeros stripped: 7000 fils OMR → '7', 2900 → '2.9').
function decimalString(amountFils: number, currency: string): string {
  const scale = currencyScale(currency);
  const whole = Math.floor(amountFils / scale);
  const frac = `${amountFils % scale}`.padStart(decimalsFor(currency), '0').replace(/0+$/, '');
  return frac.length === 0 ? `${whole}` : `${whole}.${frac}`;
}

export const recordSettlement = onCall<
  RecordSettlementInput,
  Promise<RecordSettlementOutput>
>(
  { enforceAppCheck: true },
  async (request: CallableRequest<RecordSettlementInput>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required.');
    }
    const uid = request.auth.uid;

    const groupId = validId(request.data?.groupId, 'groupId');
    const mode = request.data?.mode;
    if (mode !== 'event' && mode !== 'group' && mode !== 'groupSettleUp') {
      throw new HttpsError('invalid-argument', 'mode must be "event", "group" or "groupSettleUp".');
    }
    const eventId = mode === 'event' ? validId(request.data?.eventId, 'eventId') : undefined;
    const payerParticipantId = validId(request.data?.payerParticipantId, 'payerParticipantId');
    const recipientParticipantId = validId(
      request.data?.recipientParticipantId,
      'recipientParticipantId',
    );
    if (payerParticipantId === recipientParticipantId) {
      throw new HttpsError('invalid-argument', 'payer and recipient must differ.');
    }
    const amountFils = positiveInt(request.data?.amountFils, 'amountFils');
    const currency = request.data?.currency;
    // Strict WRITE-path validation: canonical uppercase supported code only.
    // (currencyOf's OMR-fence is for untrusted READS — never for accepting a
    // write.) Case matters: oracle buckets are case-preserved.
    if (
      typeof currency !== 'string'
      || currency !== currency.toUpperCase()
      || !isSupportedCurrency(currency)
    ) {
      throw new HttpsError('invalid-argument', 'currency must be a supported uppercase code.');
    }
    const note = nullableFreeText(request.data?.note, 'note');
    const payerName = nullableDisplayName(request.data?.payerName, 'payerName');
    const recipientName = nullableDisplayName(request.data?.recipientName, 'recipientName');
    const observedPairEpoch = request.data?.observedPairEpoch;
    if (
      typeof observedPairEpoch !== 'number'
      || !Number.isInteger(observedPairEpoch)
      || observedPairEpoch < 0
      || observedPairEpoch > MAX_OBSERVED_EPOCH
    ) {
      throw new HttpsError('invalid-argument', 'observedPairEpoch must be a small non-negative integer.');
    }

    // legs: required iff groupSettleUp. The client routes an empty
    // decomposition (cross-event debt, invariant 11) to mode 'group' — an
    // empty legs array here is a malformed call, not a fallback.
    const rawLegs = request.data?.legs;
    let legs: RecordSettlementLeg[] | undefined;
    if (mode === 'groupSettleUp') {
      if (!Array.isArray(rawLegs) || rawLegs.length === 0) {
        throw new HttpsError('invalid-argument', 'groupSettleUp requires at least one leg.');
      }
      if (rawLegs.length > MAX_FAN_IN_EVENTS) {
        throw new HttpsError(
          'failed-precondition',
          `A settle-up may decompose into at most ${MAX_FAN_IN_EVENTS} legs (transaction write cap).`,
        );
      }
      legs = rawLegs.map((leg, i) => ({
        eventId: validId((leg as RecordSettlementLeg | undefined)?.eventId, `legs[${i}].eventId`),
        amountFils: positiveInt((leg as RecordSettlementLeg | undefined)?.amountFils, `legs[${i}].amountFils`),
      }));
      if (new Set(legs.map((l) => l.eventId)).size !== legs.length) {
        throw new HttpsError('invalid-argument', 'legs must have distinct eventIds.');
      }
      const legsTotal = legs.reduce((sum, l) => sum + l.amountFils, 0);
      if (legsTotal > amountFils) {
        throw new HttpsError(
          'failed-precondition',
          'Decomposition exceeds the total — refresh and re-stage.',
          { kind: 'stale-decomposition' },
        );
      }
    } else if (rawLegs !== undefined) {
      throw new HttpsError('invalid-argument', 'legs are only valid for groupSettleUp.');
    }

    const db = getFirestore();
    const groupRef = db.doc(`groups/${groupId}`);

    return db.runTransaction(async (tx) => {
      const groupSnap = await tx.get(groupRef);
      if (!groupSnap.exists) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      const groupData = groupSnap.data() ?? {};
      // Mirror the rules write-lock groupAllowsClientWrites server-side (the
      // Admin SDK bypasses rules) — same five flags as correctSettlement.ts.
      if (
        groupData.isDeleted === true
        || groupData.deletingInProgress === true
        || groupData.claimingInProgress === true
        || groupData.accountDeletionInProgress === true
        || groupData.departureInProgress === true
      ) {
        throw new HttpsError('not-found', 'Group not found.');
      }
      const memberIds = groupData.memberIds;
      if (!Array.isArray(memberIds) || !memberIds.includes(uid)) {
        throw new HttpsError('permission-denied', 'You are not a member of this group.');
      }
      // #1144: counterparties must be CURRENT members in every scope
      // (deleteAccount tombstone ghosts sit IN memberIds and stay settleable).
      if (!memberIds.includes(payerParticipantId) || !memberIds.includes(recipientParticipantId)) {
        throw new HttpsError(
          'failed-precondition',
          'Settlement parties are not current group members.',
          { kind: 'party-not-member' },
        );
      }

      const membersSnap = await tx.get(groupRef.collection('members'));
      const members = membersSnap.docs.map((doc) => ({ docId: doc.id, data: doc.data() }));

      let snapshot: GroupBalanceSnapshot;
      let eventName: string | null = null;
      const legRefs = new Map<string, DocumentReference>();
      let eventSettlementsRef: ReturnType<DocumentReference['collection']> | null = null;

      if (mode === 'event') {
        const eventRef = groupRef.collection('events').doc(eventId!);
        const eventSnap = await tx.get(eventRef);
        if (!eventSnap.exists) {
          throw new HttpsError('not-found', 'Event not found.');
        }
        const eventData = eventSnap.data() ?? {};
        // Mirror eventAllowsClientWrites: only soft-delete gates settlements —
        // a CLOSED event still accepts them (close gates expenses only).
        if (eventData.isDeleted === true) {
          throw new HttpsError('not-found', 'Event not found.');
        }
        const participantIds = Array.isArray(eventData.participantIds)
          ? eventData.participantIds
          : [];
        if (
          !participantIds.includes(payerParticipantId)
          || !participantIds.includes(recipientParticipantId)
        ) {
          throw new HttpsError(
            'failed-precondition',
            'Settlement parties are not event participants.',
            { kind: 'party-not-participant' },
          );
        }
        eventName = typeof eventData.name === 'string' && eventData.name.length > 0
          ? eventData.name
          : null;
        const [expensesSnap, settlementsSnap] = await Promise.all([
          tx.get(eventRef.collection('expenses')),
          tx.get(eventRef.collection('settlements')),
        ]);
        eventSettlementsRef = eventRef.collection('settlements');
        // One-event snapshot with NO group settlements: computeNetFromSnapshot
        // over it IS the client's event-scope basis (#249 universe fold of the
        // single event — the #773 revalidation basis), by construction.
        snapshot = {
          groupExists: true,
          groupData,
          members,
          events: [{
            id: eventId!,
            ref: eventRef,
            data: eventData,
            expenses: expensesSnap.docs.map((d) => d.data()),
            settlements: settlementsSnap.docs.map((d) => d.data()),
          }],
          groupSettlements: [],
        };
      } else {
        const eventsSnap = await tx.get(groupRef.collection('events'));
        // Live events only: the write-lock flags were rejected above, so the
        // #205 delete-lock resume window (the reason loadGroupBalanceSnapshot
        // fetches soft-deleted events' children) cannot apply here — the
        // compute would filter them anyway (correctLogicalSettleUp idiom).
        const liveEventDocs = eventsSnap.docs.filter(
          (doc: QueryDocumentSnapshot) => doc.data().isDeleted === false,
        );
        const liveIds = new Set(liveEventDocs.map((doc) => doc.id));
        if (legs != null) {
          for (const leg of legs) {
            if (!liveIds.has(leg.eventId)) {
              throw new HttpsError(
                'failed-precondition',
                'A decomposition leg points at a missing or deleted event — refresh and re-stage.',
                { kind: 'stale-decomposition' },
              );
            }
          }
        }
        const [groupSettlementsSnap, children] = await Promise.all([
          tx.get(groupRef.collection('settlements')),
          Promise.all(liveEventDocs.map(async (eventDoc) => {
            const [expensesSnap, settlementsSnap] = await Promise.all([
              tx.get(eventDoc.ref.collection('expenses')),
              tx.get(eventDoc.ref.collection('settlements')),
            ]);
            return {
              id: eventDoc.id,
              ref: eventDoc.ref,
              data: eventDoc.data(),
              expenses: expensesSnap.docs.map((d) => d.data()),
              settlements: settlementsSnap.docs.map((d) => d.data()),
            };
          })),
        ]);
        for (const eventDoc of liveEventDocs) {
          legRefs.set(eventDoc.id, eventDoc.ref);
        }
        snapshot = {
          groupExists: true,
          groupData,
          members,
          events: children,
          groupSettlements: groupSettlementsSnap.docs.map((d) => d.data()),
        };
      }

      const result = computeNetFromSnapshot(snapshot);

      // Ids — the #1093 grammar, epoch = the client's OBSERVATION (a dedup
      // nonce: retries re-derive the same id; it is never an equality gate —
      // the cap below is the money guard).
      const scopeKey = mode === 'event'
        ? `event:${groupId}:${eventId}`
        : mode === 'group'
          ? `group:${groupId}`
          : `gsu:${groupId}`;
      const primaryId = deterministicSettlementId({
        scopeKey,
        payerParticipantId,
        recipientParticipantId,
        currency,
        amountFils,
        pairEpoch: observedPairEpoch,
      });

      const residualFils = mode === 'groupSettleUp'
        ? amountFils - legs!.reduce((sum, l) => sum + l.amountFils, 0)
        : 0;

      const eventScopeWrites = mode === 'event' ? 1 : mode === 'groupSettleUp' ? legs!.length : 0;
      const groupScopeWrites = mode === 'group' ? 1 : residualFils > 0 ? 1 : 0;

      const groupSettlementsRef = groupRef.collection('settlements');
      // Idempotency probe: the doc a replay of THIS logical settle would have
      // created first. gsu probes the residual (or the first leg when the
      // decompose was exact) — leg/residual ids derive from the parent gsu id,
      // which encodes pair+currency+total+epoch.
      const probeRef = mode === 'event'
        ? eventSettlementsRef!.doc(primaryId)
        : mode === 'group'
          ? groupSettlementsRef.doc(primaryId)
          : residualFils > 0
            ? groupSettlementsRef.doc(decomposeResidualSettlementId(primaryId))
            : legRefs.get(legs![0].eventId)!.collection('settlements')
              .doc(decomposeLegSettlementId(primaryId, legs![0].eventId));
      const probeSnap = await tx.get(probeRef);

      if (probeSnap.exists) {
        const existing = probeSnap.data() ?? {};
        const pairMatches = existing.payerParticipantId === payerParticipantId
          && existing.recipientParticipantId === recipientParticipantId
          && existing.currency === currency;
        const matches = mode === 'groupSettleUp'
          ? pairMatches && existing.groupSettleUpId === primaryId
          : pairMatches && existing.amountFils === amountFils;
        if (matches) {
          return {
            alreadyRecorded: true,
            eventScopeWrites,
            groupScopeWrites,
            shouldBumpLedgerRevision: eventScopeWrites > 0,
            settledAt: typeof existing.settledAt === 'string'
              ? existing.settledAt
              : new Date().toISOString(),
          };
        }
        throw new HttpsError(
          'already-exists',
          'A conflicting settlement already exists — refresh and retry.',
        );
      }

      // The cap — AFTER the idempotency probe (a replay of a call that already
      // drained the pair must be recognized, not re-capped into a false
      // over-outstanding). Event mode: the one-event snapshot's aggregate IS
      // the event basis. Group/gsu: the full-group aggregate. REJECT, never
      // clamp — clamping silently changes what the user confirmed.
      const outstandingFils = outstandingForPairFils(
        result.net,
        currency,
        payerParticipantId,
        recipientParticipantId,
      );
      if (amountFils > outstandingFils) {
        throw new HttpsError(
          'failed-precondition',
          'Amount exceeds the pair\'s outstanding balance.',
          { kind: 'over-outstanding', outstandingFils, currency },
        );
      }

      // gsu legs: each ≤ the participantIds-only per-event drill-down overlap
      // (the SAME basis the client decompose allocated from — never the #249
      // universe here; the two bases deliberately do not reconcile).
      if (mode === 'groupSettleUp') {
        for (const leg of legs!) {
          const legCap = outstandingForPairFils(
            result.perEventNet.get(leg.eventId) ?? new Map(),
            currency,
            payerParticipantId,
            recipientParticipantId,
          );
          if (leg.amountFils > legCap) {
            throw new HttpsError(
              'failed-precondition',
              'A decomposition leg exceeds its event\'s outstanding — refresh and re-stage.',
              { kind: 'stale-decomposition' },
            );
          }
        }
      }

      // ISO STRINGS ONLY (Gate R2 P1): the whole read-path type-buckets on
      // String settledAt/timestamp — a Firestore Timestamp here breaks
      // ordering and epoch-0s Settlement.fromFirestore. One shared stamp for
      // every doc of the call (the client batch did the same).
      const nowIso = new Date().toISOString();

      const settlementBase: DocumentData = {
        payerParticipantId,
        recipientParticipantId,
        payerName,
        recipientName,
        currency,
        note,
        isDeleted: false,
        deletedAt: null,
        settledAt: nowIso,
        createdBy: uid,
      };
      const eventSettlementDoc = (
        id: string,
        forEventId: string,
        fils: number,
        groupSettleUpId: string | null,
      ): DocumentData => {
        const data: DocumentData = {
          id, eventId: forEventId, amountFils: fils, ...settlementBase,
        };
        if (groupSettleUpId != null) data.groupSettleUpId = groupSettleUpId;
        return data;
      };
      const groupSettlementDoc = (
        id: string,
        fils: number,
        groupSettleUpId: string | null,
      ): DocumentData => {
        const data: DocumentData = {
          id,
          groupId,
          eventId: groupId, // sentinel — group settlements have no event
          scope: 'group',
          amountFils: fils,
          ...settlementBase,
        };
        if (groupSettleUpId != null) data.groupSettleUpId = groupSettleUpId;
        return data;
      };

      // Activity actor: the RECORDER. actorId drives paid/received/between
      // classification (activity_display.dart); actorName is the avatar chip
      // only — derived from the recorder's member doc (matched by the userId
      // FIELD, never the doc id — member keying is mixed), display-name
      // floored like the client's sanitizeActorName.
      const memberDoc = members.find((m) => m.data.userId === uid);
      let actorName: string | null = null;
      if (typeof memberDoc?.data.displayName === 'string') {
        try {
          actorName = normalizeRequiredDisplayName(memberDoc.data.displayName);
        } catch (_) {
          actorName = null;
        }
      }
      actorName ??= (uid === payerParticipantId ? payerName : recipientName) ?? 'Someone';
      const counterpartyName = (uid === recipientParticipantId
        ? payerName
        : recipientName) ?? 'Someone';
      const description = `settled ${formatCurrencyFixed(amountFils, currency)} with ${counterpartyName}`;

      // #808 metadata contract — the two shapes DIVERGE per mode on purpose;
      // never homogenize (type-guarded readers key on these exact fields).
      const activityId = mode === 'groupSettleUp' ? `gstl_${primaryId}` : `stl_${primaryId}`;
      const activityType = mode === 'event' ? 'event_settlement' : 'group_settlement';
      const metadata: DocumentData = mode === 'event'
        ? {
          amountFils,
          currency,
          fromUserId: payerParticipantId,
          toUserId: recipientParticipantId,
          fromName: payerName ?? '',
          toName: recipientName ?? '',
          eventId: eventId!,
          ...(eventName != null ? { eventName } : {}),
        }
        : {
          amount: decimalString(amountFils, currency),
          recipientId: recipientParticipantId,
          currency,
          fromUserId: payerParticipantId,
          toUserId: recipientParticipantId,
          fromName: payerName ?? '',
          toName: recipientName ?? '',
        };

      // Writes — all tx.create: create-fails-on-exists is defense-in-depth
      // under any phantom-read edge (two racers past the probe still cannot
      // both land).
      if (mode === 'event') {
        tx.create(probeRef, eventSettlementDoc(primaryId, eventId!, amountFils, null));
      } else if (mode === 'group') {
        tx.create(probeRef, groupSettlementDoc(primaryId, amountFils, null));
      } else {
        for (const leg of legs!) {
          tx.create(
            legRefs.get(leg.eventId)!.collection('settlements')
              .doc(decomposeLegSettlementId(primaryId, leg.eventId)),
            eventSettlementDoc(
              decomposeLegSettlementId(primaryId, leg.eventId),
              leg.eventId,
              leg.amountFils,
              primaryId,
            ),
          );
        }
        if (residualFils > 0) {
          tx.create(
            groupSettlementsRef.doc(decomposeResidualSettlementId(primaryId)),
            groupSettlementDoc(decomposeResidualSettlementId(primaryId), residualFils, primaryId),
          );
        }
      }
      tx.create(groupRef.collection('activity').doc(activityId), {
        id: activityId,
        type: activityType,
        actorId: uid,
        actorName,
        description,
        metadata,
        timestamp: nowIso,
      });

      return {
        alreadyRecorded: false,
        eventScopeWrites,
        groupScopeWrites,
        shouldBumpLedgerRevision: eventScopeWrites > 0,
        settledAt: nowIso,
      };
    });
  },
);
