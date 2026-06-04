import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import 'package:go_router/go_router.dart';
import '../../../core/config/firebase_config.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/localized_decimal_input.dart';
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
import '../widgets/settle_up_page_body.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// Cross-event settlement screen — single-page layout per the Hi_GroupSettle
/// wireframe (Wireframes/Rihla/hifi/screens-group.jsx).
///
/// Renders an italic headline, two summary chips, optimized transfer cards,
/// each person's net balances, and inline payment history.
class GroupSettleUpScreen extends ConsumerStatefulWidget {
  final String groupId;

  /// D-22 entry point 2: highlight a specific member's tile via deep-link.
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

class _GroupSettleUpScreenState extends ConsumerState<GroupSettleUpScreen> {
  /// Keys for settlement tiles, used for auto-scroll when
  /// [widget.preSelectedMemberId] is set.
  final Map<int, GlobalKey> _tileKeys = {};

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));

    if (groupAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final group = groupAsync.valueOrNull;

    if (group == null) {
      final l10n = context.l10n;
      return Scaffold(
        backgroundColor: context.colors.scaffoldBackground,
        body: Column(
          children: [
            ModuleHeader(title: l10n.commonNotFound, useDarkTheme: true),
            Expanded(
              child: EmptyStateView(
                icon: Iconsax.warning_2,
                title: l10n.groupSettleUpMissingTitle,
                message: l10n.groupSettleUpMissingMessage,
                actionLabel: l10n.commonGoHome,
                onAction: () => context.go('/home'),
                iconColor: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final currentUid = ref.watch(currentUserIdProvider);
    final balancesAsync = ref.watch(groupBalancesProvider(widget.groupId));
    final eventsAsync = ref.watch(groupEventsProvider(widget.groupId));
    final settlementsAsync = ref.watch(
      groupSettlementsProvider(widget.groupId),
    );
    // #244: events whose money read hard-errored were silently zeroed in the
    // balance above; warn that this settle-up balance may be incomplete rather
    // than present a partial sum as authoritative.
    final failedEventIds = ref.watch(
      groupFailedEventIdsProvider(widget.groupId),
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

                  final body = SettleUpPageBody(
                    subjectName: group.name,
                    currency: group.currency,
                    optimalSettlements: optimalSettlements,
                    balances: balancesData.balances,
                    rawNames: balancesData.memberRawNames,
                    settlementsAsync: settlementsAsync,
                    currentUid: currentUid,
                    tileKeys: _tileKeys,
                    preSelectedMemberId: widget.preSelectedMemberId,
                    onRecord:
                        ({
                          required settlement,
                          required fromRawName,
                          required toRawName,
                          required fromUserId,
                          required toUserId,
                          required suggestedAmount,
                        }) => _showRecordPaymentSheet(
                          context,
                          group: group,
                          settlement: settlement,
                          fromRawName: fromRawName,
                          toRawName: toRawName,
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

                  if (failedEventIds.isEmpty) return body;
                  return Column(
                    children: [
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsetsDirectional.fromSTEB(
                          16,
                          12,
                          16,
                          0,
                        ),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.colors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: context.colors.warning.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Iconsax.warning_2,
                              size: 18,
                              color: context.colors.warning,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                context.l10n.settleUpIncompleteBalanceWarning,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(child: body),
                    ],
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
                          context.l10n.settleUpCouldNotLoadBalances,
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
                          child: Text(context.l10n.commonRetry),
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
          ? context.l10n.groupSettleUpEventLabelFallback(
              eventId.substring(eventId.length - 6),
            )
          : eventId;
    }

    final rawName = entry.name.isNotEmpty
        ? entry.name
        : EventTypeConfig.forType(entry.type).label;

    final name = rawName.length > 30
        ? '${rawName.substring(0, 27)}...'
        : rawName;

    final date = AppFormatters.formatShortMonthDay(
      entry.date,
      Localizations.localeOf(context).toLanguageTag(),
    );
    return '$name — $date';
  }

  Future<void> _showRecordPaymentSheet(
    BuildContext context, {
    required Group group,
    required Map<String, dynamic> settlement,
    required String fromRawName,
    required String toRawName,
    required String fromUserId,
    required String toUserId,
    required Decimal suggestedAmount,
  }) async {
    final fromDisplayName =
        settlement['fromUserName'] as String? ?? fromRawName;
    final toDisplayName = settlement['toUserName'] as String? ?? toRawName;
    final result = await showRecordPaymentSheet(
      context,
      currency: group.currency,
      fromName: fromDisplayName,
      toName: toDisplayName,
      suggestedAmount: suggestedAmount,
    );

    if (!context.mounted || result == null) return;

    final editedAmount =
        Decimal.tryParse(normalizeLocalizedDecimalInput(result.amount)) ??
        suggestedAmount;
    final noteText = result.note.isEmpty ? null : result.note;

    if (editedAmount <= Decimal.zero) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.settleUpAmountGreaterThanZero),
          ),
        );
      }
      return;
    }
    if (editedAmount > suggestedAmount) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.settleUpAmountExceedsOutstanding(
                AppFormatters.formatCurrency(suggestedAmount, group.currency),
              ),
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
      fromName: fromRawName,
      toName: toRawName,
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

      String currentUid;
      try {
        currentUid = FirebaseConfig.currentUser?.uid ?? fromUserId;
      } catch (_) {
        currentUid = fromUserId;
      }
      if (currentUid.isEmpty) {
        throw StateError(
          'Cannot record group settlement without an authenticated user.',
        );
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
            createdBy: currentUid,
          );

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
            content: Text(context.l10n.settleUpRecorded),
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
            content: Text(context.l10n.settleUpRecordFailed),
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
    final l10n = context.l10n;
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
                tooltip: l10n.commonBack,
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
              l10n.settleUpTitle,
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
