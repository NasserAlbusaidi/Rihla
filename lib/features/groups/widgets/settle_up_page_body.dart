import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/share_helper.dart';
import '../../../shared/widgets/directional_icon.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/models/settlement_model.dart';
import '../keys/group_keys.dart';
import '../services/member_name_resolver.dart';
import '../widgets/group_settlement_summary.dart';
import 'all_settled_state.dart';
import 'currency_buckets_explainer.dart';
import 'group_settlement_tile.dart';

/// One currency bucket's settle-up data (#382 PR-1). [balances] and
/// [optimalSettlements] MUST come from the same bucket; [currency] labels
/// every amount in the section.
typedef SettleBucket = ({
  String currency,
  List<UserBalance> balances,
  List<Map<String, dynamic>> optimalSettlements,
});

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
/// italic headline, two summary chips, optimized transfer cards, then
/// "Each person's net" and a small recorded-payment history.
///
/// Renders one section (summary card, transfer tiles, net rows) per currency
/// bucket (#382) — a single-bucket group stays pixel-identical to the
/// pre-bucketing layout, while mixed-currency groups render separate sections.
class SettleUpPageBody extends StatelessWidget {
  /// Label shown after "Optimized to minimise the number of payments across …"
  /// — group name on the group screen, event name on the event screen.
  final String subjectName;

  /// Per-currency sections, pre-sorted by the caller (GCC-first). Callers
  /// pass one empty bucket carrying the group currency when there is no
  /// money yet (keeps the zero summary card rendered).
  final List<SettleBucket> buckets;
  final Map<String, String> rawNames;
  final AsyncValue<List<Settlement>> settlementsAsync;
  final String? currentUid;
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
  final Map<String, Decimal> Function(
    String fromUserId,
    String toUserId,
    String currency,
    Decimal amount,
  )?
  buildBreakdown;

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

  const SettleUpPageBody({
    super.key,
    required this.subjectName,
    required this.buckets,
    required this.rawNames,
    required this.settlementsAsync,
    required this.currentUid,
    required this.tileKeys,
    required this.onRecord,
    this.canRecord = true,
    this.buildBreakdown,
    this.preSelectedMemberId,
    this.onRecordStepped,
    this.onCorrect,
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
        : steppedSettlePairs(
            buckets: buckets,
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
      if (bucket.optimalSettlements.isNotEmpty) {
        sections.add(const SizedBox(height: 18));
        for (final settlement in bucket.optimalSettlements) {
          sections.add(
            _buildTile(context, settlement, bucket.currency, tileIndex),
          );
          tileIndex++;
        }
      }
      if (bucket.balances.isNotEmpty) {
        sections.addAll([
          SizedBox(height: context.spacing.space24),
          _NetBalancesSection(
            balances: bucket.balances,
            currency: bucket.currency,
          ),
        ]);
      }
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettlementIntro(
            transferCount: totalTransfers,
            subjectName: subjectName,
          ),
          // #382 PR-5 L9: one-time "each currency settles separately" card,
          // shown only with ≥2 buckets. The widget self-gates on the seen flag.
          if (buckets.length >= 2)
            CurrencyBucketsExplainer(bucketCount: buckets.length),
          for (final pair in steppedPairs)
            _SteppedSettleCard(
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
              onCorrect: onCorrect,
            ),
          ],
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
          amount: amount,
          currency: currency,
          breakdown: breakdown,
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

class _SettlementIntro extends StatelessWidget {
  const _SettlementIntro({
    required this.transferCount,
    required this.subjectName,
  });

  final int transferCount;
  final String subjectName;

  @override
  Widget build(BuildContext context) {
    final headline = transferCount == 0
        ? context.l10n.settleUpEveryoneEvenHeadline
        : context.l10n.settleUpTransfersHeadline(transferCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          headline,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 28,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w400,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          transferCount == 0
              ? context.l10n.settleUpNoOptimizedPayments(subjectName)
              : context.l10n.settleUpOptimizedPayments(subjectName),
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 13,
            height: 1.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// One-gesture "settle all with X" card (#382 PR-5 D2). Shown above the bucket
/// sections for each counterparty owing across ≥2 currency buckets; tapping it
/// drives the per-bucket stepped walk. The caption joins each step's
/// code-first amount so the user sees exactly what the walk will record before
/// they start.
class _SteppedSettleCard extends StatelessWidget {
  const _SteppedSettleCard({
    super.key,
    required this.otherName,
    required this.steps,
    required this.onTap,
  });

  final String otherName;
  final List<SettleStepRequest> steps;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final amounts = steps
        .map((s) => AppFormatters.formatCurrency(s.suggestedAmount, s.currency))
        .join(' · ');
    final caption =
        '${context.l10n.settleUpSettleAllWithCount(steps.length)} · $amounts';

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
          child: Ink(
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
              border: Border.all(color: context.colors.primary),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: context.spacing.space16,
              vertical: context.spacing.space12,
            ),
            child: Row(
              children: [
                Icon(Iconsax.cards, size: 18, color: context.colors.primary),
                SizedBox(width: context.spacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.settleUpSettleAllWith(otherName),
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        caption,
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: context.spacing.space8),
                DirectionalIcon(
                  Iconsax.arrow_right_3,
                  size: 16,
                  color: context.colors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NetBalancesSection extends StatelessWidget {
  const _NetBalancesSection({required this.balances, required this.currency});

  final List<UserBalance> balances;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: context.l10n.settleUpEachPersonNet),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: context.colors.cardSurface,
            borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
            border: Border.all(color: context.colors.rule),
            boxShadow: context.shadows.raised,
          ),
          child: Column(
            children: [
              for (var i = 0; i < balances.length; i++)
                _NetBalanceRow(
                  balance: balances[i],
                  currency: currency,
                  showDivider: i < balances.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NetBalanceRow extends StatelessWidget {
  const _NetBalanceRow({
    required this.balance,
    required this.currency,
    required this.showDivider,
  });

  final UserBalance balance;
  final String currency;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final name = balance.displayName ?? context.l10n.settleUpUnknown;
    final amountColor = balance.netBalance > Decimal.zero
        ? context.colors.successText
        : balance.netBalance < Decimal.zero
        ? context.colors.errorText
        : context.colors.textSecondary;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: showDivider
              ? BorderSide(color: context.colors.rule)
              : BorderSide.none,
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: context.spacing.space16,
        vertical: context.spacing.space12,
      ),
      child: Row(
        children: [
          RAvatar(name: name, size: 28),
          SizedBox(width: context.spacing.space12),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            AppFormatters.formatCurrency(balance.netBalance, currency),
            style: TextStyle(
              color: amountColor,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: context.spacing.space4),
      child: Text(
        label,
        style: TextStyle(
          color: context.colors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
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
    this.onCorrect,
  });

  final List<Settlement> settlements;
  final Map<String, String> displayNames;

  /// Group/event name folded into the shareable receipt (#359).
  final String subjectName;

  /// #283: hands a recorded payment back for an offsetting correction.
  final void Function(Settlement settlement)? onCorrect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: context.l10n.settleUpPaymentHistory),
        const SizedBox(height: 10),
        for (var i = 0; i < settlements.length; i++)
          _HistoryTile(
            settlement: settlements[i],
            displayNames: displayNames,
            subjectName: subjectName,
            index: i,
            onCorrect: onCorrect,
          ),
      ],
    );
  }
}

/// The app-authored correction-note sentinel
/// ([AppLocalizations.settleUpCorrectionNote]) in EVERY supported locale. A
/// reversing settlement (#283) carries this note in the CORRECTOR's locale, so
/// recognizing it on read must not assume the viewer's locale matches. Computed
/// once. (#567)
final Set<String> _correctionNoteSentinels = {
  for (final locale in AppLocalizations.supportedLocales)
    lookupAppLocalizations(locale).settleUpCorrectionNote,
};

/// True when [note] marks a #283 reversing correction — so Payment history can
/// render it as a correction rather than another (duplicate-looking) payment.
bool _isCorrectionNote(String? note) =>
    note != null && _correctionNoteSentinels.contains(note);

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.settlement,
    required this.displayNames,
    required this.subjectName,
    required this.index,
    this.onCorrect,
  });

  final Settlement settlement;
  final Map<String, String> displayNames;
  final String subjectName;
  final int index;

  /// #283: when non-null AND both party ids are present, this tile shows a
  /// "correct this payment" affordance that records an offsetting reverse
  /// settlement after a confirmation dialog.
  final void Function(Settlement settlement)? onCorrect;

  /// Confirms then hands the original [settlement] to [onCorrect]. The dialog
  /// describes the REVERSE flow (the recipient pays the payer back) and reuses
  /// the tile's already-resolved [payerName]/[recipientName] locals.
  Future<void> _confirmAndCorrect(
    BuildContext context,
    String payerName,
    String recipientName,
  ) async {
    final l10n = context.l10n;
    final amountStr = AppFormatters.formatCurrency(
      settlement.amount,
      settlement.currency,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.settleUpCorrectTitle),
        content: Text(
          l10n.settleUpCorrectBody(amountStr, recipientName, payerName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.settleUpCorrectConfirm),
          ),
        ],
      ),
    );
    if (confirmed == true) onCorrect!(settlement);
  }

  /// Composes the plain-text receipt shared via [shareText] (#359). Built only
  /// from persisted fields — payer/recipient, amount, date, group/event name,
  /// and the note when present (payment method is never persisted, so it is
  /// not claimed here). The amount is formatted code-first (#144) and stays LTR.
  String _composeReceipt(
    BuildContext context,
    String payerName,
    String recipientName,
    String dateStr,
  ) {
    final l10n = context.l10n;
    final lines = <String>[
      l10n.settleUpReceiptLine(
        payerName,
        recipientName,
        AppFormatters.formatCurrency(settlement.amount, settlement.currency),
      ),
      l10n.settleUpReceiptContext(dateStr, subjectName),
    ];
    final note = settlement.note?.trim();
    if (note != null && note.isNotEmpty) {
      lines.add(note);
    }
    lines.add(l10n.settleUpReceiptFooter);
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacingTokens.standard;
    final payerId = settlement.payerParticipantId;
    final recipientId = settlement.recipientParticipantId;
    final payerName =
        (payerId == null ? null : displayNames[payerId]) ??
        settlement.payerName ??
        context.l10n.settleUpUnknown;
    final recipientName =
        (recipientId == null ? null : displayNames[recipientId]) ??
        settlement.recipientName ??
        context.l10n.settleUpUnknown;
    final dateStr = DateFormat.MMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(settlement.settledAt);
    // #567: a reversing correction must read as a correction, not as another
    // payment. Mark it with a reversal icon + label instead of the green tick.
    final isCorrection = _isCorrectionNote(settlement.note);
    final accent = isCorrection
        ? context.colors.textSecondary
        : context.colors.success;

    return Container(
          margin: EdgeInsets.only(bottom: spacing.space8),
          decoration: BoxDecoration(
            color: context.colors.cardSurface,
            borderRadius: BorderRadius.circular(spacing.radiusMedium),
            border: Border.all(color: context.colors.rule),
            boxShadow: context.shadows.raised,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: spacing.space16,
            vertical: spacing.space12,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCorrection ? Iconsax.undo : Iconsax.tick_circle,
                  size: 16,
                  color: accent,
                ),
              ),
              SizedBox(width: spacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isCorrection) ...[
                      Text(
                        context.l10n.settleUpCorrectionTag,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: context.colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    RichText(
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 13,
                          color: context.colors.textPrimary,
                        ),
                        children: [
                          TextSpan(
                            text: payerName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(
                            text: ' ${context.l10n.settleUpPaidConnector} ',
                          ),
                          TextSpan(
                            text: recipientName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                AppFormatters.formatCurrency(
                  settlement.amount,
                  settlement.currency,
                ),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: context.colors.textPrimary,
                ),
              ),
              // #283: correct a recorded payment by recording an offsetting
              // reverse settlement (append-only). Shown only when a correction
              // driver is wired AND both party ids are present (the offset needs
              // both to target). Keyed on the newest tile for a stable test hook.
              // #752: HIDDEN on a decomposed group settle-up (groupSettleUpId !=
              // null) — the group-only onCorrect reverse would move the
              // aggregate but NOT the event ledger, re-introducing the very
              // divergence this fixes. Atomic logical-settle-up correction is
              // PR2; until then, record a manual offsetting transfer. Legacy /
              // standalone settlements (null id) keep one-tap correction.
              if (onCorrect != null &&
                  settlement.groupSettleUpId == null &&
                  payerId != null &&
                  payerId.isNotEmpty &&
                  recipientId != null &&
                  recipientId.isNotEmpty) ...[
                SizedBox(width: spacing.space4),
                IconButton(
                  key: index == 0 ? GroupKeys.settleUpCorrectButton : null,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  tooltip: context.l10n.settleUpCorrect,
                  icon: Icon(
                    Iconsax.undo,
                    size: 16,
                    color: context.colors.textSecondary,
                  ),
                  onPressed: () =>
                      _confirmAndCorrect(context, payerName, recipientName),
                ),
              ],
              SizedBox(width: spacing.space4),
              // #359: share a plain-text receipt of this recorded payment. The
              // Builder gives shareText() the button's own render box as the
              // popover origin (non-zero on iPad); never call Share.share raw.
              Builder(
                builder: (buttonContext) => IconButton(
                  // Key only the newest tile so a single, predictable target
                  // anchors widget tests; every tile is still shareable.
                  key: index == 0 ? GroupKeys.settleUpShareReceiptButton : null,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  tooltip: context.l10n.settleUpShareReceipt,
                  icon: DirectionalIcon(
                    Iconsax.send_2,
                    size: 16,
                    color: context.colors.primary,
                  ),
                  onPressed: () => shareText(
                    buttonContext,
                    _composeReceipt(
                      buttonContext,
                      payerName,
                      recipientName,
                      dateStr,
                    ),
                    subject: context.l10n.settleUpReceiptShareSubject,
                  ),
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(delay: Duration(milliseconds: index * 40))
        .slideY(begin: 0.08, curve: Curves.easeOutCubic);
  }
}
