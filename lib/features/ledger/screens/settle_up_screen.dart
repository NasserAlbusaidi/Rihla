import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/error_widgets.dart';
import '../../../core/types/event_ref.dart';
import '../../../core/utils/formatters.dart';
import '../../events/models/event_model.dart';
import '../../groups/models/group_model.dart';
import '../../logistics/models/sub_group_model.dart';
import '../../logistics/providers/sub_group_provider.dart';
import '../../trip/models/trip_model.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';
import '../providers/expense_provider.dart';
import '../services/settlement_service.dart';

/// Settle Up Screen - Shows optimized settlements with payment actions
class SettleUpScreen extends ConsumerWidget {
  final Event event;
  final Group group;

  const SettleUpScreen({super.key, required this.event, required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventRef = (groupId: event.groupId, eventId: event.id);
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));
    final subGroupsAsync = ref.watch(eventSubGroupsProvider(eventRef));

    // Derive participants from event data (no SQLite needed)
    final participants = event.participantIds.map((id) {
      return Participant(
        id: id,
        tripId: event.id,
        role: ParticipantRole.member,
        joinedAt: event.createdAt,
        displayName: event.participantNames[id],
      );
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context).animate().fadeIn().slideY(begin: -0.2),
            Expanded(
              child: expensesAsync.when(
                data: (expenses) {
                  final settlementsRec = settlementsAsync.valueOrNull ?? [];
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
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => NetworkErrorWidget(
                  onRetry: () => ref.invalidate(eventExpensesProvider((groupId: event.groupId, eventId: event.id))),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderLight),
              boxShadow: AppColors.cardShadow,
            ),
            child: IconButton(
              icon: const Icon(Iconsax.arrow_left, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const Text(
            'Settle Up',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
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
    // Get current user's balance using Firebase UID
    String? currentUserId;
    try {
      currentUserId = FirebaseConfig.currentUser?.uid;
    } catch (_) {}
    final myBalance = balances.firstWhere(
      (b) => b.participantId == currentUserId,
      orElse: () => UserBalance(
              participantId: '',
              totalPaid: Decimal.zero,
              totalOwed: Decimal.zero,
              netBalance: Decimal.zero,
            ),
    );

    // Group settlements: "Action Required" (by me) vs "Waiting for Others"
    final myDebts = pendingSettlements
        .where((s) => s['fromUserId'] == myBalance.participantId)
        .toList();
    final debtToMe = pendingSettlements
        .where((s) => s['toUserId'] == myBalance.participantId)
        .toList();
    final others = pendingSettlements
        .where(
          (s) =>
              s['fromUserId'] != myBalance.participantId &&
              s['toUserId'] != myBalance.participantId,
        )
        .toList();

    // Calculate total pending
    Decimal totalPending = Decimal.zero;
    for (final s in pendingSettlements) {
      totalPending += (s['amount'] as Decimal);
    }

    final participantNames = <String, String>{
      for (var p in participants) p.id: p.displayName ?? 'Unknown',
    };

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Premium Bento-style Summary
          _buildPremiumSummary(context, totalPending, myBalance, myDebts: myDebts, ref: ref)
              .animate()
              .fadeIn(duration: 600.ms)
              .slideX(begin: -0.1, curve: Curves.easeOutCubic),

          const SizedBox(height: 32),

          // 2. Suggestions Sections
          if (pendingSettlements.isNotEmpty) ...[
            if (myDebts.isNotEmpty) ...[
              _buildSectionHeader('YOUR ACTIONS', Iconsax.wallet_3),
              const SizedBox(height: 12),
              _buildSettlementGroup(context, ref, myDebts, isUrgent: true),
              const SizedBox(height: 24),
            ],

            if (debtToMe.isNotEmpty) ...[
              _buildSectionHeader('WAITING FOR OTHERS', Iconsax.timer_1),
              const SizedBox(height: 12),
              _buildSettlementGroup(context, ref, debtToMe),
              const SizedBox(height: 24),
            ],

            if (others.isNotEmpty) ...[
              _buildSectionHeader('OTHERS SETTLING', Iconsax.people),
              const SizedBox(height: 12),
              _buildSettlementGroup(context, ref, others),
              const SizedBox(height: 24),
            ],
          ] else if (recordedSettlements.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: _buildAllSettled(context),
            ),
          ],

          // 3. History
          if (recordedSettlements.isNotEmpty)
            _buildRecordedSettlements(
              context,
              recordedSettlements,
              participantNames,
            ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 16),

          // 4. Recent Expenses
          if (expenses.isNotEmpty)
            _buildRecentExpenses(
              context,
              expenses,
            ).animate().fadeIn(delay: 300.ms),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildPremiumSummary(
    BuildContext context,
    Decimal totalPending,
    UserBalance myBalance, {
    List<Map<String, dynamic>> myDebts = const [],
    WidgetRef? ref,
  }) {
    final isPositive = myBalance.netBalance >= Decimal.zero;
    final accentColor = isPositive ? AppColors.success : AppColors.error;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: 0.15),
            AppColors.surface.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor.withValues(alpha: 0.2), width: 1),
        boxShadow: AppColors.cardShadowLarge,
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPositive ? 'YOU ARE OWED' : 'YOU OWE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        AppFormatters.formatCurrency(myBalance.netBalance.abs(), event.currency),
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPositive ? Iconsax.receipt_add : Iconsax.receipt_minus,
                  color: accentColor,
                  size: 28,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildSummaryMiniItem(
                'Trip Total Pending',
                AppFormatters.formatCurrency(totalPending, event.currency),
                Iconsax.status_up,
              ),
              const SizedBox(width: 32),
              _buildSummaryMiniItem(
                'Total Paid by You',
                AppFormatters.formatCurrency(myBalance.totalPaid, event.currency),
                Iconsax.wallet_check,
              ),
            ],
          ),
          if (!isPositive && myBalance.netBalance.abs() > Decimal.zero) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: myDebts.isNotEmpty && ref != null
                      ? () => _confirmPayment(context, ref, myDebts.first)
                      : null,
                  icon: const Icon(Iconsax.tick_circle, size: 18),
                  label: const Text('SETTLE UP'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.black,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryMiniItem(String label, String value, IconData icon) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: AppColors.textMuted,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildSettlementGroup(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, dynamic>> settlements, {
    bool isUrgent = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isUrgent
              ? AppColors.rose.withValues(alpha: 0.2)
              : AppColors.border.withValues(alpha: 0.5),
        ),
        boxShadow: isUrgent ? AppColors.cardShadow : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: settlements.asMap().entries.map((entry) {
          final index = entry.key;
          final settlement = entry.value;
          final isLast = index == settlements.length - 1;
          return _buildSettlementTile(
            context,
            ref,
            settlement,
            showDivider: !isLast,
            isUrgent: isUrgent,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSettlementTile(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> settlement, {
    bool showDivider = true,
    bool isUrgent = false,
  }) {
    final fromName = settlement['fromUserName'] as String;
    final toName = settlement['toUserName'] as String;
    final amount = (settlement['amount'] as Decimal);

    return InkWell(
      onTap: () => _confirmPayment(context, ref, settlement),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar Visual Stack
                SizedBox(
                  width: 52,
                  height: 32,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        child: _buildSmallAvatar(fromName, isPayer: true),
                      ),
                      Positioned(left: 20, child: _buildSmallAvatar(toName)),
                    ],
                  ),
                ),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const TextSpan(
                              text: ' → ',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text: toName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            AppFormatters.formatCurrency(amount, event.currency),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: isUrgent ? AppColors.rose : AppColors.mint,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (isUrgent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.rose.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'PAYMENT DUE',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.rose,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Settle Button
                const Icon(
                  Iconsax.arrow_right_3,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
          if (showDivider)
            Divider(
              height: 1,
              thickness: 1,
              color: AppColors.border.withValues(alpha: 0.5),
              indent: 16,
              endIndent: 16,
            ),
        ],
      ),
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
                    AppFormatters.formatCurrency(settlement.amount, event.currency),
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
                AppFormatters.formatCurrency(expense.amount, event.currency),
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

  Future<void> _recordSettlement(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> settlement,
  ) async {
    try {
      final eventRef = (groupId: event.groupId, eventId: event.id);
      final result = await ref
          .read(settlementServiceProvider)
          .addSettlement(
            groupId: event.groupId,
            eventId: event.id,
            payerParticipantId: settlement['fromUserId'] as String,
            recipientParticipantId: settlement['toUserId'] as String,
            amount: settlement['amount'] as Decimal,
            currency: event.currency,
          );

      if (result != null && context.mounted) {
        ref.invalidate(eventSettlementsProvider(eventRef));
        ref.invalidate(eventBalancesProvider((eventRef: eventRef, event: event)));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Iconsax.tick_circle, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Payment recorded!'),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error recording payment: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _confirmPayment(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> settlement,
  ) async {
    final fromName = settlement['fromUserName'] as String;
    final toName = settlement['toUserName'] as String;
    final amount = settlement['amount'] as Decimal;
    final amountFormatted = AppFormatters.formatCurrency(amount, event.currency);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Confirm Payment',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$fromName paid $amountFormatted to $toName',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Record this as settled? (via cash, bank transfer, or other method)',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textMuted.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),

            // Confirm button
            SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Iconsax.tick_circle, size: 20),
                  label: const Text('Mark as Paid'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.black,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Cancel
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!context.mounted || confirmed != true) return;

    _recordSettlement(context, ref, settlement);
  }

  Widget _buildSmallAvatar(String name, {bool isPayer = false}) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isPayer ? AppColors.surface : AppColors.surfaceLight,
        shape: BoxShape.circle,
        border: Border.all(
          color: isPayer ? AppColors.mint : AppColors.border,
          width: isPayer ? 2 : 1,
        ),
        boxShadow: AppColors.cardShadow,
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isPayer ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
