import '../models/settlement_model.dart';
import 'correction_note.dart';

/// #889 client mirror of the callables' bounded-legacy correction detector
/// (functions/src/callables/shared/settlementCorrection.ts
/// `isLegacyCorrectionPair`) — used ONLY to hide the write-AFFORDANCE for a
/// pre-#889 note-only correction pair (display stays note-based,
/// `isCorrectionNote`). Never a classifier for what IS a correction
/// server-side; the callable is the sole authority there.

bool _isExactInverseMoney(Settlement a, Settlement b) {
  final aPayer = a.payerParticipantId;
  final aRecipient = a.recipientParticipantId;
  final bPayer = b.payerParticipantId;
  final bRecipient = b.recipientParticipantId;
  return aPayer != null &&
      aRecipient != null &&
      bPayer != null &&
      bRecipient != null &&
      aPayer == bRecipient &&
      aRecipient == bPayer &&
      a.amount == b.amount &&
      a.currency == b.currency;
}

String? _normalizedGroupSettleUpId(Settlement s) {
  final id = s.groupSettleUpId;
  return (id != null && id.trim().isNotEmpty) ? id : null;
}

bool _sameGroupSettleUpIdState(Settlement a, Settlement b) =>
    _normalizedGroupSettleUpId(a) == _normalizedGroupSettleUpId(b);

/// True when [correction] is a live sentinel-noted row that exactly (money +
/// parties) inverts [source], a live unmarked non-sentinel row, with matching
/// `groupSettleUpId` state. The ONLY detector for a pre-#889 correction (the
/// deleted `SettlementCorrectionService` wrote uuid ids, so no
/// deterministic-id check can find it).
bool isBoundedLegacyCorrectionPair(Settlement correction, Settlement source) {
  return isCorrectionNote(correction.note) &&
      !correction.isDeleted &&
      correction.deletedAt == null &&
      !correction.isMarkedCorrection &&
      !source.isDeleted &&
      source.deletedAt == null &&
      !source.isMarkedCorrection &&
      !isCorrectionNote(source.note) &&
      _isExactInverseMoney(correction, source) &&
      _sameGroupSettleUpIdState(correction, source);
}

/// Does [candidate] already have a LIVE bounded-legacy correction pointed at
/// it within [visible]?
bool hasLiveBoundedLegacyCorrectionOf(
  Settlement candidate,
  List<Settlement> visible,
) {
  return visible.any(
    (other) => other.id != candidate.id && isBoundedLegacyCorrectionPair(other, candidate),
  );
}

/// Is [candidate] ITSELF a bounded-legacy correction of some other row in
/// [visible]? (No correction-of-correction support — #889 Non-Scope.)
bool isItselfBoundedLegacyCorrection(
  Settlement candidate,
  List<Settlement> visible,
) {
  return visible.any(
    (other) => other.id != candidate.id && isBoundedLegacyCorrectionPair(candidate, other),
  );
}

/// Solo-row write-affordance hide (`settle_up_page_body.dart` Correct button
/// gate): a marked reverse OR a bounded-legacy note-only correction target
/// hides the Correct button. [visible] MUST be the screen's OWN settlement
/// list — the event and group screens pass different lists; never compare
/// across screens.
bool isSoloCorrectionHidden(Settlement settlement, List<Settlement> visible) {
  return settlement.isMarkedCorrection ||
      hasLiveBoundedLegacyCorrectionOf(settlement, visible);
}

/// True iff every eligible original in [members] (one `groupSettleUpId`-tagged
/// set) provably has a valid marked reverse (`other.isMarkedCorrection &&
/// other.correctionOfSettlementId == original.id`) or a bounded-legacy exact
/// inverse WITHIN the same set. Drives the logical row's write-affordance
/// (`LogicalHistoryRow.affordanceCorrected`) and `_correctLogicalSettleUp`'s
/// local already-corrected decision — DISTINCT from the note-based display
/// `isCorrected`. A partially-marked set returns false so the action stays
/// available for the callable to repair (#889 intentional transient: display
/// may already read "corrected" while this stays false).
bool logicalSetAffordanceCorrected(List<Settlement> members) {
  final eligibleOriginals = members.where(
    (m) => !m.isMarkedCorrection && !isItselfBoundedLegacyCorrection(m, members),
  );
  if (eligibleOriginals.isEmpty) return false;
  return eligibleOriginals.every(
    (original) => members.any(
      (other) =>
          other.id != original.id &&
          ((other.isMarkedCorrection &&
                  other.correctionOfSettlementId == original.id) ||
              isBoundedLegacyCorrectionPair(other, original)),
    ),
  );
}

/// #1149 client mirror of the correctSettlement.ts / correctLogicalSettleUp.ts
/// current-party check: both parties must be in FULL `group.memberIds`.
/// Ghosts (deleteAccount tombstones) and shadows ARE in memberIds — exact
/// set-membership only, nothing fancier; NEVER the active set here, ghost
/// debt cleanup stays live. A null party id is never current.
bool settlementPartiesAreCurrentMembers(
  Settlement settlement,
  Set<String> memberIds,
) {
  final payer = settlement.payerParticipantId;
  final recipient = settlement.recipientParticipantId;
  return payer != null &&
      recipient != null &&
      memberIds.contains(payer) &&
      memberIds.contains(recipient);
}
