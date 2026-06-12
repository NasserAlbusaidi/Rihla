import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/share_helper.dart';
import '../../../shared/widgets/directional_icon.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/models/settlement_model.dart';
import '../keys/group_keys.dart';
import '../services/member_name_resolver.dart';
import '../widgets/group_settlement_summary.dart';
import 'all_settled_state.dart';
import 'group_settlement_tile.dart';

/// One currency bucket's settle-up data (#382 PR-1). [balances] and
/// [optimalSettlements] MUST come from the same bucket; [currency] labels
/// every amount in the section.
typedef SettleBucket = ({
  String currency,
  List<UserBalance> balances,
  List<Map<String, dynamic>> optimalSettlements,
});

/// Single-page body for the Settle-Up screens (group + event).
///
/// Wireframe (Hi_GroupSettle, screens-group.jsx) renders one scrollable view:
/// italic headline, two summary chips, optimized transfer cards, then
/// "Each person's net" and a small recorded-payment history.
///
/// Renders one section (summary card, transfer tiles, net rows) per currency
/// bucket (#382 PR-1) — with a single bucket (all prod data under the live
/// uniformity rules) the page is pixel-identical to the pre-bucketing layout.
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

  /// Optional per-tile breakdown (e.g. group-level "per event" attribution).
  /// Return an empty map (or pass null) to hide the expand affordance.
  final Map<String, Decimal> Function(String fromUserId, String toUserId)?
  buildBreakdown;

  const SettleUpPageBody({
    super.key,
    required this.subjectName,
    required this.buckets,
    required this.rawNames,
    required this.settlementsAsync,
    required this.currentUid,
    required this.tileKeys,
    required this.onRecord,
    this.buildBreakdown,
    this.preSelectedMemberId,
  });

  @override
  Widget build(BuildContext context) {
    final totalTransfers = buckets.fold<int>(
      0,
      (n, b) => n + b.optimalSettlements.length,
    );
    final history = settlementsAsync.valueOrNull ?? const <Settlement>[];
    final allSettled = totalTransfers == 0 && history.isEmpty;
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
        buildBreakdown?.call(fromUserId, toUserId) ?? const <String, Decimal>{};

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
          // #282: the debtor records a payment made; the creditor records a
          // payment received. Both write the same direction (payer=debtor,
          // recipient=creditor) — only the framing differs. A pure third party
          // (neither side) still gets no record affordance.
          onRecord: (isYourAction || isCreditor)
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
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space16, vertical: context.spacing.space12),
      child: Row(
        children: [
          _MiniAvatar(name: name),
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

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: context.colors.saffronTint,
        shape: BoxShape.circle,
        border: Border.all(color: context.colors.rule2),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: context.colors.ink2,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
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
  });

  final List<Settlement> settlements;
  final Map<String, String> displayNames;

  /// Group/event name folded into the shareable receipt (#359).
  final String subjectName;

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
          ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.settlement,
    required this.displayNames,
    required this.subjectName,
    required this.index,
  });

  final Settlement settlement;
  final Map<String, String> displayNames;
  final String subjectName;
  final int index;

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
                  color: context.colors.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Iconsax.tick_circle,
                  size: 16,
                  color: context.colors.success,
                ),
              ),
              SizedBox(width: spacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                AppFormatters.formatCurrency(settlement.amount, settlement.currency),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: context.colors.textPrimary,
                ),
              ),
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
