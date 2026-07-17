import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/services/firebase_functions_service.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/services/money_serializer.dart';
import '../../../core/services/review_prompt.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/localized_decimal_input.dart';
import '../../../core/utils/settle_notify.dart';
import '../../../core/utils/settlement_write_error.dart';
import '../../../core/utils/share_helper.dart';
import '../../../core/utils/whatsapp_share.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../events/providers/event_provider.dart';
import '../../../core/constants/supported_currencies.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../../groups/services/member_name_resolver.dart';
import '../../groups/widgets/record_payment_sheet.dart';
import '../../groups/widgets/settle_notify_sheet.dart';
import '../../groups/widgets/settle_up_page_body.dart';
import '../../trip/models/trip_model.dart';
import '../keys/ledger_keys.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';
import '../providers/expense_provider.dart';
import '../services/pre_settlement_review.dart';
import '../services/settlement_service.dart';
import '../widgets/pre_settlement_review_sheet.dart';
import '../widgets/settle_up/settle_up_top_bar.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

/// Event-scoped Settle Up screen.
///
/// Mirrors the Group Settle-Up wireframe (Hi_GroupSettle): italic intro,
/// summary chips, suggested transfer cards (optimized or direct per the
/// group's #363 `simplifyDebts` mode), "Each person's net", and a
/// payment-history footer. Routed at `/group/:gid/event/:eid/ledger/settle-up`.
class SettleUpScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String eventId;

  /// Highlight a specific member's tile via deep-link (`?memberId=`).
  final String? preSelectedMemberId;

  /// #758: content-only mode for the tabbed event view — skips the Scaffold,
  /// top bar, and offline banner (the tabbed shell owns chrome). All record /
  /// revalidation / notify logic is unchanged.
  final bool embedded;

  const SettleUpScreen({
    super.key,
    required this.groupId,
    required this.eventId,
    this.preSelectedMemberId,
    this.embedded = false,
  });

  @override
  ConsumerState<SettleUpScreen> createState() => _SettleUpScreenState();
}

class _SettleUpScreenState extends ConsumerState<SettleUpScreen> {
  final Map<int, GlobalKey> _tileKeys = {};

  /// #204: the pre-settlement review sheet fires once per screen entry. Guarded
  /// so the data callback (which reruns on every rebuild / stream tick) can't
  /// re-present it.
  bool _reviewSheetShown = false;

  /// #204: on first entry, if the event has review-worthy expenses (exact /
  /// custom-participant / personal / unusually-large / paid-by-a-departed-member),
  /// surface the non-blocking review sheet before the user settles. Detection is
  /// pure + display-only; the sheet never blocks settlement.
  ///
  /// [activeParticipantIds] is the current event roster narrowed to live
  /// (`!isTombstone`) group members, so it sheds both event removals and members
  /// who left the group.
  /// #1058: flags the viewer already settled past (viewer-party settlement in
  /// the same currency, newer than the expense) are suppressed even while the
  /// currency bucket stays outstanding — see suppressFlagsSettledPastByViewer.
  void _maybeShowReviewSheet(
    BuildContext context,
    List<Expense> expenses, [
    Set<String> outstandingCurrencies = const {},
    Set<String> activeParticipantIds = const {},
    List<Settlement> settlements = const [],
    String? viewerUid,
  ]) {
    if (_reviewSheetShown) return;
    final flags = suppressFlagsSettledPastByViewer(
      filterFlagsToOutstandingCurrencies(
        detectReviewWorthyExpenses(
          expenses,
          activeParticipantIds: activeParticipantIds,
        ),
        outstandingCurrencies,
      ),
      settlements: settlements,
      viewerUid: viewerUid,
    );
    if (flags.isEmpty) return;
    _reviewSheetShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showPreSettlementReviewSheet(
        context,
        flags: flags,
        onTapExpense: (e) => context.push(
          '/group/${widget.groupId}/event/${widget.eventId}/ledger/edit/${e.id}',
        ),
        onReviewAll: () => context.push(
          '/group/${widget.groupId}/event/${widget.eventId}/ledger',
        ),
      );
    });
  }

  /// Route chrome: Scaffold + top bar + SafeArea (+ [banner] on the data
  /// branch). Embedded mode (#758) returns [child] bare — the tabbed shell
  /// owns the Scaffold, back affordance, and offline banner.
  Widget _chrome(
    BuildContext context,
    Widget child, {
    Key? scaffoldKey,
    bool banner = false,
  }) {
    if (widget.embedded) return child;
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            SettleUpTopBar(groupId: widget.groupId, eventId: widget.eventId),
            if (banner) const OfflineBanner(),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  /// #818 Wave 5.3: nav-only "View recap & export" CTA, standalone-event
  /// settle-up ONLY — gated on `!widget.embedded && expenses.isNotEmpty`. Does
  /// NOT copy the command-center's `!event.isClosed` conjunct: a closed
  /// event's standalone settle-up should still reach the recap/export.
  /// Pushes the existing recap route directly — never opens
  /// `showRecapShareSheet` here (that would drag `eventRecapProvider` +
  /// `ledgerViewProvider` watches into settle-up); export stays owned by the
  /// recap screen.
  Widget? _buildRecapCta(BuildContext context, List<Expense> expenses) {
    if (widget.embedded || expenses.isEmpty) return null;
    return Padding(
      padding: EdgeInsetsDirectional.only(top: context.spacing.space24),
      child: OutlinedButton.icon(
        key: LedgerKeys.settleUpRecapCta,
        onPressed: () {
          HapticService.lightClick();
          GoRouter.of(
            context,
          ).push('/group/${widget.groupId}/event/${widget.eventId}/recap');
        },
        icon: const Icon(Iconsax.document_text),
        label: Text(context.l10n.settleUpViewRecapCta),
      ),
    );
  }

  Widget _missingView(BuildContext context) {
    return EmptyStateView(
      icon: Iconsax.warning_2,
      title: context.l10n.settleUpEventMissingTitle,
      message: context.l10n.settleUpEventMissingMessage,
      actionLabel: context.l10n.commonGoHome,
      onAction: () => context.go('/home'),
      iconColor: context.colors.textSecondary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventRef = (groupId: widget.groupId, eventId: widget.eventId);
    final eventAsync = ref.watch(eventDetailProvider(eventRef));
    // #382: settlements are denominated in the selected balance bucket's
    // currency. The group still has to resolve so an empty ledger can render a
    // zero bucket in the group default instead of falling back to literal OMR.
    // Three branches mirror group_settle_up_screen.dart: loading / null group /
    // data.
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));

    if (eventAsync.isLoading || groupAsync.isLoading) {
      return _chrome(context, SkeletonLoader.groupList());
    }

    final event = eventAsync.valueOrNull;

    if (event == null) {
      return _chrome(context, _missingView(context));
    }

    // #261: a deleted/missing group emits null — show an error rather than
    // folding it into the loader (which would spin forever).
    final group = groupAsync.valueOrNull;
    if (group == null) {
      return _chrome(context, _missingView(context));
    }
    final groupCurrency = group.currency;

    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));
    final currentUid = ref.watch(currentUserIdProvider);
    final groupMembersAsync = ref.watch(groupMembersProvider(widget.groupId));
    final groupMembers = groupMembersAsync.valueOrNull ?? [];

    // #249: member-id sets for the per-event balance universe. The universe
    // itself (and the name maps + participants derived from it) is built inside
    // the data callback below, where expenses/settlements are available.
    // #773 DRIFT GUARD: `_freshOutstandingForPair` reconstructs this same
    // universe basis for the pre-write revalidation cap — keep the two in sync.
    final allMemberIds = groupMembers.map((m) => m.userId).toSet();
    final liveMemberIds = groupMembers
        .where((m) => !m.isTombstone)
        .map((m) => m.userId)
        .toSet();

    return _chrome(
      context,
      scaffoldKey: LedgerKeys.settleUpScreen,
      banner: true,
      expensesAsync.when(
        data: (expenses) {
          // #1028: a hard-errored settlements stream must not fold to [] —
          // the basis is OUTBOUND (feeds the settlement write) and empty
          // folds resurrect settled debts as over-pay suggestions. Stale-
          // valued errors keep rendering (#1005 hard-error pattern); the
          // first-value window gets the same skeleton as expenses loading.
          if (settlementsAsync.hasError && !settlementsAsync.hasValue) {
            return _balancesErrorView(context, eventRef);
          }
          if (settlementsAsync.isLoading && !settlementsAsync.hasValue) {
            return SkeletonLoader.groupList();
          }
          final settlements = settlementsAsync.valueOrNull ?? const [];

          // #1030: a hard-errored members stream must not fold to [] — the
          // #249 universe intersects split recipients with allMemberIds, so
          // empty members computes WRONG money on this OUTBOUND basis (and
          // userRawNames feeds the settlement write). Stale-valued errors
          // keep serving; the first-value window gets the same skeleton as
          // the settlements leg. The #204/#898 review-sheet fallback is
          // re-scoped to the stale-valued leg — under a hard error no settle
          // write is reachable at all, which dominates "warn but allow".
          if (groupMembersAsync.hasError && !groupMembersAsync.hasValue) {
            return _balancesErrorView(context, eventRef);
          }
          if (groupMembersAsync.isLoading && !groupMembersAsync.hasValue) {
            return SkeletonLoader.groupList();
          }

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
          final outstandingCurrencies = {
            for (final entry in bucketed.entries)
              if (entry.value.any((b) => b.netBalance != Decimal.zero))
                entry.key,
          };

          // #204/#898: gate membership-sensitive detection on resolved members
          // and settled-bucket suppression on resolved settlements so the
          // one-shot does not latch before live members and money-flow basis
          // are authoritative. Past the #1028/#1030 loud gates above, both
          // streams are guaranteed to carry a value here (possibly stale under
          // an error — the accepted #1005 leg), so the full detector always
          // runs; the old reduced members-error fallback became unreachable
          // and was removed (#1030 — a valueless members stream never reaches
          // this point anymore).
          if (settlementsAsync.hasValue && groupMembersAsync.hasValue) {
            final activeParticipantIds = event.participantIds
                .toSet()
                .intersection(liveMemberIds);
            _maybeShowReviewSheet(
              context,
              expenses,
              outstandingCurrencies,
              activeParticipantIds,
              settlements,
              currentUid,
            );
          }

          // #382 PR-1: one section per currency bucket, the suggestion
          // allocator run per bucket (no cross-currency netting, ever). No
          // money yet → one empty group-currency bucket (zero summary card).
          // The recorded settlement carries the BUCKET currency.
          // #363: the group's simplifyDebts mode picks the allocator —
          // optimizer (default) vs direct pro-rata fan-out.
          final buckets = <SettleBucket>[
            for (final c in sortedGccFirst(bucketed.keys))
              (
                currency: c,
                balances: bucketed[c]!,
                optimalSettlements: group.simplifyDebts
                    ? BalanceCalculator.calculateOptimalSettlements(
                        balances: bucketed[c]!,
                        userNames: userDisplayNames,
                      )
                    : BalanceCalculator.calculateDirectSettlements(
                        balances: bucketed[c]!,
                        currency: c,
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

          // #595/#598: write-eligibility gates BOTH the forward Record
          // button and the #283 "correct this payment" offset. The event
          // settlement create/offset rule pins the WRITER to
          // event.participantIds (isEventParticipant); a group member who
          // can read this event but isn't a participant would be
          // permission-denied on EITHER write, so both affordances are
          // suppressed for them. The group screen has no such pin (every
          // viewer is a member → passes true / wires both).
          final canRecord =
              currentUid != null && event.participantIds.contains(currentUid);

          return SettleUpPageBody(
            scope: SettleScope.event,
            subjectName: event.name,
            // #363: must match the allocator that produced the buckets above.
            simplifyDebts: group.simplifyDebts,
            buckets: buckets,
            rawNames: userRawNames,
            settlementsAsync: settlementsAsync,
            currentUid: currentUid,
            // Actor policy: Correct renders per-settlement for the group
            // creator or a party only (mirrors the correctSettlement gate).
            groupCreatorId: group.createdBy,
            // #1149: FULL memberIds — prunes departed-party suggestion tiles
            // and hides Correct on departed-party history (ghosts stay).
            currentMemberIds: group.memberIds.toSet(),
            tileKeys: _tileKeys,
            canRecord: canRecord,
            preSelectedMemberId: widget.preSelectedMemberId,
            // #789→#1078: the workspace FAB now shows on the Expenses tab
            // only, so the embedded panel no longer reserves clearance —
            // both modes use the default gutter.
            bottomInset: 24,
            // #818 Wave 5.3: nav-only entry to the existing recap/export
            // route, standalone-event-settle-up only (no group entry — Trip
            // Receipt is event-scoped, #704 open; no embedded entry — the
            // Recap tab sits in the same tab strip one swipe away).
            footer: _buildRecapCta(context, expenses),
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
                  // #367: scope for the post-record WhatsApp notify —
                  // event settle names the event AND its group.
                  eventName: event.name,
                  groupName: group.name,
                ),
            // #831: thread the event name so every stepped row's activity
            // metadata carries it (the walk itself still never nudges).
            onRecordStepped: (steps) =>
                _runSteppedSettle(steps, eventName: event.name),
            // #283/#889/#598: correct a recorded payment via the
            // server-authoritative correctSettlement callable — gated by the
            // same write-eligibility as the forward Record, since a
            // non-participant's correction would server-reject too. The
            // callable writes the offsetting reverse with an un-forgeable
            // correctionOfSettlementId marker; it never emits a client
            // activity row (mirrors the pre-#889 logActivity:false intent).
            onCorrect: canRecord
                ? (s) => _correctSettlement(context, original: s)
                : null,
          );
        },
        loading: SkeletonLoader.groupList,
        error: (e, _) => _balancesErrorView(context, eventRef),
      ),
    );
  }

  /// Loud couldn't-load view shared by the expenses error branch and the
  /// #1028 settlements / #1030 members hard-error gates. Retry invalidates
  /// all THREE streams — a settlements- or members-triggered error could
  /// never heal off an expenses-only invalidate.
  Widget _balancesErrorView(BuildContext context, EventRef eventRef) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.spacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Iconsax.warning_2, size: 40, color: context.colors.error),
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
              onPressed: () {
                ref.invalidate(eventExpensesProvider(eventRef));
                ref.invalidate(eventSettlementsProvider(eventRef));
                ref.invalidate(groupMembersProvider(widget.groupId));
              },
              child: Text(context.l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }

  /// Walks a stepped multi-currency settlement (#382 PR-5 D2): one record sheet
  /// per [steps] bucket, each its own independent append-only write. Per-step
  /// success snackbars are suppressed; ONE final summary snackbar reports the
  /// outcome (L4). Any cancel/validation-reject/write-error STOPS the walk —
  /// steps already recorded stay (append-only); re-entry recomputes the
  /// remaining buckets from live streams (L3/L5).
  Future<void> _runSteppedSettle(
    List<SettleStepRequest> steps, {
    String? eventName,
  }) async {
    if (steps.isEmpty) return;
    // #104/#412: capture the notifiers ONCE before the loop so the per-step
    // post-write effects survive a disposal mid-walk (the screen could rebuild
    // between steps). The walk dies with the screen, so a captured list is
    // never re-run after death (L5).
    final ledgerRevision = ref.read(ledgerRevisionProvider.notifier);
    final connectivity = ref.read(connectivityProvider.notifier);
    // Capture context-derived handles ONCE before the loop's awaits (same
    // #104/#412 discipline as the notifiers): the final summary snackbar uses
    // them after the walk without re-reading a possibly-disposed context.
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final successColor = context.colors.success;

    var recorded = 0;
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final outcome = await _showRecordPaymentSheet(
        context,
        settlement: step.settlement,
        fromRawName: step.fromRawName,
        toRawName: step.toRawName,
        fromUserId: step.fromUserId,
        toUserId: step.toUserId,
        suggestedAmount: step.suggestedAmount,
        currency: step.currency,
        stepLabel: l10n.settleUpStepIndicator(i + 1, steps.length),
        eventName: eventName,
        showSuccessSnackbar: false,
        ledgerRevision: ledgerRevision,
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
    // #1263: one review ask per completed walk (see the single-tile site).
    unawaited(ref.read(reviewPromptProvider).maybeRequest());
  }

  /// #773: the LIVE directed-pair outstanding for [currency], recomputed from a
  /// FRESH read of the event ledger — or null when the data isn't available
  /// (offline / still loading), in which case the caller skips revalidation
  /// (safety add-on, never a new blocker). Reconstructs build()'s
  /// universe→participants→`calculateBalances`; participant display names are
  /// provably irrelevant to the net math (`calculateBalances` keys every bucket,
  /// allocation, and output on `participant.id` — `displayName` feeds only the
  /// output `UserBalance.displayName`, which `outstandingForPair` never reads),
  /// so they're minimised to the id here. DRIFT GUARD: the universe basis must
  /// match build()'s — if the `allMemberIds`/`liveMemberIds` derivation or the
  /// `eventBalanceUniverse` call in build() (~L176-205) changes, mirror it here,
  /// or the revalidation cap diverges from the suggestion it gates.
  Decimal? _freshOutstandingForPair({
    required String currency,
    required String fromUserId,
    required String toUserId,
  }) {
    final eventRef = (groupId: widget.groupId, eventId: widget.eventId);
    final event = ref.read(eventDetailProvider(eventRef)).valueOrNull;
    final expenses = ref.read(eventExpensesProvider(eventRef)).valueOrNull;
    // #1028: a valueless settlements read (loading or hard error) must SKIP
    // revalidation like the expenses leg — folding it to [] recomputed the
    // cap against a basis missing every settlement (#773 demands parity).
    // A legitimately empty list is [], never null.
    final settlements = ref
        .read(eventSettlementsProvider(eventRef))
        .valueOrNull;
    if (event == null || expenses == null || settlements == null) return null;
    // #1030: a valueless members read must SKIP revalidation like the legs
    // above — folding it to [] recomputes the cap against the wrong #249
    // universe. Stale values serve; post-#1030 render gates this is
    // defensive parity, same profile as the event==null sibling.
    final membersAsync = ref.read(groupMembersProvider(widget.groupId));
    if (!membersAsync.hasValue) return null;
    final groupMembers = membersAsync.requireValue;
    final allMemberIds = groupMembers.map((m) => m.userId).toSet();
    final liveMemberIds = groupMembers
        .where((m) => !m.isTombstone)
        .map((m) => m.userId)
        .toSet();
    final universe = eventBalanceUniverse(
      event: event,
      expenses: expenses,
      settlements: settlements,
      allMemberIds: allMemberIds,
      liveMemberIds: liveMemberIds,
    );
    final participants = [
      for (final id in universe)
        Participant(
          id: id,
          tripId: event.id,
          role: ParticipantRole.member,
          joinedAt: event.createdAt,
          displayName: id,
        ),
    ];
    final bucketed = BalanceCalculator.calculateBalances(
      expenses: expenses,
      settlements: settlements,
      participants: participants,
    );
    return BalanceCalculator.outstandingForPair(
      bucket: bucketed[currency] ?? const <UserBalance>[],
      fromUserId: fromUserId,
      toUserId: toUserId,
    );
  }

  /// Drives one record sheet → validate → write. Returns the per-step
  /// [_StepOutcome] so the stepped walk can decide whether to continue (L3).
  /// On the single-tile path [stepLabel] is null and [showSuccessSnackbar] is
  /// true — byte-identical to the pre-walk behavior. During a walk the caller
  /// passes the captured [ledgerRevision]/[connectivity] notifiers; the tile
  /// path leaves them null and they are read here.
  Future<_StepOutcome> _showRecordPaymentSheet(
    BuildContext context, {
    required Map<String, dynamic> settlement,
    required String fromRawName,
    required String toRawName,
    required String fromUserId,
    required String toUserId,
    required Decimal suggestedAmount,
    required String currency,
    String? stepLabel,
    // #367: scope for the post-record WhatsApp notify (single-tile only — the
    // stepped walk never nudges, see the gate below). #831: eventName ALSO
    // feeds the activity-row metadata, so the stepped walk now passes it too.
    String? eventName,
    String? groupName,
    bool showSuccessSnackbar = true,
    StateController<int>? ledgerRevision,
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
            // #1201: amount embedded in a composed l10n sentence — stays
            // formatCurrency; RAmount governs standalone displayed amounts
            // (DESIGN.md §8).
            context.l10n.settleUpAmountExceedsOutstanding(
              AppFormatters.formatCurrency(suggestedAmount, currency),
            ),
          ),
        ),
      );
      return const _StepOutcome(_StepOutcomeKind.invalid);
    }

    // #773 (event mirror of #719 / #200 Scope 6): `suggestedAmount` was captured
    // when the tile was tapped; the record sheet may have been open long enough
    // for another device to pay or add an expense. Re-read the LIVE event
    // balances and revalidate the directed-pair outstanding before writing — if
    // it dropped below `editedAmount`, abort and force review-again rather than
    // silently overpaying a stale debt. Data unavailable (offline / still
    // loading) → skip; this is a safety add-on, never a new offline blocker. The
    // event write takes one (from, to, amount) — no fresh-balance propagation
    // like the group decompose (#719) needs.
    final freshOutstanding = _freshOutstandingForPair(
      currency: currency,
      fromUserId: fromUserId,
      toUserId: toUserId,
    );
    if (freshOutstanding != null && editedAmount > freshOutstanding) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              // #1201: amount embedded in a composed l10n sentence — stays
              // formatCurrency; RAmount governs standalone displayed amounts
              // (DESIGN.md §8).
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

    final outcome = await _recordSettlement(
      context,
      fromUserId: fromUserId,
      toUserId: toUserId,
      fromName: fromRawName,
      toName: toRawName,
      amount: editedAmount,
      note: noteText,
      currency: currency,
      showSuccessSnackbar: showSuccessSnackbar,
      ledgerRevision: ledgerRevision,
      connectivity: connectivity,
    );

    // #367: after the DEBTOR records a payment THEY made on the single-tile
    // path, offer to let the creditor know via WhatsApp. Gated to: single-tile
    // (stepLabel == null — the stepped walk shows its own aggregate snackbar and
    // carries one amount/currency), the paying perspective (creditor-records
    // #282 / settle-on-behalf #595 never nudge), and a clean record. An #1129
    // idempotent replay never re-nudges — the user already recorded (and was
    // offered the nudge for) this exact payment once.
    if (stepLabel == null &&
        currentUid == fromUserId &&
        outcome.kind == _StepOutcomeKind.recorded &&
        !outcome.alreadyRecorded &&
        context.mounted) {
      await _offerWhatsAppNotify(
        context,
        // Plain raw name for the greeting — the app-internal disambiguator
        // suffix ("(former member)" / "(2)") doesn't belong in a message sent
        // TO that person; the user picks the actual chat in WhatsApp.
        recipientName: toRawName,
        amount: editedAmount,
        currency: currency,
        eventName: eventName,
        groupName: groupName ?? '',
      );
    }

    // #1263: a completed settle is the natural review moment. Fire-and-forget —
    // cooldown/availability/emulator gating all live inside ReviewPrompt. The
    // #1129 idempotent replay never re-prompts (same reasoning as the #367
    // nudge above); stepped walks prompt once at walk end, not per step.
    if (stepLabel == null &&
        outcome.kind == _StepOutcomeKind.recorded &&
        !outcome.alreadyRecorded) {
      unawaited(ref.read(reviewPromptProvider).maybeRequest());
    }
    return outcome;
  }

  /// #367: present the post-record nudge and, if accepted, open WhatsApp
  /// prefilled with the past-tense scoped message. Numberless — the user picks
  /// the recipient in WhatsApp; WhatsApp-not-installed falls back to the OS share
  /// sheet so the courtesy can never dead-end.
  Future<void> _offerWhatsAppNotify(
    BuildContext context, {
    required String recipientName,
    required Decimal amount,
    required String currency,
    String? eventName,
    required String groupName,
  }) async {
    // #1201: amount embedded in a WhatsApp share string — stays formatCurrency;
    // RAmount governs standalone displayed amounts (DESIGN.md §8).
    final message = settleNotifyMessage(
      l10n: context.l10n,
      recipientName: recipientName,
      amountDisplay: AppFormatters.formatCurrency(amount, currency),
      eventName: eventName,
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
    StateController<int>? ledgerRevision,
    ConnectivityNotifier? connectivity,
  }) async {
    // #1129 pre-flight: settlement creates are an HTTPS callable — there is
    // no offline queue, so a provably-offline device gets the honest failure
    // copy instead of a doomed call. `syncing` PROCEEDS (the device is
    // online; the up-to-60s stale-probe window must not block recording).
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
    HapticService.success();
    final currentUid = ref.read(currentUserIdProvider);
    if (currentUid == null || currentUid.isEmpty) {
      throw StateError(
        'Cannot record settlement without an authenticated user.',
      );
    }
    // #104: capture before the await so post-write effects survive a disposal
    // during the wait. The stepped walk passes the notifiers it captured once
    // before its loop; the single-tile path reads them here.
    final StateController<int> ledgerRevisionNotifier =
        ledgerRevision ?? ref.read(ledgerRevisionProvider.notifier);
    final ConnectivityNotifier connectivityNotifier =
        connectivity ?? ref.read(connectivityProvider.notifier);
    try {
      // #1093/#1129: the client OBSERVES the directed-pair epoch from the
      // SAME provider-filtered basis as the #773 revalidation; the SERVER
      // derives the deterministic dedup id from it, so two devices observing
      // the identical state converge on ONE recorded payment. Fails closed on
      // a valueless basis read, mirroring the #1028 skip semantics. The
      // server authors the settlement doc AND the activity row (actor name,
      // description, event name) — the client sends money facts only.
      final settlements = ref
          .read(
            eventSettlementsProvider((
              groupId: widget.groupId,
              eventId: widget.eventId,
            )),
          )
          .valueOrNull;
      if (settlements == null) {
        throw StateError(
          'settlement basis unavailable — cannot derive dedup epoch',
        );
      }
      final result = await ref
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
            note: note,
            observedPairEpoch: SettlementService.directedPairEpoch(
              settlements,
              payerParticipantId: fromUserId,
              recipientParticipantId: toUserId,
            ),
          );

      // #104: refresh home balance — the server reports whether event-scope
      // content changed (the fail-safe parse defaults toward bumping).
      if (result.shouldBumpLedgerRevision) ledgerRevisionNotifier.state++;
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
        // #1129: an over-outstanding rejection carries the LIVE server-side
        // outstanding — surface it with the #773 balance-changed copy so the
        // user re-reviews against the real number instead of a generic error.
        // #1201: amount embedded in a composed l10n sentence — stays
        // formatCurrency; RAmount governs standalone displayed amounts
        // (DESIGN.md §8).
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

  /// #889: correct a recorded event settlement via the server-authoritative
  /// `correctSettlement` callable (`scope: 'event'`). Replaces the old
  /// client-direct reverse write — the server writes the offsetting reverse
  /// with an un-forgeable `correctionOfSettlementId` marker and emits no
  /// client activity row on its own (mirrors the pre-#889 `logActivity:
  /// false` intent). Corrections are ONLINE-ONLY (an HTTPS callable, not a
  /// Firestore write) — never show the queued/"will sync" success copy;
  /// offline/failure surfaces the existing settlement write-error copy and
  /// writes nothing.
  Future<void> _correctSettlement(
    BuildContext context, {
    required Settlement original,
  }) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final successColor = context.colors.success;
    final errorColor = context.colors.error;
    // #104/#412: capture before the await so the effect survives a disposal
    // during the (now bounded) wait.
    final ledgerRevisionNotifier = ref.read(ledgerRevisionProvider.notifier);
    final connectivityNotifier = ref.read(connectivityProvider.notifier);
    try {
      final result = await ref
          .read(firebaseFunctionsServiceProvider)
          .correctSettlement(
            groupId: widget.groupId,
            scope: 'event',
            eventId: widget.eventId,
            settlementId: original.id,
            correctionNote: l10n.settleUpCorrectionNote,
          );
      if (result.shouldBumpLedgerRevision) {
        ledgerRevisionNotifier.state++; // #104: refresh home balance
      }
      // #1213: a correction rewrote event-scope docs, so the home aggregate
      // doc lags until the async balanceAggregator trigger catches up. Mark it
      // dirty UNCONDITIONALLY on success (independent of the bump above) so the
      // online home facade stays on the once-path instead of serving the
      // pre-correction aggregate. Mirrors the record path (#357).
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
