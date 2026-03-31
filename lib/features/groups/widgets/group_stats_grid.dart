import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../keys/group_keys.dart';
import '../../../core/theme/tokens/color_tokens.dart';

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
      < 0 => AppColorTokens.light.errorText,
      > 0 => AppColorTokens.light.successText,
      _ => AppColorTokens.light.textPrimary,
    };

    return GridView.count(
      key: GroupKeys.statsGrid,
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
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
          valueColor: AppColorTokens.light.textPrimary,
        ),
        _StatCard(
          key: GroupKeys.statActiveMembers,
          label: 'ACTIVE MEMBERS',
          value: '$activeMembers',
          valueColor: AppColorTokens.light.textPrimary,
        ),
        _StatCard(
          key: GroupKeys.statEvents,
          label: 'EVENTS',
          value: '$eventCount',
          valueColor: AppColorTokens.light.textPrimary,
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
        color: AppColorTokens.light.cardSurface,
        border: Border.all(color: AppColorTokens.light.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColorTokens.light.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
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
