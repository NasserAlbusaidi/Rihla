import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/firestore_repository.dart';
import '../../../core/services/money_serializer.dart';
import '../../../core/utils/safe_deserialize.dart';
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
          // #928 money-fence backstop: a doc-level catastrophe is skipped
          // rather than erroring the settle-up stream. Skip has no server-oracle
          // counterpart for a money doc (the oracle is total) — the factory's
          // totality (test 7) is the real invariant, this is a last resort.
          (snap) => decodeDocsSkippingMalformed(
            snap.docs,
            (d) => Settlement.fromFirestore(
              {...d.data()! as Map<String, dynamic>, 'id': d.id},
            ),
            context: 'SettlementService.watchSettlements',
          ),
        );
  }

  /// One-shot read of non-deleted settlements for an event — the same query as
  /// [watchSettlements] but a single `.get()`. Used by the home dashboard's
  /// one-shot balance aggregation (#104) so the per-event listeners are not held
  /// open session-long. Served from the Firestore offline cache when offline.
  Future<List<Settlement>> getSettlements(String groupId, String eventId) async {
    final snap = await eventSubcollection(groupId, eventId, 'settlements')
        .where('isDeleted', isEqualTo: false)
        .orderBy('settledAt', descending: true)
        .get();
    // #928 money-fence backstop (home once-path): skip a doc-level catastrophe,
    // never error the aggregation. No server-oracle counterpart (oracle is
    // total); the factory's totality (test 7) is the invariant.
    return decodeDocsSkippingMalformed(
      snap.docs,
      (d) => Settlement.fromFirestore(
        {...d.data()! as Map<String, dynamic>, 'id': d.id},
      ),
      context: 'SettlementService.getSettlements',
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
    required String createdBy,
    String currency = 'OMR',
    String? payerName,
    String? recipientName,
    String? note,
    String? groupSettleUpId,
  }) async {
    if (createdBy.isEmpty) {
      throw ArgumentError.value(
        createdBy,
        'createdBy',
        'createdBy must be the auth UID of the current user — Firestore '
            'rules reject settlement writes without it.',
      );
    }
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    final data = <String, dynamic>{
      'id': id,
      'eventId': eventId,
      'payerParticipantId': payerParticipantId,
      'recipientParticipantId': recipientParticipantId,
      // Fields absent on pre-2026-05-16 docs render as 'Someone' via the model fallback.
      'payerName': payerName,
      'recipientName': recipientName,
      'amountFils': MoneySerializer.toSubunits(amount, currency),
      'currency': currency,
      'note': note,
      'isDeleted': false,
      'deletedAt': null,
      'settledAt': now.toIso8601String(),
      'createdBy': createdBy,
    };
    // Omit the key when null so directly-recorded settlements keep the existing
    // shape and legacy docs stay valid (#752; rules guard `!('x' in data) ||`).
    if (groupSettleUpId != null) data['groupSettleUpId'] = groupSettleUpId;
    try {
      await eventSubcollection(
        groupId,
        eventId,
        'settlements',
      ).doc(id).set(data);
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'SettlementService.addSettlement failed: ${e.code} ${e.message}',
        );
      }
      rethrow;
    }
    return Settlement.fromFirestore(data);
  }

  // E3 / B3: settlements are append-only. There is no deleteSettlement —
  // the corresponding Firestore rule denies update + delete on settlement
  // docs. The watchSettlements stream still honors the legacy isDeleted
  // flag on any pre-B3 records that may have it.
}
