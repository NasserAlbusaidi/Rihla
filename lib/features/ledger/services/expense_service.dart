import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/split_mode.dart';
import '../../../core/services/firestore_repository.dart';
import '../../../core/services/money_serializer.dart';
import '../models/expense_model.dart';

/// Firestore-backed service for Expense CRUD operations.
///
/// Extends [FirestoreRepository] for production use or test injection via
/// [ExpenseService.withFirestore].
///
/// Expenses are stored in the subcollection:
///   `groups/{groupId}/events/{eventId}/expenses/{expenseId}`
///
/// All money amounts are stored as integer fils via [MoneySerializer] at the
/// Firestore boundary. Internal logic always uses [Decimal].
class ExpenseService extends FirestoreRepository {
  ExpenseService() : super();

  /// Test constructor -- injects a [FakeFirebaseFirestore] for unit testing.
  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  ExpenseService.withFirestore(super.db) : super.withFirestore();

  /// Returns a real-time stream of non-deleted expenses for the given event,
  /// ordered newest first.
  ///
  /// The query filters `isDeleted == false` so soft-deleted documents are
  /// excluded from the stream without a client-side filter.
  Stream<List<Expense>> watchExpenses(String groupId, String eventId) {
    return eventSubcollection(groupId, eventId, 'expenses')
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) => Expense.fromFirestore({...doc.data(), 'id': doc.id}),
              )
              .toList(),
        );
  }

  /// One-shot read of non-deleted expenses for an event — the same query as
  /// [watchExpenses] but a single `.get()` instead of a live `.snapshots()`
  /// listener. Used by the home dashboard's one-shot balance aggregation (#104)
  /// so the O(G×E) per-event listeners are not held open for the whole session.
  /// Served from the Firestore offline cache (incl. pending local writes) when
  /// offline, same as the stream.
  Future<List<Expense>> getExpenses(String groupId, String eventId) async {
    final snap = await eventSubcollection(groupId, eventId, 'expenses')
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs
        .map((doc) => Expense.fromFirestore({...doc.data(), 'id': doc.id}))
        .toList();
  }

  /// ARCH-03: Server-side Firestore range query on `createdAt` (ISO-8601 string).
  ///
  /// Returns a real-time stream of non-deleted expenses whose `createdAt`
  /// falls within `[startUtc, endExclusiveUtc)`. Uses lexicographic string
  /// comparison on the ISO-8601 field — correct for UTC timestamps.
  ///
  /// Firestore composite index required: `(isDeleted ASC, createdAt DESC)`.
  /// The existing index in `firestore.indexes.json` covers this predicate
  /// (verified 2026-04-16). If deployment returns FAILED_PRECONDITION,
  /// follow the error URL to add the exact fields requested.
  Stream<List<Expense>> watchExpensesInRange({
    required String groupId,
    required String eventId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) {
    return eventSubcollection(groupId, eventId, 'expenses')
        .where('isDeleted', isEqualTo: false)
        .where('createdAt', isGreaterThanOrEqualTo: startUtc.toIso8601String())
        .where('createdAt', isLessThan: endExclusiveUtc.toIso8601String())
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) => Expense.fromFirestore({...doc.data(), 'id': doc.id}),
              )
              .toList(),
        );
  }

  /// Creates a new expense document in Firestore and returns the resulting
  /// [Expense] object.
  ///
  /// The [amount] is converted to integer fils via [MoneySerializer.toSubunits]
  /// before being stored. The returned [Expense] is deserialized from the data
  /// that was written, so amount round-trips through [MoneySerializer].
  Future<Expense> addExpense({
    required String groupId,
    required String eventId,
    required String payerParticipantId,
    required Decimal amount,
    required String createdBy,
    String currency = 'OMR',
    String? description,
    ExpenseScope scope = ExpenseScope.global,
    String? subGroupId,
    List<String>? customSplitParticipants,
    SplitMode? splitMode,
    Map<String, Decimal>? splitDistribution,
    String? receiptUrl,
    String? categoryId,
    String? note,
  }) async {
    if (createdBy.isEmpty) {
      throw ArgumentError.value(
        createdBy,
        'createdBy',
        'createdBy must be the auth UID of the current user — Firestore '
            'rules reject expense writes without it.',
      );
    }
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    final data = <String, dynamic>{
      'id': id,
      'eventId': eventId,
      'payerParticipantId': payerParticipantId,
      'amountFils': MoneySerializer.toSubunits(amount, currency),
      'currency': currency,
      'description': description,
      'scope': scope.value,
      'subGroupId': scope == ExpenseScope.subGroup ? subGroupId : null,
      'customSplitParticipants': customSplitParticipants ?? [],
      if (splitMode != null && splitMode != SplitMode.equally) ...{
        'splitMode': splitMode.storageKey,
        'splitDistribution': _encodeDistribution(
          splitMode,
          splitDistribution ?? const {},
          currency,
        ),
      },
      'receiptUrl': receiptUrl,
      'categoryId': categoryId,
      'note': note,
      'isDeleted': false,
      'deletedAt': null,
      'createdAt': now.toIso8601String(),
      'createdBy': createdBy,
      // #248: the creator is the editor at create time. Rules pin
      // lastEditedBy == auth.uid; createdBy is already pinned to it.
      'lastEditedBy': createdBy,
    };
    try {
      await eventSubcollection(groupId, eventId, 'expenses').doc(id).set(data);
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint('ExpenseService.addExpense failed: ${e.code} ${e.message}');
      }
      rethrow;
    }

    // #248 PR 2: the expenseAuditLogger Cloud Functions trigger writes the
    // activity_logs entry server-side (tamper-proof, attributed via lastEditedBy);
    // the client no longer writes it.
    return Expense.fromFirestore(data);
  }

  /// Updates specific fields of an existing expense document.
  ///
  /// Only non-null parameters are included in the Firestore update to avoid
  /// overwriting fields with null. If [amount] is provided, [currency] is
  /// used for the MoneySerializer conversion (defaults to 'OMR').
  Future<void> updateExpense({
    required String groupId,
    required String eventId,
    required String expenseId,
    Decimal? amount,
    String? currency,
    String? description,
    ExpenseScope? scope,
    String? subGroupId,
    List<String>? customSplitParticipants,
    SplitMode? splitMode,
    Map<String, Decimal>? splitDistribution,
    bool clearSplit = false,
    String? note,
    String? categoryId,
    String? payerParticipantId,
    String? lastEditedBy,
  }) async {
    final updates = <String, dynamic>{};
    if (amount != null) {
      // #261: never default the currency on an amount edit — that silently
      // re-scales amountFils (a USD 10.00 read back as OMR 1.000) and clobbers
      // the stored currency. The caller (edit_expense_screen) passes
      // original.currency; a uid-less / currency-less amount edit is a bug.
      if (currency == null) {
        throw ArgumentError('updateExpense requires a currency when amount is set');
      }
      updates['amountFils'] = MoneySerializer.toSubunits(amount, currency);
      updates['currency'] = currency;
    }
    if (description != null) updates['description'] = description;
    if (scope != null) updates['scope'] = scope.value;
    if (subGroupId != null) updates['subGroupId'] = subGroupId;
    if (customSplitParticipants != null) {
      updates['customSplitParticipants'] = customSplitParticipants;
    }
    if (clearSplit) {
      updates['splitMode'] = FieldValue.delete();
      updates['splitDistribution'] = FieldValue.delete();
    } else if (splitMode != null && splitMode != SplitMode.equally) {
      updates['splitMode'] = splitMode.storageKey;
      updates['splitDistribution'] = _encodeDistribution(
        splitMode,
        splitDistribution ?? const {},
        currency ?? 'OMR',
      );
    }
    if (note != null) updates['note'] = note;
    if (categoryId != null) updates['categoryId'] = categoryId;
    if (payerParticipantId != null) {
      updates['payerParticipantId'] = payerParticipantId;
    }
    if (updates.isNotEmpty) {
      // #248: stamp the editor's UID on every real change. PR4 makes the rules
      // pin MANDATORY (lastEditedBy == auth.uid on every update), so an authed
      // caller MUST supply its uid here or the write is rejected — the trigger
      // then attributes the edit to the real editor, never the creator. The
      // null/empty guard only skips a uid-less caller, who cannot write anyway
      // (rules require signedIn()); it is not a backward-compat escape hatch.
      if (lastEditedBy != null && lastEditedBy.isNotEmpty) {
        updates['lastEditedBy'] = lastEditedBy;
      }
      try {
        await eventSubcollection(
          groupId,
          eventId,
          'expenses',
        ).doc(expenseId).update(updates);
      } on FirebaseException catch (e) {
        if (kDebugMode) {
          debugPrint(
            'ExpenseService.updateExpense failed: ${e.code} ${e.message}',
          );
        }
        rethrow;
      }
    }
  }

  /// Soft-deletes an expense by setting [isDeleted] = true and recording a
  /// [deletedAt] timestamp. The document is NOT removed from Firestore.
  Future<void> deleteExpense({
    required String groupId,
    required String eventId,
    required String expenseId,
    String? lastEditedBy,
  }) async {
    try {
      await eventSubcollection(
        groupId,
        eventId,
        'expenses',
      ).doc(expenseId).update({
        'isDeleted': true,
        'deletedAt': DateTime.now().toUtc().toIso8601String(),
        // #248: attribute the deleter so PR2's trigger logs who removed it.
        if (lastEditedBy != null && lastEditedBy.isNotEmpty)
          'lastEditedBy': lastEditedBy,
      });
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'ExpenseService.deleteExpense failed: ${e.code} ${e.message}',
        );
      }
      rethrow;
    }
  }

  /// Encodes a split distribution map into the integer form Firestore stores.
  /// Exact: scaled to currency subunits via [MoneySerializer].
  /// Percent: scaled by 1000 so 33.333 % round-trips as 33333.
  /// Shares: raw integer count.
  static Map<String, int> _encodeDistribution(
    SplitMode mode,
    Map<String, Decimal> distribution,
    String currency,
  ) {
    return {
      for (final entry in distribution.entries)
        entry.key: switch (mode) {
          SplitMode.exact =>
            MoneySerializer.toSubunits(entry.value, currency),
          SplitMode.percent =>
            (entry.value * Decimal.fromInt(1000)).toBigInt().toInt(),
          SplitMode.shares ||
          SplitMode.equally =>
            entry.value.toBigInt().toInt(),
        },
    };
  }
}
