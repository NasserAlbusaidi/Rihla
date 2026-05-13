import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import 'package:go_router/go_router.dart';
import '../../../core/config/firebase_config.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../keys/group_keys.dart';
import '../../events/models/event_model.dart';
import '../../events/models/event_type_config.dart';
import '../../events/providers/event_provider.dart';
import '../../ledger/providers/expense_provider.dart';
import '../models/group_model.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';
import '../widgets/record_payment_sheet.dart';
import '../widgets/settle_up_tab_layout.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// Full-screen cross-event settlement UI with 4-tab layout (D-01, D-02, D-03, D-05, D-06).
///
/// Tabs: You Owe / Owed to You / Between Others / History
/// Uses [ModuleHeader] with dark theme and [AppTabBar] for navigation.
/// Supports [preSelectedMemberId] for deep-link auto-selection.
///
/// Screen responsibilities (post Phase 36 Plan 01 decomposition):
/// - Data fetching via Riverpod providers
/// - [_autoSelectTab] logic (mutates [_tabController])
/// - [_showRecordPaymentSheet] delegates to [showRecordPaymentSheet]
/// - [_recordSettlement] write operation
/// - [_buildPerEventBreakdown] and [_buildEventLabel] helpers
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final group = groupAsync.valueOrNull;

    // Not-found state per D-11
    if (group == null) {
      return Scaffold(
        backgroundColor: context.colors.scaffoldBackground,
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
                iconColor: context.colors.textSecondary,
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
    final settlementsAsync = ref.watch(
      groupSettlementsProvider(widget.groupId),
    );
    final eventNameMap =
        <String, ({String name, EventType type, DateTime date})>{
          for (final e in eventsAsync.valueOrNull ?? <Event>[])
            e.id: (
              name: e.name,
              type: e.type,
              date: e.startDate ?? e.createdAt,
            ),
        };

    return Scaffold(
      key: GroupKeys.settleUpScreen,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            _SettlementTopBar(groupId: widget.groupId),
            Expanded(
              child: balancesAsync.when(
                data: (balancesData) {
                  final optimalSettlements =
                      BalanceCalculator.calculateOptimalSettlements(
                        balances: balancesData.balances,
                        userNames: balancesData.memberNames,
                      );

                  _autoSelectTab(optimalSettlements, currentUid);

                  return SettleUpTabLayout(
                    controller: _tabController,
                    group: group,
                    optimalSettlements: optimalSettlements,
                    balancesData: balancesData,
                    settlementsAsync: settlementsAsync,
                    currentUid: currentUid,
                    tileKeys: _tileKeys,
                    preSelectedMemberId: widget.preSelectedMemberId,
                    onRecord:
                        ({
                          required settlement,
                          required fromName,
                          required toName,
                          required fromUserId,
                          required toUserId,
                          required suggestedAmount,
                        }) => _showRecordPaymentSheet(
                          context,
                          group: group,
                          settlement: settlement,
                          fromName: fromName,
                          toName: toName,
                          fromUserId: fromUserId,
                          toUserId: toUserId,
                          suggestedAmount: suggestedAmount,
                        ),
                    buildBreakdown: (fromUserId, toUserId) =>
                        _buildPerEventBreakdown(
                          fromUserId,
                          toUserId,
                          balancesData,
                          eventNameMap,
                        ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Iconsax.warning_2,
                          size: 40,
                          color: context.colors.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Couldn\'t load balances.',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: context.colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => ref.invalidate(
                            groupBalancesProvider(widget.groupId),
                          ),
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

  Map<String, Decimal> _buildPerEventBreakdown(
    String fromUserId,
    String toUserId,
    GroupBalances balancesData,
    Map<String, ({String name, EventType type, DateTime date})> eventNameMap,
  ) {
    final result = <String, Decimal>{};
    final fromBreakdown = balancesData.perEventBreakdown[fromUserId] ?? {};
    final toBreakdown = balancesData.perEventBreakdown[toUserId] ?? {};

    final allEventIds = {...fromBreakdown.keys, ...toBreakdown.keys};

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
    final result = await showRecordPaymentSheet(
      context,
      group: group,
      fromName: fromName,
      toName: toName,
      suggestedAmount: suggestedAmount,
    );

    if (!context.mounted || result == null) return;

    final editedAmount = Decimal.tryParse(result.amount) ?? suggestedAmount;
    final noteText = result.note.isEmpty ? null : result.note;

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

      ref
          .read(groupActivityServiceProvider)
          .logGroupEvent(
            groupId: widget.groupId,
            type: 'group_settlement',
            actorId: currentUid,
            actorName: actorName,
            description:
                'settled ${AppFormatters.formatCurrency(amount, group.currency)} with $toName',
            metadata: {'amount': amount.toString(), 'recipientId': toUserId},
          );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Settlement recorded.'),
            backgroundColor: context.colors.success,
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
            backgroundColor: context.colors.error,
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

class _SettlementTopBar extends StatelessWidget {
  const _SettlementTopBar({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 20, 8),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back',
                icon: const Icon(Iconsax.arrow_left_2, size: 20),
                color: context.colors.textPrimary,
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/group/$groupId');
                  }
                },
              ),
            ),
            Text(
              'Settle Up',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
