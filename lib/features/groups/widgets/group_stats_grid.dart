import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../keys/group_keys.dart';

/// 2x2 stats grid for the GroupDetailScreen above-the-fold summary.
///
/// Displays four stat tiles: YOUR BALANCE (color-coded), GROUP TOTAL,
/// ACTIVE MEMBERS, and EVENTS.
///
/// Per D-08: the grid is always visible (not conditional on expense data).
/// Per D-01: YOUR BALANCE uses errorText/successText/textPrimary based on
/// whether the user owes money, is owed money, or is settled.
class GroupStatsGrid extends StatelessWidget {
  /// Current user's net balance across all events in the group.
  final Decimal userNetBalance;

  /// Total amount spent across all events in the group.
  final Decimal groupTotal;

  /// Number of active members in the group.
  final int activeMembers;

  /// Total number of events in the group.
  final int eventCount;

  /// Currency code for formatting financial values (e.g., 'OMR').
  final String currency;

  const GroupStatsGrid({
    super.key,
    required this.userNetBalance,
    required this.groupTotal,
    required this.activeMembers,
    required this.eventCount,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    // Dart 3 switch expression for YOUR BALANCE color coding (D-01)
    final balanceColor = switch (userNetBalance.compareTo(Decimal.zero)) {
      < 0 => AppColors.errorText,
      > 0 => AppColors.successText,
      _ => AppColors.textPrimary,
    };

    return GridView.count(
      key: GroupKeys.statsGrid,
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppColors.space8,
      mainAxisSpacing: AppColors.space8,
      childAspectRatio: 1.6,
      children: [
        _StatCard(
          key: GroupKeys.statYourBalance,
          label: 'YOUR BALANCE',
          value: AppFormatters.formatCurrency(userNetBalance.abs(), currency),
          valueColor: balanceColor,
        ),
        _StatCard(
          key: GroupKeys.statGroupTotal,
          label: 'GROUP TOTAL',
          value: AppFormatters.formatCurrency(groupTotal, currency),
          valueColor: AppColors.textPrimary,
        ),
        _StatCard(
          key: GroupKeys.statActiveMembers,
          label: 'ACTIVE MEMBERS',
          value: '$activeMembers',
          valueColor: AppColors.textPrimary,
        ),
        _StatCard(
          key: GroupKeys.statEvents,
          label: 'EVENTS',
          value: '$eventCount',
          valueColor: AppColors.textPrimary,
        ),
      ],
    );
  }
}

/// A single stat tile inside the stats grid.
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppColors.radiusSmall),
      ),
      padding: const EdgeInsets.all(AppColors.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppColors.space4),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
