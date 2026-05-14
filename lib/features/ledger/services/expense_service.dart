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
    String? actorId,
    String? actorName,
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
    };
    try {
      await eventSubcollection(groupId, eventId, 'expenses').doc(id).set(data);
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint('ExpenseService.addExpense failed: ${e.code} ${e.message}');
      }
      rethrow;
    }

    try {
      await _addExpenseCreatedActivity(
        groupId: groupId,
        eventId: eventId,
        expenseId: id,
        payerParticipantId: payerParticipantId,
        amount: amount,
        currency: currency,
        actorId: actorId ?? payerParticipantId,
        actorName: actorName,
        description: description,
        scope: scope,
        subGroupId: subGroupId,
        customSplitParticipants: customSplitParticipants,
        categoryId: categoryId,
      );
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'ExpenseService.addExpense activity log failed: ${e.code} ${e.message}',
        );
      }
    }

    return Expense.fromFirestore(data);
  }

  Future<void> _addExpenseCreatedActivity({
    required String groupId,
    required String eventId,
    required String expenseId,
    required String payerParticipantId,
    required Decimal amount,
    required String currency,
    required String actorId,
    required ExpenseScope scope,
    String? actorName,
    String? description,
    String? subGroupId,
    List<String>? customSplitParticipants,
    String? categoryId,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    final trimmedActorName = actorName?.trim();
    final normalizedActorName =
        trimmedActorName == null || trimmedActorName.isEmpty
        ? null
        : trimmedActorName;
    final trimmedDescription = description?.trim();
    final expenseLabel =
        trimmedDescription == null || trimmedDescription.isEmpty
        ? 'an expense'
        : trimmedDescription;
    final amountText = '${amount.toString()} $currency';

    await eventSubcollection(groupId, eventId, 'activity_logs').doc(id).set({
      'id': id,
      'eventId': eventId,
      'category': 'MONEY',
      'eventType': 'CREATE',
      'logText':
          '${normalizedActorName ?? 'Someone'} added $expenseLabel for $amountText',
      'actorId': actorId,
      'actorName': normalizedActorName,
      'metadata': {
        'expenseId': expenseId,
        'amount': amount.toString(),
        'amountFils': MoneySerializer.toSubunits(amount, currency),
        'currency': currency,
        'description': trimmedDescription,
        'payerParticipantId': payerParticipantId,
        'scope': scope.value,
        'subGroupId': subGroupId,
        'customSplitParticipants': customSplitParticipants ?? const <String>[],
        'categoryId': categoryId,
      },
      'createdAt': now.toIso8601String(),
    });
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
  }) async {
    final updates = <String, dynamic>{};
    if (amount != null) {
      final cur = currency ?? 'OMR';
      updates['amountFils'] = MoneySerializer.toSubunits(amount, cur);
      updates['currency'] = cur;
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
  }) async {
    try {
      await eventSubcollection(
        groupId,
        eventId,
        'expenses',
      ).doc(expenseId).update({
        'isDeleted': true,
        'deletedAt': DateTime.now().toUtc().toIso8601String(),
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
