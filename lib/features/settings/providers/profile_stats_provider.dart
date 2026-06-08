import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/supported_currencies.dart';
import '../../events/providers/event_provider.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';

/// One currency's slice of lifetime spend (#378). [amount] is the gross sum of
/// every group's `totalSpent` in [currency] — currencies are NEVER summed
/// together (there is no FX; #382).
typedef CurrencySpend = ({String currency, Decimal amount});

/// Aggregated profile statistics derived from existing providers.
///
/// All values are derived from [userGroupsProvider], [groupEventsProvider],
/// and [groupBalancesProvider] — no new Firestore queries.
///
/// [spentByCurrency] is bucketed per currency (#378) — one entry per currency
/// the user has nonzero lifetime spend in, sorted GCC-first (same rank rule as
/// [crossGroupBalanceProvider]'s `byCurrency`). Replaces the old currency-blind
/// `totalSpent` scalar, which summed e.g. 10 USD + 10 OMR into a nonsense "20".
typedef ProfileStats = ({
  int groupCount,
  int eventCount,
  List<CurrencySpend> spentByCurrency,
});

/// GCC-first sort of the spend buckets, identical rank rule to
/// `_sortedCurrencyBuckets` in `group_balance_provider.dart`: known codes in
/// [kSupportedCurrencies] order, an off-list legacy code sorts last (never
/// dropped), alpha tiebreak. Drops zero-amount buckets.
List<CurrencySpend> _sortedSpendBuckets(Map<String, Decimal> spentMap) {
  final list = <CurrencySpend>[
    for (final e in spentMap.entries)
      if (e.value != Decimal.zero) (currency: e.key, amount: e.value),
  ];
  int rank(String c) {
    final i = kSupportedCurrencies.indexOf(c);
    return i < 0 ? kSupportedCurrencies.length : i;
  }

  list.sort((a, b) {
    final r = rank(a.currency).compareTo(rank(b.currency));
    return r != 0 ? r : a.currency.compareTo(b.currency);
  });
  return list;
}

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
    return const AsyncValue.data((
      groupCount: 0,
      eventCount: 0,
      spentByCurrency: <CurrencySpend>[],
    ));
  }

  // Step 2: Accumulate event count and per-currency spend across all groups.
  // Spend is bucketed by the group's (single, immutable) currency — never
  // summed across currencies (#378).
  var eventCount = 0;
  final spentMap = <String, Decimal>{};
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
        spentMap[group.currency] =
            (spentMap[group.currency] ?? Decimal.zero) + balances.totalSpent;
      }
    }
  }

  // If anything is still loading and we have no real data yet, stay loading
  if (anyLoading && eventCount == 0 && spentMap.isEmpty) {
    return const AsyncValue.loading();
  }

  return AsyncValue.data((
    groupCount: groups.length,
    eventCount: eventCount,
    spentByCurrency: _sortedSpendBuckets(spentMap),
  ));
});
