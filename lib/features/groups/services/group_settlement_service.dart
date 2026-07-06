import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/firestore_repository.dart';
import '../../../core/services/money_serializer.dart';
import '../../../core/utils/safe_deserialize.dart';
import '../../ledger/models/settlement_model.dart';
import '../../ledger/services/settlement_service.dart';

/// The most event legs a decomposed group settle-up may stage into ONE atomic
/// [WriteBatch] (#929). Security rules give a batched write a SHARED budget of
/// 20 document-access calls for the ENTIRE commit (Firebase `rules-conditions`
/// "Access call limits"; single-doc requests get 10 each). Each event-settlement
/// create reads TWO distinct docs — the group (`isGroupMember` +
/// `groupAllowsClientWrites`) and the event (`eventAllowsClientWrites` +
/// `participants()`); the residual group-settlement create reads ONE (the group).
/// So an N-event batch costs `2·N + 1` access calls: N = 9 → 19 ≤ 20; N = 10
/// would be `permission-denied` in toto (and, recorded OFFLINE, silently
/// discarded in full at replay). Above this cap the caller falls back to a
/// single atomic group settlement (§ceiling of the #929 spec). The bound is
/// conservative (assumes zero cross-op caching); widening it requires emulator
/// evidence, not the doc's best-effort same-doc caching promise.
const kMaxDecomposeLegsAtomic = 9;

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

  /// Test seam (#929): overrides the [WriteBatch] factory so a unit test can
  /// inject a mock batch — to count `set()`/`commit()`, capture staged refs, or
  /// simulate a rejected/never-acking commit. Null in production, where
  /// [stageDecomposedSettleUp] uses `db.batch`.
  @visibleForTesting
  WriteBatch Function()? batchFactoryOverride;

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

  /// Builds the Firestore document map for a group-level settlement — the
  /// SINGLE source of the group-settlement write shape (#929).
  ///
  /// [addGroupSettlement] delegates here for a directly-recorded group
  /// settlement; [stageDecomposedSettleUp] calls it for the residual leg of a
  /// decomposed settle-up, so both paths write a byte-identical doc. The doc
  /// carries the `eventId: groupId` sentinel + `scope: 'group'` (D-10).
  /// [settledAtUtc] is stamped by the caller so a batch can share ONE timestamp
  /// across all its legs.
  static Map<String, dynamic> buildGroupSettlementDoc({
    required String id,
    required String groupId,
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
      'settledAt': settledAtUtc.toIso8601String(),
      'createdBy': createdBy,
    };
    // Omit the key when null so legacy/standalone group settlements keep the
    // existing shape (#752; rules guard `!('x' in data) ||`).
    if (groupSettleUpId != null) data['groupSettleUpId'] = groupSettleUpId;
    return data;
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
    final data = buildGroupSettlementDoc(
      id: id,
      groupId: groupId,
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
      await _settlementsRef(groupId).doc(id).set(data);
    } on FirebaseException catch (e) {
      if (kDebugMode) debugPrint('GroupSettlementService.addGroupSettlement failed: ${e.code} ${e.message}');
      rethrow;
    }
    return Settlement.fromFirestore(data);
  }

  /// Stages a whole decomposed group settle-up — N per-event settlement docs +
  /// one residual group settlement — into a SINGLE atomic [WriteBatch] (#929).
  ///
  /// A `WriteBatch` is one Commit: rules evaluate per-op but the commit applies
  /// all-or-nothing, and OFFLINE it queues + replays as one unit. So a rules
  /// rejection of ANY leg (a party's membership/participation changed while the
  /// write was queued) persists NOTHING — retiring the old sequential walk's
  /// partial-persist seam (#752's PR2 deferral).
  ///
  /// [eventLegs] is caller-ordered (the screen's `eventOrder`); each contributes
  /// one event-settlement doc. [residual] stages a group settlement ONLY when
  /// `> 0`. All docs share ONE `settledAt` so a decomposed settle-up carries a
  /// stable timestamp. Refs AND the batch come from THIS service's [db].
  ///
  /// Returns `(ack: batch.commit(), staged: [...])` — the commit future is NOT
  /// awaited here; the caller races it via `awaitServerAck` (#412). [staged] is
  /// the local echo of the written docs (kept for tests; not consumed by the
  /// screen).
  ///
  /// Throws [ArgumentError] on empty [createdBy] (parity with the `add*`
  /// methods) or when `eventLegs.length` exceeds [kMaxDecomposeLegsAtomic] —
  /// defense in depth; the screen's pre-gate is the routing decision that keeps
  /// an over-cap settle-up off this path entirely.
  ({Future<void> ack, List<Settlement> staged}) stageDecomposedSettleUp({
    required String groupId,
    required List<({String eventId, Decimal amount})> eventLegs,
    required Decimal residual,
    required String payerParticipantId,
    required String recipientParticipantId,
    required String currency,
    required String createdBy,
    required String groupSettleUpId,
    String? payerName,
    String? recipientName,
    String? note,
  }) {
    if (createdBy.isEmpty) {
      throw ArgumentError.value(
        createdBy,
        'createdBy',
        'createdBy must be the auth UID of the current user — Firestore '
            'rules reject settlement writes without it.',
      );
    }
    if (eventLegs.length > kMaxDecomposeLegsAtomic) {
      throw ArgumentError.value(
        eventLegs.length,
        'eventLegs',
        'exceeds kMaxDecomposeLegsAtomic ($kMaxDecomposeLegsAtomic) — the '
            'caller must route a > $kMaxDecomposeLegsAtomic-leg settle-up to a '
            'single atomic group settlement (the 20-access-call batch budget).',
      );
    }

    final batch = (batchFactoryOverride ?? db.batch)();
    // ONE timestamp across every leg — a stable settledAt for the logical
    // settle-up and a tractable builder-level parity test.
    final now = DateTime.now().toUtc();
    final staged = <Settlement>[];

    for (final leg in eventLegs) {
      final id = const Uuid().v4();
      final data = SettlementService.buildSettlementDoc(
        id: id,
        eventId: leg.eventId,
        payerParticipantId: payerParticipantId,
        recipientParticipantId: recipientParticipantId,
        amount: leg.amount,
        createdBy: createdBy,
        currency: currency,
        settledAtUtc: now,
        payerName: payerName,
        recipientName: recipientName,
        note: note,
        groupSettleUpId: groupSettleUpId,
      );
      batch.set(
        eventSubcollection(groupId, leg.eventId, 'settlements').doc(id),
        data,
      );
      staged.add(Settlement.fromFirestore(data));
    }

    if (residual > Decimal.zero) {
      final id = const Uuid().v4();
      final data = GroupSettlementService.buildGroupSettlementDoc(
        id: id,
        groupId: groupId,
        payerParticipantId: payerParticipantId,
        recipientParticipantId: recipientParticipantId,
        amount: residual,
        createdBy: createdBy,
        currency: currency,
        settledAtUtc: now,
        payerName: payerName,
        recipientName: recipientName,
        note: note,
        groupSettleUpId: groupSettleUpId,
      );
      batch.set(_settlementsRef(groupId).doc(id), data);
      staged.add(Settlement.fromFirestore(data));
    }

    return (ack: batch.commit(), staged: staged);
  }

  // E3 / B3: group settlements are append-only. There is no
  // deleteGroupSettlement — the corresponding Firestore rule denies
  // update + delete on settlement docs. The watch stream still honors
  // the legacy isDeleted flag on any pre-B3 records that may have it.
}
