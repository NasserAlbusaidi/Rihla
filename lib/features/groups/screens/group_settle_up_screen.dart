import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:uuid/uuid.dart';

import 'package:go_router/go_router.dart';
import '../../../core/config/firebase_config.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/localized_decimal_input.dart';
import '../../../core/utils/settle_notify.dart';
import '../../../core/utils/settlement_write_error.dart';
import '../../../core/utils/share_helper.dart';
import '../../../core/utils/whatsapp_share.dart';
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
import '../../ledger/models/settlement_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../ledger/utils/correction_note.dart';
import '../../ledger/widgets/pre_settlement_review_sheet.dart';
import '../models/group_model.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_presettle_review_provider.dart';
import '../providers/group_provider.dart';
import '../widgets/record_payment_sheet.dart';
import '../widgets/settle_notify_sheet.dart';
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

  /// #753: logical settle-up ids whose atomic correction is mid-flight. The
  /// synchronous add-before-await guards against a double-tap reversing the same
  /// settle-up twice in the window before the reverse stream emits.
  final Set<String> _correctingSettleUpIds = <String>{};

  /// #204: the pre-settlement review sheet fires once per screen entry —
  /// same one-shot contract as the event-level settle-up.
  bool _reviewSheetShown = false;

  void _maybeShowReviewSheet(
    BuildContext context,
    GroupPreSettleReview review,
  ) {
    if (_reviewSheetShown || !review.resolved || review.flags.isEmpty) return;
    _reviewSheetShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showPreSettlementReviewSheet(
        context,
        flags: review.flags,
        // Group scope: each row deep-links to its OWN event's editor
        // (expense.tripId is the Firestore eventId). No review-all CTA —
        // there is no group-wide ledger surface (#422 deferred).
        onTapExpense: (e) => context.push(
          '/group/${widget.groupId}/event/${e.tripId}/ledger/edit/${e.id}',
        ),
      );
    });
  }

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
    // #752: the group history UNIONS group-settlement docs with the
    // groupSettleUpId-tagged EVENT settlements of decomposed settle-ups — else a
    // single-event settle-up (0 group docs) would vanish from group history.
    final taggedEventSettlements = ref.watch(
      groupTaggedEventSettlementsProvider(widget.groupId),
    );
    final settlementsAsync = ref
        .watch(groupSettlementsProvider(widget.groupId))
        .whenData(
          (groupSettlements) =>
              <Settlement>[...groupSettlements, ...taggedEventSettlements]
                ..sort((a, b) => b.settledAt.compareTo(a.settledAt)),
        );
    // #244: events whose money read hard-errored were silently zeroed in the
    // balance above; warn that this settle-up balance may be incomplete rather
    // than present a partial sum as authoritative.
    final failedEventIds = ref.watch(
      groupFailedEventIdsProvider(widget.groupId),
    );
    // #204: review-worthy expenses across the whole settle basis (zero new
    // listeners — sibling of the balance provider).
    final preSettleReview = ref.watch(
      groupPreSettleReviewProvider(widget.groupId),
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
    // #752: the deterministic event order shared by the displayed breakdown and
    // the decomposed write — they MUST use the same order so displayed rows ==
    // written rows (the allocator's per-event split is cap-exhaustion-order
    // dependent; totals/residual are order-invariant).
    final eventOrder = [
      for (final e in eventsAsync.valueOrNull ?? <Event>[]) e.id,
    ];

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
                  // #204: surface review-worthy expenses (from ANY event in
                  // the settle basis) once, before the user settles. Fired
                  // from the data branch so the sheet never covers a skeleton.
                  _maybeShowReviewSheet(context, preSettleReview);

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
                    scope: SettleScope.group,
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
                          balancesData: balancesData,
                          eventOrder: eventOrder,
                          settlement: settlement,
                          fromRawName: fromRawName,
                          toRawName: toRawName,
                          fromUserId: fromUserId,
                          toUserId: toUserId,
                          suggestedAmount: suggestedAmount,
                          currency: currency,
                        ),
                    buildBreakdown:
                        (fromUserId, toUserId, currency, suggestedAmount) =>
                            _buildPerEventBreakdown(
                              fromUserId,
                              toUserId,
                              currency,
                              suggestedAmount,
                              eventOrder,
                              balancesData,
                              eventNameMap,
                            ),
                    onRecordStepped: (steps) => _runSteppedSettle(
                      context,
                      group: group,
                      balancesData: balancesData,
                      eventOrder: eventOrder,
                      steps: steps,
                    ),
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
                    // #753: correct a DECOMPOSED settle-up — reverse all its
                    // tagged docs atomically. Wiring this also switches the
                    // history regroup on (the event screen leaves it null).
                    onCorrectLogical: (groupSettleUpId) =>
                        _correctLogicalSettleUp(
                          context,
                          group: group,
                          groupSettleUpId: groupSettleUpId,
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
  /// (#382 PR-3): the breakdown is per-currency, so the decomposition below is
  /// per-bucket by construction — no cross-currency netting, ever.
  ///
  /// #752: this is the SAME [BalanceCalculator.decomposeGroupSettlement] call,
  /// with the SAME [eventOrder], that the write uses — so the displayed rows
  /// equal the written settlements (WYSIWYG). The allocator caps the total at
  /// [suggestedAmount], fixing the old over-display (offsetting cross-event nets
  /// once showed the raw per-event overlap, exceeding the actual transfer). The
  /// cross-event remainder surfaces as one "Across events" residual row.
  Map<String, Decimal> _buildPerEventBreakdown(
    String fromUserId,
    String toUserId,
    String currency,
    Decimal suggestedAmount,
    List<String> eventOrder,
    GroupBalances balancesData,
    Map<String, ({String name, EventType type, DateTime date})> eventNameMap,
  ) {
    final decomposition = BalanceCalculator.decomposeGroupSettlement(
      payerPerEventNet:
          balancesData.perEventBreakdown[fromUserId] ??
          const <String, Map<String, Decimal>>{},
      recipientPerEventNet:
          balancesData.perEventBreakdown[toUserId] ??
          const <String, Map<String, Decimal>>{},
      currency: currency,
      amount: suggestedAmount,
      eventOrder: eventOrder,
    );

    final result = <String, Decimal>{};
    for (final eventId in eventOrder) {
      final slice = decomposition.perEvent[eventId];
      if (slice != null && slice > Decimal.zero) {
        result[_buildEventLabel(eventId, eventNameMap)] = slice;
      }
    }
    if (decomposition.residual > Decimal.zero) {
      result[context.l10n.groupSettleUpAcrossEventsLabel] =
          decomposition.residual;
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
    required GroupBalances balancesData,
    required List<String> eventOrder,
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
        balancesData: balancesData,
        eventOrder: eventOrder,
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
    required GroupBalances balancesData,
    required List<String> eventOrder,
    required Map<String, dynamic> settlement,
    required String fromRawName,
    required String toRawName,
    required String fromUserId,
    required String toUserId,
    required Decimal suggestedAmount,
    // #382: the BUCKET currency the suggestion was computed in — the write
    // must carry it. Rules require a supported currency code; balances remain
    // bucketed with no cross-currency netting.
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

    final parsedAmount = Decimal.tryParse(
      normalizeLocalizedDecimalInput(result.amount),
    );
    // An empty field means "settle the full suggested amount". A NON-empty but
    // unparseable value (e.g. ambiguous European 1.234,56 — #530) must be
    // rejected, never silently coerced into the suggested amount.
    if (parsedAmount == null && result.amount.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settleUpEnterValidAmount)),
      );
      return const _StepOutcome(_StepOutcomeKind.invalid);
    }
    final editedAmount = parsedAmount ?? suggestedAmount;
    final noteText = result.note.isEmpty ? null : result.note;

    if (editedAmount <= Decimal.zero) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settleUpAmountGreaterThanZero)),
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

    // #719 (Scope 6 of #200): `suggestedAmount` + `balancesData` were captured
    // when the tile was tapped; the record sheet may have been open long enough
    // for another device to pay or add an expense. Re-read the LIVE balances and
    // revalidate the directed-pair outstanding before writing. If it dropped
    // below `editedAmount`, abort and force review-again rather than silently
    // overpaying a stale debt. Offline / balances-unavailable → behave exactly as
    // before (use the captured snapshot); this is a safety add-on, never a new
    // offline blocker. When fresh data IS available we also decompose from it, so
    // the write reflects current per-event nets — note the tile's last-rendered
    // breakdown may then differ from the fresh write (aggregate stays capped at
    // `editedAmount`; `eventOrder` is unchanged so the WYSIWYG order contract holds).
    var writeBalances = balancesData;
    final fresh = ref.read(groupBalancesProvider(widget.groupId)).valueOrNull;
    if (fresh != null) {
      final freshOutstanding = BalanceCalculator.outstandingForPair(
        bucket: fresh.balances[currency] ?? const <UserBalance>[],
        fromUserId: fromUserId,
        toUserId: toUserId,
      );
      if (editedAmount > freshOutstanding) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.settleUpBalanceChangedReviewAgain(
                  AppFormatters.formatCurrency(freshOutstanding, currency),
                ),
              ),
              duration: const Duration(seconds: 6),
            ),
          );
        }
        return const _StepOutcome(_StepOutcomeKind.invalid);
      }
      writeBalances = fresh;
    }

    final outcome = await _recordDecomposedSettlement(
      context,
      group: group,
      balancesData: writeBalances,
      eventOrder: eventOrder,
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

    // #367: after the DEBTOR records a group-level payment THEY made on the
    // single-tile path, offer to let the creditor know via WhatsApp. Same gate
    // as the event screen: single-tile (stepLabel == null), paying perspective
    // (creditor-records #282 / on-behalf #595 never nudge), clean record. A
    // GROUP settle spans events, so the message names only the group.
    if (stepLabel == null &&
        currentUid == fromUserId &&
        outcome.kind == _StepOutcomeKind.recorded &&
        context.mounted) {
      await _offerWhatsAppNotify(
        context,
        // Plain raw name for the greeting — the app-internal disambiguator
        // suffix doesn't belong in a message sent TO that person.
        recipientName: toRawName,
        amount: editedAmount,
        currency: currency,
        groupName: group.name,
      );
    }
    return outcome;
  }

  /// #367: present the post-record nudge and, if accepted, open WhatsApp
  /// prefilled with the past-tense group-scoped message. Numberless; falls back
  /// to the OS share sheet when WhatsApp isn't installed.
  Future<void> _offerWhatsAppNotify(
    BuildContext context, {
    required String recipientName,
    required Decimal amount,
    required String currency,
    required String groupName,
  }) async {
    final message = settleNotifyMessage(
      l10n: context.l10n,
      recipientName: recipientName,
      amountDisplay: AppFormatters.formatCurrency(amount, currency),
      groupName: groupName,
    );
    final wantsNotify = await showSettleNotifySheet(
      context,
      recipientName: recipientName,
      message: message,
    );
    if (!wantsNotify || !context.mounted) return;
    await shareViaWhatsApp(
      message,
      fallback: () => shareText(context, message),
    );
  }

  /// #752: record a group transfer by DECOMPOSING it into per-event settlement
  /// writes (which the event ledgers read) + one residual group settlement —
  /// instead of a single group settlement that only moved the aggregate. The
  /// pure allocator ([BalanceCalculator.decomposeGroupSettlement]) is the SSOT
  /// shared with the displayed breakdown (it is called with the SAME
  /// [eventOrder]). Returns the aggregate [_StepOutcome] so the stepped walk can
  /// decide whether to continue.
  ///
  /// Falls back to a single [GroupSettlementService.addGroupSettlement] (today's
  /// atomic path) when the transfer can't be safely decomposed:
  ///  - either party is NOT a live group member (`group.memberIds`): the
  ///    residual group write requires both parties in `memberIds`, but event
  ///    writes only require event participation, so a departed party (#249)
  ///    would partial-persist event docs then hit permission-denied on the
  ///    residual. The single group write fails atomically instead (today's
  ///    behavior — you already cannot settle a departed member at the group
  ///    level). Read from `group.memberIds` — the EXACT set the residual rule
  ///    checks — not a member-subcollection stream that can diverge.
  ///  - no per-event attribution at all (pure cross-event / no shared event):
  ///    identical to today's single group settlement.
  ///
  /// Once-semantics: the N event writes + residual run as RAW writes; the
  /// activity log and success/queued snackbar fire EXACTLY ONCE after the walk
  /// (amount = A), and `ledgerRevisionProvider` is bumped per successful event
  /// write (the home one-shot reads event settlements; bumping per-write keeps
  /// home fresh even on a partial-failure walk).
  Future<_StepOutcome> _recordDecomposedSettlement(
    BuildContext context, {
    required Group group,
    required GroupBalances balancesData,
    required List<String> eventOrder,
    required String fromUserId,
    required String toUserId,
    required String fromName,
    required String toName,
    required Decimal amount,
    required String currency,
    String? note,
    bool showSuccessSnackbar = true,
    ConnectivityNotifier? connectivity,
  }) async {
    final decomposition = BalanceCalculator.decomposeGroupSettlement(
      payerPerEventNet:
          balancesData.perEventBreakdown[fromUserId] ??
          const <String, Map<String, Decimal>>{},
      recipientPerEventNet:
          balancesData.perEventBreakdown[toUserId] ??
          const <String, Map<String, Decimal>>{},
      currency: currency,
      amount: amount,
      eventOrder: eventOrder,
    );
    final bothLiveMembers =
        group.memberIds.contains(fromUserId) &&
        group.memberIds.contains(toUserId);
    // Fall back to today's atomic single group write (no decompose).
    if (!bothLiveMembers || decomposition.perEvent.isEmpty) {
      return _recordSettlement(
        context,
        group: group,
        fromUserId: fromUserId,
        toUserId: toUserId,
        fromName: fromName,
        toName: toName,
        amount: amount,
        currency: currency,
        note: note,
        showSuccessSnackbar: showSuccessSnackbar,
        connectivity: connectivity,
      );
    }

    final groupSettleUpId = const Uuid().v4();
    final ConnectivityNotifier connectivityNotifier =
        connectivity ?? ref.read(connectivityProvider.notifier);
    final skipWait =
        ref.read(connectivityProvider) != ConnectivityStatus.online;

    try {
      String actorName;
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

      final eventService = ref.read(settlementServiceProvider);
      final ledgerRevision = ref.read(ledgerRevisionProvider.notifier);
      var anyQueued = false;

      // Events first, residual last — every intermediate state stays consistent
      // (event ledgers + aggregate move together). A failed write throws → the
      // catch stops the walk; recorded rows persist (append-only); re-entry
      // recomputes the remainder from the live streams.
      for (final eventId in eventOrder) {
        final slice = decomposition.perEvent[eventId];
        if (slice == null) continue;
        final ack = await awaitServerAck(
          eventService.addSettlement(
            groupId: widget.groupId,
            eventId: eventId,
            payerParticipantId: fromUserId,
            recipientParticipantId: toUserId,
            amount: slice,
            currency: currency,
            createdBy: currentUid,
            payerName: fromName,
            recipientName: toName,
            note: note,
            groupSettleUpId: groupSettleUpId,
          ),
          skipWait: skipWait,
        );
        if (ack == WriteAck.queued) anyQueued = true;
        // #752/#104: the home one-shot reads EVENT settlements — bump per
        // successful event write so home stays fresh even on a partial walk.
        ledgerRevision.state++;
      }

      if (decomposition.residual > Decimal.zero) {
        final ack = await awaitServerAck(
          ref
              .read(groupSettlementServiceProvider)
              .addGroupSettlement(
                groupId: widget.groupId,
                payerParticipantId: fromUserId,
                recipientParticipantId: toUserId,
                amount: decomposition.residual,
                currency: currency,
                note: note,
                payerName: fromName,
                recipientName: toName,
                createdBy: currentUid,
                groupSettleUpId: groupSettleUpId,
              ),
          skipWait: skipWait,
        );
        if (ack == WriteAck.queued) anyQueued = true;
      }

      // Connectivity note ONCE after the walk (#357/#412).
      if (anyQueued) {
        connectivityNotifier.noteQueuedWrite(groupId: widget.groupId);
      } else {
        connectivityNotifier.noteLocalWrite(groupId: widget.groupId);
      }

      // Activity log ONCE for the whole logical settle-up, amount = A (#282:
      // name the OTHER party relative to the actor).
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

      if (showSuccessSnackbar && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              anyQueued
                  ? context.l10n.settleUpRecordedWillSync
                  : context.l10n.settleUpRecorded,
            ),
            backgroundColor: context.colors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
      return _StepOutcome(
        _StepOutcomeKind.recorded,
        ack: anyQueued ? WriteAck.queued : WriteAck.acked,
      );
    } catch (e) {
      // L4: error snackbar stays loud even during a walk; the caller breaks on a
      // non-recorded outcome.
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
        connectivityNotifier.noteLocalWrite(groupId: widget.groupId); // #357
      } else {
        connectivityNotifier.noteQueuedWrite(groupId: widget.groupId); // #412
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

  /// #753: correct a DECOMPOSED group settle-up by reversing ALL of its tagged
  /// docs (the N event settlements + the residual) in ONE atomic WriteBatch — so
  /// the per-event ledgers and the aggregate re-open together, never partially.
  /// The reverses carry the SAME groupSettleUpId + the correction-note sentinel,
  /// so the logical history row flips to "corrected" and a re-tap is a no-op.
  /// Append-only (B3): the originals stay; corrections are new offsetting rows.
  Future<void> _correctLogicalSettleUp(
    BuildContext context, {
    required Group group,
    required String groupSettleUpId,
  }) async {
    // Gather every live doc of this logical settle-up (group residual + tagged
    // event docs) — the same lists that feed the history regroup.
    final groupDocs =
        ref.read(groupSettlementsProvider(widget.groupId)).valueOrNull ??
        const <Settlement>[];
    final taggedEventDocs = ref.read(
      groupTaggedEventSettlementsProvider(widget.groupId),
    );
    final tagged = [
      for (final s in [...groupDocs, ...taggedEventDocs])
        if (s.groupSettleUpId == groupSettleUpId && !s.isDeleted) s,
    ];

    // In-flight guard (synchronous, before any await): closes the double-tap
    // window the already-corrected guard (which needs the reverse stream to
    // emit) cannot.
    if (_correctingSettleUpIds.contains(groupSettleUpId)) return;
    // Already corrected (re-entry after the reverse landed) → no-op.
    if (tagged.any((s) => isCorrectionNote(s.note))) return;
    final originals = [
      for (final s in tagged)
        if (!isCorrectionNote(s.note)) s,
    ];
    if (originals.isEmpty) return;

    final correctedBy = ref.read(currentUserIdProvider);
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final successColor = context.colors.success;
    final errorColor = context.colors.error;
    if (correctedBy == null || correctedBy.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            settlementWriteErrorMessage(l10n, SettlementWriteErrorKind.unknown),
          ),
          backgroundColor: errorColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    _correctingSettleUpIds.add(groupSettleUpId);
    final connectivityNotifier = ref.read(connectivityProvider.notifier);
    final skipWait =
        ref.read(connectivityProvider) != ConnectivityStatus.online;
    try {
      // One atomic WriteBatch — all reverses commit or none do (rules-checked +
      // offline-queued atomically); a departed-party residual fails the WHOLE
      // batch (clean), never a partial reversal (#753 §3c).
      final ack = await awaitServerAck(
        ref
            .read(settlementCorrectionServiceProvider)
            .reverseLogicalSettleUp(
              groupId: widget.groupId,
              groupSettleUpId: groupSettleUpId,
              originals: originals,
              correctedBy: correctedBy,
              correctionNote: l10n.settleUpCorrectionNote,
            ),
        skipWait: skipWait,
      );
      // The reverse includes EVENT settlements → the home one-shot reads them;
      // bump after the ack RETURNS (acked OR queued) so home isn't stale offline.
      ref.read(ledgerRevisionProvider.notifier).state++;
      if (ack == WriteAck.queued) {
        connectivityNotifier.noteQueuedWrite(groupId: widget.groupId);
      } else {
        connectivityNotifier.noteLocalWrite(groupId: widget.groupId);
      }
      // No activity log — a reversal must not surface as a fresh feed payment.
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              ack == WriteAck.queued
                  ? l10n.settleUpRecordedWillSync
                  : l10n.settleUpRecorded,
            ),
            backgroundColor: successColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              settlementWriteErrorMessage(
                l10n,
                classifySettlementWriteError(e),
              ),
            ),
            backgroundColor: errorColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      _correctingSettleUpIds.remove(groupSettleUpId);
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
