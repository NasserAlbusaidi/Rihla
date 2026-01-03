import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../logistics/providers/sub_group_provider.dart';
import '../../trip/models/trip_model.dart';
import '../../trip/providers/trip_provider.dart';
import '../providers/expense_provider.dart';
import '../services/settlement_service.dart';

/// Settle Up Screen - Shows optimized settlements with payment actions
class SettleUpScreen extends ConsumerWidget {
  final Trip trip;

  const SettleUpScreen({super.key, required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(tripExpensesProvider(trip.id));
    final participantsAsync = ref.watch(
      tripLogisticsParticipantsProvider(trip.id),
    );
    final settlementsAsync = ref.watch(tripSettlementsProvider(trip.id));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context).animate().fadeIn().slideY(begin: -0.2),
            Expanded(
              child: expensesAsync.when(
                data: (expenses) => participantsAsync.when(
                  data: (participants) {
                    final settlementsRec = settlementsAsync.value ?? [];
                    final subGroupsAsync = ref.watch(
                      tripSubGroupsProvider(trip.id),
                    );
                    final subGroups = subGroupsAsync.valueOrNull ?? [];

                    final balances = BalanceCalculator.calculateBalances(
                      expenses: expenses,
                      settlements: settlementsRec,
                      participants: participants,
                      subGroups: subGroups,
                    );

                    final Map<String, String> userNames = {
                      for (var p in participants)
                        p.id: p.displayName ?? 'Unknown',
                    };

                    final optimalSettlements =
                        BalanceCalculator.calculateOptimalSettlements(
                          balances: balances,
                          userNames: userNames,
                        );

                    return _buildContent(
                      context,
                      ref,
                      optimalSettlements,
                      userNames,
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Iconsax.arrow_left),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text(
              'Settle Up',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, dynamic>> settlements,
    Map<String, String> userNames,
  ) {
    if (settlements.isEmpty) {
      return _buildAllSettled(context);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCard(
            context,
            settlements,
          ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),
          const SizedBox(height: 24),
          const Text(
            'Payments Needed',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 16),
          ...settlements.asMap().entries.map((entry) {
            final index = entry.key;
            final settlement = entry.value;
            return _buildSettlementCard(context, ref, settlement)
                .animate()
                .fadeIn(delay: Duration(milliseconds: 250 + (index * 100)))
                .slideX(begin: 0.1);
          }),
          const SizedBox(height: 24),
          _buildPaymentMethods(
            context,
          ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.1),
        ],
      ),
    );
  }

  Widget _buildAllSettled(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Iconsax.tick_circle,
              color: Colors.white,
              size: 48,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'All Settled! 🎉',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'No payments needed',
            style: TextStyle(fontSize: 16, color: AppColors.textMuted),
          ),
        ],
      ),
    ).animate().fadeIn().scale();
  }

  Widget _buildSummaryCard(
    BuildContext context,
    List<Map<String, dynamic>> settlements,
  ) {
    Decimal totalToSettle = Decimal.zero;
    for (final s in settlements) {
      totalToSettle = totalToSettle + (s['amount'] as Decimal);
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Iconsax.wallet_2, color: Colors.white, size: 48),
          const SizedBox(height: 16),
          Text(
            '${totalToSettle.toStringAsFixed(3)} OMR',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${settlements.length} payment${settlements.length > 1 ? 's' : ''} to settle',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettlementCard(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> settlement,
  ) {
    final fromName = settlement['fromUserName'] as String;
    final toName = settlement['toUserName'] as String;
    final amount = (settlement['amount'] as Decimal);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildAvatar(fromName, AppColors.error),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            fromName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(
                          Iconsax.arrow_right_1,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        Expanded(
                          child: Text(
                            toName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${amount.toStringAsFixed(3)} OMR',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildAvatar(toName, AppColors.success),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _confirmPayment(context, ref, settlement),
              icon: const Icon(Iconsax.tick_circle, size: 18),
              label: const Text('Mark as Paid'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPayment(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> settlement,
  ) async {
    final fromName = settlement['fromUserName'];
    final toName = settlement['toUserName'];
    final amount = (settlement['amount'] as Decimal).toStringAsFixed(3);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Payment'),
        content: Text(
          'Mark that $fromName paid $amount OMR to $toName?\n\nThis will record a settlement and update balances.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        final result = await ref
            .read(settlementServiceProvider)
            .addSettlement(
              tripId: trip.id,
              payerId: settlement['fromUserId'],
              recipientId: settlement['toUserId'],
              amount: settlement['amount'],
            );

        if (result != null && context.mounted) {
          // Invalidate providers to refresh UI
          ref.invalidate(tripSettlementsProvider(trip.id));
          ref.invalidate(tripBalancesProvider(trip.id));

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment recorded successfully!'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error recording payment: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Widget _buildAvatar(String name, Color color) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethods(BuildContext context) {
    final methods = [
      {'name': 'STC Pay', 'icon': Iconsax.mobile},
      {'name': 'Bank Transfer', 'icon': Iconsax.bank},
      {'name': 'Cash', 'icon': Iconsax.money},
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Iconsax.wallet_1, size: 20, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Payment Methods',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: methods.map((m) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      m['icon'] as IconData,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      m['name'] as String,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
