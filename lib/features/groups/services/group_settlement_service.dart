import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

import '../../../core/services/firebase_functions_service.dart';
import '../../../core/services/firestore_repository.dart';
import '../../../core/services/money_serializer.dart';
import '../../../core/utils/safe_deserialize.dart';
import '../../ledger/models/record_settlement_result.dart';
import '../../ledger/models/settlement_model.dart';

/// Group settlement service: Firestore-backed READS, callable-backed CREATE
/// (#1129).
///
/// Group settlements are stored in the subcollection:
///   `groups/{groupId}/settlements/{settlementId}`
///
/// This is separate from event-level settlements (which live at
/// `groups/{groupId}/events/{eventId}/settlements`). Group settlements
/// represent cross-event debts settled between group members.
///
/// Creates route through the server-authoritative `recordSettlement` callable
/// — `firestore.rules` denies client direct settlement writes, the server
/// recomputes the pair's outstanding inside a transaction and caps the
/// amount, and (for a decomposed settle-up) writes every event leg + residual
/// + the ONE activity row atomically, retiring the client `WriteBatch` and
/// its 20-access-call `kMaxDecomposeLegsAtomic` ceiling. Creates are
/// ONLINE-ONLY (HTTPS callables have no offline queue) — callers pre-flight
/// `ConnectivityStatus.offline`.
///
/// All money amounts cross the wire as integer fils via [MoneySerializer] at
/// the boundary. Internal logic always uses [Decimal].
class GroupSettlementService extends FirestoreRepository {
  GroupSettlementService({FirebaseFunctionsService? functionsService})
    : _functionsServiceOverride = functionsService,
      super();

  /// Test constructor — injects a [FakeFirebaseFirestore] for unit testing.
  @visibleForTesting
  GroupSettlementService.withFirestore(
    super.db, {
    FirebaseFunctionsService? functionsService,
  }) : _functionsServiceOverride = functionsService,
       super.withFirestore();

  final FirebaseFunctionsService? _functionsServiceOverride;

  /// Lazy so pure-stream tests (`withFirestore`, no functions fake) never
  /// touch `FirebaseConfig.functions` — it THROWS `[core/no-app]` without a
  /// Firebase app, it does not return null. Production wiring injects it via
  /// `groupSettlementServiceProvider`.
  late final FirebaseFunctionsService _functionsService =
      _functionsServiceOverride ?? FirebaseFunctionsService();

  CollectionReference<Map<String, dynamic>> _settlementsRef(String groupId) =>
      db.collection('groups').doc(groupId).collection('settlements');

  /// Returns a real-time stream of non-deleted group-level settlements,
  /// ordered newest first.
  Stream<List<Settlement>> watchGroupSettlements(String groupId) {
    return recoverListen(() {
      return _settlementsRef(groupId)
          .where('isDeleted', isEqualTo: false)
          .orderBy('settledAt', descending: true)
          .snapshots()
          .map(
            // #928 money-fence backstop: this feeds the home once-path fold via
            // `groupSettlementsProvider`. Skip a doc-level catastrophe rather
            // than erroring the whole fold; no server-oracle counterpart (oracle
            // is total) — the factory's totality (test 7) is the real invariant.
            (snap) => decodeDocsSkippingMalformed(
              snap.docs,
              (d) => Settlement.fromFirestore(
                {...d.data()! as Map<String, dynamic>, 'id': d.id},
              ),
              context: 'GroupSettlementService.watchGroupSettlements',
            ),
          );
    });
  }

  /// Records a GROUP-scope settlement via the `recordSettlement` callable
  /// (#1129, mode `'group'`) — the aggregate cross-event settle (the
  /// empty-decompose fallback and the departed-party path). The server writes
  /// the doc with the `eventId: groupId` sentinel + `scope: 'group'` (D-10),
  /// caps the amount at the pair's full-group outstanding, and authors the
  /// `group_settlement` activity row atomically.
  ///
  /// ONLINE-ONLY: propagates [FirebaseFunctionsException]; nothing queues.
  Future<RecordSettlementResult> addGroupSettlement({
    required String groupId,
    required String payerParticipantId,
    required String recipientParticipantId,
    required Decimal amount,
    required String currency,
    required int observedPairEpoch,
    String? note,
    String? payerName,
    String? recipientName,
  }) {
    return _functionsService.recordSettlement(
      groupId: groupId,
      mode: 'group',
      payerParticipantId: payerParticipantId,
      recipientParticipantId: recipientParticipantId,
      amountFils: MoneySerializer.toSubunits(amount, currency),
      currency: currency,
      note: note,
      payerName: payerName,
      recipientName: recipientName,
      observedPairEpoch: observedPairEpoch,
    );
  }

  /// Records a whole decomposed group settle-up (#752) via the
  /// `recordSettlement` callable (mode `'groupSettleUp'`): N per-event legs +
  /// the residual, written server-side in ONE transaction — all or nothing,
  /// no leg cap (the old client `WriteBatch` was bounded at 8 legs by the
  /// shared 20-access-call rules budget; the server bound is 400 legs).
  ///
  /// [eventLegs] is caller-ordered (the screen's `eventOrder` — the #752
  /// WYSIWYG contract: the display breakdown and the write share the order).
  /// [amount] is the TOTAL being decomposed; the server verifies
  /// `Σ legs + residual == amountFils` and derives the shared
  /// `groupSettleUpId` (= the #1093 gsu dedup id) from [observedPairEpoch],
  /// so the client no longer mints a UUID.
  ///
  /// ONLINE-ONLY: propagates [FirebaseFunctionsException]; nothing queues.
  Future<RecordSettlementResult> recordDecomposedSettleUp({
    required String groupId,
    required List<({String eventId, Decimal amount})> eventLegs,
    required Decimal amount,
    required String payerParticipantId,
    required String recipientParticipantId,
    required String currency,
    required int observedPairEpoch,
    String? payerName,
    String? recipientName,
    String? note,
  }) {
    return _functionsService.recordSettlement(
      groupId: groupId,
      mode: 'groupSettleUp',
      payerParticipantId: payerParticipantId,
      recipientParticipantId: recipientParticipantId,
      amountFils: MoneySerializer.toSubunits(amount, currency),
      currency: currency,
      note: note,
      payerName: payerName,
      recipientName: recipientName,
      observedPairEpoch: observedPairEpoch,
      legs: [
        for (final leg in eventLegs)
          {
            'eventId': leg.eventId,
            'amountFils': MoneySerializer.toSubunits(leg.amount, currency),
          },
      ],
    );
  }

  // E3 / B3: group settlements are append-only. There is no
  // deleteGroupSettlement — the corresponding Firestore rule denies
  // update + delete on settlement docs. The watch stream still honors
  // the legacy isDeleted flag on any pre-B3 records that may have it.
}
