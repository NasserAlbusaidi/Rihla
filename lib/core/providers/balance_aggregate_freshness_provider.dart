import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Groups whose home balance aggregate may lag behind local Firestore writes.
///
/// Connectivity can prove queued writes reached Firestore, but the
/// `groups/{gid}/aggregates/balance` doc is refreshed later by Cloud Functions
/// triggers. Marking a group here keeps the home facade on the once-path until
/// the aggregate values catch up to the local Firestore view.
final balanceAggregateFreshnessProvider =
    StateNotifierProvider<BalanceAggregateFreshnessNotifier, Set<String>>((
      ref,
    ) {
      return BalanceAggregateFreshnessNotifier();
    });

class BalanceAggregateFreshnessNotifier extends StateNotifier<Set<String>> {
  BalanceAggregateFreshnessNotifier() : super(const <String>{});

  void markGroupDirty(String groupId) {
    if (groupId.isEmpty || state.contains(groupId)) return;
    state = {...state, groupId};
  }

  void clearGroupDirty(String groupId) {
    if (!state.contains(groupId)) return;
    state = {...state}..remove(groupId);
  }
}
