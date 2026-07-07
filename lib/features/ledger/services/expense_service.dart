import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/split_mode.dart';
import '../../../core/services/firestore_repository.dart';
import '../../../core/services/money_serializer.dart';
import '../../../core/utils/safe_deserialize.dart';
import '../models/expense_model.dart';
import '../models/split_explanation.dart';

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
    // The #632 diff cache lives INSIDE the subscribe closure so a #997
    // re-listen starts clean against its fresh full snapshot.
    return recoverListen(() {
      final cache = <String, Expense>{};
      return eventSubcollection(groupId, eventId, 'expenses')
          .where('isDeleted', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snap) => _reconcileExpenses(cache, snap));
    });
  }

  /// Maps a fresh expense-query [snap] to `List<Expense>`, deserializing only
  /// the docs that changed since the previous tick (#632).
  ///
  /// Firestore re-emits the FULL document set on every `.snapshots()` tick, but
  /// its `docChanges` delta names only the added/modified/removed docs (the
  /// initial snapshot reports every doc as `added`). `Expense.fromFirestore`
  /// runs O(P) `Decimal`/`MoneySerializer` allocations per doc, so remapping all
  /// N docs each tick is an O(N×P) UI-isolate burst on every add/edit/delete by
  /// any member. The [cache] (`id → Expense`) lets us re-deserialize only the
  /// changed docs and reuse the cached immutable [Expense] for every unchanged
  /// one. Per-tick cost becomes an O(N) list rebuild + O(changed×P)
  /// deserialization (typically one doc), down from O(N×P). The first tick still
  /// parses all N once (all `added`) — unavoidable on open.
  ///
  /// [cache] is created fresh per `watchExpenses`/`watchExpensesInRange` call,
  /// and each call returns its own stream listened to exactly once (production
  /// `.snapshots()` is single-subscription), so the cache is effectively
  /// per-subscription — no cross-subscription bleed. The `??=` in the build loop
  /// is a defensive parse-on-miss; in practice the docChanges loop fills the
  /// cache before the list is rebuilt.
  List<Expense> _reconcileExpenses(
    Map<String, Expense> cache,
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    // #928 money-fence backstop (BOTH parse points). The total-parse
    // `Expense.fromFirestore` makes a throw practically unreachable, but a
    // SKIPPED money doc has NO server-oracle counterpart (the oracle is total),
    // so this catch is a doc-catastrophe last resort — NOT a safety net for a
    // future non-total factory field. A persistently-throwing doc re-reports per
    // tick via the cache miss below.
    for (final change in snap.docChanges) {
      final doc = change.doc;
      if (change.type == DocumentChangeType.removed) {
        cache.remove(doc.id);
        continue;
      }
      final data = doc.data();
      if (data != null) {
        try {
          cache[doc.id] = Expense.fromFirestore({...data, 'id': doc.id});
        } catch (e, st) {
          cache.remove(doc.id);
          _reportSkippedExpense(doc.id, e, st);
        }
      }
    }
    // Manual loop (not a collection-`for` with `??=`) so the per-doc try/catch
    // can wrap the cache-miss parse: one malformed row is skipped, never blanks
    // the whole list.
    final out = <Expense>[];
    for (final doc in snap.docs) {
      var expense = cache[doc.id];
      if (expense == null) {
        try {
          expense = Expense.fromFirestore({...doc.data(), 'id': doc.id});
          cache[doc.id] = expense;
        } catch (e, st) {
          _reportSkippedExpense(doc.id, e, st);
          continue;
        }
      }
      out.add(expense);
    }
    return out;
  }

  static void _reportSkippedExpense(String docId, Object e, StackTrace st) {
    assert(() {
      debugPrint('[ExpenseService._reconcileExpenses] skipped malformed '
          'doc $docId: $e');
      return true;
    }());
    unawaited(Sentry.captureException(e, stackTrace: st));
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
    // #928 money-fence backstop: a doc-level catastrophe is skipped rather than
    // erroring the home once-path. This has no server-oracle counterpart (the
    // oracle is total) — it is NOT a safety net for a non-total factory field;
    // the factory's totality (test 7) is what keeps client/server in lockstep.
    return decodeDocsSkippingMalformed(
      snap.docs,
      (d) => Expense.fromFirestore(
        {...d.data()! as Map<String, dynamic>, 'id': d.id},
      ),
      context: 'ExpenseService.getExpenses',
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
    final cache = <String, Expense>{};
    return eventSubcollection(groupId, eventId, 'expenses')
        .where('isDeleted', isEqualTo: false)
        .where('createdAt', isGreaterThanOrEqualTo: startUtc.toIso8601String())
        .where('createdAt', isLessThan: endExclusiveUtc.toIso8601String())
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => _reconcileExpenses(cache, snap));
  }

  /// Creates a new expense document in Firestore and returns the resulting
  /// [Expense] object once the SERVER has acknowledged the write.
  ///
  /// Offline, that ack only arrives on reconnect — UI flows that must not
  /// block on it use [stageExpense] instead (#412).
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
    SplitExplanation? splitExplanation,
    String? receiptUrl,
    String? categoryId,
    String? note,
  }) async {
    final staged = stageExpense(
      groupId: groupId,
      eventId: eventId,
      payerParticipantId: payerParticipantId,
      amount: amount,
      createdBy: createdBy,
      currency: currency,
      description: description,
      scope: scope,
      subGroupId: subGroupId,
      customSplitParticipants: customSplitParticipants,
      splitMode: splitMode,
      splitDistribution: splitDistribution,
      splitExplanation: splitExplanation,
      receiptUrl: receiptUrl,
      categoryId: categoryId,
      note: note,
    );
    try {
      await staged.ack;
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint('ExpenseService.addExpense failed: ${e.code} ${e.message}');
      }
      rethrow;
    }
    return staged.expense;
  }

  /// Stages a new expense: applies the write to the local Firestore cache and
  /// returns the locally-built [Expense] IMMEDIATELY, plus the server-ack
  /// future (#412). The ack resolves only when the server confirms — offline
  /// it stays pending until reconnect while the SDK queues the replay, so
  /// callers race it (`awaitServerAck`) instead of awaiting it raw.
  ///
  /// The [amount] is converted to integer fils via [MoneySerializer.toSubunits]
  /// before being stored. The returned [Expense] is deserialized from the data
  /// that was written, so amount round-trips through [MoneySerializer].
  ///
  /// Throws [ArgumentError] synchronously when [createdBy] is empty.
  ({Expense expense, Future<void> ack}) stageExpense({
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
    SplitExplanation? splitExplanation,
    String? receiptUrl,
    String? categoryId,
    String? note,
  }) {
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
      // #203 S2: opaque itemized display metadata. TOP-LEVEL (not nested in the
      // splitMode block, which is omitted for an equally split). Write only when
      // present — a null value fails the `is map` rules bound.
      if (splitExplanation != null) 'splitExplanation': splitExplanation.toMap(),
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
    final ack = eventSubcollection(groupId, eventId, 'expenses')
        .doc(id)
        .set(data);

    // #248 PR 2: the expenseAuditLogger Cloud Functions trigger writes the
    // activity_logs entry server-side (tamper-proof, attributed via lastEditedBy);
    // the client no longer writes it.
    return (expense: Expense.fromFirestore(data), ack: ack);
  }

  /// Updates specific fields of an existing expense document.
  ///
  /// Only non-null parameters are included in the Firestore update to avoid
  /// overwriting fields with null. [currency] is required for every update path
  /// that serializes money: [amount] and [SplitMode.exact] distributions.
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
    SplitExplanation? splitExplanation,
    bool clearExplanation = false,
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
        throw ArgumentError(
          'updateExpense requires a currency when amount is set',
        );
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
        currency,
      );
    }
    // #203 S2: itemized display metadata, written through its OWN flags —
    // independent of clearSplit/splitMode so a relabel-only edit (identical
    // distribution) still persists the new map. clearExplanation orphan-deletes
    // it when an expense stops being itemized; absent both flags, the key is
    // untouched so an unrelated edit (e.g. a note change) preserves it.
    if (clearExplanation) {
      updates['splitExplanation'] = FieldValue.delete();
    } else if (splitExplanation != null) {
      updates['splitExplanation'] = splitExplanation.toMap();
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
    String? currency,
  ) {
    if (mode == SplitMode.exact && currency == null) {
      throw ArgumentError(
        'updateExpense requires a currency when exact split is set',
      );
    }

    return {
      for (final entry in distribution.entries)
        entry.key: switch (mode) {
          SplitMode.exact =>
            MoneySerializer.toSubunits(entry.value, currency!),
          SplitMode.percent =>
            (entry.value * Decimal.fromInt(1000)).toBigInt().toInt(),
          SplitMode.shares ||
          SplitMode.equally =>
            entry.value.toBigInt().toInt(),
        },
    };
  }
}
