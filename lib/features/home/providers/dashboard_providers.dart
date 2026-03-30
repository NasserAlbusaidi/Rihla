import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../groups/models/group_activity_log_model.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../../events/providers/event_provider.dart';
import '../../ledger/providers/expense_provider.dart';

// ---------------------------------------------------------------------------
// CrossGroupActivity
// ---------------------------------------------------------------------------

/// Record type for a cross-group activity entry enriched with group name.
///
/// The [groupName] is included because D-14 requires the activity feed to
/// display which group each entry belongs to.
typedef CrossGroupActivityEntry = ({
  GroupActivityLog log,
  String groupName,
  String groupId,
});

/// Aggregates the 5 most recent activity entries across ALL groups,
/// merged chronologically (newest first).
///
/// For each group, watches [groupActivityProvider] (which returns the 5 most
/// recent per-group). Merges all entries, sorts by timestamp descending,
/// takes top 5.
///
/// Each entry is enriched with [groupName] from the groups list (D-14).
///
/// Returns:
/// - [AsyncValue.loading] while [userGroupsProvider] has no value
/// - [AsyncValue.error] if [userGroupsProvider] errors
/// - [AsyncValue.data] with a list of up to 5 [CrossGroupActivityEntry] records
final crossGroupActivityProvider =
    Provider<AsyncValue<List<CrossGroupActivityEntry>>>((ref) {
  final groupsAsync = ref.watch(userGroupsProvider);
  if (groupsAsync.isLoading && !groupsAsync.hasValue) {
    return const AsyncValue.loading();
  }
  if (groupsAsync.hasError) {
    return AsyncValue.error(groupsAsync.error!, groupsAsync.stackTrace!);
  }
  final groups = groupsAsync.valueOrNull ?? [];
  if (groups.isEmpty) return const AsyncValue.data([]);

  final allEntries = <CrossGroupActivityEntry>[];
  var anyLoading = false;

  for (final group in groups) {
    final activityAsync = ref.watch(groupActivityProvider(group.id));
    if (activityAsync.isLoading && !activityAsync.hasValue) {
      anyLoading = true;
      continue;
    }
    final logs = activityAsync.valueOrNull ?? [];
    for (final log in logs) {
      allEntries.add((log: log, groupName: group.name, groupId: group.id));
    }
  }

  if (anyLoading && allEntries.isEmpty) return const AsyncValue.loading();

  // Sort descending by timestamp (newest first), take top 5
  allEntries.sort((a, b) => b.log.timestamp.compareTo(a.log.timestamp));
  final top5 =
      allEntries.length > 5 ? allEntries.sublist(0, 5) : allEntries;
  return AsyncValue.data(top5);
});

// ---------------------------------------------------------------------------
// WeeklyGroupSpending
// ---------------------------------------------------------------------------

/// Record type for daily spending aggregation.
///
/// [date] is the calendar date (time component is midnight local).
/// [amount] is the total amount spent across all groups on that day.
typedef DailySpending = ({DateTime date, Decimal amount});

/// Aggregates expenses across all groups' events for the current week (Mon-Sun).
///
/// Watches [userGroupsProvider] → [groupEventsProvider] per group →
/// [eventExpensesProvider] per event. Filters expenses by
/// `createdAt >= startOfWeek` and sums per day.
///
/// Returns a list of exactly 7 [DailySpending] entries (one per day,
/// Monday through Sunday). Days with no expenses have [DailySpending.amount]
/// set to [Decimal.zero].
final weeklyGroupSpendingProvider =
    Provider<AsyncValue<List<DailySpending>>>((ref) {
  final groupsAsync = ref.watch(userGroupsProvider);
  if (groupsAsync.isLoading && !groupsAsync.hasValue) {
    return const AsyncValue.loading();
  }
  if (groupsAsync.hasError) {
    return AsyncValue.error(groupsAsync.error!, groupsAsync.stackTrace!);
  }
  final groups = groupsAsync.valueOrNull ?? [];

  // Compute start of current week (Monday 00:00:00 local)
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final weekday = today.weekday; // 1 = Monday, 7 = Sunday
  final startOfWeek = today.subtract(Duration(days: weekday - 1));

  if (groups.isEmpty) {
    return AsyncValue.data(_emptyWeek(startOfWeek));
  }

  // Gather all expense amounts keyed by calendar date
  final allExpenseAmounts = <DateTime, Decimal>{};
  var anyLoading = false;

  for (final group in groups) {
    final eventsAsync = ref.watch(groupEventsProvider(group.id));
    if (eventsAsync.isLoading && !eventsAsync.hasValue) {
      anyLoading = true;
      continue;
    }
    final events = eventsAsync.valueOrNull ?? [];
    for (final event in events) {
      final eventRef = (groupId: group.id, eventId: event.id);
      final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
      if (expensesAsync.isLoading && !expensesAsync.hasValue) {
        anyLoading = true;
        continue;
      }
      final expenses = expensesAsync.valueOrNull ?? [];
      for (final expense in expenses) {
        final expenseDate = DateTime(
          expense.createdAt.year,
          expense.createdAt.month,
          expense.createdAt.day,
        );
        // Only include expenses within the current week
        if (expenseDate.isBefore(startOfWeek)) continue;
        if (expenseDate.isAfter(today)) continue;
        allExpenseAmounts[expenseDate] =
            (allExpenseAmounts[expenseDate] ?? Decimal.zero) + expense.amount;
      }
    }
  }

  if (anyLoading && allExpenseAmounts.isEmpty) {
    return const AsyncValue.loading();
  }

  // Build 7-day list (Mon-Sun)
  final week = List.generate(7, (i) {
    final date = startOfWeek.add(Duration(days: i));
    return (date: date, amount: allExpenseAmounts[date] ?? Decimal.zero);
  });

  return AsyncValue.data(week);
});

/// Returns a list of 7 [DailySpending] entries all with [Decimal.zero] amounts.
List<DailySpending> _emptyWeek(DateTime startOfWeek) {
  return List.generate(7, (i) {
    final date = startOfWeek.add(Duration(days: i));
    return (date: date, amount: Decimal.zero);
  });
}
