import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

import '../../../core/services/firebase_functions_service.dart';
import '../../../core/services/firestore_repository.dart';
import '../../../core/services/money_serializer.dart';
import '../../../core/utils/safe_deserialize.dart';
import '../models/record_settlement_result.dart';
import '../models/settlement_model.dart';

/// Settlement service: Firestore-backed READS, callable-backed CREATE (#1129).
///
/// Settlements are stored in the subcollection:
///   `groups/{groupId}/events/{eventId}/settlements/{settlementId}`
///
/// Reads (streams / one-shots) come straight from Firestore and are served by
/// the SDK's offline cache. The CREATE is the server-authoritative
/// `recordSettlement` callable — `firestore.rules` denies client direct
/// settlement writes in both scopes, the server recomputes the pair's
/// outstanding inside a transaction and caps the amount, and it derives the
/// #1093 `sd1` dedup id from [directedPairEpoch]'s observation. Creates are
/// therefore ONLINE-ONLY (HTTPS callables have no offline queue) — callers
/// pre-flight `ConnectivityStatus.offline`.
///
/// All money amounts cross the wire as integer fils via [MoneySerializer] at
/// the boundary. Internal logic always uses [Decimal].
class SettlementService extends FirestoreRepository {
  SettlementService({FirebaseFunctionsService? functionsService})
    : _functionsServiceOverride = functionsService,
      super();

  /// Test constructor -- injects a [FakeFirebaseFirestore] for unit testing.
  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  SettlementService.withFirestore(
    super.db, {
    FirebaseFunctionsService? functionsService,
  }) : _functionsServiceOverride = functionsService,
       super.withFirestore();

  final FirebaseFunctionsService? _functionsServiceOverride;

  /// Lazy so pure-stream tests (`withFirestore`, no functions fake) never
  /// touch `FirebaseConfig.functions` — it THROWS `[core/no-app]` without a
  /// Firebase app, it does not return null. Production wiring injects it via
  /// `settlementServiceProvider`.
  late final FirebaseFunctionsService _functionsService =
      _functionsServiceOverride ?? FirebaseFunctionsService();

  /// Returns a real-time stream of non-deleted settlements for the given event,
  /// ordered newest first.
  ///
  /// The query filters `isDeleted == false` so soft-deleted documents are
  /// excluded from the stream without a client-side filter.
  Stream<List<Settlement>> watchSettlements(String groupId, String eventId) {
    return recoverListen(() {
      return eventSubcollection(groupId, eventId, 'settlements')
          .where('isDeleted', isEqualTo: false)
          .orderBy('settledAt', descending: true)
          .snapshots()
          .map(
            // #928 money-fence backstop: a doc-level catastrophe is skipped
            // rather than erroring the settle-up stream. Skip has no
            // server-oracle counterpart for a money doc (the oracle is total) —
            // the factory's totality (test 7) is the real invariant, this is a
            // last resort.
            (snap) => decodeDocsSkippingMalformed(
              snap.docs,
              (d) => Settlement.fromFirestore(
                {...d.data()! as Map<String, dynamic>, 'id': d.id},
              ),
              context: 'SettlementService.watchSettlements',
            ),
          );
    });
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

  /// Counts settlements for the DIRECTED pair (payer -> recipient) in
  /// [settlements] — the `observedPairEpoch` sent to `recordSettlement`, from
  /// which the SERVER derives the #1093 dedup id (a dedup nonce, never an
  /// equality gate — the server's outstanding cap is the money guard). Pure:
  /// it counts exactly the list it is given. Callers are responsible for
  /// feeding provider-filtered `isDeleted == false` rows so two devices
  /// observing the same state send the identical epoch and their retries
  /// collide into one recorded payment.
  static int directedPairEpoch(
    Iterable<Settlement> settlements, {
    required String payerParticipantId,
    required String recipientParticipantId,
  }) =>
      settlements
          .where(
            (s) =>
                s.payerParticipantId == payerParticipantId &&
                s.recipientParticipantId == recipientParticipantId,
          )
          .length;

  /// Records an EVENT-scope settlement via the `recordSettlement` callable
  /// (#1129) — the only settlement create path (rules deny direct writes).
  ///
  /// The server recomputes the pair's outstanding on this event's basis inside
  /// a transaction, caps the amount (`failed-precondition` with
  /// `details.kind == 'over-outstanding'`), derives the #1093 dedup id from
  /// [observedPairEpoch], writes the doc + the ONE activity row atomically,
  /// and stamps `settledAt`/actor fields itself. [amount] is converted to
  /// integer fils via [MoneySerializer.toSubunits] at this boundary — the
  /// exact conversion the old direct write performed, so id-amount and stored
  /// `amountFils` cannot drift.
  ///
  /// ONLINE-ONLY: propagates [FirebaseFunctionsException] which callers
  /// classify via `classifySettlementWriteError`; nothing ever queues.
  Future<RecordSettlementResult> addSettlement({
    required String groupId,
    required String eventId,
    required String payerParticipantId,
    required String recipientParticipantId,
    required Decimal amount,
    required String currency,
    required int observedPairEpoch,
    String? payerName,
    String? recipientName,
    String? note,
  }) {
    return _functionsService.recordSettlement(
      groupId: groupId,
      mode: 'event',
      eventId: eventId,
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

  // E3 / B3: settlements are append-only. There is no deleteSettlement —
  // the corresponding Firestore rule denies update + delete on settlement
  // docs. The watchSettlements stream still honors the legacy isDeleted
  // flag on any pre-B3 records that may have it.
}
