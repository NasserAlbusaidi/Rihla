import 'dart:math';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/error_widgets.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_tab_bar.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../activity/services/activity_service.dart';
import '../../activity/widgets/timeline_card.dart';
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

class _LedgerScreenState extends ConsumerState<LedgerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabs = ['All Debts', 'My Debts', 'To Pay', 'Settled'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openSettleUp(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
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
    final participantCount = max(1, participants.length);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _buildBalanceHeader(
            context,
            netBalance,
            participantCount,
          ).animate().fadeIn().slideY(begin: -0.2),
        ),
        // Offline indicator
        const SliverToBoxAdapter(
          child: OfflineBanner(),
        ),
        // Combined Activity Section
        // We can either keep the Activity Log (audit trail) OR replace it with the Ledger List.
        // The user asked for "transaction logging", implying the Ledger List IS the log.
        // However, Activity Log has "creates/updates" which might be useful.
        // Let's keep the Activity Log for "Audit" but rename it, and use the Ledger for "Financial History".
        SliverToBoxAdapter(
          child: _buildRecentActivity(context).animate().fadeIn(delay: 150.ms),
        ),
        SliverToBoxAdapter(
          child: _buildDebtTabs(context).animate().fadeIn(delay: 200.ms),
        ),
        SliverToBoxAdapter(
          child: _buildTabContent(
            context,
            transactions,
            balances,
            currentParticipantId,
            netBalance,
            settlements.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  /// Collapsible Recent Activity section showing transaction timeline
  Widget _buildRecentActivity(BuildContext context) {
    final activityAsync = ref.watch(
      tripTransactionActivityProvider(widget.trip.id),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight, width: 1.5),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: false,
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Iconsax.activity,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              title: const Text(
                'Activity',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: -0.3,
                ),
              ),
              subtitle: Text(
                'Track changes & updates',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [
                activityAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Error: $e'),
                  data: (logs) {
                    if (logs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          'No recent activity',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: logs.take(5).toList().asMap().entries.map((
                        entry,
                      ) {
                        return TimelineCard(
                          log: entry.value,
                          isLast: entry.key == min(logs.length, 5) - 1,
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
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
          // Glass Balance Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CURRENT BALANCE',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            isPositive ? '+' : '-',
                            style: TextStyle(
                              color: isPositive
                                  ? AppColors.primary
                                  : AppColors.error,
                              fontSize: 32,
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
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.trip.currency,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isPositive
                            ? 'You are currently owed'
                            : 'You currently owe others',
                        style: TextStyle(
                          color: isPositive
                              ? AppColors.primary.withValues(alpha: 0.8)
                              : AppColors.error.withValues(alpha: 0.8),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

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
                  Iconsax.arrange_circle_2,
                  Colors.white.withValues(alpha: 0.1),
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
      onTap: onTap,
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

  Widget _buildDebtTabs(BuildContext context) {
    return AppTabBar(
      controller: _tabController,
      tabs: _tabs,
    );
  }

  Widget _buildTabContent(
    BuildContext context,
    List<Transaction> transactions,
    List<UserBalance> balances,
    String? currentParticipantId,
    Decimal netBalance,
    int settlementsCount,
  ) {
    final isPositive = netBalance >= Decimal.zero;

    // Filter balances based on selected tab
    List<UserBalance> filteredBalances;
    String tabTitle;
    switch (_tabController.index) {
      case 0: // All Debts - show everyone
        filteredBalances = balances;
        tabTitle = 'All Balances';
        break;
      case 1: // My Debts - only current user
        filteredBalances = balances
            .where((b) => b.participantId == currentParticipantId)
            .toList();
        tabTitle = 'My Balance';
        break;
      case 2: // To Pay - users with negative balance
        filteredBalances = balances
            .where((b) => b.netBalance < Decimal.zero)
            .toList();
        tabTitle = 'Members Who Owe';
        break;
      case 3: // Settled - show settled settlements count
        filteredBalances = balances
            .where((b) => b.netBalance == Decimal.zero)
            .toList();
        tabTitle = 'Settled Up ($settlementsCount payments)';
        break;
      default:
        filteredBalances = balances;
        tabTitle = 'All Balances';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Balance',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isPositive
                  ? AppColors.success.withValues(alpha: 0.05)
                  : AppColors.error.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isPositive
                    ? AppColors.success.withValues(alpha: 0.2)
                    : AppColors.error.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isPositive ? AppColors.success : AppColors.error,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (isPositive ? AppColors.success : AppColors.error)
                                .withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    isPositive ? Iconsax.arrow_up_1 : Iconsax.arrow_down_1,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPositive ? 'YOU ARE OWED' : 'YOU OWE',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 1.2,
                          color: isPositive
                              ? AppColors.success
                              : AppColors.error,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isPositive
                            ? 'Clean sheet, plus some.'
                            : 'Time to settle up, maybe?',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  AppFormatters.formatCurrency(netBalance.abs(), widget.trip.currency),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: isPositive ? AppColors.success : AppColors.error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Balances with tappable avatars
          Text(
            tabTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: filteredBalances.isEmpty ? 60 : 80,
            child: filteredBalances.isEmpty
                ? Center(
                    child: Text(
                      _tabController.index == 3
                          ? 'No settlements yet'
                          : 'No one in this category',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: filteredBalances.length,
                    itemBuilder: (context, index) {
                      final balance = filteredBalances[index];
                      final isMe =
                          balance.participantId == currentParticipantId;
                      final isPositive = balance.netBalance >= Decimal.zero;

                      return GestureDetector(
                        onTap: () => _showBalanceTooltip(context, balance),
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
                                      (balance.displayName ?? 'U')[0]
                                          .toUpperCase(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isMe
                                            ? Colors.white
                                            : (isPositive
                                                  ? AppColors.success
                                                  : AppColors.error),
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
                                        color: isPositive
                                            ? AppColors.success
                                            : AppColors.error,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
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
                                  isMe
                                      ? 'You'
                                      : (balance.displayName ?? 'User'),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isMe
                                        ? FontWeight.w600
                                        : FontWeight.normal,
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
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Transactions History',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () => _openSettleUp(context),
                child: const Text('Settle Up'),
              ),
            ],
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
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => AddExpenseScreen(tripId: widget.trip.id),
                      ),
                    ),
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
                .take(10) // Show last 10 mixed transactions
                .map(
                  (transaction) =>
                      _buildTransactionCard(context, transaction, currentParticipantId),
                ),
        ],
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
          ? () => _editExpense(context, transaction.expense!)
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
      MaterialPageRoute(
        builder: (context) => AddExpenseScreen(tripId: widget.trip.id),
      ),
    );
  }
}
