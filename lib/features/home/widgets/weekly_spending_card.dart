import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/skeleton_loader.dart';
import '../keys/home_keys.dart';
import '../providers/dashboard_providers.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// Weekly spending bar chart card for the home dashboard.
///
/// Renders 7 proportional-height teal bars for Mon-Sun with day labels.
/// Shows "No spending this week" when all day amounts are zero.
/// Shows skeleton while data loads.
///
/// Pitfall guard: divides bar height by maxAmount only when maxAmount > 0
/// (RESEARCH Pitfall 5 — guard division by zero).
class WeeklySpendingCard extends ConsumerWidget {
  const WeeklySpendingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spendingAsync = ref.watch(weeklyGroupSpendingProvider);

    return spendingAsync.when(
      loading: () => _buildCardShell(
        context: context,
        key: HomeKeys.weeklySpendingCard,
        child: SkeletonLoader.generic(count: 3),
      ),
      error: (error, stack) => _buildCardShell(
        context: context,
        key: HomeKeys.weeklySpendingCard,
        child: Text(
          'Spending data unavailable',
          style: TextStyle(
            fontSize: 14,
            color: context.colors.textSecondary,
          ),
        ),
      ),
      data: (weekData) => _buildCard(context, weekData),
    );
  }

  Widget _buildCard(BuildContext context, List<DailySpending> weekData) {
    final maxAmount = weekData.fold(
      Decimal.zero,
      (prev, entry) => entry.amount > prev ? entry.amount : prev,
    );
    final allZero = maxAmount == Decimal.zero;

    return _buildCardShell(
      context: context,
      key: HomeKeys.weeklySpendingCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Weekly Spending (OMR)',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: context.colors.textPrimary,
            ),
          ),
          SizedBox(height: context.spacing.space16),
          if (allZero)
            Text(
              'No spending this week',
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
              ),
            )
          else
            SizedBox(
              height: 96,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: weekData.map((entry) {
                  final fraction = maxAmount > Decimal.zero
                      ? (entry.amount / maxAmount).toDouble()
                      : 0.0;
                  final barHeight = 60 * fraction;
                  final dayLabel = DateFormat.E()
                      .format(entry.date)
                      .substring(0, 3);

                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (entry.amount > Decimal.zero)
                          Text(
                            entry.amount.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: context.colors.textSecondary,
                            ),
                          ),
                        if (entry.amount > Decimal.zero)
                          SizedBox(height: context.spacing.space4),
                        Container(
                          height: barHeight > 0 ? barHeight : 2,
                          decoration: BoxDecoration(
                            color: barHeight > 0
                                ? context.colors.primary
                                : context.colors.inputFill,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        SizedBox(height: context.spacing.space4),
                        // Day label (Mon/Tue/...) — functional data label per D-11
                        // → textSecondary (was textMuted prior to Phase 37).
                        Text(
                          dayLabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCardShell({
    required BuildContext context,
    required Key key,
    required Widget child,
  }) {
    return Container(
      key: key,
      margin: EdgeInsets.symmetric(horizontal: context.spacing.space16),
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.shadows.raised,
      ),
      padding: EdgeInsets.all(context.spacing.space16),
      child: child,
    );
  }
}
