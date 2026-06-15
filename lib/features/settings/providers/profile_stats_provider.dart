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
/// and [groupBalancesOnceProvider] — no new Firestore queries.
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
  var anyEventsLoading = false;
  var anyBalanceLoading = false;

  for (final group in groups) {
    // Watch events for this group to get an accurate event count
    final eventsAsync = ref.watch(groupEventsProvider(group.id));
    if (eventsAsync.isLoading && !eventsAsync.hasValue) {
      anyEventsLoading = true;
    } else {
      eventCount += (eventsAsync.valueOrNull ?? []).length;
    }

    // Watch group balances for total spending via the ONE-SHOT path (#517):
    // the live [groupBalancesProvider] holds a per-event `.snapshots()` listener
    // for every event of every group, and the always-mounted Profile tab would
    // leak them O(G×E) for the whole session (the #104 leak, reopened). The
    // one-shot variant reads per-event money with `.get()` — zero live leaf
    // listeners — and computes the same `totalSpent` via [computeGroupBalances].
    final balancesAsync = ref.watch(groupBalancesOnceProvider(group.id));
    if (balancesAsync.isLoading && !balancesAsync.hasValue) {
      anyBalanceLoading = true;
    } else {
      final balances = balancesAsync.valueOrNull?.balances;
      if (balances != null) {
        // #382 PR-1: merge by the BUCKET currency (the honest key — equal to
        // group.currency for all prod data under the uniformity rules). Never
        // collapse back to group.currency: that re-introduces the #378
        // cross-currency sum for legacy/forged mixed docs.
        for (final entry in balances.totalSpent.entries) {
          spentMap[entry.key] =
              (spentMap[entry.key] ?? Decimal.zero) + entry.value;
        }
      }
    }
  }

  // Stay on the loading skeleton rather than emit a partial frame that flashes
  // a false value (#517 Gate P2): the one-shot balance path emits loading-FIRST
  // (unlike the old synchronous live provider, which resolved spend in the same
  // pass as the counts), so a balance still mid-flight with NO spend known yet
  // must not render the hard "0.000" Spent tile. Once ANY real spend lands a
  // growing partial is fine. Symmetric guard keeps the skeleton while the event
  // count is still unknown. A resolved genuinely-zero group (empty spend, no
  // loading) falls through to data and renders its honest 0.000.
  if ((anyBalanceLoading && spentMap.isEmpty) ||
      (anyEventsLoading && eventCount == 0)) {
    return const AsyncValue.loading();
  }

  return AsyncValue.data((
    groupCount: groups.length,
    eventCount: eventCount,
    spentByCurrency: _sortedSpendBuckets(spentMap),
  ));
});
