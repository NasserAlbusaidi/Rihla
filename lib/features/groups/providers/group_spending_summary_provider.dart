import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../events/models/event_model.dart';
import '../../events/providers/event_provider.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../ledger/utils/group_spending_summary.dart';
import 'group_balance_provider.dart';

/// Derived spending insights for one group (#180). Display-only sibling of
/// [groupBalancesProvider] — a projection, never a money source.
///
/// Iterates the SAME [groupEventsProvider] list and the SAME per-event
/// [eventExpensesProvider]/[eventSettlementsProvider] family instances the
/// live balance provider watches, so this adds NO new Firestore listeners
/// (the streams are already open while the group screen is mounted — same
/// argument as [groupTaggedEventSettlementsProvider]).
final groupSpendingSummaryProvider =
    Provider.family<GroupSpendingSummary, String>((ref, groupId) {
      final events =
          ref.watch(groupEventsProvider(groupId)).valueOrNull ??
          const <Event>[];
      final balancesAsync = ref.watch(groupBalancesProvider(groupId));
      // A hard-errored balance basis (not merely loading) means the
      // superlatives can't be computed — mark it loud so the card doesn't
      // render a partial summary as complete (#1034). Loading keeps the
      // blessed silent path (superlatives just absent).
      final balancesUnavailable =
          balancesAsync.hasError && !balancesAsync.hasValue;
      final balances = balancesAsync.valueOrNull;

      final expensesByEvent = <String, List<Expense>>{};
      for (final event in events) {
        final eventRef = (groupId: groupId, eventId: event.id);
        final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
        final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));
        // Mirrors groupBalancesProvider's OR-skip (loading/error on EITHER
        // money stream) so the summary's event universe can never disagree
        // with the balances feeding topPayer/topConsumer.
        if ((expensesAsync.isLoading && !expensesAsync.hasValue) ||
            (settlementsAsync.isLoading && !settlementsAsync.hasValue)) {
          continue;
        }
        if ((expensesAsync.hasError && !expensesAsync.hasValue) ||
            (settlementsAsync.hasError && !settlementsAsync.hasValue)) {
          continue;
        }
        expensesByEvent[event.id] =
            expensesAsync.valueOrNull ?? const <Expense>[];
      }

      return computeGroupSpendingSummary(
        expensesByEvent: expensesByEvent,
        balances: balances?.balances ?? const <String, List<UserBalance>>{},
        balancesUnavailable: balancesUnavailable,
      );
    });
