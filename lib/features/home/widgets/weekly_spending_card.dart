import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../keys/home_keys.dart';
import '../providers/dashboard_providers.dart';

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
        key: HomeKeys.weeklySpendingCard,
        child: SkeletonLoader.generic(count: 3),
      ),
      error: (error, stack) => _buildCardShell(
        key: HomeKeys.weeklySpendingCard,
        child: const Text(
          'Spending data unavailable',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
      ),
      data: _buildCard,
    );
  }

  Widget _buildCard(List<DailySpending> weekData) {
    final maxAmount = weekData.fold(
      Decimal.zero,
      (prev, entry) => entry.amount > prev ? entry.amount : prev,
    );
    final allZero = maxAmount == Decimal.zero;

    return _buildCardShell(
      key: HomeKeys.weeklySpendingCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'This Week',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppColors.space16),
          if (allZero)
            const Text(
              'No spending this week',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            )
          else
            SizedBox(
              height: 80,
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
                        Container(
                          height: barHeight > 0 ? barHeight : 2,
                          decoration: BoxDecoration(
                            color: barHeight > 0
                                ? AppColors.primary
                                : AppColors.surfaceLight,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dayLabel,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
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

  Widget _buildCardShell({required Key key, required Widget child}) {
    return Container(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: AppColors.space16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.radiusLarge),
        boxShadow: AppColors.shadowRaised,
      ),
      padding: const EdgeInsets.all(AppColors.space16),
      child: child,
    );
  }
}
