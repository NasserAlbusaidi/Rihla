import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../groups/models/group_activity_log_model.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../../events/providers/event_provider.dart';
import '../../ledger/models/expense_model.dart';
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
      final top5 = allEntries.length > 5
          ? allEntries.sublist(0, 5)
          : allEntries;
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

// ---------------------------------------------------------------------------
// ARCH-02: Per-group aggregate stream for weekly expenses.
// Bounds the listener count to O(G), not O(G×E).
// ---------------------------------------------------------------------------

/// Returns all non-deleted expenses in the current week for one group,
/// aggregated across all of that group's events via Firestore range queries.
///
/// Server-side filter: `createdAt >= startOfWeek AND createdAt < startOfNextWeek`.
/// ISO-8601 string comparison is lexicographically correct for UTC timestamps.
///
/// Does NOT watch [eventExpensesProvider] — that provider downloads all
/// expenses (not just the current week) and would defeat the whole point
/// of this refactor.
final weeklyGroupExpensesProvider =
    StreamProvider.family<List<Expense>, String>((ref, groupId) {
      final eventsAsync = ref.watch(groupEventsProvider(groupId));
      final events = eventsAsync.valueOrNull ?? const [];
      if (events.isEmpty) return Stream.value(const []);

      // Compute the week window in UTC (to match ISO-8601 storage).
      final now = DateTime.now().toUtc();
      final today = DateTime.utc(now.year, now.month, now.day);
      final weekday = today.weekday; // 1 = Monday, 7 = Sunday
      final startOfWeek = today.subtract(Duration(days: weekday - 1));
      final startOfNextWeek = startOfWeek.add(const Duration(days: 7));

      final service = ref.read(expenseServiceProvider);

      final streams = events
          .map(
            (event) => service.watchExpensesInRange(
              groupId: groupId,
              eventId: event.id,
              startUtc: startOfWeek,
              endExclusiveUtc: startOfNextWeek,
            ),
          )
          .toList();

      return _combineExpenseStreams(streams);
    });

/// Combines N `Stream<List<Expense>>` into one `Stream<List<Expense>>`.
///
/// Maintains a per-stream latest list and emits the flattened concatenation
/// whenever any source emits. Emits only after all N sources have emitted at
/// least once (prevents partial state from reaching consumers).
Stream<List<Expense>> _combineExpenseStreams(
  List<Stream<List<Expense>>> streams,
) {
  if (streams.isEmpty) return Stream.value(const []);

  // ignore: close_sinks — closed via onCancel when the Riverpod subscriber disposes
  final controller = StreamController<List<Expense>>();
  final latest = List<List<Expense>?>.filled(streams.length, null);
  var pendingCount = streams.length;
  final subs = <StreamSubscription<List<Expense>>>[];

  void tryEmit() {
    if (pendingCount > 0) return; // not all streams have emitted yet
    controller.add(latest.expand((l) => l!).toList());
  }

  for (var i = 0; i < streams.length; i++) {
    final index = i;
    subs.add(
      streams[index].listen(
        (list) {
          if (latest[index] == null) pendingCount--;
          latest[index] = list;
          tryEmit();
        },
        onError: controller.addError,
        cancelOnError: false,
      ),
    );
  }

  controller.onCancel = () async {
    for (final sub in subs) {
      await sub.cancel();
    }
    await controller.close();
  };

  return controller.stream;
}

/// Aggregates weekly expenses across all groups using the per-group
/// [weeklyGroupExpensesProvider] (O(G) listeners, not O(G×E)).
///
/// Returns a list of exactly 7 [DailySpending] entries (one per day,
/// Monday through Sunday). Days with no expenses have [DailySpending.amount]
/// set to [Decimal.zero].
final weeklyGroupSpendingProvider = Provider<AsyncValue<List<DailySpending>>>((
  ref,
) {
  final groupsAsync = ref.watch(userGroupsProvider);
  if (groupsAsync.isLoading && !groupsAsync.hasValue) {
    return const AsyncValue.loading();
  }
  if (groupsAsync.hasError) {
    return AsyncValue.error(groupsAsync.error!, groupsAsync.stackTrace!);
  }
  final groups = groupsAsync.valueOrNull ?? [];

  // Compute start of current week in local time for day-bucket grouping.
  // (createdAt deserialises to local DateTime via Expense.fromFirestore.)
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final weekday = today.weekday; // 1 = Monday, 7 = Sunday
  final startOfWeek = today.subtract(Duration(days: weekday - 1));
  final startOfNextWeek = startOfWeek.add(const Duration(days: 7));

  if (groups.isEmpty) {
    return AsyncValue.data(_emptyWeek(startOfWeek));
  }

  final allExpenseAmounts = <DateTime, Decimal>{};
  var anyLoading = false;

  for (final group in groups) {
    // ARCH-02: O(G) — one per-group provider, not one per event.
    final expensesAsync = ref.watch(weeklyGroupExpensesProvider(group.id));
    if (expensesAsync.isLoading && !expensesAsync.hasValue) {
      anyLoading = true;
      continue;
    }
    final expenses = expensesAsync.valueOrNull ?? const [];
    for (final expense in expenses) {
      final expenseDate = DateTime(
        expense.createdAt.year,
        expense.createdAt.month,
        expense.createdAt.day,
      );
      // Defensive trim: Firestore range may include UTC boundary overlap
      if (expenseDate.isBefore(startOfWeek)) continue;
      if (!expenseDate.isBefore(startOfNextWeek)) continue;
      allExpenseAmounts[expenseDate] =
          (allExpenseAmounts[expenseDate] ?? Decimal.zero) + expense.amount;
    }
  }

  if (anyLoading && allExpenseAmounts.isEmpty) {
    return const AsyncValue.loading();
  }

  return AsyncValue.data(
    List.generate(7, (i) {
      final date = startOfWeek.add(Duration(days: i));
      return (date: date, amount: allExpenseAmounts[date] ?? Decimal.zero);
    }),
  );
});

/// Returns a list of 7 [DailySpending] entries all with [Decimal.zero] amounts.
List<DailySpending> _emptyWeek(DateTime startOfWeek) {
  return List.generate(7, (i) {
    final date = startOfWeek.add(Duration(days: i));
    return (date: date, amount: Decimal.zero);
  });
}
