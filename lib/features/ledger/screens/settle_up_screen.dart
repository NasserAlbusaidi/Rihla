import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/localized_decimal_input.dart';
import '../../../core/utils/settlement_write_error.dart';
import '../../../core/utils/write_ack.dart';
import '../../../shared/widgets/directional_icon.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../events/providers/event_provider.dart';
import '../../../core/constants/supported_currencies.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../../groups/services/member_name_resolver.dart';
import '../../groups/widgets/record_payment_sheet.dart';
import '../../groups/widgets/settle_up_page_body.dart';
import '../../trip/models/trip_model.dart';
import '../keys/ledger_keys.dart';
import '../models/expense_model.dart';
import '../providers/expense_provider.dart';

/// Event-scoped Settle Up screen.
///
/// Mirrors the Group Settle-Up wireframe (Hi_GroupSettle): italic intro,
/// summary chips, optimized transfer cards, "Each person's net", and a
/// payment-history footer. Routed at `/group/:gid/event/:eid/ledger/settle-up`.
class SettleUpScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String eventId;

  /// Highlight a specific member's tile via deep-link (`?memberId=`).
  final String? preSelectedMemberId;

  const SettleUpScreen({
    super.key,
    required this.groupId,
    required this.eventId,
    this.preSelectedMemberId,
  });

  @override
  ConsumerState<SettleUpScreen> createState() => _SettleUpScreenState();
}

class _SettleUpScreenState extends ConsumerState<SettleUpScreen> {
  final Map<int, GlobalKey> _tileKeys = {};

  @override
  Widget build(BuildContext context) {
    final eventRef = (groupId: widget.groupId, eventId: widget.eventId);
    final eventAsync = ref.watch(eventDetailProvider(eventRef));
    // #261: settlements are denominated in the owning group's currency. Gate
    // the screen on the group resolving — never default to 'OMR' (a non-OMR
    // group would mis-scale 10× and be rules-rejected). Three branches mirror
    // group_settle_up_screen.dart: loading / null group / data.
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));

    if (eventAsync.isLoading || groupAsync.isLoading) {
      return Scaffold(
        backgroundColor: context.colors.scaffoldBackground,
        body: SafeArea(
          child: Column(
            children: [
              _SettleUpTopBar(groupId: widget.groupId, eventId: widget.eventId),
              Expanded(child: SkeletonLoader.groupList()),
            ],
          ),
        ),
      );
    }

    final event = eventAsync.valueOrNull;

    if (event == null) {
      return Scaffold(
        backgroundColor: context.colors.scaffoldBackground,
        body: SafeArea(
          child: Column(
            children: [
              _SettleUpTopBar(groupId: widget.groupId, eventId: widget.eventId),
              Expanded(
                child: EmptyStateView(
                  icon: Iconsax.warning_2,
                  title: context.l10n.settleUpEventMissingTitle,
                  message: context.l10n.settleUpEventMissingMessage,
                  actionLabel: context.l10n.commonGoHome,
                  onAction: () => context.go('/home'),
                  iconColor: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // #261: a deleted/missing group emits null — show an error rather than
    // folding it into the loader (which would spin forever).
    final group = groupAsync.valueOrNull;
    if (group == null) {
      return Scaffold(
        backgroundColor: context.colors.scaffoldBackground,
        body: SafeArea(
          child: Column(
            children: [
              _SettleUpTopBar(groupId: widget.groupId, eventId: widget.eventId),
              Expanded(
                child: EmptyStateView(
                  icon: Iconsax.warning_2,
                  title: context.l10n.settleUpEventMissingTitle,
                  message: context.l10n.settleUpEventMissingMessage,
                  actionLabel: context.l10n.commonGoHome,
                  onAction: () => context.go('/home'),
                  iconColor: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final groupCurrency = group.currency;

    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));
    final currentUid = ref.watch(currentUserIdProvider);
    final groupMembers =
        ref.watch(groupMembersProvider(widget.groupId)).valueOrNull ?? [];

    // #249: member-id sets for the per-event balance universe. The universe
    // itself (and the name maps + participants derived from it) is built inside
    // the data callback below, where expenses/settlements are available.
    final allMemberIds = groupMembers.map((m) => m.userId).toSet();
    final liveMemberIds =
        groupMembers.where((m) => !m.isTombstone).map((m) => m.userId).toSet();

    return Scaffold(
      key: LedgerKeys.settleUpScreen,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            _SettleUpTopBar(groupId: widget.groupId, eventId: widget.eventId),
            const OfflineBanner(),
            Expanded(
              child: expensesAsync.when(
                data: (expenses) {
                  final settlements = settlementsAsync.valueOrNull ?? const [];

                  // #249: fold departed-member split recipients into the
                  // balance universe so settle-up suggestions conserve. The
                  // name maps MUST span the universe — OUTBOUND: userRawNames
                  // feeds the settlement write path.
                  final universe = eventBalanceUniverse(
                    event: event,
                    expenses: expenses,
                    settlements: settlements,
                    allMemberIds: allMemberIds,
                    liveMemberIds: liveMemberIds,
                  );
                  final displaysByUid = <String, MemberDisplay>{
                    for (final id in universe)
                      id: MemberNameResolver.resolveEventScoped(
                        uid: id,
                        event: event,
                        members: groupMembers,
                      ),
                  };
                  // Render-only disambiguation (#196); raw names stay raw —
                  // they feed the settlement write path.
                  final userDisplayNames = MemberNameResolver.disambiguate(
                    displaysByUid,
                  );
                  final userRawNames = <String, String>{
                    for (final entry in displaysByUid.entries)
                      entry.key: entry.value.rawName,
                  };
                  final participants = universe.map((id) {
                    return Participant(
                      id: id,
                      tripId: event.id,
                      role: ParticipantRole.member,
                      joinedAt: event.createdAt,
                      displayName:
                          userDisplayNames[id] ??
                          MemberNameResolver.format(displaysByUid[id]!),
                    );
                  }).toList();

                  final bucketed = BalanceCalculator.calculateBalances(
                    expenses: expenses,
                    settlements: settlements,
                    participants: participants,
                  );

                  // #382 PR-1: one section per currency bucket, the optimizer
                  // run per bucket (no cross-currency netting, ever). No money
                  // yet → one empty group-currency bucket (zero summary card).
                  // The recorded settlement carries the BUCKET currency.
                  final buckets = <SettleBucket>[
                    for (final c in sortedGccFirst(bucketed.keys))
                      (
                        currency: c,
                        balances: bucketed[c]!,
                        optimalSettlements:
                            BalanceCalculator.calculateOptimalSettlements(
                              balances: bucketed[c]!,
                              userNames: userDisplayNames,
                            ),
                      ),
                    if (bucketed.isEmpty)
                      (
                        currency: groupCurrency,
                        balances: const <UserBalance>[],
                        optimalSettlements: const <Map<String, dynamic>>[],
                      ),
                  ];

                  return SettleUpPageBody(
                    subjectName: event.name,
                    buckets: buckets,
                    rawNames: userRawNames,
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
                          required currency,
                        }) => _showRecordPaymentSheet(
                          context,
                          settlement: settlement,
                          fromRawName: fromRawName,
                          toRawName: toRawName,
                          fromUserId: fromUserId,
                          toUserId: toUserId,
                          suggestedAmount: suggestedAmount,
                          currency: currency,
                        ),
                  );
                },
                loading: SkeletonLoader.groupList,
                error: (e, _) => Center(
                  child: Padding(
                    padding: EdgeInsets.all(context.spacing.space24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Iconsax.warning_2,
                          size: 40,
                          color: context.colors.error,
                        ),
                        SizedBox(height: context.spacing.space16),
                        Text(
                          context.l10n.settleUpCouldNotLoadBalances,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: context.colors.textPrimary,
                          ),
                        ),
                        SizedBox(height: context.spacing.space8),
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(eventExpensesProvider(eventRef)),
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

  Future<void> _showRecordPaymentSheet(
    BuildContext context, {
    required Map<String, dynamic> settlement,
    required String fromRawName,
    required String toRawName,
    required String fromUserId,
    required String toUserId,
    required Decimal suggestedAmount,
    required String currency,
  }) async {
    final fromDisplayName =
        settlement['fromUserName'] as String? ?? fromRawName;
    final toDisplayName = settlement['toUserName'] as String? ?? toRawName;
    // #282: the recipient (creditor) is recording a payment received.
    final isReceiving = ref.read(currentUserIdProvider) == toUserId;

    final result = await showRecordPaymentSheet(
      context,
      currency: currency,
      fromName: fromDisplayName,
      toName: toDisplayName,
      suggestedAmount: suggestedAmount,
      isReceiving: isReceiving,
    );

    if (!context.mounted || result == null) return;

    final editedAmount =
        Decimal.tryParse(normalizeLocalizedDecimalInput(result.amount)) ??
        suggestedAmount;
    final noteText = result.note.isEmpty ? null : result.note;

    if (editedAmount <= Decimal.zero) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settleUpAmountGreaterThanZero)),
      );
      return;
    }
    if (editedAmount > suggestedAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.settleUpAmountExceedsOutstanding(
              AppFormatters.formatCurrency(suggestedAmount, currency),
            ),
          ),
        ),
      );
      return;
    }

    await _recordSettlement(
      context,
      fromUserId: fromUserId,
      toUserId: toUserId,
      fromName: fromRawName,
      toName: toRawName,
      amount: editedAmount,
      note: noteText,
      currency: currency,
    );
  }

  Future<void> _recordSettlement(
    BuildContext context, {
    required String fromUserId,
    required String toUserId,
    required String fromName,
    required String toName,
    required Decimal amount,
    required String currency,
    String? note,
  }) async {
    HapticService.success();
    final currentUid = ref.read(currentUserIdProvider);
    if (currentUid == null || currentUid.isEmpty) {
      throw StateError(
        'Cannot record settlement without an authenticated user.',
      );
    }
    // #104/#412: capture before the await so post-write effects survive a
    // disposal during the (now bounded) wait.
    final ledgerRevision = ref.read(ledgerRevisionProvider.notifier);
    final connectivity = ref.read(connectivityProvider.notifier);
    final connectivityStatus = ref.read(connectivityProvider);
    try {
      // #412: never gate the UI on the raw server-ack future — offline it
      // stays pending until reconnect. Race it; queued means the SDK replays.
      final outcome = await awaitServerAck(
        ref
            .read(settlementServiceProvider)
            .addSettlement(
              groupId: widget.groupId,
              eventId: widget.eventId,
              payerParticipantId: fromUserId,
              recipientParticipantId: toUserId,
              payerName: fromName,
              recipientName: toName,
              amount: amount,
              currency: currency,
              createdBy: currentUid,
              note: note,
            ),
        skipWait: connectivityStatus != ConnectivityStatus.online,
      );

      ledgerRevision.state++; // #104: refresh home balance
      if (outcome == WriteAck.acked) {
        connectivity.noteLocalWrite(); // #357
      } else {
        connectivity.noteQueuedWrite(); // #412: queued — force "will sync"
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              outcome == WriteAck.acked
                  ? context.l10n.settleUpRecorded
                  : context.l10n.settleUpRecordedWillSync,
            ),
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
            content: Text(
              settlementWriteErrorMessage(
                context.l10n,
                classifySettlementWriteError(e),
              ),
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

class _SettleUpTopBar extends StatelessWidget {
  const _SettleUpTopBar({required this.groupId, required this.eventId});

  final String groupId;
  final String eventId;

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
              alignment: AlignmentDirectional.centerStart,
              child: IconButton(
                tooltip: context.l10n.commonBack,
                icon: const DirectionalIcon(Iconsax.arrow_left_2, size: 20),
                color: context.colors.textPrimary,
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/group/$groupId/event/$eventId/ledger');
                  }
                },
              ),
            ),
            Text(
              context.l10n.settleUpTitle,
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
