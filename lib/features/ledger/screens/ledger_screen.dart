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
import '../../events/models/event_model.dart';
import '../../groups/models/group_model.dart';
import '../../trip/models/trip_model.dart';
import '../../logistics/models/sub_group_model.dart';
import '../../logistics/providers/sub_group_provider.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';
import '../models/transaction_model.dart';
import '../providers/expense_provider.dart';
import '../providers/ledger_provider.dart';
import '../widgets/member_balances_section.dart';
import '../widgets/spending_summary_section.dart';
import '../widgets/transaction_list.dart';
import 'add_expense_screen.dart';
import 'edit_expense_sheet.dart';
import '../keys/ledger_keys.dart';
import 'settle_up_screen.dart';

/// Ledger Screen - Event Settlement with dark header, debt tabs, and actions
class LedgerScreen extends ConsumerStatefulWidget {
  final Event event;
  final Group group;

  const LedgerScreen({super.key, required this.event, required this.group});

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  void _openSettleUp(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute(
        builder: (context) =>
            SettleUpScreen(event: widget.event, group: widget.group),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventRef = (groupId: widget.event.groupId, eventId: widget.event.id);

    // Watch raw streams for Balance Calculation using EventRef-based providers
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));

    // Watch Unified Ledger for Transaction List
    final ledgerAsync = ref.watch(eventUnifiedLedgerProvider(eventRef));

    // Derive participants from event data (no SQLite lookup needed)
    final participants = widget.event.participantIds.map((id) {
      return Participant(
        id: id,
        tripId: widget.event.id,
        role: ParticipantRole.member,
        joinedAt: widget.event.createdAt,
        displayName: widget.event.participantNames[id],
      );
    }).toList();

    // Sub-groups from Firestore
    final subGroupsAsync = ref.watch(eventSubGroupsProvider(eventRef));
    final subGroups = subGroupsAsync.valueOrNull ?? [];

    // Current participant: match device name to event participant
    final currentParticipantId = participants.isNotEmpty
        ? participants.first.id
        : null;

    return Scaffold(
      key: LedgerKeys.screen,
      backgroundColor: AppColors.background,
      body: expensesAsync.when(
        data: (expenses) => settlementsAsync.when(
          data: (settlements) {
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
            onRetry: () => ref.invalidate(eventSettlementsProvider(eventRef)),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => NetworkErrorWidget(
          onRetry: () => ref.invalidate(eventExpensesProvider(eventRef)),
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
          child: MemberBalancesSection(
            balances: balances,
            currentParticipantId: currentParticipantId,
            currency: widget.event.currency,
          ).animate().fadeIn(delay: 100.ms),
        ),
        // Spending summary toggle
        SliverToBoxAdapter(
          child: SpendingSummarySection(
            expenses: expenses,
            currency: widget.event.currency,
          ).animate().fadeIn(delay: 150.ms),
        ),
        // Transactions
        SliverToBoxAdapter(
          child: TransactionList(
            transactions: transactions,
            currentParticipantId: currentParticipantId,
            currency: widget.event.currency,
            onEditExpense: (expense) => _editExpense(context, expense),
            onAddExpense: () => _addExpense(context),
          ).animate().fadeIn(delay: 200.ms),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
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
      subtitle: widget.event.name.toUpperCase(),
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
                              AppFormatters.currencyConfig[widget.event.currency]?.decimals ?? 3,
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
                            widget.event.currency,
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

  void _editExpense(BuildContext context, Expense expense) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EditExpenseSheet(
        groupId: widget.event.groupId,
        eventId: widget.event.id,
        expense: expense,
      ),
    );
  }

  void _addExpense(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute(
        builder: (context) => AddExpenseScreen(
          groupId: widget.event.groupId,
          eventId: widget.event.id,
        ),
      ),
    );
  }
}
