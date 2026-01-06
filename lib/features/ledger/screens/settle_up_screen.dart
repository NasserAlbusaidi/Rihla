import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../logistics/providers/sub_group_provider.dart';
import '../../trip/models/trip_model.dart';
import '../../trip/providers/trip_provider.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';
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
                      balances,
                      expenses,
                      settlementsRec,
                      participants,
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
    List<Map<String, dynamic>> pendingSettlements,
    Map<String, String> userNames,
    List<UserBalance> balances,
    List<Expense> expenses,
    List<Settlement> recordedSettlements,
    List<Participant> participants,
  ) {
    if (pendingSettlements.isEmpty && recordedSettlements.isEmpty) {
      return _buildAllSettled(context);
    }

    // Get current user's balance
    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;
    final myBalance = balances.firstWhere(
      (b) {
        return participants.any(
          (p) => p.id == b.participantId && p.userId == currentUserId,
        );
      },
      orElse: () => balances.isNotEmpty
          ? balances.first
          : UserBalance(
              participantId: '',
              totalPaid: Decimal.zero,
              totalOwed: Decimal.zero,
              netBalance: Decimal.zero,
            ),
    );

    // Calculate total expenses and fair share
    Decimal totalExpenses = Decimal.zero;
    for (final e in expenses) {
      totalExpenses = totalExpenses + e.amount;
    }
    final fairShare = balances.isNotEmpty
        ? (totalExpenses / Decimal.fromInt(balances.length)).toDecimal()
        : Decimal.zero;

    // Build participant name map for settlements display
    final participantNames = <String, String>{
      for (var p in participants) p.id: p.displayName ?? 'Unknown',
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCard(
            context,
            pendingSettlements,
          ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),
          const SizedBox(height: 16),

          // Balance Breakdown Card
          _buildBalanceBreakdown(
            context,
            totalExpenses,
            fairShare,
            myBalance,
          ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.1),
          const SizedBox(height: 16),

          // Recorded Settlements Section (always visible)
          _buildRecordedSettlements(
            context,
            recordedSettlements,
            participantNames,
          ).animate().fadeIn(delay: 175.ms).slideY(begin: 0.1),
          const SizedBox(height: 16),

          // Recent Expenses Section
          _buildRecentExpenses(
            context,
            expenses,
          ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),
          const SizedBox(height: 24),

          const Text(
            'Payments Needed',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ).animate().fadeIn(delay: 250.ms),
          const SizedBox(height: 16),
          ...pendingSettlements.asMap().entries.map((entry) {
            final index = entry.key;
            final settlement = entry.value;
            return _buildSettlementCard(context, ref, settlement)
                .animate()
                .fadeIn(
                  delay: Duration(milliseconds: 300 + (index.toInt() * 100)),
                )
                .slideX(begin: 0.1);
          }),
        ],
      ),
    );
  }

  /// Balance breakdown showing Total Paid, Fair Share, Net Balance
  Widget _buildBalanceBreakdown(
    BuildContext context,
    Decimal totalExpenses,
    Decimal fairShare,
    UserBalance myBalance,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Iconsax.chart_2, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Your Balance Breakdown',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Total Expenses',
                  '${totalExpenses.toStringAsFixed(2)} OMR',
                  Iconsax.receipt_2,
                  AppColors.textSecondary,
                ),
              ),
              Container(width: 1, height: 40, color: AppColors.border),
              Expanded(
                child: _buildStatItem(
                  'Fair Share',
                  '${fairShare.toStringAsFixed(2)} OMR',
                  Iconsax.people,
                  AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'You Paid',
                  '${myBalance.totalPaid.toStringAsFixed(2)} OMR',
                  Iconsax.wallet_money,
                  AppColors.success,
                ),
              ),
              Container(width: 1, height: 40, color: AppColors.border),
              Expanded(
                child: _buildStatItem(
                  'Net Balance',
                  '${myBalance.netBalance.abs().toStringAsFixed(2)} OMR',
                  myBalance.netBalance >= Decimal.zero
                      ? Iconsax.arrow_down
                      : Iconsax.arrow_up,
                  myBalance.netBalance >= Decimal.zero
                      ? AppColors.success
                      : AppColors.error,
                  subtitle: myBalance.netBalance >= Decimal.zero
                      ? 'You are owed'
                      : 'You owe',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color, {
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: color.withValues(alpha: 0.8),
              ),
            ),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Recent expenses collapsible section
  Widget _buildRecentExpenses(BuildContext context, List<Expense> expenses) {
    final recentExpenses = expenses.take(5).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Iconsax.receipt_1,
              size: 18,
              color: AppColors.primary,
            ),
          ),
          title: const Text(
            'Recent Expenses',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: Text(
            '${expenses.length} total expenses',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          children: [
            if (recentExpenses.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No expenses yet',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              )
            else
              ...recentExpenses.map((expense) => _buildExpenseItem(expense)),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseItem(Expense expense) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                expense.categoryIcon ?? '💰',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.description ?? 'Expense',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  expense.categoryName ?? 'Expense',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${expense.amount.toStringAsFixed(2)} OMR',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  /// Recorded settlements section showing payments already logged
  Widget _buildRecordedSettlements(
    BuildContext context,
    List<Settlement> settlements,
    Map<String, String> participantNames,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: settlements.isNotEmpty,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Iconsax.tick_circle,
              size: 18,
              color: AppColors.success,
            ),
          ),
          title: const Text(
            'Recorded Payments',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: Text(
            settlements.isEmpty
                ? 'No payments recorded yet'
                : '${settlements.length} payment${settlements.length > 1 ? 's' : ''} recorded',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          children: [
            if (settlements.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No settlements recorded yet',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              )
            else
              ...settlements.map(
                (s) => _buildRecordedSettlementItem(s, participantNames),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordedSettlementItem(
    Settlement settlement,
    Map<String, String> participantNames,
  ) {
    final payerName =
        participantNames[settlement.payerParticipantId] ?? 'Unknown';
    final recipientName =
        participantNames[settlement.recipientParticipantId] ?? 'Unknown';
    final amountStr = settlement.amount.toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Icon(
                Iconsax.arrow_swap,
                size: 14,
                color: AppColors.success,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$payerName → $recipientName',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatDate(settlement.settledAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$amountStr OMR',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
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
}
