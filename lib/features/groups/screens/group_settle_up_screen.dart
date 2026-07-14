import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import 'package:go_router/go_router.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/services/firebase_functions_service.dart';
import '../../../core/services/money_serializer.dart';
import '../../../core/utils/bidi.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/localized_decimal_input.dart';
import '../../../core/utils/settle_notify.dart';
import '../../../core/utils/settlement_write_error.dart';
import '../../../core/utils/share_helper.dart';
import '../../../core/utils/whatsapp_share.dart';
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
import '../../ledger/services/settlement_service.dart';
import '../../ledger/utils/settlement_correction_affordance.dart';
import '../../ledger/widgets/pre_settlement_review_sheet.dart';
import '../models/group_model.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_presettle_review_provider.dart';
import '../providers/group_provider.dart';
import '../widgets/group_settle_up/settlement_top_bar.dart';
import '../widgets/record_payment_sheet.dart';
import '../widgets/settle_notify_sheet.dart';
import '../widgets/settle_up_page_body.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

/// Cross-event settlement screen — single-page layout per the Hi_GroupSettle
/// wireframe (Wireframes/Rihla/hifi/screens-group.jsx).
///
/// Renders an italic headline, two summary chips, suggested transfer cards
/// (optimized or direct per the group's #363 `simplifyDebts` mode), each
/// person's net balances, and inline payment history.
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
            SettlementTopBar(groupId: widget.groupId),
            Expanded(
              child: balancesAsync.when(
                data: (balancesData) {
                  // #204: surface review-worthy expenses (from ANY event in
                  // the settle basis) once, before the user settles. Fired
                  // from the data branch so the sheet never covers a skeleton.
                  _maybeShowReviewSheet(context, preSettleReview);

                  // #382 PR-1: one section per currency bucket, the suggestion
                  // allocator run per bucket (no cross-currency netting,
                  // ever). No money yet → one empty group-currency bucket
                  // (zero summary card). The recorded settlement carries the
                  // BUCKET currency.
                  // #363: the group's simplifyDebts mode picks the allocator —
                  // optimizer (default) vs direct pro-rata fan-out.
                  final buckets = <SettleBucket>[
                    for (final c in sortedGccFirst(balancesData.balances.keys))
                      (
                        currency: c,
                        balances: balancesData.balances[c]!,
                        optimalSettlements: group.simplifyDebts
                            ? BalanceCalculator.calculateOptimalSettlements(
                                balances: balancesData.balances[c]!,
                                userNames: balancesData.memberNames,
                              )
                            : BalanceCalculator.calculateDirectSettlements(
                                balances: balancesData.balances[c]!,
                                currency: c,
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
                    // #363: must match the allocator that produced the
                    // buckets above.
                    simplifyDebts: group.simplifyDebts,
                    buckets: buckets,
                    rawNames: balancesData.memberRawNames,
                    settlementsAsync: settlementsAsync,
                    currentUid: currentUid,
                    // Actor policy: Correct renders per-settlement for the
                    // group creator or a party only (mirrors the
                    // correctSettlement/correctLogicalSettleUp gate).
                    groupCreatorId: group.createdBy,
                    // #1149: FULL memberIds — prunes departed-party suggestion
                    // tiles/stepped cards and hides Correct on departed-party
                    // history (ghosts and shadows are IN memberIds and stay).
                    currentMemberIds: group.memberIds.toSet(),
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
                    // #1204: resolves a _buildPerEventBreakdown key (eventId
                    // or the residual sentinel) into its display label at
                    // render time — see _resolveBreakdownLabel.
                    breakdownLabel: (key) =>
                        _resolveBreakdownLabel(key, eventNameMap),
                    onRecordStepped: (steps) => _runSteppedSettle(
                      context,
                      group: group,
                      balancesData: balancesData,
                      eventOrder: eventOrder,
                      steps: steps,
                    ),
                    // #283/#889: correct a recorded standalone group payment
                    // via the server-authoritative correctSettlement callable
                    // (scope: 'group') — the reverse carries the un-forgeable
                    // correctionOfSettlementId marker and never surfaces as a
                    // fresh feed payment (no client activity write).
                    onCorrect: (s) => _correctSettlement(context, original: s),
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
                                style: AppTypography.sans(
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
                          style: AppTypography.sans(
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

  /// Sentinel breakdown key for the cross-event residual row (#752/#1204) —
  /// never a real event id (Firestore/test event ids never equal this
  /// literal), so it can't collide with an [eventOrder] member. Resolved to
  /// the localized "Across events" label by [_resolveBreakdownLabel] —
  /// never displayed raw.
  static const _kAcrossEventsBreakdownKey = '__group_settle_up_across_events__';

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
  ///
  /// #1204: keyed by the RAW eventId (or the [_kAcrossEventsBreakdownKey]
  /// sentinel for the residual) — NOT the display label. Two distinct events
  /// sharing a display label (same name, same day) would collide on a
  /// label-keyed map and silently overwrite each other's slice, desyncing
  /// the displayed sum from the settlement amount. `decomposition.perEvent`
  /// is itself eventId-keyed, so this map is collision-free by construction;
  /// the display label is resolved separately, at render time, by
  /// [_resolveBreakdownLabel] (wired through [SettleUpPageBody.breakdownLabel]
  /// / [GroupSettlementTile.breakdownLabel]).
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
        result[eventId] = slice;
      }
    }
    if (decomposition.residual > Decimal.zero) {
      result[_kAcrossEventsBreakdownKey] = decomposition.residual;
    }
    return result;
  }

  /// #1204: resolves a [_buildPerEventBreakdown] key (a raw eventId, or the
  /// [_kAcrossEventsBreakdownKey] residual sentinel) into its display label
  /// AT RENDER TIME, in [GroupSettlementTile] — keeping the breakdown map
  /// itself collision-free regardless of how many events share a display
  /// label.
  String _resolveBreakdownLabel(
    String key,
    Map<String, ({String name, EventType type, DateTime date})> eventNameMap,
  ) {
    if (key == _kAcrossEventsBreakdownKey) {
      return context.l10n.groupSettleUpAcrossEventsLabel;
    }
    return _buildEventLabel(key, eventNameMap);
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

    // #1217: truncate on GRAPHEME boundaries (`package:characters`), never
    // raw UTF-16 code units. `String.length`/`substring` count UTF-16 units,
    // so a name whose 30th-ish visible character is an astral emoji (a
    // 2-unit surrogate pair) could get cut BETWEEN the pair's high and low
    // surrogate, leaving an unpaired surrogate that Flutter's text layer
    // throws on ("string is not well-formed UTF-16"). "Roughly 30 visible
    // characters, ellipsis when longer" is preserved; the count now measures
    // graphemes instead of UTF-16 units, so a name with astral characters
    // may show fewer than 30 raw code units before truncating.
    final rawNameCharacters = rawName.characters;
    final name = rawNameCharacters.length > 30
        ? '${rawNameCharacters.take(27)}...'
        : rawName;

    final date = AppFormatters.formatShortMonthDay(
      entry.date,
      Localizations.localeOf(context).toLanguageTag(),
    );
    // #1216b: isolate the POST-truncation event name (never rawName — the
    // #1217 grapheme-truncate would drop a closing PDI and leak an unterminated
    // FSI into "— $date"). The name sits directly before the date descriptor.
    return '${bidiIsolate(name)} — $date';
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
    }

    if (recorded == 0) return; // cancel at step 1 → no final snackbar
    // #1129: no queued branch — settlement creates are callable-backed, so a
    // recorded step IS server-acked.
    final message = recorded == steps.length
        ? l10n.settleUpSteppedRecordedAll(recorded)
        : l10n.settleUpSteppedRecordedPartial(recorded, steps.length);
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
    // Steps ≥2 of the stepped walk re-enter here in the async continuation
    // after the previous sheet closed — the context may be disposed.
    // coverage:ignore-start
    if (!context.mounted) {
      return const _StepOutcome(_StepOutcomeKind.cancelled);
    }
    // coverage:ignore-end
    // #1106: the live balance provider proceeds-on-partial while per-event
    // streams deliver their FIRST snapshot (the #244 loading-skip, deliberately
    // kept for display). A sheet opened inside that window carries an
    // understated suggestion the #719 re-read below can never catch (an
    // understated amount passes a later-converged higher outstanding). Refuse
    // to open — write-time only; the screen itself stays proceed-on-partial.
    if (ref.read(groupConvergingEventIdsProvider(widget.groupId)).isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settleUpBalanceStillSyncing)),
      );
      return const _StepOutcome(_StepOutcomeKind.invalid);
    }
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
      fromUserId: fromUserId,
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
    // #1106 (confirm-time twin of the entry gate): a convergence window can
    // OPEN while the sheet is up (another device adds an event — its streams
    // have no first snapshot here yet). The fresh re-read below would silently
    // omit that event's money and revalidate against itself — refuse instead.
    if (ref.read(groupConvergingEventIdsProvider(widget.groupId)).isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settleUpBalanceStillSyncing)),
      );
      return const _StepOutcome(_StepOutcomeKind.invalid);
    }
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
    // An #1129 idempotent replay never re-nudges — the user already recorded
    // (and was offered the nudge for) this exact payment once.
    if (stepLabel == null &&
        currentUid == fromUserId &&
        outcome.kind == _StepOutcomeKind.recorded &&
        !outcome.alreadyRecorded &&
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
  /// legs (which the event ledgers read) + one residual group settlement —
  /// instead of a single group settlement that only moved the aggregate. The
  /// pure allocator ([BalanceCalculator.decomposeGroupSettlement]) is the SSOT
  /// shared with the displayed breakdown (it is called with the SAME
  /// [eventOrder]). Returns the aggregate [_StepOutcome] so the stepped walk can
  /// decide whether to continue.
  ///
  /// Since #1129 the whole decompose is ONE `recordSettlement` server
  /// transaction (mode `'groupSettleUp'`) — all legs + residual + the ONE
  /// #1140 activity row commit or nothing does; the server re-verifies
  /// conservation (`Σ legs + residual == total`), caps the total at the
  /// pair's aggregate outstanding and each leg at its event's drill-down
  /// overlap, enforces #1144 membership itself (#720 defer-to-server), and
  /// derives the shared `groupSettleUpId`. The old departed-party
  /// (`bothLiveMembers`) and `kMaxDecomposeLegsAtomic` routing conditions are
  /// GONE with the client `WriteBatch` (the 20-access-call rules budget no
  /// longer applies; the server bound is 400 legs). The ONE remaining
  /// fallback: no per-event attribution at all (pure cross-event pair) →
  /// [_recordSettlement], a single aggregate group settlement.
  Future<_StepOutcome> _recordDecomposedSettlement(
    BuildContext context, {
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
    // #1129 pre-flight (this is the single entry to BOTH group write paths —
    // it covers the mode-'group' fallback below too): settlement creates are
    // an HTTPS callable with no offline queue, so a provably-offline device
    // gets the honest failure copy instead of a doomed call. `syncing`
    // PROCEEDS (the device is online; the up-to-60s stale-probe window must
    // not block recording).
    if (ref.read(connectivityProvider) == ConnectivityStatus.offline) {
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
      return const _StepOutcome(_StepOutcomeKind.failed);
    }
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
    if (decomposition.perEvent.isEmpty) {
      return _recordSettlement(
        context,
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

    // #104: capture before the await so post-write effects survive a disposal
    // during the wait.
    final ConnectivityNotifier connectivityNotifier =
        connectivity ?? ref.read(connectivityProvider.notifier);
    final ledgerRevision = ref.read(ledgerRevisionProvider.notifier);

    try {
      // #1093/#1129: the client OBSERVES the gsu directed-pair epoch from the
      // SAME bases both providers this screen already watches; the SERVER
      // derives the shared groupSettleUpId — and every leg/residual id — from
      // it, so a racing second decompose of the identical observation
      // resolves to ONE recorded settle-up. Fails closed on a valueless
      // basis read.
      final groupDocs = ref
          .read(groupSettlementsProvider(widget.groupId))
          .valueOrNull;
      if (groupDocs == null) {
        throw StateError(
          'group settlement basis unavailable — cannot derive dedup epoch',
        );
      }
      final taggedLegs = ref.read(
        groupTaggedEventSettlementsProvider(widget.groupId),
      );
      final pairSettlements = [...groupDocs, ...taggedLegs];
      final observedPairEpoch = SettlementService.directedPairEpoch(
        pairSettlements,
        payerParticipantId: fromUserId,
        recipientParticipantId: toUserId,
      );

      // Build the event legs from the SAME eventOrder the displayed breakdown
      // used (skip null slices) — the WYSIWYG invariant (#752).
      final eventLegs = <({String eventId, Decimal amount})>[];
      for (final eventId in eventOrder) {
        final slice = decomposition.perEvent[eventId];
        if (slice != null) eventLegs.add((eventId: eventId, amount: slice));
      }

      // ONE server transaction (#1129): the N event legs + residual + the ONE
      // #1140 group_settlement activity row commit atomically or not at all.
      // The server authors the activity row (actor name, description) — the
      // client sends money facts only.
      final result = await ref
          .read(groupSettlementServiceProvider)
          .recordDecomposedSettleUp(
            groupId: widget.groupId,
            eventLegs: eventLegs,
            amount: amount,
            payerParticipantId: fromUserId,
            recipientParticipantId: toUserId,
            currency: currency,
            observedPairEpoch: observedPairEpoch,
            payerName: fromName,
            recipientName: toName,
            note: note,
          );

      // ONE bump per successful settle-up, server-gated: true iff event-scope
      // legs were written (the home once-provider reads event settlements; a
      // pure group write is live-watched and needs no bump, CLAUDE.md #366).
      // The fail-safe parse defaults toward bumping.
      if (result.shouldBumpLedgerRevision) ledgerRevision.state++;

      // #357: the callable just round-tripped the server — provably online.
      // noteQueuedWrite is dead for settlement creates (nothing ever queues).
      connectivityNotifier.noteLocalWrite(groupId: widget.groupId);

      if (showSuccessSnackbar && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.alreadyRecorded
                  ? context.l10n.settleUpAlreadyRecorded
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
        alreadyRecorded: result.alreadyRecorded,
      );
    } catch (e) {
      // L4: error snackbar stays loud even during a walk; the caller breaks on a
      // non-recorded outcome.
      if (context.mounted) {
        // #1129: an over-outstanding rejection carries the LIVE server-side
        // outstanding — surface it with the #773 balance-changed copy so the
        // user re-reviews against the real number instead of a generic error.
        final overFils = overOutstandingFils(e);
        final message = overFils != null
            ? context.l10n.settleUpBalanceChangedReviewAgain(
                AppFormatters.formatCurrency(
                  MoneySerializer.fromSubunits(overFils, currency),
                  currency,
                ),
              )
            : settlementWriteErrorMessage(
                context.l10n,
                classifySettlementWriteError(e),
              );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
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

  /// #1129 mode-'group' fallback: ONE aggregate group settlement, for the
  /// pure cross-event pair with no per-event attribution. The server writes
  /// the doc with the `eventId: groupId` sentinel + `scope: 'group'`, caps
  /// the amount at the pair's full-group outstanding, and authors the
  /// `group_settlement` activity row atomically. The #1129 offline pre-flight
  /// lives in [_recordDecomposedSettlement] — the single entry to this path.
  Future<_StepOutcome> _recordSettlement(
    BuildContext context, {
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
    // #104: capture before the await so post-write effects survive a disposal
    // during the wait. The stepped walk passes the notifier it captured once
    // before its loop; the single-tile path reads it here.
    final ConnectivityNotifier connectivityNotifier =
        connectivity ?? ref.read(connectivityProvider.notifier);
    final ledgerRevision = ref.read(ledgerRevisionProvider.notifier);
    try {
      // #1093/#1129: epoch over groupSettlementsProvider docs only — this is
      // the aggregate single write (no per-event legs), so it has no tagged
      // event-settlement basis to union in. The SERVER derives the `group:`
      // dedup id from it. Fails closed on a valueless basis read.
      final groupDocs = ref
          .read(groupSettlementsProvider(widget.groupId))
          .valueOrNull;
      if (groupDocs == null) {
        throw StateError(
          'group settlement basis unavailable — cannot derive dedup epoch',
        );
      }
      final result = await ref
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
            observedPairEpoch: SettlementService.directedPairEpoch(
              groupDocs,
              payerParticipantId: fromUserId,
              recipientParticipantId: toUserId,
            ),
          );

      // A pure group write is live-watched (groupSettlementsProvider, L6) and
      // the server returns shouldBumpLedgerRevision=false for it — honor the
      // flag anyway (the fail-safe parse defaults toward bumping).
      if (result.shouldBumpLedgerRevision) ledgerRevision.state++;
      // #357: the callable just round-tripped the server — provably online.
      // noteQueuedWrite is dead for settlement creates (nothing ever queues).
      connectivityNotifier.noteLocalWrite(groupId: widget.groupId);

      if (showSuccessSnackbar && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.alreadyRecorded
                  ? context.l10n.settleUpAlreadyRecorded
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
        alreadyRecorded: result.alreadyRecorded,
      );
    } catch (e) {
      // L4: per-step ERROR snackbar stays loud even during a walk; the walk
      // then stops (the caller breaks on a non-recorded outcome).
      if (context.mounted) {
        // #1129: surface an over-outstanding rejection with the LIVE number
        // via the #773 balance-changed copy (see the decompose catch).
        final overFils = overOutstandingFils(e);
        final message = overFils != null
            ? context.l10n.settleUpBalanceChangedReviewAgain(
                AppFormatters.formatCurrency(
                  MoneySerializer.fromSubunits(overFils, currency),
                  currency,
                ),
              )
            : settlementWriteErrorMessage(
                context.l10n,
                classifySettlementWriteError(e),
              );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
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
    // #889: already corrected (re-entry after the reverse landed) → no-op
    // LOCALLY only when EVERY eligible original provably has a valid marked
    // reverse or bounded-legacy inverse — a partially-marked set keeps the
    // action available so the callable can repair the remainder. The server
    // stays authoritative for selecting originals and writing reverses.
    if (logicalSetAffordanceCorrected(tagged)) return;

    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final successColor = context.colors.success;
    final errorColor = context.colors.error;

    _correctingSettleUpIds.add(groupSettleUpId);
    // #104/#412: capture before the await so the effect survives a disposal
    // during the (now bounded) wait.
    final ledgerRevisionNotifier = ref.read(ledgerRevisionProvider.notifier);
    final connectivityNotifier = ref.read(connectivityProvider.notifier);
    try {
      // #889: the callable validates the FULL logical set server-side (a
      // large settle-up can exceed what rules-side get() validation on a
      // client batch could afford) and writes every reverse row — event
      // slices AND the group residual — atomically, each carrying the
      // un-forgeable correctionOfSettlementId marker.
      final result = await ref
          .read(firebaseFunctionsServiceProvider)
          .correctLogicalSettleUp(
            groupId: widget.groupId,
            groupSettleUpId: groupSettleUpId,
            correctionNote: l10n.settleUpCorrectionNote,
          );
      if (result.shouldBumpLedgerRevision) {
        ledgerRevisionNotifier.state++; // home one-shot reads event slices
      }
      // #1213: the correction rewrote event-scope slices (and the residual),
      // so the home aggregate doc lags until the async balanceAggregator
      // trigger catches up. Mark it dirty UNCONDITIONALLY on success so the
      // online home facade stays on the once-path.
      connectivityNotifier.noteLocalWrite(groupId: widget.groupId);
      // No activity log — a reversal must not surface as a fresh feed payment.
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.settleUpRecorded),
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

  /// #283/#889: correct a recorded STANDALONE group payment via the
  /// server-authoritative `correctSettlement` callable (`scope: 'group'`).
  /// Replaces the old client-direct reverse write. Group-only corrections do
  /// NOT bump `ledgerRevisionProvider` — group settlements are live-watched
  /// (`groupSettlementsProvider`), unlike the event/logical paths. BUT the home
  /// aggregate doc must still be marked dirty (#1213): the once-path's live
  /// watch is irrelevant to the online facade branch, which serves the
  /// `groups/{gid}/aggregates/balance` doc directly (`group_balance_provider`
  /// facade) and would show the pre-correction balance until the async
  /// balanceAggregator trigger rewrites it. Corrections are ONLINE-ONLY:
  /// offline/failure surfaces the existing settlement write-error copy and
  /// writes nothing — never the queued/"will sync" copy.
  Future<void> _correctSettlement(
    BuildContext context, {
    required Settlement original,
  }) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final successColor = context.colors.success;
    final errorColor = context.colors.error;
    // #104/#412/#1213: capture before the await so the effect survives a
    // disposal during the wait (no ledgerRevision bump here — see doc above).
    final connectivityNotifier = ref.read(connectivityProvider.notifier);
    try {
      await ref
          .read(firebaseFunctionsServiceProvider)
          .correctSettlement(
            groupId: widget.groupId,
            scope: 'group',
            settlementId: original.id,
            correctionNote: l10n.settleUpCorrectionNote,
          );
      // #1213: mark the home aggregate dirty on success (see doc above).
      connectivityNotifier.noteLocalWrite(groupId: widget.groupId);
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.settleUpRecorded),
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
    }
  }
}

/// Outcome of one stepped-settle step (#382 PR-5). The walk continues only on
/// [recorded] (L3). [alreadyRecorded] marks the #1129 idempotent-replay
/// success — it shows the "already recorded" copy and suppresses the #367
/// nudge; there is no queued state (creates are callable-backed, #1129).
enum _StepOutcomeKind { recorded, cancelled, invalid, failed }

class _StepOutcome {
  const _StepOutcome(this.kind, {this.alreadyRecorded = false});

  final _StepOutcomeKind kind;
  final bool alreadyRecorded;
}
