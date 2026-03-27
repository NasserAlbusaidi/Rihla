import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/firestore_repository.dart';
import '../../../core/services/money_serializer.dart';
import '../models/settlement_model.dart';

/// Firestore-backed service for Settlement CRUD operations.
///
/// Extends [FirestoreRepository] for production use or test injection via
/// [SettlementService.withFirestore].
///
/// Settlements are stored in the subcollection:
///   `groups/{groupId}/events/{eventId}/settlements/{settlementId}`
///
/// All money amounts are stored as integer fils via [MoneySerializer] at the
/// Firestore boundary. Internal logic always uses [Decimal].
class SettlementService extends FirestoreRepository {
  SettlementService() : super();

  /// Test constructor -- injects a [FakeFirebaseFirestore] for unit testing.
  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  SettlementService.withFirestore(super.db) : super.withFirestore();

  /// Returns a real-time stream of non-deleted settlements for the given event,
  /// ordered newest first.
  ///
  /// The query filters `isDeleted == false` so soft-deleted documents are
  /// excluded from the stream without a client-side filter.
  Stream<List<Settlement>> watchSettlements(String groupId, String eventId) {
    return eventSubcollection(groupId, eventId, 'settlements')
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

  /// Creates a new settlement document in Firestore and returns the resulting
  /// [Settlement] object.
  ///
  /// The [amount] is converted to integer fils via [MoneySerializer.toSubunits]
  /// before being stored. The returned [Settlement] is deserialized from the
  /// data that was written, so amount round-trips through [MoneySerializer].
  Future<Settlement> addSettlement({
    required String groupId,
    required String eventId,
    required String payerParticipantId,
    required String recipientParticipantId,
    required Decimal amount,
    String currency = 'OMR',
    String? note,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    final data = <String, dynamic>{
      'id': id,
      'eventId': eventId,
      'payerParticipantId': payerParticipantId,
      'recipientParticipantId': recipientParticipantId,
      'amountFils': MoneySerializer.toSubunits(amount, currency),
      'currency': currency,
      'note': note,
      'isDeleted': false,
      'deletedAt': null,
      'settledAt': now.toIso8601String(),
    };
    try {
      await eventSubcollection(groupId, eventId, 'settlements').doc(id).set(data);
    } on FirebaseException catch (e) {
      debugPrint('SettlementService.addSettlement failed: ${e.code} ${e.message}');
      rethrow;
    }
    return Settlement.fromFirestore(data);
  }

  /// Soft-deletes a settlement by setting [isDeleted] = true and recording a
  /// [deletedAt] timestamp. The document is NOT removed from Firestore.
  Future<void> deleteSettlement({
    required String groupId,
    required String eventId,
    required String settlementId,
  }) async {
    try {
      await eventSubcollection(groupId, eventId, 'settlements')
          .doc(settlementId)
          .update({
        'isDeleted': true,
        'deletedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } on FirebaseException catch (e) {
      debugPrint('SettlementService.deleteSettlement failed: ${e.code} ${e.message}');
      rethrow;
    }
  }
}
