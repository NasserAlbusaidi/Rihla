import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../shared/widgets/animated_currency_text.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../keys/home_keys.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

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
      loading: SkeletonLoader.dashboardHero,
      error: (error, stack) => _buildErrorCard(context),
      data: (balance) => _buildCard(context, balance),
    );
  }

  Widget _buildCard(BuildContext context, CrossGroupBalance balance) {
    final net = balance.net;
    final groupCount = balance.groupCount;

    final (Color color, IconData icon, String descriptionText) =
        switch (net.compareTo(Decimal.zero)) {
      < 0 => (
          context.colors.errorText,
          Iconsax.warning_2,
          'You owe across $groupCount group${groupCount == 1 ? '' : 's'}',
        ),
      > 0 => (
          context.colors.successText,
          Iconsax.tick_circle,
          'You are owed across $groupCount group${groupCount == 1 ? '' : 's'}',
        ),
      _ => (
          context.colors.textSecondary,
          Iconsax.tick_circle,
          'All settled up',
        ),
    };

    return Container(
      key: HomeKeys.balanceHeroCard,
      margin: EdgeInsets.symmetric(horizontal: context.spacing.space16),
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.shadows.raised,
        image: const DecorationImage(
          image: AssetImage('assets/textures/grain.png'),
          repeat: ImageRepeat.repeat,
          opacity: 0.035,
          fit: BoxFit.none,
          alignment: Alignment.topLeft,
        ),
      ),
      padding: EdgeInsets.all(context.spacing.space16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 24, color: color),
          ),
          SizedBox(width: context.spacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedCurrencyText(
                  value: net,
                  currency: 'OMR',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  descriptionText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context) {
    return Container(
      key: HomeKeys.balanceHeroCard,
      margin: EdgeInsets.symmetric(horizontal: context.spacing.space16),
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.shadows.raised,
        image: const DecorationImage(
          image: AssetImage('assets/textures/grain.png'),
          repeat: ImageRepeat.repeat,
          opacity: 0.035,
          fit: BoxFit.none,
          alignment: Alignment.topLeft,
        ),
      ),
      padding: EdgeInsets.all(context.spacing.space16),
      child: Row(
        children: [
          Icon(Iconsax.warning_2, size: 24, color: context.colors.textSecondary),
          SizedBox(width: context.spacing.space12),
          Text(
            'Balance unavailable',
            style: TextStyle(
              fontSize: 14,
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
