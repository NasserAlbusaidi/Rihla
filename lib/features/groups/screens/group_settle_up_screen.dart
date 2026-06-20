import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import 'package:go_router/go_router.dart';
import '../../../core/config/firebase_config.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/localized_decimal_input.dart';
import '../../../core/utils/settlement_write_error.dart';
import '../../../core/utils/write_ack.dart';
import '../../../shared/widgets/directional_icon.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../keys/group_keys.dart';
import '../../events/models/event_model.dart';
import '../../events/models/event_type_config.dart';
import '../../../core/constants/supported_currencies.dart';
import '../../events/providers/event_provider.dart';
import '../../ledger/models/expense_model.dart';
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
      return Scaffold(body: SafeArea(child: SkeletonLoader.groupList()));
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
                  // #382 PR-1: one section per currency bucket, the optimizer
                  // run per bucket (no cross-currency netting, ever). No money
                  // yet → one empty group-currency bucket (zero summary card).
                  // The recorded settlement carries the BUCKET currency.
                  final buckets = <SettleBucket>[
                    for (final c in sortedGccFirst(balancesData.balances.keys))
                      (
                        currency: c,
                        balances: balancesData.balances[c]!,
                        optimalSettlements:
                            BalanceCalculator.calculateOptimalSettlements(
                              balances: balancesData.balances[c]!,
                              userNames: balancesData.memberNames,
                            ),
                      ),
                    if (balancesData.balances.isEmpty)
                      (
                        currency: group.currency,
                        balances: const <UserBalance>[],
                        optimalSettlements: const <Map<String, dynamic>>[],
                      ),
                  ];

                  final body = SettleUpPageBody(
                    subjectName: group.name,
                    buckets: buckets,
                    rawNames: balancesData.memberRawNames,
                    settlementsAsync: settlementsAsync,
                    currentUid: currentUid,
                    tileKeys: _tileKeys,
                    // #595: group settlement-create only requires isGroupMember,
                    // and every viewer of this screen is already a member (read
                    // is member-gated) — so any member may record any transfer.
                    canRecord: true,
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
                          group: group,
                          settlement: settlement,
                          fromRawName: fromRawName,
                          toRawName: toRawName,
                          fromUserId: fromUserId,
                          toUserId: toUserId,
                          suggestedAmount: suggestedAmount,
                          currency: currency,
                        ),
                    buildBreakdown: (fromUserId, toUserId, currency) =>
                        _buildPerEventBreakdown(
                          fromUserId,
                          toUserId,
                          currency,
                          balancesData,
                          eventNameMap,
                        ),
                    onRecordStepped: (steps) =>
                        _runSteppedSettle(context, group: group, steps: steps),
                    // #283: correct a recorded payment by recording its
                    // offsetting reverse (swap payer↔recipient, same amount +
                    // currency) through the group write path. logActivity:false
                    // — a reversal must not surface as a fresh feed payment.
                    onCorrect: (s) => _recordSettlement(
                      context,
                      group: group,
                      fromUserId: s.recipientParticipantId ?? '',
                      toUserId: s.payerParticipantId ?? '',
                      fromName: s.recipientName ?? '',
                      toName: s.payerName ?? '',
                      amount: s.amount,
                      currency: s.currency,
                      note: context.l10n.settleUpCorrectionNote,
                      logActivity: false,
                    ),
                  );

                  if (failedEventIds.isEmpty) return body;
                  return Column(
                    children: [
                      Container(
                        width: double.infinity,
                        margin: EdgeInsetsDirectional.fromSTEB(
                          context.spacing.space16,
                          context.spacing.space12,
                          context.spacing.space16,
                          0,
                        ),
                        padding: EdgeInsets.all(context.spacing.space12),
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
                            SizedBox(width: context.spacing.space8),
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

  /// Per-event attribution for the [currency] bucket whose tile invoked it
  /// (#382 PR-3): the breakdown is per-currency, so the pairwise
  /// min-attribution below is per-bucket by construction — no cross-currency
  /// netting, ever.
  Map<String, Decimal> _buildPerEventBreakdown(
    String fromUserId,
    String toUserId,
    String currency,
    GroupBalances balancesData,
    Map<String, ({String name, EventType type, DateTime date})> eventNameMap,
  ) {
    final result = <String, Decimal>{};
    final fromBreakdown = balancesData.perEventBreakdown[fromUserId] ?? {};
    final toBreakdown = balancesData.perEventBreakdown[toUserId] ?? {};

    final allEventIds = {...fromBreakdown.keys, ...toBreakdown.keys};

    for (final eventId in allEventIds) {
      final fromNet = fromBreakdown[eventId]?[currency] ?? Decimal.zero;
      final toNet = toBreakdown[eventId]?[currency] ?? Decimal.zero;

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

  /// Walks a stepped multi-currency settlement (#382 PR-5 D2): one record sheet
  /// per [steps] bucket, each its own independent append-only write. Per-step
  /// success snackbars are suppressed; ONE final summary snackbar reports the
  /// outcome (L4). Any cancel/validation-reject/write-error STOPS the walk —
  /// steps already recorded stay (append-only); re-entry recomputes the
  /// remaining buckets from live streams (L3/L5). No `ledgerRevision` bump —
  /// group settlements are live-watched (L6), unlike the event walk.
  Future<void> _runSteppedSettle(
    BuildContext context, {
    required Group group,
    required List<SettleStepRequest> steps,
  }) async {
    if (steps.isEmpty) return;
    // #104/#412: capture the connectivity notifier ONCE before the loop so the
    // per-step post-write effects survive a disposal mid-walk (the screen could
    // rebuild between steps). The walk dies with the screen, so a captured list
    // is never re-run after death (L5).
    final connectivity = ref.read(connectivityProvider.notifier);
    // Capture context-derived handles ONCE before the loop's awaits (same
    // #104/#412 discipline): the final summary snackbar uses them after the
    // walk without re-reading a possibly-disposed context.
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final successColor = context.colors.success;

    var recorded = 0;
    var anyQueued = false;
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final outcome = await _showRecordPaymentSheet(
        context,
        group: group,
        settlement: step.settlement,
        fromRawName: step.fromRawName,
        toRawName: step.toRawName,
        fromUserId: step.fromUserId,
        toUserId: step.toUserId,
        suggestedAmount: step.suggestedAmount,
        currency: step.currency,
        stepLabel: l10n.settleUpStepIndicator(i + 1, steps.length),
        showSuccessSnackbar: false,
        connectivity: connectivity,
      );
      if (outcome.kind != _StepOutcomeKind.recorded) break; // L3: stop the walk
      recorded++;
      if (outcome.ack == WriteAck.queued) anyQueued = true;
    }

    if (recorded == 0) return; // cancel at step 1 → no final snackbar
    final allRecorded = recorded == steps.length;
    final message = allRecorded
        ? (anyQueued
              ? l10n.settleUpSteppedRecordedAllWillSync(recorded)
              : l10n.settleUpSteppedRecordedAll(recorded))
        : (anyQueued
              ? l10n.settleUpSteppedRecordedPartialWillSync(
                  recorded,
                  steps.length,
                )
              : l10n.settleUpSteppedRecordedPartial(recorded, steps.length));
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: successColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  /// Drives one record sheet → validate → write. Returns the per-step
  /// [_StepOutcome] so the stepped walk can decide whether to continue (L3).
  /// On the single-tile path [stepLabel] is null and [showSuccessSnackbar] is
  /// true — byte-identical to the pre-walk behavior. During a walk the caller
  /// passes the captured [connectivity] notifier; the tile path leaves it null
  /// and it is read here.
  Future<_StepOutcome> _showRecordPaymentSheet(
    BuildContext context, {
    required Group group,
    required Map<String, dynamic> settlement,
    required String fromRawName,
    required String toRawName,
    required String fromUserId,
    required String toUserId,
    required Decimal suggestedAmount,
    // #382 PR-1: the BUCKET currency the suggestion was computed in — the
    // write must carry it (== group.currency for all prod data; a foreign
    // legacy/forged bucket is rules-refused, the correct outcome until PR-6).
    required String currency,
    String? stepLabel,
    bool showSuccessSnackbar = true,
    ConnectivityNotifier? connectivity,
  }) async {
    final fromDisplayName =
        settlement['fromUserName'] as String? ?? fromRawName;
    final toDisplayName = settlement['toUserName'] as String? ?? toRawName;
    // #282/#595: frame by the writer's relationship to this transfer — payer
    // ("paid"), recipient ("received"), or neither (a member recording on the
    // group's behalf). A null uid (shouldn't reach here) falls to neutral.
    final currentUid = ref.read(currentUserIdProvider);
    final perspective = currentUid == fromUserId
        ? RecordPaymentPerspective.paying
        : currentUid == toUserId
        ? RecordPaymentPerspective.receiving
        : RecordPaymentPerspective.recording;
    final result = await showRecordPaymentSheet(
      context,
      currency: currency,
      fromName: fromDisplayName,
      toName: toDisplayName,
      suggestedAmount: suggestedAmount,
      perspective: perspective,
      stepLabel: stepLabel,
    );

    if (!context.mounted || result == null) {
      return const _StepOutcome(_StepOutcomeKind.cancelled);
    }

    final editedAmount =
        Decimal.tryParse(normalizeLocalizedDecimalInput(result.amount)) ??
        suggestedAmount;
    final noteText = result.note.isEmpty ? null : result.note;

    if (editedAmount <= Decimal.zero) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.settleUpAmountGreaterThanZero),
        ),
      );
      return const _StepOutcome(_StepOutcomeKind.invalid);
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
      return const _StepOutcome(_StepOutcomeKind.invalid);
    }

    return _recordSettlement(
      context,
      group: group,
      fromUserId: fromUserId,
      toUserId: toUserId,
      fromName: fromRawName,
      toName: toRawName,
      amount: editedAmount,
      note: noteText,
      currency: currency,
      showSuccessSnackbar: showSuccessSnackbar,
      connectivity: connectivity,
    );
  }

  Future<_StepOutcome> _recordSettlement(
    BuildContext context, {
    required Group group,
    required String fromUserId,
    required String toUserId,
    required String fromName,
    required String toName,
    required Decimal amount,
    required String currency,
    String? note,
    bool showSuccessSnackbar = true,
    ConnectivityNotifier? connectivity,
    // #283: corrections record an offsetting reverse settlement but must NOT
    // emit a `group_settlement` activity entry — the type-rendered feed would
    // show a reversal as a fresh payment. The correction stays auditable via
    // settlement history + balances.
    bool logActivity = true,
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

      // #104/#412: capture before the await so post-write effects survive a
      // disposal during the (now bounded) wait. NO ledgerRevision bump here —
      // group settlements are live-watched (groupSettlementsProvider) (L6). The
      // stepped walk passes the notifier it captured once before its loop; the
      // single-tile path reads it here.
      final ConnectivityNotifier connectivityNotifier =
          connectivity ?? ref.read(connectivityProvider.notifier);
      final connectivityStatus = ref.read(connectivityProvider);

      // #412: never gate the UI on the raw server-ack future — offline it
      // stays pending until reconnect. Race it; queued means the SDK replays.
      final outcome = await awaitServerAck(
        ref
            .read(groupSettlementServiceProvider)
            .addGroupSettlement(
              groupId: widget.groupId,
              payerParticipantId: fromUserId,
              recipientParticipantId: toUserId,
              amount: amount,
              currency: currency,
              note: note,
              payerName: fromName,
              recipientName: toName,
              createdBy: currentUid,
            ),
        skipWait: connectivityStatus != ConnectivityStatus.online,
      );

      if (outcome == WriteAck.acked) {
        connectivityNotifier.noteLocalWrite(); // #357
      } else {
        connectivityNotifier.noteQueuedWrite(); // #412: queued — force "will sync"
      }

      // #282: name the OTHER party relative to the actor. When the creditor
      // (recipient) records the payment, the counterparty is the payer — not
      // `toName`, which would otherwise read "Alice settled … with Alice".
      if (logActivity) {
        final counterpartyName = currentUid == toUserId ? fromName : toName;
        ref
            .read(groupActivityServiceProvider)
            .logGroupEvent(
              groupId: widget.groupId,
              type: 'group_settlement',
              actorId: currentUid,
              actorName: actorName,
              description:
                  'settled ${AppFormatters.formatCurrency(amount, currency)} with $counterpartyName',
              metadata: {
                'amount': amount.toString(),
                'recipientId': toUserId,
                'currency': currency,
              },
            );
      }

      if (showSuccessSnackbar && context.mounted) {
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
      return _StepOutcome(_StepOutcomeKind.recorded, ack: outcome);
    } catch (e) {
      // L4: per-step ERROR snackbar stays loud even during a walk; the walk
      // then stops (the caller breaks on a non-recorded outcome).
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
      return const _StepOutcome(_StepOutcomeKind.failed);
    }
  }
}

/// Outcome of one stepped-settle step (#382 PR-5). Only [recorded] carries the
/// queued/acked [ack]; the walk continues only on [recorded] (L3).
enum _StepOutcomeKind { recorded, cancelled, invalid, failed }

class _StepOutcome {
  const _StepOutcome(this.kind, {this.ack});

  final _StepOutcomeKind kind;
  final WriteAck? ack;
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
              alignment: AlignmentDirectional.centerStart,
              child: IconButton(
                tooltip: l10n.commonBack,
                icon: const DirectionalIcon(Iconsax.arrow_left_2, size: 20),
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
