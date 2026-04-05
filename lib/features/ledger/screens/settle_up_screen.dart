import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/error_widgets.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../events/providers/event_provider.dart';
import '../../trip/models/trip_model.dart';
import '../../logistics/providers/sub_group_provider.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';
import '../providers/expense_provider.dart';
import '../widgets/recent_expenses_section.dart';
import '../widgets/recorded_settlements_section.dart';
import '../keys/ledger_keys.dart';
import '../widgets/settlement_summary_card.dart';
import '../widgets/settlement_tile.dart';
import '../../../core/theme/tokens/color_tokens.dart';

/// Settle Up Screen - Shows optimized settlements with payment actions.
///
/// GoRouter route at /group/:gid/event/:eid/ledger/settle-up per D-07.
/// Takes string IDs per D-14. Uses [eventDetailProvider] internally.
/// Shows a not-found error state per D-11 when event is null.
class SettleUpScreen extends ConsumerWidget {
  final String groupId;
  final String eventId;

  const SettleUpScreen({
    super.key,
    required this.groupId,
    required this.eventId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventRef = (groupId: groupId, eventId: eventId);

    final eventAsync = ref.watch(eventDetailProvider(eventRef));

    // Loading state
    if (eventAsync.isLoading) {
      return Scaffold(
        backgroundColor: AppColorTokens.light.scaffoldBackground,
        body: Column(
          children: [
            const ModuleHeader(title: 'Settle Up', useDarkTheme: true),
            Expanded(child: SkeletonLoader.expenseList()),
          ],
        ),
      );
    }

    final event = eventAsync.valueOrNull;

    // Not-found state per D-11
    if (event == null) {
      return Scaffold(
        backgroundColor: AppColorTokens.light.scaffoldBackground,
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
                iconColor: AppColorTokens.light.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

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
      key: LedgerKeys.settleUpScreen,
      backgroundColor: AppColorTokens.light.scaffoldBackground,
      body: Column(
        children: [
          ModuleHeader(
            title: 'Settle Up',
            subtitle: event.name.toUpperCase(),
            useDarkTheme: true,
          ),
          const OfflineBanner(),
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
                  event,
                  optimalSettlements,
                  userNames,
                  balances,
                  expenses,
                  settlementsRec,
                  participants,
                );
              },
              loading: () => SkeletonLoader.expenseList(),
              error: (e, _) => NetworkErrorWidget(
                onRetry: () => ref.invalidate(
                  eventExpensesProvider(
                      (groupId: groupId, eventId: eventId)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    event,
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
          SettlementSummaryCard(
            netBalance: myBalance.netBalance,
            totalPending: totalPending,
            myBalance: myBalance,
            currency: event.currency,
            myDebts: myDebts,
            onSettleUp: myDebts.isNotEmpty
                ? () => _confirmPayment(context, ref, event, myDebts.first)
                : null,
          )
              .animate()
              .fadeIn(duration: 600.ms)
              .slideX(begin: -0.1, curve: Curves.easeOutCubic),

          const SizedBox(height: 32),

          // 2. Suggestions Sections
          if (pendingSettlements.isNotEmpty) ...[
            if (myDebts.isNotEmpty) ...[
              _buildSectionHeader('YOUR ACTIONS', Iconsax.wallet_3),
              const SizedBox(height: 12),
              SettlementGroupCard(
                settlements: myDebts,
                currency: event.currency,
                isUrgent: true,
                onTap: (s) => _confirmPayment(context, ref, event, s),
              ),
              const SizedBox(height: 24),
            ],

            if (debtToMe.isNotEmpty) ...[
              _buildSectionHeader('WAITING FOR OTHERS', Iconsax.timer_1),
              const SizedBox(height: 12),
              SettlementGroupCard(
                settlements: debtToMe,
                currency: event.currency,
                onTap: (s) => _confirmPayment(context, ref, event, s),
              ),
              const SizedBox(height: 24),
            ],

            if (others.isNotEmpty) ...[
              _buildSectionHeader('OTHERS SETTLING', Iconsax.people),
              const SizedBox(height: 12),
              SettlementGroupCard(
                settlements: others,
                currency: event.currency,
                onTap: (s) => _confirmPayment(context, ref, event, s),
              ),
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
            RecordedSettlementsSection(
              settlements: recordedSettlements,
              participantNames: participantNames,
              currency: event.currency,
            ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 16),

          // 4. Recent Expenses
          if (expenses.isNotEmpty)
            RecentExpensesSection(
              expenses: expenses,
              currency: event.currency,
            ).animate().fadeIn(delay: 300.ms),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColorTokens.light.textSecondary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: AppColorTokens.light.textSecondary,
            letterSpacing: 1.2,
          ),
        ),
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
              color: AppColorTokens.light.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Iconsax.tick_circle,
              color: AppColorTokens.light.success,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'All Settled!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColorTokens.light.textPrimary,
            ),
          ),
          Text(
            'No payments needed',
            style: TextStyle(fontSize: 14, color: AppColorTokens.light.textMuted),
          ),
        ],
      ),
    ).animate().fadeIn().scale();
  }

  Future<void> _recordSettlement(
    BuildContext context,
    WidgetRef ref,
    event,
    Map<String, dynamic> settlement,
  ) async {
    HapticService.success(); // D-02: fire on tap before async write
    final eventRef = (groupId: groupId, eventId: eventId);
    try {
      await ref
          .read(settlementServiceProvider)
          .addSettlement(
            groupId: groupId,
            eventId: eventId,
            payerParticipantId: settlement['fromUserId'] as String,
            recipientParticipantId: settlement['toUserId'] as String,
            amount: settlement['amount'] as Decimal,
            currency: event.currency,
          );

      if (context.mounted) {
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
            backgroundColor: AppColorTokens.light.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error recording payment: $e'),
            backgroundColor: AppColorTokens.light.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _confirmPayment(
    BuildContext context,
    WidgetRef ref,
    event,
    Map<String, dynamic> settlement,
  ) async {
    final fromName = settlement['fromUserName'] as String;
    final toName = settlement['toUserName'] as String;
    final amount = settlement['amount'] as Decimal;
    final amountFormatted =
        AppFormatters.formatCurrency(amount, event.currency);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColorTokens.light.cardSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColorTokens.light.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Confirm Payment',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColorTokens.light.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$fromName paid $amountFormatted to $toName',
              style: TextStyle(
                fontSize: 14,
                color: AppColorTokens.light.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Record this as settled? (via cash, bank transfer, or other method)',
              style: TextStyle(
                fontSize: 13,
                color: AppColorTokens.light.textMuted.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),

            // Confirm button
            SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  gradient: AppColorTokens.light.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColorTokens.light.primary.withValues(alpha: 0.3),
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
                    padding:
                        const EdgeInsets.symmetric(vertical: 16),
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
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppColorTokens.light.textMuted,
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

    _recordSettlement(context, ref, event, settlement);
  }
}
