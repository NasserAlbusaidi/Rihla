import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/error_widgets.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../logistics/models/sub_group_model.dart';
import '../../logistics/providers/sub_group_provider.dart';
import '../../trip/models/trip_model.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';
import '../models/transaction_model.dart';
import '../providers/expense_provider.dart';
import '../providers/ledger_provider.dart';
import '../../trip/providers/trip_provider.dart';
import 'add_expense_screen.dart';
import 'edit_expense_sheet.dart';
import 'settle_up_screen.dart';

/// Ledger Screen - Trip Settlement with dark header, debt tabs, and actions
class LedgerScreen extends ConsumerStatefulWidget {
  final Trip trip;

  const LedgerScreen({super.key, required this.trip});

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  bool _showByCategory = false;

  void _openSettleUp(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute(
        builder: (context) => SettleUpScreen(trip: widget.trip),
      ),
    );
  }

  IconData _getCategoryIcon(String? iconName) {
    switch (iconName) {
      case 'gas':
        return Iconsax.gas_station;
      case 'food':
        return Iconsax.coffee;
      case 'gear':
        return Iconsax.bag_2;
      case 'lodging':
        return Iconsax.building;
      case 'transport':
        return Iconsax.car;
      default:
        return Iconsax.receipt;
    }
  }

  /// Show a tooltip popup with member balance details
  void _showBalanceTooltip(BuildContext context, UserBalance balance) {
    final isPositive = balance.netBalance >= Decimal.zero;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: isPositive
                  ? AppColors.success.withValues(alpha: 0.15)
                  : AppColors.error.withValues(alpha: 0.15),
              child: Text(
                (balance.displayName ?? 'U')[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isPositive ? AppColors.success : AppColors.error,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              balance.displayName ?? 'Unknown',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildBalanceRow(
                    'Total Paid',
                    balance.totalPaid,
                    AppColors.primary,
                  ),
                  const SizedBox(height: 8),
                  _buildBalanceRow(
                    'Fair Share',
                    balance.totalOwed,
                    AppColors.textMuted,
                  ),
                  const Divider(height: 24),
                  _buildBalanceRow(
                    isPositive ? 'Is Owed' : 'Owes',
                    balance.netBalance.abs(),
                    isPositive ? AppColors.success : AppColors.error,
                    isBold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isPositive
                  ? 'Paid more than their share'
                  : 'Paid less than their share',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceRow(
    String label,
    Decimal amount,
    Color color, {
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          AppFormatters.formatCurrency(amount, widget.trip.currency),
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch raw streams for Balance Calculation
    final expensesAsync = ref.watch(tripExpensesProvider(widget.trip.id));
    final settlementsAsync = ref.watch(tripSettlementsProvider(widget.trip.id));
    
    // Watch Unified Ledger for Transaction List
    final ledgerAsync = ref.watch(tripUnifiedLedgerProvider(widget.trip.id));
    
    final participantsAsync = ref.watch(
      tripLogisticsParticipantsProvider(widget.trip.id),
    );
    final currentParticipant = ref.watch(
      currentParticipantProvider(widget.trip.id),
    );
    final currentParticipantId = currentParticipant?.id;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: expensesAsync.when(
        data: (expenses) => settlementsAsync.when(
          data: (settlements) => participantsAsync.when(
            data: (participants) {
              final subGroupsAsync = ref.watch(
                tripSubGroupsProvider(widget.trip.id),
              );
              final subGroups = subGroupsAsync.valueOrNull ?? [];
              
              // Use unified ledger if available, else empty
              final transactions = ledgerAsync.valueOrNull ?? [];

              return _buildContent(
                context,
                expenses,
                settlements,
                transactions,
                participants,
                currentParticipantId,
                subGroups,
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => NetworkErrorWidget(
              onRetry: () => ref.invalidate(
                tripLogisticsParticipantsProvider(widget.trip.id),
              ),
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => NetworkErrorWidget(
            onRetry: () => ref.invalidate(tripSettlementsProvider(widget.trip.id)),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => NetworkErrorWidget(
          onRetry: () => ref.invalidate(tripExpensesProvider(widget.trip.id)),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<Expense> expenses,
    List<Settlement> settlements,
    List<Transaction> transactions,
    List<Participant> participants,
    String? currentParticipantId,
    List<SubGroup> subGroups,
  ) {
    final balances = BalanceCalculator.calculateBalances(
      expenses: expenses,
      settlements: settlements,
      participants: participants,
      subGroups: subGroups,
    );

    final myBalance = balances.firstWhere(
      (b) => b.participantId == currentParticipantId,
      orElse: () => UserBalance(
        participantId: currentParticipantId ?? '',
        displayName: 'You',
        totalPaid: Decimal.zero,
        totalOwed: Decimal.zero,
        netBalance: Decimal.zero,
      ),
    );

    final netBalance = myBalance.netBalance;
    final participantCount = participants.length > 1 ? participants.length : 1;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _buildBalanceHeader(
            context,
            netBalance,
            participantCount,
          ).animate().fadeIn().slideY(begin: -0.2),
        ),
        const SliverToBoxAdapter(child: OfflineBanner()),
        // Member balances
        SliverToBoxAdapter(
          child: _buildMemberBalances(
            context,
            balances,
            currentParticipantId,
          ).animate().fadeIn(delay: 100.ms),
        ),
        // Spending summary toggle
        SliverToBoxAdapter(
          child: _buildSpendingSummary(
            context,
            expenses,
          ).animate().fadeIn(delay: 150.ms),
        ),
        // Transactions
        SliverToBoxAdapter(
          child: _buildTransactionList(
            context,
            transactions,
            currentParticipantId,
          ).animate().fadeIn(delay: 200.ms),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildMemberBalances(
    BuildContext context,
    List<UserBalance> balances,
    String? currentParticipantId,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'BALANCES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: AppColors.textMuted,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
            child: balances.isEmpty
                ? const Center(
                    child: Text(
                      'No participants yet',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: balances.length,
                    itemBuilder: (context, index) {
                      final balance = balances[index];
                      final isMe = balance.participantId == currentParticipantId;
                      final isPositive = balance.netBalance >= Decimal.zero;

                      return GestureDetector(
                        onTap: () {
                          HapticService.lightClick();
                          _showBalanceTooltip(context, balance);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 12),
                          child: Column(
                            children: [
                              Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: isMe
                                        ? AppColors.primary
                                        : (isPositive
                                                  ? AppColors.success
                                                  : AppColors.error)
                                              .withValues(alpha: 0.15),
                                    child: Text(
                                      (balance.displayName ?? 'U')[0].toUpperCase(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isMe
                                            ? Colors.white
                                            : (isPositive ? AppColors.success : AppColors.error),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: isPositive ? AppColors.success : AppColors.error,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                      child: Icon(
                                        isPositive ? Icons.add : Icons.remove,
                                        size: 8,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: 60,
                                child: Text(
                                  isMe ? 'You' : (balance.displayName ?? 'User'),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isMe ? FontWeight.w600 : FontWeight.normal,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpendingSummary(
    BuildContext context,
    List<Expense> expenses,
  ) {
    // Group expenses by category
    final Map<String, ({String name, String icon, Decimal total, int count})> categoryTotals = {};
    Decimal grandTotal = Decimal.zero;

    for (final e in expenses) {
      grandTotal = grandTotal + e.amount;
      final key = e.categoryName ?? 'Other';
      final existing = categoryTotals[key];
      if (existing != null) {
        categoryTotals[key] = (
          name: existing.name,
          icon: e.categoryIcon ?? 'other',
          total: existing.total + e.amount,
          count: existing.count + 1,
        );
      } else {
        categoryTotals[key] = (
          name: key,
          icon: e.categoryIcon ?? 'other',
          total: e.amount,
          count: 1,
        );
      }
    }

    final sortedCategories = categoryTotals.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SPENDING',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textMuted,
                  letterSpacing: 1.5,
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _showByCategory = !_showByCategory),
                child: Text(
                  _showByCategory ? 'Hide Categories' : 'By Category',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Total spending card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
              boxShadow: AppColors.cardShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Iconsax.wallet_3, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Spent',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppFormatters.formatCurrency(grandTotal, widget.trip.currency),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${expenses.length} expenses',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          // Category breakdown
          if (_showByCategory && sortedCategories.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
                boxShadow: AppColors.cardShadow,
              ),
              child: Column(
                children: sortedCategories.map((cat) {
                  final percentage = grandTotal > Decimal.zero
                      ? (cat.total / grandTotal).toDecimal(scaleOnInfinitePrecision: 4).toDouble() * 100
                      : 0.0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _getCategoryIcon(cat.icon),
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cat.name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: percentage / 100,
                                  backgroundColor: AppColors.surfaceLight,
                                  color: AppColors.primary,
                                  minHeight: 4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              AppFormatters.formatCurrency(cat.total, widget.trip.currency),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              '${percentage.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTransactionList(
    BuildContext context,
    List<Transaction> transactions,
    String? currentParticipantId,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const Text(
            'RECENT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: AppColors.textMuted,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          if (transactions.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(
                      Iconsax.wallet_3,
                      size: 32,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'No Expenses Yet',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add your first expense to start tracking\ncosts and splitting them with your group.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      HapticService.medium();
                      _addExpense(context);
                    },
                    icon: const Icon(Iconsax.add, size: 18),
                    label: const Text('Add Expense'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ...transactions
                .take(15)
                .toList()
                .asMap()
                .entries
                .map(
                  (entry) =>
                      _buildTransactionCard(context, entry.value, currentParticipantId)
                          .animate()
                          .fadeIn(delay: Duration(milliseconds: (50 * entry.key).clamp(0, 500)), duration: 300.ms)
                          .slideY(begin: 0.05, end: 0, delay: Duration(milliseconds: (50 * entry.key).clamp(0, 500))),
                ),
        ],
      ),
    );
  }

  Widget _buildBalanceHeader(
    BuildContext context,
    Decimal netBalance,
    int participantCount,
  ) {
    final isPositive = netBalance >= Decimal.zero;
    final absBalance = netBalance.abs();

    return ModuleHeader(
      title: 'Ledger',
      subtitle: widget.trip.name.toUpperCase(),
      useDarkTheme: true,
      actions: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(AppColors.radiusSmall + 2),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: IconButton(
            icon: const Icon(
              Iconsax.money_send,
              color: AppColors.primary,
              size: 20,
            ),
            onPressed: () => _openSettleUp(context),
          ),
        ),
      ],
      bottom: Column(
        children: [
          // Balance summary
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            isPositive ? '+' : '-',
                            style: TextStyle(
                              color: isPositive ? AppColors.primary : AppColors.error,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            absBalance.toStringAsFixed(
                              AppFormatters.currencyConfig[widget.trip.currency]?.decimals ?? 3,
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.trip.currency,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isPositive ? 'You are owed' : 'You owe others',
                        style: TextStyle(
                          color: isPositive
                              ? AppColors.primary.withValues(alpha: 0.8)
                              : AppColors.error.withValues(alpha: 0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: _buildHeaderAction(
                  'ADD EXPENSE',
                  Iconsax.add,
                  AppColors.primary,
                  () => _addExpense(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildHeaderAction(
                  'SETTLE UP',
                  Iconsax.money_send,
                  AppColors.emerald,
                  () => _openSettleUp(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderAction(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    final isPrimary = color == AppColors.primary;
    return GestureDetector(
      onTap: () {
        HapticService.medium();
        onTap();
      },
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
          border: isPrimary
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildTransactionCard(
    BuildContext context,
    Transaction transaction,
    String? currentParticipantId,
  ) {
    final isExpense = transaction.type == TransactionType.expense;
    final isSettlement = transaction.type == TransactionType.settlement;
    
    // For settlements: payer is "from", recipient is "to"
    // For expenses: payer is "paid by"
    final isPayer = transaction.payerId == currentParticipantId;
    
    Color iconColor;
    IconData iconData;
    String title;
    String subtitle;
    
    if (isSettlement) {
      iconColor = AppColors.success;
      iconData = Iconsax.money_send;
      title = 'Payment to ${transaction.settlement?.recipientName ?? "Member"}';
      subtitle = isPayer 
        ? 'You paid' 
        : 'Paid by ${transaction.settlement?.payerName ?? "Member"}';
    } else {
      // Expense
      iconColor = AppColors.primary;
      iconData = _getCategoryIcon(transaction.expense?.categoryIcon);
      title = transaction.expense?.description ?? transaction.expense?.categoryName ?? 'Expense';
      subtitle = isPayer
          ? 'You paid full'
          : 'Paid by ${transaction.expense?.payerName ?? 'Member'}';
    }

    return GestureDetector(
      onTap: isExpense && transaction.expense != null
          ? () {
              HapticService.lightClick();
              _editExpense(context, transaction.expense!);
            }
          : null, // Settlements aren't editable here yet
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSettlement 
              ? AppColors.success.withValues(alpha: 0.3) 
              : AppColors.borderLight, 
            width: isSettlement ? 1.5 : 1.5
          ),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: isExpense && (transaction.expense?.receiptUrl != null || transaction.expense?.receiptPath != null)
                  ? Stack(
                      children: [
                        Icon(
                          iconData,
                          size: 24,
                          color: iconColor,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: AppColors.mint,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: const Icon(Iconsax.camera, size: 9, color: Colors.white),
                          ),
                        ),
                      ],
                    )
                  : Icon(
                      iconData,
                      size: 24,
                      color: iconColor,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              AppFormatters.formatCurrency(transaction.amount, widget.trip.currency),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: isSettlement ? AppColors.success : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _editExpense(BuildContext context, Expense expense) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          EditExpenseSheet(tripId: widget.trip.id, expense: expense),
    );
  }

  void _addExpense(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute(
        builder: (context) => AddExpenseScreen(tripId: widget.trip.id),
      ),
    );
  }
}
