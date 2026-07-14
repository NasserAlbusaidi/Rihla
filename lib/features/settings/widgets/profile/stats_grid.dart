import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../keys/profile_keys.dart';
import '../../providers/profile_stats_provider.dart';
import 'spent_value.dart';
import 'stat_card.dart';
import 'stats_error_card.dart';
import 'stats_grid_skeleton.dart';

class StatsGrid extends ConsumerWidget {
  const StatsGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // #488: explicit loading skeleton + error state — never an ambiguous "—"
    // that reads as zero / no-data when the stats actually failed or are still
    // loading.
    return ref
        .watch(profileStatsProvider)
        .when(
          loading: () => const StatsGridSkeleton(),
          error: (_, _) => const StatsErrorCard(),
          data: (stats) => Padding(
            key: ProfileKeys.statsSection,
            padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
            child: Row(
              children: [
                Expanded(
                  child: StatCard(
                    statKey: ProfileKeys.statEvents,
                    keyLabel: l10n.profileStatsJourneysLabel,
                    value: '${stats.eventCount}',
                    sub: l10n.profileStatsAllTime,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatCard(
                    statKey: ProfileKeys.statGroups,
                    keyLabel: l10n.profileStatsGroupsLabel,
                    value: '${stats.groupCount}',
                    sub: l10n.profileStatsActive,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatCard(
                    statKey: ProfileKeys.statSpent,
                    keyLabel: l10n.profileStatsSpentLabel,
                    valueWidget: SpentValue(spent: stats.spentByCurrency),
                    sub: l10n.profileStatsLifetime,
                  ),
                ),
              ],
            ),
          ),
        );
  }
}
