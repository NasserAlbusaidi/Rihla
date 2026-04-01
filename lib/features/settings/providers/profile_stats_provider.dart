import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../events/providers/event_provider.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';

/// Aggregated profile statistics derived from existing providers.
///
/// All values are derived from [userGroupsProvider], [groupEventsProvider],
/// and [groupBalancesProvider] — no new Firestore queries.
typedef ProfileStats = ({
  int groupCount,
  int eventCount,
  Decimal totalSpent,
});

/// Aggregates cross-group stats for the current user's profile.
///
/// Uses [Provider] (not [StreamProvider]) so that [ref.watch] calls inside
/// a loop over a variable-length groups list work correctly — same pattern
/// as [groupBalancesProvider] and [crossGroupBalanceProvider].
///
/// Returns:
/// - [AsyncValue.loading] while [userGroupsProvider] has no value, or while
///   any group's events / balances are still loading with zero data
/// - [AsyncValue.error] if [userGroupsProvider] errors
/// - [AsyncValue.data] with aggregated [ProfileStats] once all data is ready
final profileStatsProvider = Provider<AsyncValue<ProfileStats>>((ref) {
  // Step 1: Watch the user's groups
  final groupsAsync = ref.watch(userGroupsProvider);
  if (groupsAsync.isLoading && !groupsAsync.hasValue) {
    return const AsyncValue.loading();
  }
  if (groupsAsync.hasError) {
    return AsyncValue.error(groupsAsync.error!, groupsAsync.stackTrace!);
  }
  final groups = groupsAsync.valueOrNull ?? [];

  if (groups.isEmpty) {
    return AsyncValue.data((
      groupCount: 0,
      eventCount: 0,
      totalSpent: Decimal.zero,
    ));
  }

  // Step 2: Accumulate event count and total spending across all groups
  var eventCount = 0;
  var totalSpent = Decimal.zero;
  var anyLoading = false;

  for (final group in groups) {
    // Watch events for this group to get an accurate event count
    final eventsAsync = ref.watch(groupEventsProvider(group.id));
    if (eventsAsync.isLoading && !eventsAsync.hasValue) {
      anyLoading = true;
    } else {
      eventCount += (eventsAsync.valueOrNull ?? []).length;
    }

    // Watch group balances for total spending
    final balancesAsync = ref.watch(groupBalancesProvider(group.id));
    if (balancesAsync.isLoading && !balancesAsync.hasValue) {
      anyLoading = true;
    } else {
      final balances = balancesAsync.valueOrNull;
      if (balances != null) {
        totalSpent = totalSpent + balances.totalSpent;
      }
    }
  }

  // If anything is still loading and we have no real data yet, stay loading
  if (anyLoading && eventCount == 0 && totalSpent == Decimal.zero) {
    return const AsyncValue.loading();
  }

  return AsyncValue.data((
    groupCount: groups.length,
    eventCount: eventCount,
    totalSpent: totalSpent,
  ));
});
