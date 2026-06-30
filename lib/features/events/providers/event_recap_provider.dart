import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../groups/providers/group_balance_provider.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../ledger/providers/ledger_view_provider.dart';
import '../models/event_recap.dart';
import 'event_provider.dart';

/// On-demand recap projection for one event (#202 Slice 1). A thin wrapper that
/// watches the existing per-event providers and delegates all money assembly to
/// the pure [EventRecap.from] factory.
///
/// Reuses the memoized [ledgerViewProvider] (the `BalanceCalculator` pass), so
/// opening the recap costs no extra Decimal work. Reads the current user via the
/// reactive, recovery-safe [currentUserIdProvider] — never `FirebaseConfig`.
final eventRecapProvider = Provider.family<EventRecap, EventRef>((ref, eventRef) {
  final event = ref.watch(eventDetailProvider(eventRef)).valueOrNull;
  final view = ref.watch(ledgerViewProvider(eventRef));
  final expenses =
      ref.watch(eventExpensesProvider(eventRef)).valueOrNull ??
      const <Expense>[];
  final uid = ref.watch(currentUserIdProvider);

  // Null/loading/soft-deleted event → empty recap; the screen renders a
  // not-found state for a hard-missing event (Gate R3 P2).
  if (event == null) {
    return const EventRecap(
      eventId: '',
      eventName: '',
      startDate: null,
      endDate: null,
      participantCount: 0,
      expenseCount: 0,
      totalSpentByCurrency: {},
      userPaidByCurrency: {},
      userShareByCurrency: {},
      userSettledByCurrency: {},
      userNetByCurrency: {},
      biggestExpenseByCurrency: {},
      payerTotalsByCurrency: {},
      categoryTotalsByCurrency: {},
      participantNetsByCurrency: {},
      isSettledByCurrency: {},
      isEmpty: true,
    );
  }

  // #766 (Slice 6): a CLOSED event with a captured snapshot serves the frozen
  // SPENDING half from the snapshot while settlement stays LIVE (from
  // view.balances). Open events, and closed-but-unsnapshotted legacy/empty
  // events, fall through to the fully-live projection below.
  final snapshot = event.spendingSnapshot;
  if (event.isClosed && snapshot != null) {
    return EventRecap.fromSnapshot(
      snapshot: snapshot,
      eventId: event.id,
      eventName: event.name,
      startDate: event.startDate,
      endDate: event.endDate,
      balances: view.balances,
      uid: uid,
    );
  }

  return EventRecap.from(
    eventId: event.id,
    eventName: event.name,
    startDate: event.startDate,
    endDate: event.endDate,
    participantIds: event.participantIds,
    expenseCount: expenses.length,
    totalSpentByCurrency: view.eventTotal,
    balances: view.balances,
    expenses: expenses,
    uid: uid,
  );
});
