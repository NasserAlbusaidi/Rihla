import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../keys/group_keys.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

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
      < 0 => context.colors.errorText,
      > 0 => context.colors.successText,
      _ => context.colors.textPrimary,
    };

    // Direction label for YOUR BALANCE — makes sign explicit (D-12)
    final balanceSubtitle = switch (userNetBalance.compareTo(Decimal.zero)) {
      < 0 => 'You owe',
      > 0 => 'Owed to you',
      _ => 'Settled',
    };

    return Container(
      key: GroupKeys.statsGrid,
      decoration: BoxDecoration(
        color: context.colors.inputFillWarm,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: context.colors.border.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _StatCard(
                    key: GroupKeys.statYourBalance,
                    label: 'YOUR BALANCE',
                    value: AppFormatters.formatCurrency(userNetBalance.abs(), currency),
                    valueColor: balanceColor,
                    subtitle: balanceSubtitle,
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 0.5,
                  color: context.colors.border.withValues(alpha: 0.4),
                  indent: 12,
                  endIndent: 12,
                ),
                Expanded(
                  child: _StatCard(
                    key: GroupKeys.statGroupTotal,
                    label: 'GROUP TOTAL',
                    value: AppFormatters.formatCurrency(groupTotal, currency),
                    valueColor: context.colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: context.colors.border.withValues(alpha: 0.4),
            indent: 12,
            endIndent: 12,
          ),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _StatCard(
                    key: GroupKeys.statActiveMembers,
                    label: 'MEMBERS',
                    value: '$activeMembers',
                    valueColor: context.colors.textPrimary,
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 0.5,
                  color: context.colors.border.withValues(alpha: 0.4),
                  indent: 12,
                  endIndent: 12,
                ),
                Expanded(
                  child: _StatCard(
                    key: GroupKeys.statEvents,
                    label: 'EVENTS',
                    value: '$eventCount',
                    valueColor: context.colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single stat tile inside the stats grid.
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  /// Optional direction label rendered below the value (e.g. "You owe",
  /// "Owed to you", "Settled"). Only used for YOUR BALANCE tile (D-12).
  final String? subtitle;

  const _StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.valueColor,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: context.colors.textSecondary.withValues(alpha: 0.7),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: valueColor,
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: valueColor.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
