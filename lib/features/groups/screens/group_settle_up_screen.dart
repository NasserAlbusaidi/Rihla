import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import 'package:go_router/go_router.dart';
import '../../../core/config/firebase_config.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/app_tab_bar.dart';
import '../keys/group_keys.dart';
import '../../events/models/event_model.dart';
import '../../events/models/event_type_config.dart';
import '../../events/providers/event_provider.dart';
import '../../ledger/models/settlement_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../models/group_model.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';
import '../widgets/group_settlement_summary.dart';
import '../widgets/group_settlement_tile.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';

/// Full-screen cross-event settlement UI with 4-tab layout (D-01, D-02, D-03, D-05, D-06).
///
/// Tabs: You Owe / Owed to You / Between Others / History
/// Uses [ModuleHeader] with dark theme and [AppTabBar] for navigation.
/// Supports [preSelectedMemberId] for deep-link auto-selection.
class GroupSettleUpScreen extends ConsumerStatefulWidget {
  final String groupId;

  /// D-22 entry point 2: pre-select a specific member to settle with.
  final String? preSelectedMemberId;

  const GroupSettleUpScreen({
    super.key,
    required this.groupId,
    this.preSelectedMemberId,
  });

  @override
  ConsumerState<GroupSettleUpScreen> createState() =>
      _GroupSettleUpScreenState();
}

class _GroupSettleUpScreenState extends ConsumerState<GroupSettleUpScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// Keys for settlement tiles, used for auto-scroll when
  /// [widget.preSelectedMemberId] is set.
  final Map<int, GlobalKey> _tileKeys = {};

  /// Guard to prevent _autoSelectTab from re-running on every rebuild.
  bool _hasAutoSelected = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _autoSelectTab(
    List<Map<String, dynamic>> optimalSettlements,
    String? currentUid,
  ) {
    if (_hasAutoSelected) return;
    if (widget.preSelectedMemberId == null) return;
    _hasAutoSelected = true;
    final pid = widget.preSelectedMemberId!;

    // Check if any settlement in "You Owe" involves preSelectedMemberId
    final inYouOwe = optimalSettlements.any(
      (s) =>
          s['fromUserId'] == currentUid &&
          (s['toUserId'] == pid || s['fromUserId'] == pid),
    );
    if (inYouOwe) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tabController.animateTo(0);
      });
      return;
    }

    // Check "Owed to You"
    final inOwedToYou = optimalSettlements.any(
      (s) =>
          s['toUserId'] == currentUid &&
          (s['fromUserId'] == pid || s['toUserId'] == pid),
    );
    if (inOwedToYou) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tabController.animateTo(1);
      });
      return;
    }

    // Default tab 0
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tabController.animateTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));

    // Loading state
    if (groupAsync.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final group = groupAsync.valueOrNull;

    // Not-found state per D-11
    if (group == null) {
      return Scaffold(
        backgroundColor: AppColorTokens.light.scaffoldBackground,
        body: Column(
          children: [
            const ModuleHeader(title: 'Not Found', useDarkTheme: true),
            Expanded(
              child: EmptyStateView(
                icon: Iconsax.warning_2,
                title: 'This group is no longer available',
                message:
                    'You may have been removed. Tap below to go back home.',
                actionLabel: 'Go Home',
                onAction: () => context.go('/home'),
                iconColor: AppColorTokens.light.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    // Read currentUid from provider for testability
    final currentUid = ref.watch(currentUserIdProvider);

    final balancesAsync = ref.watch(groupBalancesProvider(widget.groupId));
    final eventsAsync = ref.watch(groupEventsProvider(widget.groupId));
    final settlementsAsync = ref.watch(groupSettlementsProvider(widget.groupId));
    final eventNameMap = <String, ({String name, EventType type, DateTime date})>{
      for (final e in eventsAsync.valueOrNull ?? <Event>[])
        e.id: (
          name: e.name,
          type: e.type,
          date: e.startDate ?? e.createdAt,
        ),
    };

    return Scaffold(
      key: GroupKeys.settleUpScreen,
      backgroundColor: AppColorTokens.light.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            ModuleHeader(
              title: 'Settle Up',
              subtitle: group.name,
              useDarkTheme: true,
            ),
            Expanded(
              child: balancesAsync.when(
                data: (balancesData) {
                  final optimalSettlements =
                      BalanceCalculator.calculateOptimalSettlements(
                    balances: balancesData.balances,
                    userNames: balancesData.memberNames,
                  );

                  _autoSelectTab(optimalSettlements, currentUid);

                  return _buildTabLayout(
                    context,
                    group,
                    optimalSettlements,
                    balancesData,
                    eventNameMap,
                    settlementsAsync,
                    currentUid,
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Iconsax.warning_2,
                            size: 40, color: AppColorTokens.light.error),
                        const SizedBox(height: 16),
                        Text(
                          'Couldn\'t load balances.',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColorTokens.light.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => ref
                              .invalidate(groupBalancesProvider(widget.groupId)),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabLayout(
    BuildContext context,
    Group group,
    List<Map<String, dynamic>> optimalSettlements,
    GroupBalances balancesData,
    Map<String, ({String name, EventType type, DateTime date})> eventNameMap,
    AsyncValue<List<Settlement>> settlementsAsync,
    String? currentUid,
  ) {
    const spacing = AppSpacingTokens.standard;

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

    // All-settled state (D-06): when ALL tabs have 0 items and history empty
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
            _buildAllSettledState(context),
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
          controller: _tabController,
          tabs: const ['You Owe', 'Owed to You', 'Between Others', 'History'],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 0: You Owe
              _buildSettlementTabContent(
                context,
                group,
                youOwe,
                balancesData,
                eventNameMap,
                isYourAction: true,
                isCreditor: false,
                emptyIcon: Iconsax.wallet_check,
                emptyTitle: 'Nothing to pay',
                emptyMessage: "You don't owe anyone in this group right now.",
              ),
              // Tab 1: Owed to You
              _buildSettlementTabContent(
                context,
                group,
                owedToYou,
                balancesData,
                eventNameMap,
                isYourAction: false,
                isCreditor: true,
                emptyIcon: Iconsax.money_recive,
                emptyTitle: 'Nothing owed to you',
                emptyMessage: 'No one owes you in this group right now.',
              ),
              // Tab 2: Between Others
              _buildSettlementTabContent(
                context,
                group,
                betweenOthers,
                balancesData,
                eventNameMap,
                isYourAction: false,
                isCreditor: false,
                emptyIcon: Iconsax.people,
                emptyTitle: 'All balanced',
                emptyMessage:
                    'No outstanding amounts between other members.',
              ),
              // Tab 3: History
              _buildHistoryTab(settlementsAsync, group.currency, spacing),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettlementTabContent(
    BuildContext context,
    Group group,
    List<Map<String, dynamic>> settlements,
    GroupBalances balancesData,
    Map<String, ({String name, EventType type, DateTime date})> eventNameMap, {
    required bool isYourAction,
    required bool isCreditor,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyMessage,
  }) {
    if (settlements.isEmpty) {
      return EmptyStateView(
        icon: emptyIcon,
        title: emptyTitle,
        message: emptyMessage,
        iconColor: AppColorTokens.light.textSecondary,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: settlements.length,
      itemBuilder: (context, index) {
        final settlement = settlements[index];
        final fromUserId = settlement['fromUserId'] as String;
        final toUserId = settlement['toUserId'] as String;
        final fromName = settlement['fromUserName'] as String;
        final toName = settlement['toUserName'] as String;
        final amount = settlement['amount'] as Decimal;
        final isHighlighted = widget.preSelectedMemberId != null &&
            (fromUserId == widget.preSelectedMemberId ||
                toUserId == widget.preSelectedMemberId);

        final tileKey = GlobalKey();
        _tileKeys[index] = tileKey;

        final breakdown = _buildPerEventBreakdown(
          fromUserId,
          toUserId,
          balancesData,
          eventNameMap,
        );

        return GroupSettlementTile(
          fromName: fromName,
          toName: toName,
          amount: amount,
          currency: group.currency,
          breakdown: breakdown,
          isYourAction: isYourAction,
          isCreditor: isCreditor,
          isHighlighted: isHighlighted,
          tileKey: tileKey,
          onRecord: () => _showRecordPaymentSheet(
            context,
            group: group,
            settlement: settlement,
            fromName: fromName,
            toName: toName,
            fromUserId: fromUserId,
            toUserId: toUserId,
            suggestedAmount: amount,
          ),
        )
            .animate()
            .fadeIn(delay: Duration(milliseconds: index * 50))
            .slideY(begin: 0.1, curve: Curves.easeOutCubic);
      },
    );
  }

  Widget _buildHistoryTab(
    AsyncValue<List<Settlement>> settlementsAsync,
    String currency,
    AppSpacingTokens spacing,
  ) {
    return settlementsAsync.when(
      data: (settlements) {
        if (settlements.isEmpty) {
          return const EmptyStateView(
            icon: Iconsax.receipt_1,
            title: 'No recorded payments',
            message: 'Payments recorded in this group will appear here.',
          );
        }
        return ListView.builder(
          padding: EdgeInsets.fromLTRB(
            spacing.space20,
            spacing.space12,
            spacing.space20,
            spacing.space24,
          ),
          physics: const BouncingScrollPhysics(),
          itemCount: settlements.length,
          itemBuilder: (context, index) {
            final settlement = settlements[index];
            return _buildHistoryTile(settlement, currency, spacing, index);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => EmptyStateView(
        icon: Iconsax.warning_2,
        title: 'Couldn\'t load history',
        message: 'Check your connection and try again.',
        iconColor: AppColorTokens.light.textSecondary,
      ),
    );
  }

  Widget _buildHistoryTile(
    Settlement settlement,
    String currency,
    AppSpacingTokens spacing,
    int index,
  ) {
    final payerName = settlement.payerName ?? 'Unknown';
    final recipientName = settlement.recipientName ?? 'Unknown';
    final dateStr = DateFormat('MMM d').format(settlement.settledAt);

    return Container(
      margin: EdgeInsets.only(bottom: spacing.space12),
      decoration: BoxDecoration(
        color: AppColorTokens.light.cardSurface,
        borderRadius: BorderRadius.circular(spacing.radiusLarge),
        boxShadow: AppShadowTokens.standard.raised,
        border: Border.all(
          color: AppColorTokens.light.border.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(spacing.space16),
        child: Row(
          children: [
            // Overlapping avatar pair for history tile
            SizedBox(
              width: 52,
              height: 32,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    child: _buildHistoryAvatar(payerName, isPayer: true),
                  ),
                  Positioned(
                    left: 20,
                    child: _buildHistoryAvatar(recipientName, isPayer: false),
                  ),
                ],
              ),
            ),
            SizedBox(width: spacing.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$payerName paid $recipientName',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColorTokens.light.textPrimary,
                    ),
                  ),
                  SizedBox(height: spacing.space4),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColorTokens.light.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              AppFormatters.formatCurrency(settlement.amount, currency),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColorTokens.light.textPrimary,
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(delay: Duration(milliseconds: index * 50))
        .slideY(begin: 0.1, curve: Curves.easeOutCubic);
  }

  Widget _buildHistoryAvatar(String name, {required bool isPayer}) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isPayer
            ? AppColorTokens.light.primary.withValues(alpha: 0.15)
            : AppColorTokens.light.inputFill,
        shape: BoxShape.circle,
        border: Border.all(
          color: isPayer
              ? AppColorTokens.light.primary.withValues(alpha: 0.4)
              : AppColorTokens.light.border,
          width: isPayer ? 2 : 1,
        ),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isPayer
                ? AppColorTokens.light.primary
                : AppColorTokens.light.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildAllSettledState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColorTokens.light.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Iconsax.tick_circle,
              color: AppColorTokens.light.success,
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'All settled up',
            key: GroupKeys.settleUpAllSettledMessage,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColorTokens.light.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Everyone is square. No outstanding amounts.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColorTokens.light.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Map<String, Decimal> _buildPerEventBreakdown(
    String fromUserId,
    String toUserId,
    GroupBalances balancesData,
    Map<String, ({String name, EventType type, DateTime date})> eventNameMap,
  ) {
    final result = <String, Decimal>{};
    final fromBreakdown = balancesData.perEventBreakdown[fromUserId] ?? {};
    final toBreakdown = balancesData.perEventBreakdown[toUserId] ?? {};

    final allEventIds = {
      ...fromBreakdown.keys,
      ...toBreakdown.keys,
    };

    for (final eventId in allEventIds) {
      final fromNet = fromBreakdown[eventId] ?? Decimal.zero;
      final toNet = toBreakdown[eventId] ?? Decimal.zero;

      if (fromNet < Decimal.zero && toNet > Decimal.zero) {
        final attribution = fromNet.abs() < toNet ? fromNet.abs() : toNet;
        if (attribution > Decimal.zero) {
          result[_buildEventLabel(eventId, eventNameMap)] = attribution;
        }
      }
    }

    return result;
  }

  String _buildEventLabel(
    String eventId,
    Map<String, ({String name, EventType type, DateTime date})> eventMap,
  ) {
    final entry = eventMap[eventId];
    if (entry == null) {
      return eventId.length > 8
          ? 'Event ...${eventId.substring(eventId.length - 6)}'
          : eventId;
    }

    final rawName = entry.name.isNotEmpty
        ? entry.name
        : EventTypeConfig.forType(entry.type).label;

    final name = rawName.length > 30
        ? '${rawName.substring(0, 27)}...'
        : rawName;

    final date = AppFormatters.formatShortMonthDay(entry.date);
    return '$name \u2014 $date';
  }

  Future<void> _showRecordPaymentSheet(
    BuildContext context, {
    required Group group,
    required Map<String, dynamic> settlement,
    required String fromName,
    required String toName,
    required String fromUserId,
    required String toUserId,
    required Decimal suggestedAmount,
  }) async {
    const spacing = AppSpacingTokens.standard;
    final amountController = TextEditingController(
      text: suggestedAmount.toStringAsFixed(3),
    );
    final noteController = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColorTokens.light.scaffoldBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
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
                'Record Payment',
                key: GroupKeys.settleUpRecordSheetTitle,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColorTokens.light.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$fromName paid ${AppFormatters.formatCurrency(suggestedAmount, group.currency)} to $toName.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColorTokens.light.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              // Amount field
              TextFormField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,3}'),
                  ),
                ],
                decoration: InputDecoration(
                  labelText: 'Amount (${group.currency})',
                  filled: true,
                  fillColor: AppColorTokens.light.inputFillWarm,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(spacing.radiusMedium),
                    borderSide: BorderSide(
                      color: AppColorTokens.light.borderWarm,
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(spacing.radiusMedium),
                    borderSide: BorderSide(
                      color: AppColorTokens.light.focusBorderWarm,
                      width: 2,
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(spacing.radiusMedium),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Note field
              TextFormField(
                controller: noteController,
                decoration: InputDecoration(
                  labelText: 'Optional note (e.g. Venmo, cash)',
                  filled: true,
                  fillColor: AppColorTokens.light.inputFillWarm,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(spacing.radiusMedium),
                    borderSide: BorderSide(
                      color: AppColorTokens.light.borderWarm,
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(spacing.radiusMedium),
                    borderSide: BorderSide(
                      color: AppColorTokens.light.focusBorderWarm,
                      width: 2,
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(spacing.radiusMedium),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Record Payment CTA
              SizedBox(
                width: double.infinity,
                height: spacing.buttonHeight,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppColorTokens.light.primaryGradient,
                    borderRadius: BorderRadius.circular(spacing.radiusMedium),
                  ),
                  child: ElevatedButton(
                    key: GroupKeys.markAsPaidButton,
                    onPressed: () {
                      Navigator.pop(sheetContext, true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(spacing.radiusMedium),
                      ),
                    ),
                    child: const Text(
                      'Record Payment',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: GroupKeys.notNowButton,
                onPressed: () => Navigator.pop(sheetContext),
                child: Text(
                  'Not Now',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColorTokens.light.textMuted,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (!context.mounted || confirmed != true) return;

    final editedAmount = Decimal.tryParse(amountController.text.trim()) ??
        suggestedAmount;
    final noteText =
        noteController.text.trim().isEmpty ? null : noteController.text.trim();

    // Validate amount before recording
    if (editedAmount <= Decimal.zero) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Amount must be greater than zero')),
        );
      }
      return;
    }
    if (editedAmount > suggestedAmount) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Amount cannot exceed the outstanding balance of '
              '${AppFormatters.formatCurrency(suggestedAmount, group.currency)}',
            ),
          ),
        );
      }
      return;
    }

    await _recordSettlement(
      context,
      group: group,
      fromUserId: fromUserId,
      toUserId: toUserId,
      fromName: fromName,
      toName: toName,
      amount: editedAmount,
      note: noteText,
    );
  }

  Future<void> _recordSettlement(
    BuildContext context, {
    required Group group,
    required String fromUserId,
    required String toUserId,
    required String fromName,
    required String toName,
    required Decimal amount,
    String? note,
  }) async {
    try {
      String? actorName;
      try {
        actorName = ref.read(settingsProvider).deviceName.isNotEmpty
            ? ref.read(settingsProvider).deviceName
            : fromName;
      } catch (_) {
        actorName = fromName;
      }

      await ref
          .read(groupSettlementServiceProvider)
          .addGroupSettlement(
            groupId: widget.groupId,
            payerParticipantId: fromUserId,
            recipientParticipantId: toUserId,
            amount: amount,
            currency: group.currency,
            note: note,
            payerName: fromName,
            recipientName: toName,
          );

      String? currentUid;
      try {
        currentUid = FirebaseConfig.currentUser?.uid ?? fromUserId;
      } catch (_) {
        currentUid = fromUserId;
      }

      ref.read(groupActivityServiceProvider).logGroupEvent(
            groupId: widget.groupId,
            type: 'group_settlement',
            actorId: currentUid,
            actorName: actorName,
            description:
                'settled ${AppFormatters.formatCurrency(amount, group.currency)} with $toName',
            metadata: {
              'amount': amount.toString(),
              'recipientId': toUserId,
            },
          );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Settlement recorded.'),
            backgroundColor: AppColorTokens.light.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Couldn\'t record settlement. Check your connection and try again.',
            ),
            backgroundColor: AppColorTokens.light.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }
}
