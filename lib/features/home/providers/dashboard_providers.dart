import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../groups/models/group_activity_log_model.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';

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
  String currency,
});

/// Cap on the merged cross-group feed. 30 keeps the Activity tab's filter
/// chips honest — they filter a real window, not a 5-item cache that lets
/// last week's settlement age out before the chip is ever tapped. The home
/// RECENTLY section is unaffected (it slices `take(3)`).
const kCrossGroupActivityMergedCap = 30;

/// Aggregates the most recent activity entries across ALL groups,
/// merged chronologically (newest first), capped at
/// [kCrossGroupActivityMergedCap].
///
/// For each group, watches [groupActivityProvider] (which returns the
/// `kCrossGroupActivityPerGroupLimit` most recent per-group). Merges all
/// entries, sorts by timestamp descending, takes the cap.
///
/// Each entry is enriched with [groupName] from the groups list (D-14).
///
/// Returns:
/// - [AsyncValue.loading] while [userGroupsProvider] has no value
/// - [AsyncValue.error] if [userGroupsProvider] errors
/// - [AsyncValue.data] with up to [kCrossGroupActivityMergedCap] entries
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
          allEntries.add((
            log: log,
            groupName: group.name,
            groupId: group.id,
            currency: group.currency,
          ));
        }
      }

      if (anyLoading && allEntries.isEmpty) return const AsyncValue.loading();

      // Sort descending by timestamp (newest first), take the cap.
      allEntries.sort((a, b) => b.log.timestamp.compareTo(a.log.timestamp));
      final window = allEntries.length > kCrossGroupActivityMergedCap
          ? allEntries.sublist(0, kCrossGroupActivityMergedCap)
          : allEntries;
      return AsyncValue.data(window);
    });
