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

  /// Scroll to the tile that involves [widget.preSelectedMemberId] after
  /// the first build completes.
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
    // Get current user UID safely (D-22 test safety pattern)
    String? currentUid;
    try {
      currentUid = FirebaseConfig.currentUser?.uid;
    } catch (_) {
      currentUid = null;
    }

    // Categorise into three groups per UI-SPEC Screen 4
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

    // Compute total pending amount
    Decimal totalPending = Decimal.zero;
    for (final s in optimalSettlements) {
      totalPending += (s['amount'] as Decimal);
    }

    // Trigger scroll after frame if preSelectedMemberId set
    _scrollToPreSelected(optimalSettlements);

    // Build flat ordered list for tile key mapping
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
          // Summary card
          _buildSummaryCard(
            totalPending: totalPending,
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

  Widget _buildSummaryCard({
    required Decimal totalPending,
    required int eventCount,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.12),
            AppColors.surface.withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: AppColors.cardShadowLarge,
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'GROUP TOTAL PENDING',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppFormatters.formatCurrency(totalPending, widget.group.currency),
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Across $eventCount event${eventCount == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppColors.textMuted,
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.radiusLarge),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        boxShadow: isYourAction ? AppColors.cardShadow : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: settlements.asMap().entries.map((entry) {
          final settlement = entry.value;
          final isLast = entry.key == settlements.length - 1;
          final globalIdx = orderedSettlements.indexOf(settlement);
          final isHighlighted = widget.preSelectedMemberId != null &&
              (settlement['fromUserId'] == widget.preSelectedMemberId ||
                  settlement['toUserId'] == widget.preSelectedMemberId);
          return _buildSettlementTile(
            context,
            settlement,
            balancesData,
            eventNameMap,
            showDivider: !isLast,
            isYourAction: isYourAction,
            isHighlighted: isHighlighted,
            tileKey: _tileKeys[globalIdx],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSettlementTile(
    BuildContext context,
    Map<String, dynamic> settlement,
    GroupBalances balancesData,
    Map<String, ({String name, EventType type, DateTime date})> eventNameMap, {
    bool showDivider = true,
    required bool isYourAction,
    bool isHighlighted = false,
    GlobalKey? tileKey,
  }) {
    final fromName = settlement['fromUserName'] as String;
    final toName = settlement['toUserName'] as String;
    final fromUserId = settlement['fromUserId'] as String;
    final toUserId = settlement['toUserId'] as String;
    final amount = settlement['amount'] as Decimal;

    // Build per-event breakdown for this pair
    final breakdown = _buildPerEventBreakdown(
      fromUserId,
      toUserId,
      balancesData,
      eventNameMap,
    );

    return Container(
      key: tileKey,
      color: isHighlighted
          ? AppColors.primary.withValues(alpha: 0.05)
          : null,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Avatar stack
                    SizedBox(
                      width: 52,
                      height: 32,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            child: _buildAvatar(fromName, isPayer: true),
                          ),
                          Positioned(
                            left: 20,
                            child: _buildAvatar(toName),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                              children: [
                                TextSpan(
                                  text: fromName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const TextSpan(
                                  text: ' pays ',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                  ),
                                ),
                                TextSpan(
                                  text: toName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppFormatters.formatCurrency(
                              amount,
                              widget.group.currency,
                            ),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: isYourAction
                                  ? AppColors.rose
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Per-event breakdown (D-24)
                if (breakdown.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...breakdown.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(left: 64, top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              e.key,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            ': ${AppFormatters.formatCurrency(e.value, widget.group.currency)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Record Settlement button — YOUR ACTIONS and WAITING FOR OTHERS
                if (isYourAction || _isCurrentUser(toUserId)) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius:
                            BorderRadius.circular(AppColors.radiusMedium),
                      ),
                      child: ElevatedButton(
                        onPressed: () => _showSettlementConfirmation(
                          context,
                          settlement: settlement,
                          fromName: fromName,
                          toName: toName,
                          fromUserId: fromUserId,
                          toUserId: toUserId,
                          suggestedAmount: amount,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.black,
                          shadowColor: Colors.transparent,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppColors.radiusMedium,
                            ),
                          ),
                        ),
                        child: Text(
                          isYourAction ? 'Record Settlement' : 'Confirm Received',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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

  /// Builds per-event breakdown for a (fromUserId, toUserId) pair.
  ///
  /// Looks up both UIDs in [balancesData.perEventBreakdown] and finds
  /// events where the breakdown implies one owes the other.
  Map<String, Decimal> _buildPerEventBreakdown(
    String fromUserId,
    String toUserId,
    GroupBalances balancesData,
    Map<String, ({String name, EventType type, DateTime date})> eventNameMap,
  ) {
    final result = <String, Decimal>{};
    final fromBreakdown = balancesData.perEventBreakdown[fromUserId] ?? {};
    final toBreakdown = balancesData.perEventBreakdown[toUserId] ?? {};

    // Find events where fromUserId has a negative balance and toUserId has a
    // positive balance (fromUserId owes toUserId in that event).
    final allEventIds = {
      ...fromBreakdown.keys,
      ...toBreakdown.keys,
    };

    for (final eventId in allEventIds) {
      final fromNet = fromBreakdown[eventId] ?? Decimal.zero;
      final toNet = toBreakdown[eventId] ?? Decimal.zero;

      // Show this event if from has negative balance (owes) and to has positive
      if (fromNet < Decimal.zero && toNet > Decimal.zero) {
        // Amount attributable: min of what from owes and what to is owed
        final attribution = fromNet.abs() < toNet ? fromNet.abs() : toNet;
        if (attribution > Decimal.zero) {
          result[_buildEventLabel(eventId, eventNameMap)] = attribution;
        }
      }
    }

    return result;
  }

  /// Builds a human-readable label for an event in the per-event breakdown.
  ///
  /// Format per D-01, D-04: "Camping Weekend \u2014 Mar 15"
  /// Truncation per D-01: names > 30 chars truncated at 27 + "..."
  /// Fallback per D-02: event type label when event not found in map
  /// No navigation per D-03: labels are static text
  String _buildEventLabel(
    String eventId,
    Map<String, ({String name, EventType type, DateTime date})> eventMap,
  ) {
    final entry = eventMap[eventId];
    if (entry == null) {
      // Fallback: event not in map (loading or deleted)
      // Return a minimal label — will update on next rebuild when data arrives
      return eventId.length > 8
          ? 'Event ...${eventId.substring(eventId.length - 6)}'
          : eventId;
    }

    // D-02: use event name, fallback to event type label
    final rawName = entry.name.isNotEmpty
        ? entry.name
        : EventTypeConfig.forType(entry.type).label;

    // D-01: truncate names > 30 chars
    final name = rawName.length > 30
        ? '${rawName.substring(0, 27)}...'
        : rawName;

    // D-04: append short date
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

  Widget _buildAvatar(String name, {bool isPayer = false}) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isPayer ? AppColors.surface : AppColors.surfaceLight,
        shape: BoxShape.circle,
        border: Border.all(
          color: isPayer ? AppColors.primary : AppColors.border,
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
            color:
                isPayer ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// Shows the settlement confirmation bottom sheet (D-26).
  ///
  /// Pre-fills the amount (D-11 partial settlement support). User can edit
  /// the amount and add an optional note before confirming.
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
              // Drag handle
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

              // Amount field (D-11 partial settlement)
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

              // Note field (D-12)
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

              // Mark as Paid button
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

              // Not Now button
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

    // Parse edited amount
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

  /// Records a group settlement in Firestore and logs the activity.
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
