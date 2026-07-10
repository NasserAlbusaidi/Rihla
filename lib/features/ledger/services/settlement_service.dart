import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
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

  /// Builds the Firestore document map for an event settlement — the SINGLE
  /// source of the event-settlement write shape (#929).
  ///
  /// [addSettlement] delegates here for a directly-recorded settlement;
  /// [GroupSettlementService.stageDecomposedSettleUp] calls it for each
  /// per-event leg of a decomposed group settle-up, so both paths write a
  /// byte-identical doc. [amount] is quantized to integer fils via
  /// [MoneySerializer.toSubunits]; [settledAtUtc] is stamped by the caller so a
  /// batch can share ONE timestamp across all its legs.
  static Map<String, dynamic> buildSettlementDoc({
    required String id,
    required String eventId,
    required String payerParticipantId,
    required String recipientParticipantId,
    required Decimal amount,
    required String createdBy,
    required String currency,
    required DateTime settledAtUtc,
    String? payerName,
    String? recipientName,
    String? note,
    String? groupSettleUpId,
  }) {
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
      'settledAt': settledAtUtc.toIso8601String(),
      'createdBy': createdBy,
    };
    // Omit the key when null so directly-recorded settlements keep the existing
    // shape and legacy docs stay valid (#752; rules guard `!('x' in data) ||`).
    if (groupSettleUpId != null) data['groupSettleUpId'] = groupSettleUpId;
    return data;
  }

  /// Derives a deterministic settlement doc id (#1093) from the settle state
  /// so two writers observing the same state produce the SAME id: the second
  /// identical write collides with the first and is denied by the already-live
  /// `allow update: if false` on both settlement blocks (no rules change).
  ///
  /// [amountFils] is derived here via [MoneySerializer.toSubunits] — the exact
  /// conversion [buildSettlementDoc] performs — so id-amount and stored
  /// `amountFils` cannot drift. [pairEpoch] must come from
  /// [directedPairEpoch] over a provider-filtered (`isDeleted == false`) live
  /// settlement list; this function itself does no filtering.
  ///
  /// Deliberately EXCLUDES `settledAt` (differs per device), names (mirrors
  /// differ per device), `note` (a different note is still the same payment),
  /// and `createdBy` (settling-on-behalf must collide with self-settling).
  static String deterministicSettlementId({
    required String scopeKey,
    required String payerParticipantId,
    required String recipientParticipantId,
    required String currency,
    required Decimal amount,
    required int pairEpoch,
  }) {
    final fils = MoneySerializer.toSubunits(amount, currency);
    final canonical = [
      'sd1',
      scopeKey,
      payerParticipantId,
      recipientParticipantId,
      currency,
      '$fils',
      '$pairEpoch',
    ].join('\x1f');
    return 'sd1${sha256.convert(utf8.encode(canonical)).toString().substring(0, 40)}';
  }

  /// Counts settlements for the DIRECTED pair (payer -> recipient) in
  /// [settlements] — the epoch input to [deterministicSettlementId]. Pure: it
  /// counts exactly the list it is given. Callers are responsible for feeding
  /// provider-filtered `isDeleted == false` rows so both devices apply the
  /// identical filter and determinism holds.
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

  /// Deterministic id for one per-event leg of a decomposed group settle-up
  /// (#752/#1093), keyed by the shared `groupSettleUpId` + the leg's event id
  /// — legs are per-event unique, so this cannot collide across legs of the
  /// same decompose.
  static String decomposeLegSettlementId(String groupSettleUpId, String eventId) =>
      'sd1${sha256.convert(utf8.encode('sd1leg\x1f$groupSettleUpId\x1f$eventId')).toString().substring(0, 40)}';

  /// Deterministic id for the residual group-scoped leg of a decomposed
  /// group settle-up (#752/#1093), keyed by the shared `groupSettleUpId`.
  static String decomposeResidualSettlementId(String groupSettleUpId) =>
      'sd1${sha256.convert(utf8.encode('sd1res\x1f$groupSettleUpId')).toString().substring(0, 40)}';

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
    final data = buildSettlementDoc(
      id: id,
      eventId: eventId,
      payerParticipantId: payerParticipantId,
      recipientParticipantId: recipientParticipantId,
      amount: amount,
      createdBy: createdBy,
      currency: currency,
      settledAtUtc: DateTime.now().toUtc(),
      payerName: payerName,
      recipientName: recipientName,
      note: note,
      groupSettleUpId: groupSettleUpId,
    );
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
