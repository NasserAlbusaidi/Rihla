import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/firestore_repository.dart';
import '../../../core/services/money_serializer.dart';
import '../../ledger/models/settlement_model.dart';

/// Firestore-backed service for group-level settlement operations.
///
/// Group settlements are stored in the subcollection:
///   `groups/{groupId}/settlements/{settlementId}`
///
/// This is separate from event-level settlements (which live at
/// `groups/{groupId}/events/{eventId}/settlements`). Group settlements
/// represent cross-event debts settled between group members.
///
/// All money amounts are stored as integer fils via [MoneySerializer] at the
/// Firestore boundary. Internal logic always uses [Decimal].
class GroupSettlementService extends FirestoreRepository {
  GroupSettlementService() : super();

  /// Test constructor — injects a [FakeFirebaseFirestore] for unit testing.
  @visibleForTesting
  GroupSettlementService.withFirestore(FirebaseFirestore db)
      : super.withFirestore(db);

  CollectionReference<Map<String, dynamic>> _settlementsRef(String groupId) =>
      db.collection('groups').doc(groupId).collection('settlements');

  /// Returns a real-time stream of non-deleted group-level settlements,
  /// ordered newest first.
  Stream<List<Settlement>> watchGroupSettlements(String groupId) {
    return _settlementsRef(groupId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('settledAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) =>
                    Settlement.fromFirestore({...doc.data(), 'id': doc.id}),
              )
              .toList(),
        );
  }

  /// Creates a new group-level settlement and returns the resulting [Settlement].
  ///
  /// The [amount] is converted to integer fils via [MoneySerializer.toSubunits]
  /// before storage. The returned [Settlement] is deserialized from the written
  /// data so amount round-trips through [MoneySerializer].
  ///
  /// The settlement is written with [scope] = 'group' per D-10.
  Future<Settlement> addGroupSettlement({
    required String groupId,
    required String payerParticipantId,
    required String recipientParticipantId,
    required Decimal amount,
    String currency = 'OMR',
    String? note,
    String? payerName,
    String? recipientName,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    final data = <String, dynamic>{
      'id': id,
      'groupId': groupId,
      'eventId': groupId, // sentinel per RESEARCH Pitfall 3 — group settlements have no eventId
      'scope': 'group',
      'payerParticipantId': payerParticipantId,
      'recipientParticipantId': recipientParticipantId,
      'amountFils': MoneySerializer.toSubunits(amount, currency),
      'currency': currency,
      'note': note,
      'payerName': payerName,
      'recipientName': recipientName,
      'isDeleted': false,
      'deletedAt': null,
      'settledAt': now.toIso8601String(),
    };
    await _settlementsRef(groupId).doc(id).set(data);
    return Settlement.fromFirestore(data);
  }

  /// Soft-deletes a group settlement by setting [isDeleted] = true.
  Future<void> deleteGroupSettlement({
    required String groupId,
    required String settlementId,
  }) async {
    await _settlementsRef(groupId).doc(settlementId).update({
      'isDeleted': true,
      'deletedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
