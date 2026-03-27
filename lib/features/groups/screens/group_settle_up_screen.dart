import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../events/models/event_model.dart';
import '../../events/models/event_type_config.dart';
import '../../events/providers/event_provider.dart';
import '../../ledger/providers/expense_provider.dart';
import '../models/group_model.dart';
import '../providers/group_balance_provider.dart';
import '../widgets/group_settlement_summary.dart';
import '../widgets/group_settlement_tile.dart';

/// Full-screen cross-event settlement UI (FIN-04, D-22).
///
/// Shows optimized settlement tiles computed from group-level balances
/// via [BalanceCalculator.calculateOptimalSettlements]. Supports
/// [preSelectedMemberId] for D-22 entry point 2 (auto-scroll to or highlight
/// the tile involving a specific member).
class GroupSettleUpScreen extends ConsumerStatefulWidget {
  final String groupId;
  final Group group;

  /// D-22 entry point 2: pre-select a specific member to settle with.
  final String? preSelectedMemberId;

  const GroupSettleUpScreen({
    super.key,
    required this.groupId,
    required this.group,
    this.preSelectedMemberId,
  });

  @override
  ConsumerState<GroupSettleUpScreen> createState() =>
      _GroupSettleUpScreenState();
}

class _GroupSettleUpScreenState extends ConsumerState<GroupSettleUpScreen> {
  final ScrollController _scrollController = ScrollController();

  /// Keys for each settlement tile, used for auto-scroll when
  /// [widget.preSelectedMemberId] is set.
  final Map<int, GlobalKey> _tileKeys = {};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _isCurrentUser(String uid) {
    try {
      return FirebaseConfig.currentUser?.uid == uid;
    } catch (_) {
      return false;
    }
  }

  void _scrollToPreSelected(List<Map<String, dynamic>> allSettlements) {
    if (widget.preSelectedMemberId == null) return;
    final idx = allSettlements.indexWhere(
      (s) =>
          s['fromUserId'] == widget.preSelectedMemberId ||
          s['toUserId'] == widget.preSelectedMemberId,
    );
    if (idx < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _tileKeys[idx];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          alignment: 0.2,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final balancesAsync = ref.watch(groupBalancesProvider(widget.groupId));
    final eventsAsync = ref.watch(groupEventsProvider(widget.groupId));
    final eventNameMap = <String, ({String name, EventType type, DateTime date})>{
      for (final e in eventsAsync.valueOrNull ?? <Event>[])
        e.id: (
          name: e.name,
          type: e.type,
          date: e.startDate ?? e.createdAt,
        ),
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: balancesAsync.when(
                data: (balancesData) {
                  final optimalSettlements =
                      BalanceCalculator.calculateOptimalSettlements(
                    balances: balancesData.balances,
                    userNames: balancesData.memberNames,
                  );
                  return _buildContent(context, optimalSettlements, balancesData, eventNameMap);
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Iconsax.warning_2,
                            size: 40, color: AppColors.rose),
                        const SizedBox(height: 16),
                        const Text(
                          'Couldn\'t load balances.',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
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

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppColors.radiusSmall),
              border: Border.all(color: AppColors.borderLight, width: 1),
              boxShadow: AppColors.cardShadow,
            ),
            child: IconButton(
              icon: const Icon(Iconsax.arrow_left, size: 20),
              onPressed: () => Navigator.pop(context),
              tooltip: 'Back',
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                ),
              ),
            ),
          ),
          const Text(
            'Settle Up',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<Map<String, dynamic>> optimalSettlements,
    GroupBalances balancesData,
    Map<String, ({String name, EventType type, DateTime date})> eventNameMap,
  ) {
    String? currentUid;
    try {
      currentUid = FirebaseConfig.currentUser?.uid;
    } catch (_) {
      currentUid = null;
    }

    final yourActions = optimalSettlements
        .where((s) => s['fromUserId'] == currentUid)
        .toList();
    final waitingForOthers = optimalSettlements
        .where((s) => s['toUserId'] == currentUid)
        .toList();
    final othersSettling = optimalSettlements
        .where(
          (s) =>
              s['fromUserId'] != currentUid && s['toUserId'] != currentUid,
        )
        .toList();

    Decimal totalPending = Decimal.zero;
    for (final s in optimalSettlements) {
      totalPending += (s['amount'] as Decimal);
    }

    _scrollToPreSelected(optimalSettlements);

    final orderedSettlements = [
      ...yourActions,
      ...waitingForOthers,
      ...othersSettling,
    ];
    _tileKeys.clear();
    for (var i = 0; i < orderedSettlements.length; i++) {
      _tileKeys[i] = GlobalKey();
    }

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GroupSettlementSummaryCard(
            totalPending: totalPending,
            currency: widget.group.currency,
            eventCount: balancesData.eventCount,
          ),
          const SizedBox(height: 32),

          if (optimalSettlements.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: _buildAllSettled(context),
            )
          else ...[
            if (yourActions.isNotEmpty) ...[
              _buildSectionHeader('YOUR ACTIONS', Iconsax.arrow_up_1),
              const SizedBox(height: 12),
              _buildSettlementGroup(
                context,
                yourActions,
                orderedSettlements,
                balancesData,
                eventNameMap,
                isYourAction: true,
              ),
              const SizedBox(height: 24),
            ],
            if (waitingForOthers.isNotEmpty) ...[
              _buildSectionHeader('WAITING FOR OTHERS', Iconsax.timer_1),
              const SizedBox(height: 12),
              _buildSettlementGroup(
                context,
                waitingForOthers,
                orderedSettlements,
                balancesData,
                eventNameMap,
                isYourAction: false,
              ),
              const SizedBox(height: 24),
            ],
            if (othersSettling.isNotEmpty) ...[
              _buildSectionHeader('OTHERS SETTLING', Iconsax.people),
              const SizedBox(height: 12),
              _buildSettlementGroup(
                context,
                othersSettling,
                orderedSettlements,
                balancesData,
                eventNameMap,
                isYourAction: false,
              ),
              const SizedBox(height: 24),
            ],
          ],
          const SizedBox(height: 24),
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
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildSettlementGroup(
    BuildContext context,
    List<Map<String, dynamic>> settlements,
    List<Map<String, dynamic>> orderedSettlements,
    GroupBalances balancesData,
    Map<String, ({String name, EventType type, DateTime date})> eventNameMap, {
    required bool isYourAction,
  }) {
    final tiles = settlements.asMap().entries.map((entry) {
      final settlement = entry.value;
      final isLast = entry.key == settlements.length - 1;
      final globalIdx = orderedSettlements.indexOf(settlement);
      final fromUserId = settlement['fromUserId'] as String;
      final toUserId = settlement['toUserId'] as String;
      final fromName = settlement['fromUserName'] as String;
      final toName = settlement['toUserName'] as String;
      final amount = settlement['amount'] as Decimal;
      final isHighlighted = widget.preSelectedMemberId != null &&
          (fromUserId == widget.preSelectedMemberId ||
              toUserId == widget.preSelectedMemberId);
      final showButton = isYourAction || _isCurrentUser(toUserId);

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
        currency: widget.group.currency,
        breakdown: breakdown,
        showDivider: !isLast,
        isYourAction: isYourAction,
        isHighlighted: isHighlighted,
        tileKey: _tileKeys[globalIdx],
        onRecord: showButton
            ? () => _showSettlementConfirmation(
                  context,
                  settlement: settlement,
                  fromName: fromName,
                  toName: toName,
                  fromUserId: fromUserId,
                  toUserId: toUserId,
                  suggestedAmount: amount,
                )
            : null,
      );
    }).toList();

    return GroupSettlementGroupCard(
      tiles: tiles,
      isYourAction: isYourAction,
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

  Widget _buildAllSettled(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Iconsax.tick_circle,
              color: AppColors.success,
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'All settled across the group!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'No payments needed right now.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _showSettlementConfirmation(
    BuildContext context, {
    required Map<String, dynamic> settlement,
    required String fromName,
    required String toName,
    required String fromUserId,
    required String toUserId,
    required Decimal suggestedAmount,
  }) async {
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
                'Record Settlement',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$fromName paid ${AppFormatters.formatCurrency(suggestedAmount, widget.group.currency)} to $toName. '
                'Record this as settled? (via cash, bank transfer, or other method)',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount (${widget.group.currency})',
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppColors.radiusMedium),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: noteController,
                decoration: InputDecoration(
                  labelText: 'Add a note (optional)',
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppColors.radiusMedium),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius:
                        BorderRadius.circular(AppColors.radiusMedium),
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(sheetContext, true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.black,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppColors.radiusMedium),
                      ),
                    ),
                    child: const Text(
                      'Mark as Paid',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text(
                  'Not Now',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
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

    await _recordSettlement(
      context,
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
        actorName = FirebaseConfig.currentUser?.displayName ?? fromName;
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
            currency: widget.group.currency,
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
                'settled ${AppFormatters.formatCurrency(amount, widget.group.currency)} with $toName',
            metadata: {
              'amount': amount.toString(),
              'recipientId': toUserId,
            },
          );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Settlement recorded.'),
            backgroundColor: AppColors.success,
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
            backgroundColor: AppColors.rose,
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
