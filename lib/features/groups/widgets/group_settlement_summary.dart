import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../keys/group_keys.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// Summary card displayed at the top of the Group Settle-Up screen.
///
/// Shows total pending amount across all events in the group.
class GroupSettlementSummaryCard extends StatelessWidget {
  final Decimal totalPending;
  final String currency;
  final int eventCount;

  const GroupSettlementSummaryCard({
    super.key,
    required this.totalPending,
    required this.currency,
    required this.eventCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            context.colors.primary.withValues(alpha: 0.12),
            context.colors.cardSurface.withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: context.colors.primary.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: context.shadows.floating,
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GROUP TOTAL PENDING',
            key: GroupKeys.settleUpGroupTotalLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppFormatters.formatCurrency(totalPending, currency),
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Across $eventCount event${eventCount == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
