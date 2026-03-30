import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../keys/home_keys.dart';

/// Balance hero card for the home dashboard.
///
/// Displays the current user's net balance across all groups.
/// Shows three distinct visual states:
/// - Red "You owe" when net is negative
/// - Green "You are owed" when net is positive
/// - Gray "All settled up" when net is zero
///
/// Shows [SkeletonLoader.dashboardHero] while data loads.
class BalanceHeroCard extends ConsumerWidget {
  const BalanceHeroCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(crossGroupBalanceProvider);

    return balanceAsync.when(
      loading: () => SkeletonLoader.dashboardHero(),
      error: (_, __) => _buildErrorCard(),
      data: (balance) => _buildCard(balance),
    );
  }

  Widget _buildCard(CrossGroupBalance balance) {
    final net = balance.net;
    final groupCount = balance.groupCount;

    final (Color color, IconData icon, String amountText, String descriptionText) =
        switch (net.compareTo(Decimal.zero)) {
      < 0 => (
          AppColors.errorText,
          Iconsax.warning_2,
          'OMR ${net.abs().toStringAsFixed(3)}',
          'You owe across $groupCount group${groupCount == 1 ? '' : 's'}',
        ),
      > 0 => (
          AppColors.successText,
          Iconsax.tick_circle,
          'OMR ${net.toStringAsFixed(3)}',
          'You are owed across $groupCount group${groupCount == 1 ? '' : 's'}',
        ),
      _ => (
          AppColors.textSecondary,
          Iconsax.tick_circle,
          'OMR 0.000',
          'All settled up',
        ),
    };

    return Container(
      key: HomeKeys.balanceHeroCard,
      margin: const EdgeInsets.symmetric(horizontal: AppColors.space16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.radiusLarge),
        boxShadow: AppColors.shadowRaised,
      ),
      padding: const EdgeInsets.all(AppColors.space16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppColors.radiusMedium),
            ),
            child: Icon(icon, size: 24, color: color),
          ),
          const SizedBox(width: AppColors.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  amountText,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  descriptionText,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      key: HomeKeys.balanceHeroCard,
      margin: const EdgeInsets.symmetric(horizontal: AppColors.space16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.radiusLarge),
        boxShadow: AppColors.shadowRaised,
      ),
      padding: const EdgeInsets.all(AppColors.space16),
      child: const Row(
        children: [
          Icon(Iconsax.warning_2, size: 24, color: AppColors.textSecondary),
          SizedBox(width: AppColors.space12),
          Text(
            'Balance unavailable',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
