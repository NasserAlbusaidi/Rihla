import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

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
    String currency = 'OMR',
    String? description,
    ExpenseScope scope = ExpenseScope.global,
    String? subGroupId,
    List<String>? customSplitParticipants,
    String? receiptUrl,
    String? categoryId,
    String? note,
  }) async {
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
      'receiptUrl': receiptUrl,
      'categoryId': categoryId,
      'note': note,
      'isDeleted': false,
      'deletedAt': null,
      'createdAt': now.toIso8601String(),
    };
    await eventSubcollection(groupId, eventId, 'expenses').doc(id).set(data);
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
    String? note,
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
    if (note != null) updates['note'] = note;
    if (updates.isNotEmpty) {
      await eventSubcollection(groupId, eventId, 'expenses')
          .doc(expenseId)
          .update(updates);
    }
  }

  /// Soft-deletes an expense by setting [isDeleted] = true and recording a
  /// [deletedAt] timestamp. The document is NOT removed from Firestore.
  Future<void> deleteExpense({
    required String groupId,
    required String eventId,
    required String expenseId,
  }) async {
    await eventSubcollection(groupId, eventId, 'expenses').doc(expenseId).update({
      'isDeleted': true,
      'deletedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
