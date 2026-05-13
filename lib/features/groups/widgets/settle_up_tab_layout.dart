import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_tab_bar.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/models/settlement_model.dart';
import '../keys/group_keys.dart';
import '../models/group_model.dart';
import '../providers/group_balance_provider.dart';
import '../widgets/group_settlement_summary.dart';
import 'all_settled_state.dart';
import 'settle_up_history_tab.dart';
import 'settlement_tab_content.dart';

/// Tab layout for the Group Settle-Up screen.
///
/// Renders:
/// - [GroupSettlementSummaryCard] at the top
/// - [AppTabBar] with 4 tabs: You Owe / Owed to You / Between Others / History
/// - [TabBarView] whose children are [SettlementTabContent] × 3 + [SettleUpHistoryTab]
///
/// Handles the all-settled empty state (D-06) when no optimal settlements
/// and no history exist.
///
/// Extracted from [GroupSettleUpScreen._buildTabLayout] (Phase 36 Plan 01).
class SettleUpTabLayout extends StatelessWidget {
  final TabController controller;
  final Group group;
  final List<Map<String, dynamic>> optimalSettlements;
  final GroupBalances balancesData;
  final AsyncValue<List<Settlement>> settlementsAsync;
  final String? currentUid;
  final Map<int, GlobalKey> tileKeys;

  /// Callback used to show the record payment bottom sheet.
  final void Function({
    required Map<String, dynamic> settlement,
    required String fromName,
    required String toName,
    required String fromUserId,
    required String toUserId,
    required Decimal suggestedAmount,
  })
  onRecord;

  /// Builds the per-event breakdown for a settlement pair.
  final Map<String, Decimal> Function(String fromUserId, String toUserId)
  buildBreakdown;

  /// The pre-selected member ID, used for highlight logic.
  final String? preSelectedMemberId;

  const SettleUpTabLayout({
    super.key,
    required this.controller,
    required this.group,
    required this.optimalSettlements,
    required this.balancesData,
    required this.settlementsAsync,
    required this.currentUid,
    required this.tileKeys,
    required this.onRecord,
    required this.buildBreakdown,
    this.preSelectedMemberId,
  });

  @override
  Widget build(BuildContext context) {
    // Split settlements into tab buckets
    final youOwe = optimalSettlements
        .where((s) => s['fromUserId'] == currentUid)
        .toList();
    final owedToYou = optimalSettlements
        .where((s) => s['toUserId'] == currentUid)
        .toList();
    final betweenOthers = optimalSettlements
        .where(
          (s) => s['fromUserId'] != currentUid && s['toUserId'] != currentUid,
        )
        .toList();

    Decimal totalPending = Decimal.zero;
    for (final s in optimalSettlements) {
      totalPending += (s['amount'] as Decimal);
    }

    // D-06: all-settled state when all tabs empty and history empty
    final historyIsEmpty = settlementsAsync.valueOrNull?.isEmpty ?? true;
    if (optimalSettlements.isEmpty && historyIsEmpty) {
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettlementIntro(transferCount: 0, groupName: group.name),
            const SizedBox(height: 18),
            GroupSettlementSummaryCard(
              totalPending: Decimal.zero,
              currency: group.currency,
              eventCount: balancesData.eventCount,
              transferCount: 0,
            ),
            const SizedBox(height: 32),
            const AllSettledState(),
            const SizedBox(height: 24),
            _NetBalancesSection(
              balances: balancesData.balances,
              currency: group.currency,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettlementIntro(
                transferCount: optimalSettlements.length,
                groupName: group.name,
              ),
              const SizedBox(height: 18),
              GroupSettlementSummaryCard(
                totalPending: totalPending,
                currency: group.currency,
                eventCount: balancesData.eventCount,
                transferCount: optimalSettlements.length,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        AppTabBar(
          key: GroupKeys.settleUpTabBar,
          controller: controller,
          tabs: const ['You Owe', 'Owed to You', 'Between Others', 'History'],
        ),
        Expanded(
          child: TabBarView(
            controller: controller,
            children: [
              // Tab 0: You Owe
              SettlementTabContent(
                settlements: youOwe,
                isYourAction: true,
                isCreditor: false,
                emptyIcon: Iconsax.wallet_check,
                emptyTitle: 'Nothing to pay',
                emptyMessage: "You don't owe anyone in this group right now.",
                currency: group.currency,
                tileKeys: tileKeys,
                preSelectedMemberId: preSelectedMemberId,
                onRecord: onRecord,
                buildBreakdown: buildBreakdown,
                footer: _NetBalancesSection(
                  balances: balancesData.balances,
                  currency: group.currency,
                ),
              ),
              // Tab 1: Owed to You
              SettlementTabContent(
                settlements: owedToYou,
                isYourAction: false,
                isCreditor: true,
                emptyIcon: Iconsax.money_recive,
                emptyTitle: 'Nothing owed to you',
                emptyMessage: 'No one owes you in this group right now.',
                currency: group.currency,
                tileKeys: tileKeys,
                preSelectedMemberId: preSelectedMemberId,
                onRecord: onRecord,
                buildBreakdown: buildBreakdown,
                footer: _NetBalancesSection(
                  balances: balancesData.balances,
                  currency: group.currency,
                ),
              ),
              // Tab 2: Between Others
              SettlementTabContent(
                settlements: betweenOthers,
                isYourAction: false,
                isCreditor: false,
                emptyIcon: Iconsax.people,
                emptyTitle: 'All balanced',
                emptyMessage: 'No outstanding amounts between other members.',
                currency: group.currency,
                tileKeys: tileKeys,
                preSelectedMemberId: preSelectedMemberId,
                onRecord: onRecord,
                buildBreakdown: buildBreakdown,
                footer: _NetBalancesSection(
                  balances: balancesData.balances,
                  currency: group.currency,
                ),
              ),
              // Tab 3: History
              SettleUpHistoryTab(
                settlementsAsync: settlementsAsync,
                currency: group.currency,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettlementIntro extends StatelessWidget {
  const _SettlementIntro({
    required this.transferCount,
    required this.groupName,
  });

  final int transferCount;
  final String groupName;

  @override
  Widget build(BuildContext context) {
    final headline = transferCount == 0
        ? "Everyone's even."
        : "$_countWord transfers,\neveryone's even.";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          headline,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 28,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w400,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            text: transferCount == 0
                ? 'No optimized payments are needed across '
                : 'Optimized to minimise the number of payments across ',
            children: [
              TextSpan(
                text: groupName,
                style: TextStyle(
                  color: context.colors.ink2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const TextSpan(text: '.'),
            ],
          ),
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 13,
            height: 1.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String get _countWord {
    const words = {
      1: 'One',
      2: 'Two',
      3: 'Three',
      4: 'Four',
      5: 'Five',
      6: 'Six',
      7: 'Seven',
      8: 'Eight',
      9: 'Nine',
      10: 'Ten',
    };
    return words[transferCount] ?? transferCount.toString();
  }
}

class _NetBalancesSection extends StatelessWidget {
  const _NetBalancesSection({required this.balances, required this.currency});

  final List<UserBalance> balances;
  final String currency;

  @override
  Widget build(BuildContext context) {
    if (balances.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              "Each person's net",
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: context.colors.cardSurface,
              borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
              border: Border.all(color: context.colors.rule),
              boxShadow: context.shadows.raised,
            ),
            child: Column(
              children: [
                for (var i = 0; i < balances.length; i++)
                  _NetBalanceRow(
                    balance: balances[i],
                    currency: currency,
                    showDivider: i < balances.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NetBalanceRow extends StatelessWidget {
  const _NetBalanceRow({
    required this.balance,
    required this.currency,
    required this.showDivider,
  });

  final UserBalance balance;
  final String currency;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final name = balance.displayName ?? 'Unknown';
    final amountColor = balance.netBalance > Decimal.zero
        ? context.colors.successText
        : balance.netBalance < Decimal.zero
        ? context.colors.errorText
        : context.colors.textSecondary;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: showDivider
              ? BorderSide(color: context.colors.rule)
              : BorderSide.none,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _MiniAvatar(name: name),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            AppFormatters.formatCurrency(balance.netBalance, currency),
            style: TextStyle(
              color: amountColor,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: context.colors.saffronTint,
        shape: BoxShape.circle,
        border: Border.all(color: context.colors.rule2),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: context.colors.ink2,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
