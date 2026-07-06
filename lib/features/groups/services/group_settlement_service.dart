import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/firestore_repository.dart';
import '../../../core/services/money_serializer.dart';
import '../../../core/utils/safe_deserialize.dart';
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
  GroupSettlementService.withFirestore(super.db) : super.withFirestore();

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
          // #928 money-fence backstop: this feeds the home once-path fold via
          // `groupSettlementsProvider`. Skip a doc-level catastrophe rather than
          // erroring the whole fold; no server-oracle counterpart (oracle is
          // total) — the factory's totality (test 7) is the real invariant.
          (snap) => decodeDocsSkippingMalformed(
            snap.docs,
            (d) => Settlement.fromFirestore(
              {...d.data()! as Map<String, dynamic>, 'id': d.id},
            ),
            context: 'GroupSettlementService.watchGroupSettlements',
          ),
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
    required String createdBy,
    String currency = 'OMR',
    String? note,
    String? payerName,
    String? recipientName,
    String? groupSettleUpId,
  }) async {
    if (createdBy.isEmpty) {
      throw ArgumentError.value(
        createdBy,
        'createdBy',
        'createdBy must be the auth UID of the current user — Firestore '
            'rules reject group settlement writes without it.',
      );
    }
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
      'createdBy': createdBy,
    };
    // Omit the key when null so legacy/standalone group settlements keep the
    // existing shape (#752; rules guard `!('x' in data) ||`).
    if (groupSettleUpId != null) data['groupSettleUpId'] = groupSettleUpId;
    try {
      await _settlementsRef(groupId).doc(id).set(data);
    } on FirebaseException catch (e) {
      if (kDebugMode) debugPrint('GroupSettlementService.addGroupSettlement failed: ${e.code} ${e.message}');
      rethrow;
    }
    return Settlement.fromFirestore(data);
  }

  // E3 / B3: group settlements are append-only. There is no
  // deleteGroupSettlement — the corresponding Firestore rule denies
  // update + delete on settlement docs. The watch stream still honors
  // the legacy isDeleted flag on any pre-B3 records that may have it.
}
