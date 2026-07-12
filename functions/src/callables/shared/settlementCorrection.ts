import { DocumentData } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { shortHash } from './ids';

// #889: shared correction-marker foundation for the settlement-corrections
// track (#283/#753). Houses the exact-inverse contract validator, the bounded
// legacy note-only classifier, and marker classification, so both
// correctSettlement and correctLogicalSettleUp (and future #283/#753
// consumers) import ONE classifier instead of duplicating it. No trigger
// imports this — settlementNotifier/writeRateMonitor skip on marker PRESENCE
// only (un-forgeable because rules deny a client-created marker), never on the
// structural checks here.

// Frozen historical constant — legacy-classification ONLY, never used to
// validate an incoming correctionNote. Mirrors lib/l10n/app_en.arb:1039 /
// app_ar.arb:411 (the ONLY two locales that shipped before this marker
// existed). This set never grows: every locale added after #889 always writes
// a marker, so it never produces a note-only correction needing sentinel
// classification. Renaming a SHIPPED sentinel means retaining the historical
// string too, so old rows still classify — pinned by a cross-list guard test.
export const CORRECTION_NOTE_SENTINELS = [
  'Correction of a recorded payment', // EN — mirrors lib/l10n/app_en.arb:1039
  'تصحيح لدفعة مُسجَّلة', // AR — mirrors lib/l10n/app_ar.arb:411
];

// Mirror firestore.rules validFreeText (settlement note bound): <= 280 chars,
// no control chars. Rules never trim() — the length/control-char checks below
// run on the RAW value, matching that. Non-empty is checked after trim (a
// whitespace-only note is meaningless), but the value is written VERBATIM
// (untrimmed) on the reverse row for display-compat with the caller's exact
// localized string.
const CORRECTION_NOTE_MAX_LENGTH = 280;
// eslint-disable-next-line no-control-regex
const CONTROL_CHARACTER_PATTERN = /[\x00-\x1F\x7F]/u;

// Generic free-text bounds ONLY — deliberately does NOT check the note
// against CORRECTION_NOTE_SENTINELS. The note is never the discriminator (the
// structural inverse contract is); a non-sentinel note is accepted and
// written verbatim, and simply fails to render the legacy "Correction" tag on
// note-based display until the marker-based UI migration.
export function normalizeCorrectionNote(value: unknown): string {
  if (typeof value !== 'string') {
    throw new HttpsError('invalid-argument', 'correctionNote must be a string.');
  }
  if (value.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'correctionNote must not be empty.');
  }
  if (value.length > CORRECTION_NOTE_MAX_LENGTH) {
    throw new HttpsError(
      'invalid-argument',
      `correctionNote must be at most ${CORRECTION_NOTE_MAX_LENGTH} characters.`,
    );
  }
  if (CONTROL_CHARACTER_PATTERN.test(value)) {
    throw new HttpsError('invalid-argument', 'correctionNote contains invalid characters.');
  }
  return value;
}

export function isSentinelNote(note: unknown): boolean {
  return typeof note === 'string' && CORRECTION_NOTE_SENTINELS.includes(note);
}

// Mirrors Settlement.isMarkedCorrection (settlement_model.dart): present AND
// non-blank. Un-forgeable on a client-created doc — firestore.rules denies the
// key via hasOnly-omission on both settlement collections (event :900, group
// :1153) — so presence alone proves a server-written (Admin SDK) correction.
export function isMarkedCorrection(data: DocumentData): boolean {
  const value = data.correctionOfSettlementId;
  return typeof value === 'string' && value.trim().length > 0;
}

// null for absent/blank so "absent on both" and "blank on both" compare equal
// to each other, matching the rules' `!('groupSettleUpId' in data) || ...`
// absence convention (the client omits the key rather than writing null).
export function normalizedGroupSettleUpId(data: DocumentData): string | null {
  const value = data.groupSettleUpId;
  return typeof value === 'string' && value.trim().length > 0 ? value : null;
}

function sameGroupSettleUpIdState(a: DocumentData, b: DocumentData): boolean {
  return normalizedGroupSettleUpId(a) === normalizedGroupSettleUpId(b);
}

// The exact-inverse MONEY contract: swapped parties, identical amount +
// currency. Symmetric (a vs b == b vs a) — reused for BOTH the legacy
// correction/source pairing and the deterministic-reverse-already-exists
// idempotency check.
export function isExactInverseMoney(a: DocumentData, b: DocumentData): boolean {
  return typeof a.payerParticipantId === 'string'
    && typeof a.recipientParticipantId === 'string'
    && typeof b.payerParticipantId === 'string'
    && typeof b.recipientParticipantId === 'string'
    && a.payerParticipantId === b.recipientParticipantId
    && a.recipientParticipantId === b.payerParticipantId
    && typeof a.amountFils === 'number'
    && a.amountFils === b.amountFils
    && typeof a.currency === 'string'
    && a.currency === b.currency;
}

// Bounded legacy pair: `correction` is a live sentinel-noted row that exactly
// (money + parties) inverts `source`, a live unmarked non-sentinel row, with
// matching groupSettleUpId state. This is the ONLY detector for pre-#889
// correction rows (written by the deleted SettlementCorrectionService with
// uuid ids, so the deterministic-id existence check can never find them).
//
// Accepted asymmetric false-positive (#889 spec): if `source` coincidentally
// carries the exact localized sentinel as a genuine user note AND an
// independent inverse real payment exists live in the same collection, this
// misclassifies the pair — fail-closed (a blocked correction, never wrong
// money), vanishingly rare, and consistent with "note is not a safe
// discriminator" (the whole reason #889 exists). Not a bug to design around.
export function isLegacyCorrectionPair(correction: DocumentData, source: DocumentData): boolean {
  return isSentinelNote(correction.note)
    && correction.isDeleted === false
    && correction.deletedAt == null
    && !isMarkedCorrection(correction)
    && source.isDeleted === false
    && source.deletedAt == null
    && !isMarkedCorrection(source)
    && !isSentinelNote(source.note)
    && isExactInverseMoney(correction, source)
    && sameGroupSettleUpIdState(correction, source);
}

// Is `candidate` (the row the caller wants to correct) ITSELF a legacy
// note-only correction of some other row in `others`? If so it is a
// correction, not an original — correcting it is rejected (no
// correction-of-correction support, #889 Non-Scope).
export function isItselfLegacyCorrection(
  candidate: DocumentData,
  others: DocumentData[],
): boolean {
  return others.some((other) => isLegacyCorrectionPair(candidate, other));
}

// Does `candidate` (the original) already have a LIVE legacy note-only
// correction pointed at it among `others`? If so, correcting it again would
// double-reverse a pre-marker correction — the caller should no-op instead.
export function hasLiveLegacyCorrectionOf(
  candidate: DocumentData,
  others: DocumentData[],
): boolean {
  return others.some((other) => isLegacyCorrectionPair(other, candidate));
}

// Idempotency check: does `reverseData` (a doc already living at the
// deterministic reverse id) validate as the EXPECTED reverse of `originalId`
// / `originalData`? Deliberately does NOT require createdBy == callerUid or
// note == correctionNote, so a retry by a different member or locale stays
// idempotent.
export function isExpectedReverse(
  reverseData: DocumentData,
  originalId: string,
  originalData: DocumentData,
): boolean {
  return reverseData.isDeleted === false
    && reverseData.deletedAt == null
    && reverseData.correctionOfSettlementId === originalId
    && isExactInverseMoney(reverseData, originalData)
    && sameGroupSettleUpIdState(reverseData, originalData);
}

// Deterministic reverse ids so retries/concurrent calls cannot duplicate
// reverses. Never raw ids/paths embedded directly — always hashed first.
export function directReverseId(originalPath: string): string {
  return `correction_${shortHash(originalPath)}`;
}

export function logicalReverseId(groupSettleUpId: string, originalPath: string): string {
  return `correction_${shortHash(groupSettleUpId)}_${shortHash(originalPath)}`;
}

export interface ReverseSettlementInput {
  newId: string;
  originalId: string;
  originalData: DocumentData;
  correctionNote: string;
  callerUid: string;
  nowIso: string;
}

// Event reverse at groups/{gid}/events/{eid}/settlements/{newId}. Mirrors the
// current SettlementCorrectionService / addSettlement shape exactly, so
// validEventSettlementBase's hasOnly() would accept the non-marker keys (the
// marker key itself is Admin-only, never in the client allow-list).
export function buildEventReverseData(eventId: string, input: ReverseSettlementInput): DocumentData {
  const { newId, originalId, originalData, correctionNote, callerUid, nowIso } = input;
  const groupSettleUpId = normalizedGroupSettleUpId(originalData);
  return {
    id: newId,
    eventId,
    payerParticipantId: originalData.recipientParticipantId,
    recipientParticipantId: originalData.payerParticipantId,
    payerName: originalData.recipientName ?? null,
    recipientName: originalData.payerName ?? null,
    amountFils: originalData.amountFils,
    currency: originalData.currency,
    note: correctionNote,
    isDeleted: false,
    deletedAt: null,
    settledAt: nowIso,
    createdBy: callerUid,
    ...(groupSettleUpId ? { groupSettleUpId } : {}),
    correctionOfSettlementId: originalId,
  };
}

// Group residual reverse at groups/{gid}/settlements/{newId}.
export function buildGroupReverseData(groupId: string, input: ReverseSettlementInput): DocumentData {
  const { newId, originalId, originalData, correctionNote, callerUid, nowIso } = input;
  const groupSettleUpId = normalizedGroupSettleUpId(originalData);
  return {
    id: newId,
    groupId,
    // #71: no eventId sentinel on group docs (path + groupId/scope identify them).
    scope: 'group',
    payerParticipantId: originalData.recipientParticipantId,
    recipientParticipantId: originalData.payerParticipantId,
    payerName: originalData.recipientName ?? null,
    recipientName: originalData.payerName ?? null,
    amountFils: originalData.amountFils,
    currency: originalData.currency,
    note: correctionNote,
    isDeleted: false,
    deletedAt: null,
    settledAt: nowIso,
    createdBy: callerUid,
    ...(groupSettleUpId ? { groupSettleUpId } : {}),
    correctionOfSettlementId: originalId,
  };
}
