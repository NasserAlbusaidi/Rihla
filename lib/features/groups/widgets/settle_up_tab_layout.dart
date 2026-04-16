import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../shared/widgets/app_tab_bar.dart';
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
  }) onRecord;

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
          (s) =>
              s['fromUserId'] != currentUid && s['toUserId'] != currentUid,
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GroupSettlementSummaryCard(
              totalPending: Decimal.zero,
              currency: group.currency,
              eventCount: balancesData.eventCount,
            ),
            const SizedBox(height: 40),
            const AllSettledState(),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: GroupSettlementSummaryCard(
            totalPending: totalPending,
            currency: group.currency,
            eventCount: balancesData.eventCount,
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
                emptyMessage:
                    "You don't owe anyone in this group right now.",
                currency: group.currency,
                tileKeys: tileKeys,
                preSelectedMemberId: preSelectedMemberId,
                onRecord: onRecord,
                buildBreakdown: buildBreakdown,
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
              ),
              // Tab 2: Between Others
              SettlementTabContent(
                settlements: betweenOthers,
                isYourAction: false,
                isCreditor: false,
                emptyIcon: Iconsax.people,
                emptyTitle: 'All balanced',
                emptyMessage:
                    'No outstanding amounts between other members.',
                currency: group.currency,
                tileKeys: tileKeys,
                preSelectedMemberId: preSelectedMemberId,
                onRecord: onRecord,
                buildBreakdown: buildBreakdown,
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
