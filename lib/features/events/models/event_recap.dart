import 'package:decimal/decimal.dart';

import '../../ledger/models/expense_model.dart';

/// Immutable, per-currency money summary of one event for the recap/closeout
/// surface (#202 Slice 1). A pure projection over [BalanceCalculator] output —
/// it adds no money arithmetic beyond the per-currency `settled` rearrangement.
///
/// Spec + Gate review: docs/plans/2026-06-20-202-slice1-recap-core.md.
///
/// Money invariant: every field is a per-currency map keyed by currency code.
/// Decimals are NEVER summed across currencies (10 USD + 10 OMR is nonsense);
/// the recap selects from already-bucketed balances.
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
      isEmpty: expenseCount == 0,
    );
  }
}
