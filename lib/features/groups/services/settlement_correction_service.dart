import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/firestore_repository.dart';
import '../../../core/services/money_serializer.dart';
import '../../ledger/models/settlement_model.dart';

/// Atomic corrections of a DECOMPOSED group settle-up (#753 — fast-follow to
/// #752 PR1).
///
/// PR1 records one logical group settle-up as N event settlements + ≤1 residual
/// group settlement, all sharing a `groupSettleUpId`. Correcting it requires
/// reversing EVERY one of those docs together — a sequential per-doc walk is not
/// atomic (a mid-walk failure leaves the ledgers half-reversed) and would
/// double-reverse a fixed doc list on re-entry. This service reverses them all
/// in a single Firestore [WriteBatch]: all-or-nothing, rules-checked and
/// offline-queued atomically.
///
/// Append-only (B3): each reverse is a NEW offsetting settlement (swap
/// payer↔recipient), never a delete/update of the original. The reverses carry
/// the SAME `groupSettleUpId` + the localized correction-note sentinel so the
/// group history regroups them into the original logical row (now "corrected")
/// and a re-tap is a no-op.
class SettlementCorrectionService extends FirestoreRepository {
  SettlementCorrectionService() : super();

  /// Test constructor — injects a [FakeFirebaseFirestore] for unit testing.
  @visibleForTesting
  SettlementCorrectionService.withFirestore(super.db) : super.withFirestore();

  /// Atomically reverses every doc of ONE logical group settle-up.
  ///
  /// [originals] MUST be exactly the non-correction docs sharing
  /// [groupSettleUpId] (the caller filters out already-recorded reverses).
  /// Returns the commit future so the caller can race it with `awaitServerAck`
  /// (#412). Throws if the batch is rejected — NOTHING is persisted (atomicity).
  Future<void> reverseLogicalSettleUp({
    required String groupId,
    required String groupSettleUpId,
    required List<Settlement> originals,
    required String correctedBy,
    required String correctionNote,
  }) {
    if (correctedBy.isEmpty) {
      throw ArgumentError.value(
        correctedBy,
        'correctedBy',
        'correctedBy must be the auth UID of the current user — Firestore '
            'rules reject settlement writes without it.',
      );
    }

    final batch = db.batch();
    final now = DateTime.now().toUtc();
    const uuid = Uuid();

    for (final s in originals) {
      final newId = uuid.v4();
      // The residual group settlement carries scope 'group'; event settlements
      // default to 'event'. Reverse each into its OWN collection so the oracle
      // folds them the same way it folded the originals (event reverses
      // per-event, the residual reverse globally — by collection path).
      final isResidual = s.scope == 'group';
      final ref = isResidual
          ? db
              .collection('groups')
              .doc(groupId)
              .collection('settlements')
              .doc(newId)
          : eventSubcollection(groupId, s.tripId, 'settlements').doc(newId);

      // Shapes mirror addGroupSettlement / addSettlement EXACTLY so the
      // `validGroupSettlementBase` / `validEventSettlementBase` hasOnly() lists
      // accept them (security/firestore.rules). Event reverse: 14 keys, no
      // scope/groupId. Residual reverse: 16 keys, adds scope/groupId and
      // eventId == groupId sentinel.
      final data = <String, dynamic>{
        'id': newId,
        'eventId': isResidual ? groupId : s.tripId,
        if (isResidual) 'scope': 'group',
        if (isResidual) 'groupId': groupId,
        // Swap payer↔recipient — the offsetting reverse.
        'payerParticipantId': s.recipientParticipantId,
        'recipientParticipantId': s.payerParticipantId,
        'payerName': s.recipientName,
        'recipientName': s.payerName,
        'amountFils': MoneySerializer.toSubunits(s.amount, s.currency),
        'currency': s.currency,
        'note': correctionNote,
        'isDeleted': false,
        'deletedAt': null,
        'settledAt': now.toIso8601String(),
        'createdBy': correctedBy,
        'groupSettleUpId': groupSettleUpId,
      };
      batch.set(ref, data);
    }

    // Return the un-awaited commit future so the caller can race it with
    // awaitServerAck (#412) and classify any rejection. A try/catch here would
    // either not catch (un-awaited) or break the race (awaited).
    return batch.commit();
  }
}
