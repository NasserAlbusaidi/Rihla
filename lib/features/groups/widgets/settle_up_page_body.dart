import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/models/settlement_model.dart';
import '../../ledger/utils/correction_note.dart';
import '../../ledger/utils/settlement_correction_affordance.dart';
import '../services/member_name_resolver.dart';
import '../widgets/group_settlement_summary.dart';
import 'all_settled_state.dart';
import 'currency_buckets_explainer.dart';
import 'group_settlement_tile.dart';
import 'settle_scope_note.dart';
import 'settle_up_page/history_tile.dart';
import 'settle_up_page/net_balances_section.dart';
import 'settle_up_page/section_label.dart';
import 'settle_up_page/settlement_intro.dart';
import 'settle_up_page/stepped_settle_card.dart';

// Re-exported so every SettleUpPageBody caller gets [SettleScope] (#717) without
// a second import.
export 'settle_scope_note.dart' show SettleScope;

/// One currency bucket's settle-up data (#382 PR-1). [balances] and
/// [optimalSettlements] MUST come from the same bucket; [currency] labels
/// every amount in the section.
typedef SettleBucket = ({
  String currency,
  List<UserBalance> balances,
  List<Map<String, dynamic>> optimalSettlements,
});

/// #1149: prunes settle suggestions naming a party OUTSIDE [currentMemberIds]
/// (a leave/remove-departed uid — rules would deny the write; ghosts and
/// shadows ARE in memberIds and survive the filter). Null set → membership
/// unknown → fail open, nothing pruned. Display-layer only: aggregate
/// quantities (transfers headline, summary totals, all-settled) must keep
/// reading the UNPRUNED list — a departed party's debt is real, unsettleable
/// R1 money, and pruning it out of the aggregates would render "All settled"
/// over a nonzero balance row.
({List<Map<String, dynamic>> kept, int hiddenCount}) filterDepartedSuggestions(
  List<Map<String, dynamic>> optimalSettlements,
  Set<String>? currentMemberIds,
) {
  // Empty = malformed/unresolved data, not "everyone departed": a real group
  // is never memberless (create seeds [creator]; a no-survivor departure
  // soft-deletes the group) — fail open like null (#532 display robustness).
  if (currentMemberIds == null || currentMemberIds.isEmpty) {
    return (kept: optimalSettlements, hiddenCount: 0);
  }
  final kept = [
    for (final s in optimalSettlements)
      if (currentMemberIds.contains(s['fromUserId'] as String) &&
          currentMemberIds.contains(s['toUserId'] as String))
        s,
  ];
  return (kept: kept, hiddenCount: optimalSettlements.length - kept.length);
}

/// One step of a stepped-settle walk (#382 PR-5 D2): a single per-currency
/// settlement, in the bucket [currency] it was computed in. Mirrors the named
/// args of [SettleUpPageBody.onRecord] so the walk driver can reuse the exact
/// per-settlement record machinery once per bucket.
typedef SettleStepRequest = ({
  Map<String, dynamic> settlement,
  String fromRawName,
  String toRawName,
  String fromUserId,
  String toUserId,
  Decimal suggestedAmount,
  String currency,
});

/// Counterparty pairs (involving [currentUid]) that owe across ≥2 currency
/// buckets, each as an ordered list of per-bucket steps (#382 PR-5 D2).
///
/// Scans every bucket's `optimalSettlements` for suggestions where
/// [currentUid] is the payer or recipient, groups them by the OTHER party, and
/// keeps only counterparties spanning ≥2 buckets — single-bucket pairs are the
/// existing per-tile flow, so a stepped card there would be redundant (L2).
/// Steps inherit each bucket's order; callers pass buckets GCC-first so the
/// step list is GCC-first. The raw-name fallback matches `_buildTile`'s
/// (`rawNames[uid] ?? stripDiscriminator(name)`), keeping the write path raw.
List<({String otherUid, String otherName, List<SettleStepRequest> steps})>
steppedSettlePairs({
  required List<SettleBucket> buckets,
  required String? currentUid,
  required Map<String, String> rawNames,
}) {
  if (currentUid == null) return const [];

  final byCounterparty =
      <String, ({String otherName, List<SettleStepRequest> steps})>{};

  for (final bucket in buckets) {
    for (final settlement in bucket.optimalSettlements) {
      final fromUserId = settlement['fromUserId'] as String;
      final toUserId = settlement['toUserId'] as String;
      final involvesMe = fromUserId == currentUid || toUserId == currentUid;
      if (!involvesMe) continue;

      final otherUid = fromUserId == currentUid ? toUserId : fromUserId;
      final fromName = settlement['fromUserName'] as String?;
      final toName = settlement['toUserName'] as String?;
      final otherName = (fromUserId == currentUid ? toName : fromName) ?? '';

      final step = (
        settlement: settlement,
        fromRawName:
            rawNames[fromUserId] ??
            MemberNameResolver.stripDiscriminator(fromName ?? ''),
        toRawName:
            rawNames[toUserId] ??
            MemberNameResolver.stripDiscriminator(toName ?? ''),
        fromUserId: fromUserId,
        toUserId: toUserId,
        suggestedAmount: settlement['amount'] as Decimal,
        currency: bucket.currency,
      );

      final existing = byCounterparty[otherUid];
      if (existing == null) {
        byCounterparty[otherUid] = (otherName: otherName, steps: [step]);
      } else {
        existing.steps.add(step);
      }
    }
  }

  return [
    for (final entry in byCounterparty.entries)
      if (entry.value.steps.length >= 2)
        (
          otherUid: entry.key,
          otherName: entry.value.otherName,
          steps: entry.value.steps,
        ),
  ];
}

/// Single-page body for the Settle-Up screens (group + event).
///
/// Wireframe (Hi_GroupSettle, screens-group.jsx) renders one scrollable view:
/// display headline, two summary chips, the suggested transfer cards
/// (optimized or direct per the group's #363 [simplifyDebts] mode), then
/// "Each person's net" and a small recorded-payment history.
///
/// Renders one section (summary card, transfer tiles, net rows) per currency
/// bucket (#382) — a single-bucket group stays pixel-identical to the
/// pre-bucketing layout, while mixed-currency groups render separate sections.
class SettleUpPageBody extends StatelessWidget {
  /// Which ledger this settle-up surface acts on (#717) — drives the persistent
  /// scope note. Event surface = `event` (covers this event only); group surface
  /// = `group` (whole-group balance; event ledgers stay as they are).
  final SettleScope scope;

  /// Label folded into the intro subtitle ("Optimized to reduce the number of
  /// payments across …" / "Everyone pays their share … across …" per
  /// [simplifyDebts]) — group name on the group screen, event name on the
  /// event screen.
  final String subjectName;

  /// #363: the group's settle-up mode — `true` = min-transfers optimizer
  /// suggestions, `false` = direct pro-rata fan-out. Callers pass
  /// `group.simplifyDebts` (absent field ⇒ true); it MUST match the allocator
  /// that produced [buckets] — the intro copy and the multi-currency explainer
  /// select their mode-honest variants by it.
  final bool simplifyDebts;

  /// Per-currency sections, pre-sorted by the caller (GCC-first). Callers
  /// pass one empty bucket carrying the group currency when there is no
  /// money yet (keeps the zero summary card rendered).
  final List<SettleBucket> buckets;
  final Map<String, String> rawNames;
  final AsyncValue<List<Settlement>> settlementsAsync;
  final String? currentUid;

  /// Group creator uid (actor policy). When non-null, the per-settlement
  /// Correct affordance renders only for the creator or a party
  /// (payer/recipient) of that settlement — mirroring the server gate in
  /// correctSettlement/correctLogicalSettleUp so other members never tap into
  /// a permission-denied. Null leaves the affordance ungated (server still
  /// enforces).
  final String? groupCreatorId;
  final Map<int, GlobalKey> tileKeys;

  /// Pre-selected member to highlight (deep-link).
  final String? preSelectedMemberId;

  /// Whether the current viewer is *write-eligible* for settlements in this
  /// scope (#595). The server gates settlement create on the WRITER, not the
  /// transfer parties: the event path needs `isEventParticipant` (writer ∈
  /// `event.participantIds`), the group path only `isGroupMember`. Since a group
  /// member who is NOT an event participant can still READ (and reach) an event's
  /// settle-up, the event screen passes `false` for them so they don't get a
  /// Record button that the server would `permission-denied`. The group screen
  /// passes `true` (every viewer is already a member). When `false`, no per-tile
  /// Record button and no stepped card render.
  final bool canRecord;

  /// [currency] is the BUCKET currency the suggestion was computed in — the
  /// settlement write must carry it (#382 PR-1).
  final void Function({
    required Map<String, dynamic> settlement,
    required String fromRawName,
    required String toRawName,
    required String fromUserId,
    required String toUserId,
    required Decimal suggestedAmount,
    required String currency,
  })
  onRecord;

  /// Optional per-tile breakdown (e.g. group-level "per event" attribution),
  /// computed in the invoking tile's BUCKET [currency] (#382 PR-3 — the
  /// breakdown is per-currency; no cross-currency netting, ever) at the tile's
  /// suggested transfer [amount] (#752 — so the displayed rows equal what the
  /// settle-up would WRITE; the allocator caps at this amount).
  /// Return an empty map (or pass null) to hide the expand affordance.
  ///
  /// #1204: the map's keys are caller-defined identifiers (e.g. a raw
  /// eventId), NOT necessarily the display text — two entries may share a
  /// display label without colliding, since the label is resolved separately
  /// via [breakdownLabel]. Callers with no distinct identifier can key by
  /// their display label directly (the default resolver is identity).
  final Map<String, Decimal> Function(
    String fromUserId,
    String toUserId,
    String currency,
    Decimal amount,
  )?
  buildBreakdown;

  /// Optional resolver from a [buildBreakdown] key to its display label,
  /// called AT RENDER TIME by [GroupSettlementTile] (#1204) — never baked
  /// into the breakdown map's key, so distinct keys sharing a label render
  /// as distinct rows instead of colliding. Null means the key IS the label
  /// (backward-compatible default).
  final String Function(String key)? breakdownLabel;

  /// Optional one-gesture "settle all with X" driver (#382 PR-5 D2). When
  /// non-null, every counterparty owing across ≥2 currency buckets gets a
  /// stepped card whose tap hands the per-bucket [SettleStepRequest] list to
  /// the screen's walk driver. Null → no stepped cards (the per-tile flow is
  /// the only path).
  final void Function(List<SettleStepRequest> steps)? onRecordStepped;

  /// Optional "correct this payment" driver (#283). When non-null, each recorded
  /// payment in the history exposes an affordance that — after a confirmation
  /// dialog — hands the original [Settlement] back so the screen can record an
  /// offsetting reverse settlement (append-only; the original row stays). Null
  /// hides the affordance.
  final void Function(Settlement settlement)? onCorrect;

  /// Optional "correct a DECOMPOSED settle-up" driver (#753). When non-null, the
  /// history REGROUPS every `groupSettleUpId`-tagged set into one logical row
  /// whose correct affordance hands back the `groupSettleUpId` so the screen can
  /// reverse all N event docs + the residual atomically. The group screen wires
  /// it; the event screen leaves it null → NO regroup (its `settlements` are
  /// one-event-only, so a "logical" total there would be a misleading partial),
  /// preserving the PR1 per-doc rendering. Distinct from [onCorrect] so the
  /// shared single-`Settlement` contract stays untouched.
  final void Function(String groupSettleUpId)? onCorrectLogical;

  /// #1149: FULL `group.memberIds` (never the tombstone-stripped active set —
  /// ghosts stay settleable/correctable). Prunes suggestion TILES + stepped
  /// cards whose party left the group, and hides the Correct affordance on
  /// departed-party history rows. Null = membership unknown → fail open.
  final Set<String>? currentMemberIds;

  /// Bottom padding of the scroll content. Defaults to the standard gutter.
  /// (#789 raised it for the embedded event panel; moot since #1078 — the
  /// workspace FAB shows on the Expenses tab only, so no caller raises it.)
  final double bottomInset;

  /// Optional caller-supplied section rendered after the payment-history
  /// section, inside the scroll, before the [bottomInset] spacer (#818 Wave
  /// 5.3). Null renders nothing — every existing caller is unaffected.
  final Widget? footer;

  const SettleUpPageBody({
    super.key,
    required this.scope,
    required this.subjectName,
    required this.simplifyDebts,
    required this.buckets,
    required this.rawNames,
    required this.settlementsAsync,
    required this.currentUid,
    this.groupCreatorId,
    required this.tileKeys,
    required this.onRecord,
    this.canRecord = true,
    this.buildBreakdown,
    this.breakdownLabel,
    this.preSelectedMemberId,
    this.onRecordStepped,
    this.onCorrect,
    this.onCorrectLogical,
    this.currentMemberIds,
    this.bottomInset = 24,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final totalTransfers = buckets.fold<int>(
      0,
      (n, b) => n + b.optimalSettlements.length,
    );
    final history = settlementsAsync.valueOrNull ?? const <Settlement>[];
    final allSettled = totalTransfers == 0 && history.isEmpty;
    final steppedPairs = (onRecordStepped == null || !canRecord)
        ? const <
            ({String otherUid, String otherName, List<SettleStepRequest> steps})
          >[]
        // #1149: stepped cards are a RECORD surface like the tiles — they
        // must not leak a pruned departed pair. Aggregates below stay on the
        // unpruned buckets on purpose (see filterDepartedSuggestions).
        : steppedSettlePairs(
            buckets: [
              for (final b in buckets)
                (
                  currency: b.currency,
                  balances: b.balances,
                  optimalSettlements: filterDepartedSuggestions(
                    b.optimalSettlements,
                    currentMemberIds,
                  ).kept,
                ),
            ],
            currentUid: currentUid,
            rawNames: rawNames,
          );
    final displayNames = <String, String>{
      for (final bucket in buckets)
        for (final balance in bucket.balances)
          if (balance.displayName != null)
            balance.participantId: balance.displayName!,
    };

    // Tile indices run across ALL buckets so tileKeys / stagger delays stay
    // globally unique (the callers' scroll-to-tile lookup relies on it).
    var tileIndex = 0;
    final sections = <Widget>[];
    for (final bucket in buckets) {
      Decimal totalPending = Decimal.zero;
      for (final s in bucket.optimalSettlements) {
        totalPending += (s['amount'] as Decimal);
      }
      sections.addAll([
        const SizedBox(height: 18),
        GroupSettlementSummaryCard(
          totalPending: totalPending,
          currency: bucket.currency,
        ),
      ]);
      if (allSettled && bucket == buckets.first) {
        sections.addAll([
          SizedBox(height: context.spacing.space32),
          const AllSettledState(),
        ]);
      }
      // #1149: only the actionable tiles are pruned; totalPending/allSettled/
      // headline above keep the unpruned truth. The counted note reconciles
      // the gap and renders even when a bucket's suggestions fully prune.
      final filtered = filterDepartedSuggestions(
        bucket.optimalSettlements,
        currentMemberIds,
      );
      if (filtered.kept.isNotEmpty) {
        sections.add(const SizedBox(height: 18));
        for (final settlement in filtered.kept) {
          sections.add(
            _buildTile(context, settlement, bucket.currency, tileIndex),
          );
          tileIndex++;
        }
      }
      if (filtered.hiddenCount > 0) {
        sections.add(
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 12),
            child: Text(
              context.l10n.settleUpDepartedPairsHidden(filtered.hiddenCount),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: context.colors.textSecondary,
              ),
            ),
          ),
        );
      }
      if (bucket.balances.isNotEmpty) {
        sections.addAll([
          SizedBox(height: context.spacing.space24),
          NetBalancesSection(
            balances: bucket.balances,
            currency: bucket.currency,
          ),
        ]);
      }
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 4, 20, bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettlementIntro(
            transferCount: totalTransfers,
            subjectName: subjectName,
            simplifyDebts: simplifyDebts,
          ),
          // #717: persistent scope note — what a recorded payment here covers
          // (this event only vs the whole-group balance). Display-only.
          SettleScopeNote(scope: scope, subjectName: subjectName),
          // #382 PR-5 L9: one-time "each currency settles separately" card,
          // shown only with ≥2 buckets. The widget self-gates on the seen flag.
          if (buckets.length >= 2)
            CurrencyBucketsExplainer(
              bucketCount: buckets.length,
              simplifyDebts: simplifyDebts,
            ),
          for (final pair in steppedPairs)
            SteppedSettleCard(
              key: ValueKey('settle-stepped-${pair.otherUid}'),
              otherName: pair.otherName,
              steps: pair.steps,
              onTap: () => onRecordStepped!(pair.steps),
            ),
          ...sections,
          if (allSettled && buckets.isEmpty) ...[
            SizedBox(height: context.spacing.space32),
            const AllSettledState(),
          ],
          if (history.isNotEmpty) ...[
            SizedBox(height: context.spacing.space24),
            _PaymentHistorySection(
              settlements: history,
              displayNames: displayNames,
              subjectName: subjectName,
              currentUid: currentUid,
              groupCreatorId: groupCreatorId,
              currentMemberIds: currentMemberIds,
              onCorrect: onCorrect,
              onCorrectLogical: onCorrectLogical,
            ),
          ],
          ?footer,
        ],
      ),
    );
  }

  Widget _buildTile(
    BuildContext context,
    Map<String, dynamic> settlement,
    String currency,
    int index,
  ) {
    final fromUserId = settlement['fromUserId'] as String;
    final toUserId = settlement['toUserId'] as String;
    final fromName = settlement['fromUserName'] as String;
    final toName = settlement['toUserName'] as String;
    final amount = settlement['amount'] as Decimal;

    final isYourAction = currentUid != null && fromUserId == currentUid;
    final isCreditor = currentUid != null && toUserId == currentUid;
    final isHighlighted =
        preSelectedMemberId != null &&
        (fromUserId == preSelectedMemberId || toUserId == preSelectedMemberId);

    final tileKey = GlobalKey();
    tileKeys[index] = tileKey;

    final breakdown =
        buildBreakdown?.call(fromUserId, toUserId, currency, amount) ??
        const <String, Decimal>{};

    return GroupSettlementTile(
          fromName: fromName,
          toName: toName,
          fromUserId: fromUserId,
          toUserId: toUserId,
          amount: amount,
          currency: currency,
          breakdown: breakdown,
          breakdownLabel: breakdownLabel,
          isYourAction: isYourAction,
          isCreditor: isCreditor,
          isHighlighted: isHighlighted,
          tileKey: tileKey,
          // #282/#595: the debtor records a payment made, the creditor a payment
          // received, and any other write-eligible viewer records on the group's
          // behalf (an organizer settling between two others). All three write the
          // same direction (payer=debtor, recipient=creditor) — only the framing
          // (#595 RecordPaymentPerspective) differs. The server gates create on
          // the WRITER (no payer==auth pin), so the affordance is unconditional
          // for write-eligible viewers but suppressed when [canRecord] is false
          // (an event non-participant viewing an event ledger — they'd be
          // permission-denied).
          onRecord: canRecord
              ? () {
                  assert(
                    rawNames.containsKey(fromUserId),
                    'rawNames must include every settlement participant',
                  );
                  assert(
                    rawNames.containsKey(toUserId),
                    'rawNames must include every settlement participant',
                  );
                  onRecord(
                    settlement: settlement,
                    fromRawName:
                        rawNames[fromUserId] ??
                        MemberNameResolver.stripDiscriminator(fromName),
                    toRawName:
                        rawNames[toUserId] ??
                        MemberNameResolver.stripDiscriminator(toName),
                    fromUserId: fromUserId,
                    toUserId: toUserId,
                    suggestedAmount: amount,
                    currency: currency,
                  );
                }
              : null,
        )
        .animate()
        .fadeIn(delay: Duration(milliseconds: index * 50))
        .slideY(begin: 0.1, curve: Curves.easeOutCubic);
  }
}

/// Inline list of past recorded payments shown beneath net balances.
///
/// Wireframe omits this — kept as a low-emphasis footer so the feature
/// stays accessible without a dedicated tab or route.
class _PaymentHistorySection extends StatelessWidget {
  const _PaymentHistorySection({
    required this.settlements,
    required this.displayNames,
    required this.subjectName,
    this.currentUid,
    this.groupCreatorId,
    this.currentMemberIds,
    this.onCorrect,
    this.onCorrectLogical,
  });

  final List<Settlement> settlements;
  final Map<String, String> displayNames;

  /// Group/event name folded into the shareable receipt (#359).
  final String subjectName;

  /// Actor policy inputs — see [SettleUpPageBody.groupCreatorId].
  final String? currentUid;
  final String? groupCreatorId;

  /// #283: hands a recorded payment back for an offsetting correction.
  final void Function(Settlement settlement)? onCorrect;

  /// #753: hands a `groupSettleUpId` back for an atomic logical correction.
  /// Non-null ONLY on the group screen — it also switches on the regroup.
  final void Function(String groupSettleUpId)? onCorrectLogical;

  /// #1149 party gate — see [SettleUpPageBody.currentMemberIds]. Null fails
  /// open; otherwise mirrors the callables' failed-precondition check
  /// (correctSettlement.ts / correctLogicalSettleUp.ts: both parties must be
  /// in FULL memberIds — ghosts stay correctable). Orthogonal to
  /// [_canCorrect], which is ACTOR eligibility.
  final Set<String>? currentMemberIds;

  bool _canCorrect(Settlement settlement) {
    if (groupCreatorId == null) return true;
    if (currentUid == null) return false;
    return currentUid == groupCreatorId ||
        settlement.payerParticipantId == currentUid ||
        settlement.recipientParticipantId == currentUid;
  }

  bool _partiesCurrent(Settlement settlement) {
    final ids = currentMemberIds;
    // Empty = malformed data, not "everyone departed" — fail open like null
    // (same reasoning as filterDepartedSuggestions).
    if (ids == null || ids.isEmpty) return true;
    return settlementPartiesAreCurrentMembers(settlement, ids);
  }

  @override
  Widget build(BuildContext context) {
    // #753: regroup tagged settle-ups into one logical row ONLY on the group
    // screen (where onCorrectLogical is wired). The event screen keeps the PR1
    // per-doc rendering (its settlements are one-event-only; a regrouped "total"
    // would be a misleading partial).
    final children = <Widget>[
      SectionLabel(label: context.l10n.settleUpPaymentHistory),
      const SizedBox(height: 10),
    ];

    if (onCorrectLogical == null) {
      for (var i = 0; i < settlements.length; i++) {
        final settlement = settlements[i];
        children.add(
          HistoryTile(
            settlement: settlement,
            displayNames: displayNames,
            subjectName: subjectName,
            index: i,
            onCorrect: (_canCorrect(settlement) && _partiesCurrent(settlement))
                ? onCorrect
                : null,
            soloCorrectionHidden: isSoloCorrectionHidden(
              settlement,
              settlements,
            ),
          ),
        );
      }
    } else {
      final rows = groupSettlementHistory(settlements);
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        switch (row) {
          case SoloHistoryRow(:final settlement):
            children.add(
              HistoryTile(
                settlement: settlement,
                displayNames: displayNames,
                subjectName: subjectName,
                index: i,
                onCorrect:
                    (_canCorrect(settlement) && _partiesCurrent(settlement))
                    ? onCorrect
                    : null,
                soloCorrectionHidden: isSoloCorrectionHidden(
                  settlement,
                  settlements,
                ),
              ),
            );
          case LogicalHistoryRow():
            children.add(
              HistoryTile(
                settlement: row.representative,
                displayNames: displayNames,
                subjectName: subjectName,
                index: i,
                overrideAmount: row.totalAmount,
                isCorrectedLogical: row.isCorrected,
                // Every leg of a decomposed settle-up shares one
                // payer→recipient pair, so the representative stands in for
                // the whole set; the server still checks EVERY original.
                onCorrectLogical:
                    (row.affordanceCorrected ||
                        !_canCorrect(row.representative) ||
                        !_partiesCurrent(row.representative))
                    ? null
                    : () => onCorrectLogical!(row.groupSettleUpId),
              ),
            );
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// One rendered row of the settle-up payment history (#753).
sealed class HistoryRow {
  const HistoryRow();
}

/// An untagged settlement — a legacy/standalone group settlement or its
/// single-doc correction. Rendered byte-identically to the pre-#753 history
/// (its own one-tap correct, "Correction" label when the note matches).
class SoloHistoryRow extends HistoryRow {
  const SoloHistoryRow(this.settlement);
  final Settlement settlement;
}

/// A regroup of every doc sharing one `groupSettleUpId` — the N event
/// settlements + residual of one decomposed settle-up (#752/#753) collapsed into
/// ONE row. [totalAmount] folds only the NON-correction docs (= the logical
/// transfer A); [isCorrected] is true once a tagged reverse (correction note) is
/// present — DISPLAY only (accent/tag), note-based, unchanged by #889.
/// [affordanceCorrected] is the #889 marker/bounded-legacy write-affordance
/// signal that hides the correct button — true only when EVERY eligible
/// original in the tagged set provably has a valid reverse; a partially-marked
/// set keeps [isCorrected] displaying "corrected" while the action stays live
/// so the callable can repair the remainder (intentional transient).
class LogicalHistoryRow extends HistoryRow {
  const LogicalHistoryRow({
    required this.groupSettleUpId,
    required this.representative,
    required this.totalAmount,
    required this.isCorrected,
    required this.affordanceCorrected,
    required this.settledAt,
  });

  final String groupSettleUpId;

  /// The newest non-correction doc — source of payer/recipient/currency/ids.
  final Settlement representative;
  final Decimal totalAmount;
  final bool isCorrected;
  final bool affordanceCorrected;
  final DateTime settledAt;
}

/// Collapses a settle-up history into display rows. Untagged docs stay
/// individual [SoloHistoryRow]s in the incoming (newest-first) order; each
/// `groupSettleUpId`-tagged set becomes ONE [LogicalHistoryRow] positioned at
/// its newest member. Input is assumed pre-sorted newest-first (the screen sorts
/// the group-doc ∪ tagged-event-doc union by `settledAt` descending). Pure.
@visibleForTesting
List<HistoryRow> groupSettlementHistory(List<Settlement> settlements) {
  // Pre-group tagged members so a logical row sees ALL of its docs regardless
  // of where each sits in the input order.
  final tagged = <String, List<Settlement>>{};
  for (final s in settlements) {
    final id = s.groupSettleUpId;
    if (id != null) (tagged[id] ??= <Settlement>[]).add(s);
  }

  final rows = <HistoryRow>[];
  final seen = <String>{};
  for (final s in settlements) {
    final id = s.groupSettleUpId;
    if (id == null) {
      rows.add(SoloHistoryRow(s));
      continue;
    }
    if (!seen.add(id)) continue; // already folded this logical set
    final members = tagged[id]!;
    final originals = members.where((m) => !isCorrectionNote(m.note)).toList();
    if (originals.isEmpty) {
      // Defensive: a tagged set with no non-correction doc (corruption / an
      // orphaned reverse) — never a phantom logical row; render its members
      // individually at this newest-first position.
      rows.addAll(members.map(SoloHistoryRow.new));
      continue;
    }
    final total = originals.fold<Decimal>(
      Decimal.zero,
      (sum, m) => sum + m.amount,
    );
    final settledAt = members
        .map((m) => m.settledAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    rows.add(
      LogicalHistoryRow(
        groupSettleUpId: id,
        representative: originals.first,
        totalAmount: total,
        isCorrected: members.any((m) => isCorrectionNote(m.note)),
        affordanceCorrected: logicalSetAffordanceCorrected(members),
        settledAt: settledAt,
      ),
    );
  }
  return rows;
}

