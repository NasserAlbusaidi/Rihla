import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../shared/animations/fade_in_list.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../events/providers/event_provider.dart';
import '../../trip/models/trip_model.dart';
import '../keys/ledger_keys.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';
import '../providers/expense_provider.dart';
import '../widgets/expense_card.dart';
import '../widgets/ledger_hero_card.dart';
import '../widgets/settlement_row.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/gradient_tokens.dart';

/// Sealed type for a merged timeline item (expense or settlement).
sealed class _TimelineItem {
  DateTime get date;
}

final class _ExpenseItem extends _TimelineItem {
  final Expense expense;
  _ExpenseItem(this.expense);

  @override
  DateTime get date => expense.createdAt;
}

final class _SettlementItem extends _TimelineItem {
  final Settlement settlement;
  _SettlementItem(this.settlement);

  @override
  DateTime get date => settlement.settledAt;
}

/// Ledger Screen — single-scroll layout with hero card and timeline.
///
/// Implements the unified module template per D-04, D-08:
/// - Dark ModuleHeader with event name
/// - LedgerHeroCard with YOUR BALANCE, EVENT TOTAL, Add Expense, Settle Up
/// - TRANSACTIONS overline
/// - FadeInList of ExpenseCard / SettlementRow items (sorted by date desc)
///
/// Removes all tabs (AppTabBar/TabBarView), MemberBalancesSection,
/// SpendingSummarySection, TransactionList, and CircularProgressIndicator.
class LedgerScreen extends ConsumerWidget {
  final String groupId;
  final String eventId;

  const LedgerScreen({super.key, required this.groupId, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventRef = (groupId: groupId, eventId: eventId);
    final eventAsync = ref.watch(eventDetailProvider(eventRef));

    // Loading: show skeleton while event loads
    if (eventAsync.isLoading) {
      return Scaffold(
        key: LedgerKeys.screen,
        backgroundColor: context.colors.scaffoldBackground,
        body: Column(
          children: [
            const ModuleHeader(title: 'Ledger', useDarkTheme: true),
            Expanded(child: SkeletonLoader.expenseList()),
          ],
        ),
      );
    }

    final event = eventAsync.valueOrNull;

    // Not-found state per D-11
    if (event == null) {
      return Scaffold(
        key: LedgerKeys.screen,
        backgroundColor: context.colors.scaffoldBackground,
        body: Column(
          children: [
            const ModuleHeader(title: 'Not Found', useDarkTheme: true),
            Expanded(
              child: EmptyStateView(
                icon: Iconsax.warning_2,
                title: 'This event no longer exists',
                message:
                    'It may have been deleted. Tap below to go back to your groups.',
                actionLabel: 'Go Home',
                onAction: () => context.go('/home'),
                iconColor: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));

    // Derive participants from event data
    final participants = event.participantIds.map((id) {
      return Participant(
        id: id,
        tripId: event.id,
        role: ParticipantRole.member,
        joinedAt: event.createdAt,
        displayName: event.participantNames[id],
      );
    }).toList();

    // Use the first participant as current user (matches existing behaviour)
    final currentParticipantId = participants.isNotEmpty
        ? participants.first.id
        : null;

    // --- Loading state for expenses/settlements ---
    if (expensesAsync.isLoading || settlementsAsync.isLoading) {
      if (!expensesAsync.hasValue || !settlementsAsync.hasValue) {
        return Scaffold(
          key: LedgerKeys.screen,
          backgroundColor: context.colors.scaffoldBackground,
          body: Column(
            children: [
              ModuleHeader(
                title: 'Ledger',
                subtitle: event.name.toUpperCase(),
                useDarkTheme: true,
              ),
              Expanded(child: SkeletonLoader.expenseList()),
            ],
          ),
        );
      }
    }

    // --- Error state ---
    if (expensesAsync.hasError || settlementsAsync.hasError) {
      return Scaffold(
        key: LedgerKeys.screen,
        backgroundColor: context.colors.scaffoldBackground,
        body: Column(
          children: [
            ModuleHeader(
              title: 'Ledger',
              subtitle: event.name.toUpperCase(),
              useDarkTheme: true,
            ),
            Expanded(
              child: EmptyStateView(
                icon: Iconsax.warning_2,
                title: "Couldn't load Ledger",
                message: 'Check your connection and try again.',
                actionLabel: 'Reload',
                onAction: () {
                  ref.invalidate(eventExpensesProvider(eventRef));
                  ref.invalidate(eventSettlementsProvider(eventRef));
                },
                iconColor: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final rawExpenses = expensesAsync.valueOrNull ?? [];
    // Enrich expenses with payer display names from event participant data
    final expenses = rawExpenses.map((e) {
      final name = event.participantNames[e.payerParticipantId];
      return name != null ? e.copyWith(payerName: name) : e;
    }).toList();
    final settlements = settlementsAsync.valueOrNull ?? [];

    return Scaffold(
      key: LedgerKeys.screen,
      backgroundColor: context.colors.scaffoldBackground,
      body: _LedgerBody(
        groupId: groupId,
        eventId: eventId,
        event: event,
        expenses: expenses,
        settlements: settlements,
        participants: participants,
        currentParticipantId: currentParticipantId,
      ),
    );
  }
}

/// Inner body extracted for clarity.
class _LedgerBody extends StatelessWidget {
  final String groupId;
  final String eventId;
  final dynamic event;
  final List<Expense> expenses;
  final List<Settlement> settlements;
  final List<Participant> participants;
  final String? currentParticipantId;

  const _LedgerBody({
    required this.groupId,
    required this.eventId,
    required this.event,
    required this.expenses,
    required this.settlements,
    required this.participants,
    required this.currentParticipantId,
  });

  Decimal _computeNetBalance() {
    // BalanceCalculator: compute net balance for currentParticipantId from
    // expenses and settlements.
    final balances = BalanceCalculator.calculateBalances(
      expenses: expenses,
      settlements: settlements,
      participants: participants,
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

    return myBalance.netBalance;
  }

  Decimal _computeEventTotal() {
    return expenses.fold(Decimal.zero, (sum, e) => sum + e.amount);
  }

  /// Compute the current user's balance for a single expense.
  ///
  /// Positive = owed to user (user paid for others)
  /// Negative = user owes (user didn't pay but is in split)
  /// Zero = user not involved
  Decimal _expenseUserBalance(Expense expense) {
    final participantCount = participants.length;
    if (participantCount == 0) return Decimal.zero;

    final isPayer = expense.payerParticipantId == currentParticipantId;

    // Determine who is in the split
    final splitIds = expense.customSplitParticipants;
    final isInSplit = splitIds != null
        ? splitIds.contains(currentParticipantId)
        : true; // global = all participants

    final splitCount = splitIds != null ? splitIds.length : participantCount;
    if (splitCount == 0) return Decimal.zero;

    final share = (expense.amount / Decimal.fromInt(splitCount)).toDecimal(
      scaleOnInfinitePrecision: 3,
    );

    if (isPayer && isInSplit) {
      // Paid for everyone incl self: net = amount - own share
      return expense.amount - share;
    } else if (isPayer && !isInSplit) {
      // Paid but not in split (edge case): net = full amount owed back
      return expense.amount;
    } else if (!isPayer && isInSplit) {
      // Did not pay but owes a share
      return -share;
    } else {
      // Not involved at all
      return Decimal.zero;
    }
  }

  List<_TimelineItem> _buildTimeline() {
    final items = <_TimelineItem>[
      ...expenses.map(_ExpenseItem.new),
      ...settlements.map(_SettlementItem.new),
    ];
    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final netBalance = _computeNetBalance();
    final eventTotal = _computeEventTotal();
    final timeline = _buildTimeline();
    const currency = 'OMR';
    final isEmpty = expenses.isEmpty && settlements.isEmpty;

    return CustomScrollView(
      slivers: [
        // 1. Dark ModuleHeader
        SliverToBoxAdapter(
          child: ModuleHeader(
            title: 'Ledger',
            subtitle: event.name.toUpperCase(),
            useDarkTheme: true,
          ),
        ),

        // Offline banner
        const SliverToBoxAdapter(child: OfflineBanner()),

        // 2. LedgerHeroCard
        SliverToBoxAdapter(
          child: LedgerHeroCard(
            netBalance: netBalance,
            eventTotal: eventTotal,
            expenseCount: expenses.length,
            settlementCount: settlements.length,
            currency: currency,
            onAddExpense: () =>
                context.push('/group/$groupId/event/$eventId/ledger/add'),
            onSettleUp: () =>
                context.push('/group/$groupId/event/$eventId/ledger/settle-up'),
          ),
        ),

        // 3. TRANSACTIONS overline
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'TRANSACTIONS',
              key: LedgerKeys.spendingLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: context.colors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),

        // 4. Timeline or empty state
        SliverToBoxAdapter(
          child: isEmpty
              ? EmptyStateView(
                  icon: Iconsax.receipt_item,
                  title: 'No expenses yet',
                  message:
                      'Add your first expense to start tracking who paid what.',
                  actionLabel: 'Add Expense',
                  onAction: () =>
                      context.push('/group/$groupId/event/$eventId/ledger/add'),
                  accentGradient: context.gradient(AppGradients.terracotta),
                )
              : FadeInList(
                  children: timeline.map((item) {
                    return switch (item) {
                      _ExpenseItem(:final expense) => ExpenseCard(
                        key: LedgerKeys.expenseCard(expense.id),
                        expense: expense,
                        userBalance: _expenseUserBalance(expense),
                        currency: currency,
                        onTap: () => context.push(
                          '/group/$groupId/event/$eventId/ledger/edit/${expense.id}',
                        ),
                      ),
                      _SettlementItem(:final settlement) => SettlementRow(
                        key: Key('settlement_row_${settlement.id}'),
                        settlement: settlement,
                        currency: currency,
                      ),
                    };
                  }).toList(),
                ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}
