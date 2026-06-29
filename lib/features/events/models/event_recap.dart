import 'package:decimal/decimal.dart';

import '../../../core/services/money_serializer.dart';
import '../../ledger/models/expense_model.dart';

/// The single largest expense in one currency (#721 Slice 2). Display-only.
/// `description` may be null/empty → the screen falls back to the category name.
typedef RecapExpenseRef = ({
  String expenseId,
  Decimal amount,
  String? description,
  String? categoryId,
  String payerId,
});

/// A person + a positive amount: a payer-breakdown / top-payer row (#721).
typedef RecapPersonAmount = ({String participantId, Decimal amount});

/// A category id + its summed amount in one currency (#721).
typedef RecapCategoryTotal = ({String categoryId, Decimal total});

/// A person's net position in one currency (#721).
typedef RecapNet = ({String participantId, Decimal net});

/// Immutable, per-currency money summary of one event for the recap/closeout
/// surface (#202 Slice 1, extended by the full summary in #721 Slice 2). A pure
/// projection over [BalanceCalculator] output + the raw expense list — it adds
/// no money arithmetic beyond per-currency aggregation (max / sum-per-bucket).
///
/// Spec + Gate review: docs/plans/2026-06-20-202-slice1-recap-core.md (Slice 1),
/// docs/plans/2026-06-29-721-recap-full-summary.md (Slice 2).
///
/// Money invariant: every field is a per-currency map keyed by currency code.
/// Decimals are NEVER summed across currencies (10 USD + 10 OMR is nonsense);
/// the recap selects from already-bucketed balances and currency-fenced expenses.
class EventRecap {
  final String eventId;
  final String eventName;
  final DateTime? startDate;
  final DateTime? endDate;

  /// The LIVE roster size (`Event.participantIds.length`), NOT the balance
  /// universe — which folds departed/tombstoned members with residual balances
  /// (#249) and would over-count "who was on this trip".
  final int participantCount;
  final int expenseCount;

  /// Total spent per currency = `calculateTotalExpensesByCurrency`. Keyed by
  /// EXPENSE currencies, so a settlement-only currency can be absent here while
  /// still present in the user maps below.
  final Map<String, Decimal> totalSpentByCurrency;

  // The four current-user maps share ONE key set: currencies where the user is
  // present AND had real involvement (paid, owed, or a settlement). `net` is
  // carried even when 0, so a square-but-active spender is still shown.
  // For every key: net == paid - share + settled.
  final Map<String, Decimal> userPaidByCurrency;
  final Map<String, Decimal> userShareByCurrency;

  /// Net settlements per currency (`settlementAdj`): positive = the user GAVE
  /// settlements, negative = received. The reconciling term in
  /// `net = paid - share + settled`.
  final Map<String, Decimal> userSettledByCurrency;
  final Map<String, Decimal> userNetByCurrency;

  // ---- Slice 2 (#721): the full money summary, all per-currency. ----

  /// Largest single expense per currency. Keyed by EXPENSE currencies — absent
  /// for a settlement-only currency (no expense to be biggest).
  final Map<String, RecapExpenseRef> biggestExpenseByCurrency;

  /// Gross cash fronted per currency, desc, zero-paid excluded. Keyed by ALL
  /// BALANCE currencies (a settlement-only currency → empty list, never null).
  /// Built from `UserBalance.totalPaid` (settlement-INDEPENDENT) — top payer is
  /// `payerTotalsByCurrency[c].first`. Distinct from [participantNetsByCurrency].
  final Map<String, List<RecapPersonAmount>> payerTotalsByCurrency;

  /// Spend per category id per currency, desc. Keyed by EXPENSE currencies.
  /// Buckets by `categoryId ?? 'other'` — sum equals [totalSpentByCurrency].
  final Map<String, List<RecapCategoryTotal>> categoryTotalsByCurrency;

  /// Everyone's net per currency: the FULL balance universe (incl. departed
  /// members with residual balances, #249 — so their debt doesn't vanish),
  /// unlike [participantCount]. Sorted current-user-first, then net desc.
  /// `net` is settlement-FOLDED (`UserBalance.netBalance`).
  final Map<String, List<RecapNet>> participantNetsByCurrency;

  /// Per currency: true iff every net is EXACTLY zero (no tolerance — matches
  /// `nonZeroNetsGccFirst`, not `UserBalance.isSettled`'s 0.001 band).
  final Map<String, bool> isSettledByCurrency;

  final bool isEmpty;

  const EventRecap({
    required this.eventId,
    required this.eventName,
    required this.startDate,
    required this.endDate,
    required this.participantCount,
    required this.expenseCount,
    required this.totalSpentByCurrency,
    required this.userPaidByCurrency,
    required this.userShareByCurrency,
    required this.userSettledByCurrency,
    required this.userNetByCurrency,
    required this.biggestExpenseByCurrency,
    required this.payerTotalsByCurrency,
    required this.categoryTotalsByCurrency,
    required this.participantNetsByCurrency,
    required this.isSettledByCurrency,
    required this.isEmpty,
  });

  /// Pure assembly from already-computed inputs (no Riverpod, no Firestore) so
  /// the money logic is unit-testable in isolation. [balances] and
  /// [totalSpentByCurrency] come from `ledgerViewProvider`; [uid] from
  /// `currentUserIdProvider`.
  factory EventRecap.from({
    required String eventId,
    required String eventName,
    required DateTime? startDate,
    required DateTime? endDate,
    required List<String> participantIds,
    required int expenseCount,
    required Map<String, Decimal> totalSpentByCurrency,
    required Map<String, List<UserBalance>> balances,
    List<Expense> expenses = const [],
    required String? uid,
  }) {
    final paid = <String, Decimal>{};
    final share = <String, Decimal>{};
    final settled = <String, Decimal>{};
    final net = <String, Decimal>{};

    if (uid != null) {
      balances.forEach((currency, bucket) {
        UserBalance? mine;
        for (final b in bucket) {
          if (b.participantId == uid) {
            mine = b;
            break;
          }
        }
        if (mine == null) return; // user not in this currency

        // settlementAdj rearranged from net = (paid + adj) - owed.
        final settlementAdj = mine.netBalance - mine.totalPaid + mine.totalOwed;
        final involved = mine.totalPaid != Decimal.zero ||
            mine.totalOwed != Decimal.zero ||
            settlementAdj != Decimal.zero;
        if (!involved) return; // genuine no-op in this currency

        paid[currency] = mine.totalPaid;
        share[currency] = mine.totalOwed;
        settled[currency] = settlementAdj;
        net[currency] = mine.netBalance;
      });
    }

    // ---- Slice 2: expense-driven maps (biggest expense + category totals). ----
    // Currency fence MUST match `calculateTotalExpensesByCurrency` so the
    // category breakdown sums to the displayed total (decomposition invariant).
    String ccyOf(Expense e) =>
        MoneySerializer.isSupported(e.currency) ? e.currency : 'OMR';
    final biggestRaw = <String, Expense>{};
    final catRaw = <String, Map<String, Decimal>>{};
    for (final e in expenses) {
      final c = ccyOf(e);
      final cur = biggestRaw[c];
      if (cur == null ||
          e.amount > cur.amount ||
          (e.amount == cur.amount && e.id.compareTo(cur.id) < 0)) {
        biggestRaw[c] = e;
      }
      // null/unknown categoryId → 'other'; no kCategoryIds check keeps this
      // model Flutter-free. Unknown ids render as Other at the widget.
      final catId = e.categoryId ?? 'other';
      (catRaw[c] ??= <String, Decimal>{})
          .update(catId, (v) => v + e.amount, ifAbsent: () => e.amount);
    }
    final biggestExpense = <String, RecapExpenseRef>{
      for (final entry in biggestRaw.entries)
        entry.key: (
          expenseId: entry.value.id,
          amount: entry.value.amount,
          description: entry.value.description,
          categoryId: entry.value.categoryId,
          payerId: entry.value.payerParticipantId,
        ),
    };
    final categoryTotals = <String, List<RecapCategoryTotal>>{
      for (final entry in catRaw.entries)
        entry.key: List.unmodifiable(
          entry.value.entries
              .map((e) => (categoryId: e.key, total: e.value))
              .toList()
            ..sort((x, y) {
              final byTotal = y.total.compareTo(x.total); // desc
              return byTotal != 0
                  ? byTotal
                  : x.categoryId.compareTo(y.categoryId);
            }),
        ),
    };

    // ---- Slice 2: balance-driven maps (payer totals, nets, settled). ----
    final payerTotals = <String, List<RecapPersonAmount>>{};
    final participantNets = <String, List<RecapNet>>{};
    final isSettled = <String, bool>{};
    balances.forEach((currency, bucket) {
      final payers = bucket
          .where((b) => b.totalPaid > Decimal.zero)
          .map((b) => (participantId: b.participantId, amount: b.totalPaid))
          .toList()
        ..sort((x, y) {
          final byAmt = y.amount.compareTo(x.amount); // desc
          return byAmt != 0 ? byAmt : x.participantId.compareTo(y.participantId);
        });
      payerTotals[currency] = List.unmodifiable(payers);

      final nets = bucket
          .map((b) => (participantId: b.participantId, net: b.netBalance))
          .toList()
        ..sort((x, y) {
          if (uid != null) {
            if (x.participantId == uid && y.participantId != uid) return -1;
            if (y.participantId == uid && x.participantId != uid) return 1;
          }
          final byNet = y.net.compareTo(x.net); // desc (creditors first)
          return byNet != 0 ? byNet : x.participantId.compareTo(y.participantId);
        });
      participantNets[currency] = List.unmodifiable(nets);

      isSettled[currency] = bucket.every((b) => b.netBalance == Decimal.zero);
    });

    return EventRecap(
      eventId: eventId,
      eventName: eventName,
      startDate: startDate,
      endDate: endDate,
      participantCount: participantIds.length,
      expenseCount: expenseCount,
      totalSpentByCurrency: Map.unmodifiable(totalSpentByCurrency),
      userPaidByCurrency: Map.unmodifiable(paid),
      userShareByCurrency: Map.unmodifiable(share),
      userSettledByCurrency: Map.unmodifiable(settled),
      userNetByCurrency: Map.unmodifiable(net),
      biggestExpenseByCurrency: Map.unmodifiable(biggestExpense),
      payerTotalsByCurrency: Map.unmodifiable(payerTotals),
      categoryTotalsByCurrency: Map.unmodifiable(categoryTotals),
      participantNetsByCurrency: Map.unmodifiable(participantNets),
      isSettledByCurrency: Map.unmodifiable(isSettled),
      isEmpty: expenseCount == 0,
    );
  }
}
