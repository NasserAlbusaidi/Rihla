import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/formatters.dart';
import '../keys/profile_keys.dart';
import '../providers/profile_stats_provider.dart';

/// Displays cross-group stats (groups, events, total spending) in 3 cards.
///
/// Consumes [AsyncValue<ProfileStats>] and renders skeletons while loading,
/// graceful zeros on error, and real values once data is available.
class ProfileStatsSection extends StatelessWidget {
  const ProfileStatsSection({super.key, required this.stats});

  final AsyncValue<ProfileStats> stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ProfileKeys.statsSection,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Icon(
              Iconsax.chart,
              size: 16,
              color: context.colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              context.l10n.profileSectionJourney,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.colors.textSecondary,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        SizedBox(height: context.spacing.space12),
        // Stats row
        Row(
          children: _buildStatCards(context),
        ),
      ],
    );
  }

  List<Widget> _buildStatCards(BuildContext context) {
    final l10n = context.l10n;
    if (stats.isLoading) {
      // Placeholder cards while loading
      return [
        _buildStatCard(
          context: context,
          key: ProfileKeys.statGroups,
          value: '–',
          label: l10n.profileStatsGroups,
          accent: context.colors.primary,
        ),
        SizedBox(width: context.spacing.space8),
        _buildStatCard(
          context: context,
          key: ProfileKeys.statEvents,
          value: '–',
          label: l10n.profileStatsEvents,
          accent: context.colors.successText,
        ),
        SizedBox(width: context.spacing.space8),
        _buildStatCard(
          context: context,
          key: ProfileKeys.statSpent,
          value: '–',
          label: l10n.profileStatsSpent,
          accent: context.colors.primaryDark,
        ),
      ];
    }

    // Use actual data if available, fall back to zeros on error
    final data = stats.valueOrNull ??
        (groupCount: 0, eventCount: 0, totalSpent: Decimal.zero);

    return [
      _buildStatCard(
        context: context,
        key: ProfileKeys.statGroups,
        value: data.groupCount.toString(),
        label: l10n.profileStatsGroups,
        accent: context.colors.primary,
      ),
      SizedBox(width: context.spacing.space8),
      _buildStatCard(
        context: context,
        key: ProfileKeys.statEvents,
        value: data.eventCount.toString(),
        label: l10n.profileStatsEvents,
        accent: context.colors.successText,
      ),
      SizedBox(width: context.spacing.space8),
      _buildStatCard(
        context: context,
        key: ProfileKeys.statSpent,
        value: AppFormatters.formatCurrency(data.totalSpent, 'OMR'),
        label: l10n.profileStatsSpent,
        accent: context.colors.primaryDark,
      ),
    ];
  }

  Widget _buildStatCard({
    required BuildContext context,
    required Key key,
    required String value,
    required String label,
    required Color accent,
  }) {
    return Expanded(
      child: Container(
        key: key,
        padding: EdgeInsets.symmetric(
          vertical: context.spacing.space16,
          horizontal: context.spacing.space12,
        ),
        decoration: BoxDecoration(
          color: context.colors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: context.shadows.raised,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: context.spacing.space4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.colors.textSecondary,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
