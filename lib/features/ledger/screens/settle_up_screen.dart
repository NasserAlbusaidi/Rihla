import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/error_widgets.dart';
import '../../../core/utils/formatters.dart';
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
                  error: (e, _) => NetworkErrorWidget(
                    onRetry: () => ref.invalidate(
                      tripLogisticsParticipantsProvider(trip.id),
                    ),
                  ),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => NetworkErrorWidget(
                  onRetry: () => ref.invalidate(tripExpensesProvider(trip.id)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Iconsax.arrow_left, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Text(
            'Settle Up',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
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

    // Calculate total pending
    Decimal totalPending = Decimal.zero;
    for (final s in pendingSettlements) {
      totalPending += (s['amount'] as Decimal);
    }

    // Build participant name map for settlements display
    final participantNames = <String, String>{
      for (var p in participants) p.id: p.displayName ?? 'Unknown',
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Minimal Summary Section
          _buildMinimalSummary(
            totalPending,
            myBalance,
          ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),

          const SizedBox(height: 24),

          // 2. Pending Settlements (Main Actionable Items)
          if (pendingSettlements.isNotEmpty) ...[
            const Text(
              'SUGGESTED SETTLEMENTS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
                letterSpacing: 1.0,
              ),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                children: pendingSettlements.asMap().entries.map((entry) {
                  final index = entry.key;
                  final settlement = entry.value;
                  final isLast = index == pendingSettlements.length - 1;
                  return _buildSettlementTile(
                    context,
                    ref,
                    settlement,
                    showDivider: !isLast,
                  );
                }).toList(),
              ),
            ).animate().fadeIn(delay: 250.ms),
          ] else if (recordedSettlements.isEmpty) ...[
            _buildAllSettled(context),
          ],

          const SizedBox(height: 24),

          // 3. History (Collapsible)
          if (recordedSettlements.isNotEmpty)
            _buildRecordedSettlements(
              context,
              recordedSettlements,
              participantNames,
            ).animate().fadeIn(delay: 300.ms),

          const SizedBox(height: 16),

          // 4. Recent Expenses (Collapsible)
          if (expenses.isNotEmpty)
            _buildRecentExpenses(
              context,
              expenses,
            ).animate().fadeIn(delay: 350.ms),

          // Add extra padding at bottom for safe scrolling
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildMinimalSummary(Decimal totalPending, UserBalance myBalance) {
    final isPositive = myBalance.netBalance >= Decimal.zero;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Total Pending',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${totalPending.toStringAsFixed(3)} OMR',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 1,
          height: 32,
          color: AppColors.border,
          margin: const EdgeInsets.symmetric(horizontal: 16),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isPositive ? 'You are owed' : 'You owe',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${myBalance.netBalance.abs().toStringAsFixed(3)} OMR',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isPositive ? AppColors.success : AppColors.error,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettlementTile(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> settlement, {
    bool showDivider = true,
  }) {
    final fromName = settlement['fromUserName'] as String;
    final toName = settlement['toUserName'] as String;
    final amount = (settlement['amount'] as Decimal);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Avatar Circle
              _buildSmallAvatar(fromName),
              const SizedBox(width: 8),

              const Icon(
                Iconsax.arrow_right_1,
                size: 16,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 8),

              // Recipient Avatar
              _buildSmallAvatar(toName),

              const SizedBox(width: 12),

              // Text Description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                        ),
                        children: [
                          TextSpan(
                            text: fromName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const TextSpan(text: ' owes '),
                          TextSpan(
                            text: toName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${amount.toStringAsFixed(3)} OMR',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),

              // Settle Button
              TextButton(
                onPressed: () => _confirmPayment(context, ref, settlement),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  foregroundColor: AppColors.primary,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Settle',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: AppColors.border),
      ],
    );
  }

  /// Recorded settlements section - Collapsible History
  Widget _buildRecordedSettlements(
    BuildContext context,
    List<Settlement> settlements,
    Map<String, String> participantNames,
  ) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: const Text(
          'RECORDED HISTORY',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
            letterSpacing: 1.0,
          ),
        ),
        trailing: const Icon(
          Iconsax.arrow_down_1,
          size: 16,
          color: AppColors.textMuted,
        ),
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              children: settlements.asMap().entries.map((entry) {
                final index = entry.key;
                final s = entry.value;
                final isLast = index == settlements.length - 1;
                return _buildHistoryItem(s, participantNames, !isLast);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(
    Settlement settlement,
    Map<String, String> participantNames,
    bool showDivider,
  ) {
    final payerName =
        participantNames[settlement.payerParticipantId] ?? 'Unknown';
    final recipientName =
        participantNames[settlement.recipientParticipantId] ?? 'Unknown';
    final amountStr = settlement.amount.toStringAsFixed(2);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(
                Iconsax.tick_circle,
                size: 18,
                color: AppColors.success,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                    children: [
                      TextSpan(
                        text: payerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const TextSpan(text: ' paid '),
                      TextSpan(
                        text: recipientName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$amountStr OMR',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                  Text(
                    AppFormatters.formatRelativeDate(settlement.settledAt),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: AppColors.border),
      ],
    );
  }

  /// Recent expenses - Collapsible
  Widget _buildRecentExpenses(BuildContext context, List<Expense> expenses) {
    final recentExpenses = expenses.take(5).toList();

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: const Text(
          'RECENT EXPENSES',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
            letterSpacing: 1.0,
          ),
        ),
        trailing: const Icon(
          Iconsax.arrow_down_1,
          size: 16,
          color: AppColors.textMuted,
        ),
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              children: recentExpenses.asMap().entries.map((entry) {
                final index = entry.key;
                final expense = entry.value;
                final isLast = index == recentExpenses.length - 1;
                return _buildExpenseItem(expense, !isLast);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseItem(Expense expense, bool showDivider) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    expense.categoryIcon ?? '💰',
                    style: const TextStyle(fontSize: 16),
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
                      expense.categoryName ?? 'General',
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
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: AppColors.border),
      ],
    );
  }

  Widget _buildAllSettled(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Iconsax.tick_circle,
              color: AppColors.success,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'All Settled! 🎉',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const Text(
            'No payments needed',
            style: TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
        ],
      ),
    ).animate().fadeIn().scale();
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
        content: Text('Mark that $fromName paid $amount OMR to $toName?'),
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

  Widget _buildSmallAvatar(String name) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.background,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
