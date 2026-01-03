import 'dart:math';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../activity/services/activity_service.dart';
import '../../activity/widgets/timeline_card.dart';
import '../../logistics/models/sub_group_model.dart';
import '../../logistics/providers/sub_group_provider.dart';
import '../../trip/models/trip_model.dart';
import '../models/expense_model.dart';
import '../providers/expense_provider.dart';
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
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {}); // Rebuild when tab changes
      }
    });
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
          '${amount.toStringAsFixed(3)} OMR',
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
    final expensesAsync = ref.watch(tripExpensesProvider(widget.trip.id));
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
        data: (expenses) => participantsAsync.when(
          data: (participants) {
            final subGroupsAsync = ref.watch(
              tripSubGroupsProvider(widget.trip.id),
            );
            final subGroups = subGroupsAsync.valueOrNull ?? [];
            return _buildContent(
              context,
              expenses,
              participants,
              currentParticipantId,
              subGroups,
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<Expense> expenses,
    List<Participant> participants,
    String? currentParticipantId,
    List<SubGroup> subGroups,
  ) {
    final settlements =
        ref.watch(tripSettlementsProvider(widget.trip.id)).value ?? [];

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
        SliverToBoxAdapter(
          child: _buildRecentActivity(context).animate().fadeIn(delay: 150.ms),
        ),
        SliverToBoxAdapter(
          child: _buildDebtTabs(context).animate().fadeIn(delay: 200.ms),
        ),
        SliverToBoxAdapter(
          child: _buildTabContent(
            context,
            expenses,
            balances,
            currentParticipantId,
            netBalance,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  /// Collapsible Recent Activity section showing transaction timeline
  Widget _buildRecentActivity(BuildContext context) {
    final activityAsync = ref.watch(tripActivityProvider(widget.trip.id));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              Iconsax.clock,
              size: 18,
              color: AppColors.primary,
            ),
          ),
          title: const Text(
            'Recent Activity',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: Text(
            'Transaction timeline & audit trail',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          children: [
            activityAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Error loading activity: $e'),
              ),
              data: (logs) {
                if (logs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(Iconsax.clock, size: 32, color: Colors.grey[300]),
                        const SizedBox(height: 8),
                        Text(
                          'No activity yet',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  );
                }

                // Show last 5 activities
                final recentLogs = logs.take(5).toList();
                return Column(
                  children: recentLogs.asMap().entries.map((entry) {
                    final index = entry.key;
                    final log = entry.value;
                    return TimelineCard(
                      log: log,
                      isLast: index == recentLogs.length - 1,
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
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
    final progressPercent = min(
      100,
      (absBalance.toDouble() / 100 * 100).round(),
    );

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A2A3A), Color(0xFF0D1B2A)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Iconsax.arrow_left, color: Colors.white),
                    onPressed: () => context.pop(),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Trip Settlement',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _openSettleUp(context),
                    icon: const Icon(Iconsax.money_send, size: 18),
                    label: const Text('SETTLE UP'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NET BALANCE',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isPositive ? '+' : '-',
                              style: TextStyle(
                                color: isPositive
                                    ? AppColors.primary
                                    : AppColors.error,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'OMR ${absBalance.toStringAsFixed(3)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isPositive
                              ? 'You are owed by others'
                              : 'You owe others',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: Stack(
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CircularProgressIndicator(
                            value: progressPercent / 100,
                            strokeWidth: 6,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.2,
                            ),
                            valueColor: AlwaysStoppedAnimation(
                              isPositive
                                  ? AppColors.primary
                                  : AppColors.warning,
                            ),
                          ),
                        ),
                        Center(
                          child: Text(
                            '$progressPercent%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Iconsax.scan_barcode,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'My QR Code',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _addExpense(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Iconsax.add, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Add Expense',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDebtTabs(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: _tabs.asMap().entries.map((entry) {
            final index = entry.key;
            final tab = entry.value;
            final isSelected = _tabController.index == index;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _tabController.index = index),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.textPrimary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    tab,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTabContent(
    BuildContext context,
    List<Expense> expenses,
    List<UserBalance> balances,
    String? currentParticipantId,
    Decimal netBalance,
  ) {
    final isPositive = netBalance >= Decimal.zero;
    final settlements =
        ref.watch(tripSettlementsProvider(widget.trip.id)).value ?? [];

    // Filter balances based on selected tab
    List<UserBalance> filteredBalances;
    String tabTitle;
    switch (_tabController.index) {
      case 0: // All Debts - show everyone
        filteredBalances = balances;
        tabTitle = 'All Team Balances';
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
        tabTitle = 'Settled Up (${settlements.length} payments)';
        break;
      default:
        filteredBalances = balances;
        tabTitle = 'Team Balances';
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isPositive
                  ? AppColors.success.withValues(alpha: 0.1)
                  : AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isPositive
                    ? AppColors.success.withValues(alpha: 0.3)
                    : AppColors.error.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: isPositive
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.error.withValues(alpha: 0.15),
                  child: Icon(
                    isPositive ? Iconsax.arrow_up : Iconsax.arrow_down,
                    color: isPositive ? AppColors.success : AppColors.error,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPositive ? 'Others owe you' : 'You owe others',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        isPositive
                            ? 'You paid more than your share'
                            : 'You paid less than your share',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${netBalance.abs().toStringAsFixed(3)} OMR',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isPositive ? AppColors.success : AppColors.error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Team Balances with tappable avatars
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
                'Recent Expenses',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () => _openSettleUp(context),
                child: const Text('Settle Up'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (expenses.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  'No expenses yet',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            )
          else
            ...expenses
                .take(5)
                .map(
                  (expense) =>
                      _buildExpenseCard(context, expense, currentParticipantId),
                ),
        ],
      ),
    );
  }

  Widget _buildExpenseCard(
    BuildContext context,
    Expense expense,
    String? currentParticipantId,
  ) {
    final isPayer = expense.payerParticipantId == currentParticipantId;
    return GestureDetector(
      onTap: () => _editExpense(context, expense),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          children: [
            // Category icon or receipt thumbnail
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: expense.receiptUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        children: [
                          Image.network(
                            expense.receiptUrl!,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              _getCategoryIcon(expense.categoryIcon),
                              size: 20,
                              color: AppColors.primary,
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: AppColors.mint,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(
                                Iconsax.receipt_1,
                                size: 8,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Icon(
                      _getCategoryIcon(expense.categoryIcon),
                      size: 20,
                      color: AppColors.primary,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          expense.description ??
                              expense.categoryName ??
                              'Expense',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Scope indicator
                      if (expense.scope != ExpenseScope.global)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: expense.scope == ExpenseScope.subGroup
                                ? AppColors.primary.withValues(alpha: 0.1)
                                : expense.scope == ExpenseScope.custom
                                ? AppColors.mint.withValues(alpha: 0.1)
                                : AppColors.textMuted.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            expense.scope == ExpenseScope.subGroup
                                ? 'Car'
                                : expense.scope == ExpenseScope.custom
                                ? 'Custom'
                                : 'Personal',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: expense.scope == ExpenseScope.subGroup
                                  ? AppColors.primary
                                  : expense.scope == ExpenseScope.custom
                                  ? AppColors.mint
                                  : AppColors.textMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                  Text(
                    isPayer
                        ? 'You paid'
                        : 'Paid by ${expense.payerName ?? 'member'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  expense.amount.toStringAsFixed(3),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text(
                  'OMR',
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Icon(Iconsax.arrow_right_3, size: 16, color: AppColors.textMuted),
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
