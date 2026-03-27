import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';

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
            AppColors.primary.withValues(alpha: 0.12),
            AppColors.surface.withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: AppColors.cardShadowLarge,
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'GROUP TOTAL PENDING',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppFormatters.formatCurrency(totalPending, currency),
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Across $eventCount event${eventCount == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
