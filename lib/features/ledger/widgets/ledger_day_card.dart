import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/models/split_mode.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/r_amount.dart';
import '../keys/ledger_keys.dart';
import '../models/expense_model.dart';
import '../utils/ledger_categories.dart';
import '../utils/ledger_timeline.dart';

/// Two-row day stamp.
///
/// Row 1: italic display name ("Today")
/// Row 2: mono date ("MAY 7") · italic sub-caption (optional)
class LedgerDayStamp extends StatelessWidget {
  const LedgerDayStamp({super.key, required this.label, this.sub});
  final String label;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Label arrives as "Today · May 7" or "May 12" — split on the first " · ".
    final separator = label.indexOf(' · ');
    final name = separator == -1 ? label : label.substring(0, separator);
    final date = separator == -1 ? null : label.substring(separator + 3);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: AppTypography.display(
              fontSize: 23,
              color: colors.textPrimary,
              letterSpacing: -0.3,
              height: 1.1,
            ),
          ),
          if (date != null || (sub != null && sub!.isNotEmpty))
            Padding(
              padding: EdgeInsets.only(top: context.spacing.space4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 2,
                children: [
                  if (date != null)
                    Text(
                      date.toUpperCase(),
                      style: AppTypography.mono(
                        fontSize: 10,
                        color: colors.textSecondary,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (date != null && (sub != null && sub!.isNotEmpty))
                    // textMuted-decorative-justified: middle-dot separator between date and sub-caption is non-textual punctuation.
                    Text(
                      '·',
                      style: AppTypography.mono(
                        fontSize: 10,
                        color: colors.textMuted,
                      ),
                    ),
                  if (sub != null && sub!.isNotEmpty)
                    Text(
                      sub!,
                      style: AppTypography.display(
                        fontSize: 13.5,
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Whole day card — stamp above, white rounded card containing rows.
class LedgerDayCard extends StatelessWidget {
  const LedgerDayCard({
    super.key,
    required this.dayLabel,
    required this.sub,
    required this.items,
    required this.currentParticipantId,
    required this.participantCount,
    required this.expensePayerDisplayNames,
    required this.settlementDisplayNames,
    required this.onExpenseTap,
  });

  final String dayLabel;
  final String? sub;
  final List<LedgerTimelineItem> items;
  final String? currentParticipantId;
  final int participantCount;
  final Map<String, String> expensePayerDisplayNames;
  final Map<String, ({String payerName, String recipientName})>
  settlementDisplayNames;
  final ValueChanged<Expense> onExpenseTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerDayStamp(label: dayLabel, sub: sub),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
          child: Container(
            decoration: BoxDecoration(
              color: colors.cardSurface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: context.shadows.raised,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  _buildRow(context, items[i], i, items.length),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(
    BuildContext context,
    LedgerTimelineItem item,
    int index,
    int total,
  ) {
    return switch (item) {
      LedgerExpenseItem(:final expense) => _ExpenseRow(
        key: LedgerKeys.expenseCard(expense.id),
        expense: expense,
        divider: index < total - 1,
        currentParticipantId: currentParticipantId,
        participantCount: participantCount,
        payerDisplayName:
            expensePayerDisplayNames[expense.id] ??
            expense.payerName ??
            context.l10n.ledgerMemberFallback,
        onTap: () => onExpenseTap(expense),
      ),
      LedgerSettlementItem(:final settlement) => LedgerSettleRow(
        payerName:
            settlementDisplayNames[settlement.id]?.payerName ??
            settlement.payerName ??
            context.l10n.ledgerSomeone,
        recipientName:
            settlementDisplayNames[settlement.id]?.recipientName ??
            settlement.recipientName ??
            context.l10n.ledgerSomeoneLower,
        amount: settlement.amount,
        currency: settlement.currency,
        note: settlement.note,
      ),
    };
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({
    super.key,
    required this.expense,
    required this.divider,
    required this.currentParticipantId,
    required this.participantCount,
    required this.payerDisplayName,
    required this.onTap,
  });

  final Expense expense;
  final bool divider;
  final String? currentParticipantId;
  final int participantCount;
  final String payerDisplayName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bucket = ledgerCategoryBucket(expense.categoryName);
    final isPayer = expense.payerParticipantId == currentParticipantId;
    final l10n = context.l10n;
    final payerName = isPayer ? l10n.ledgerYou : payerDisplayName;
    final splitIds = _effectiveSplitIds(expense);
    final splitCount = splitIds?.length ?? participantCount;
    final share = _userShare(expense);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: context.spacing.space16, vertical: 14),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _CategoryBadge(bucket: bucket),
                SizedBox(width: context.spacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        (expense.description?.isNotEmpty ?? false)
                            ? expense.description!
                            : l10n.ledgerExpenseFallback,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$payerName ${l10n.ledgerPaidConnector} · '
                        '${l10n.ledgerSplitWays(splitCount)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.sans(
                          fontSize: 11.5,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: context.spacing.space8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RAmount(
                      value: expense.amount,
                      currency: expense.currency,
                      size: 14,
                      showCurrency: false,
                    ),
                    if (share != Decimal.zero) ...[
                      const SizedBox(height: 2),
                      RAmount(
                        value: share,
                        currency: expense.currency,
                        size: 11,
                        sign: true,
                        weight: FontWeight.w500,
                        showCurrency: false,
                      ),
                    ],
                  ],
                ),
              ],
            ),
            if (divider) ...[
              const SizedBox(height: 14),
              Container(height: 0.5, color: colors.rule),
            ],
          ],
        ),
      ),
    );
  }

  /// Who shares this expense, mirroring `BalanceCalculator`'s recipient
  /// selection by scope. A non-custom expense persists
  /// `customSplitParticipants: []` (the writer coalesces null -> []), so the
  /// raw field cannot be read as "split 0 ways". Returning null means "fall
  /// back to all participants" (the build/`_userShare` default). (#125)
  static List<String>? _effectiveSplitIds(Expense expense) {
    switch (expense.scope) {
      case ExpenseScope.personal:
        // Only the payer is responsible — no redistribution.
        return [expense.payerParticipantId];
      case ExpenseScope.custom:
        final ids = expense.customSplitParticipants;
        // Empty custom list falls back to all, matching BalanceCalculator.
        return (ids != null && ids.isNotEmpty) ? ids : null;
      case ExpenseScope.global:
      case ExpenseScope.subGroup:
        // Split across everyone; customSplitParticipants is ignored.
        return null;
    }
  }

  /// True for shares/exact/percent splits. `BalanceCalculator` allocates these
  /// via `splitDistribution`; the row only renders an equal per-head share, so
  /// it omits the share line here rather than showing a misleading equal
  /// figure it cannot reproduce. (#125)
  static bool _isNonEqualSplit(Expense expense) {
    final mode = expense.splitMode;
    final distribution = expense.splitDistribution;
    return mode != null &&
        mode != SplitMode.equally &&
        distribution != null &&
        distribution.isNotEmpty;
  }

  Decimal _userShare(Expense expense) {
    if (participantCount == 0 || currentParticipantId == null) {
      return Decimal.zero;
    }
    if (_isNonEqualSplit(expense)) return Decimal.zero;
    final isPayer = expense.payerParticipantId == currentParticipantId;
    final splitIds = _effectiveSplitIds(expense);
    final isInSplit = splitIds?.contains(currentParticipantId) ?? true;
    final splitCount = splitIds?.length ?? participantCount;
    if (splitCount == 0) return Decimal.zero;
    final share = (expense.amount / Decimal.fromInt(splitCount)).toDecimal(
      scaleOnInfinitePrecision: 3,
    );
    if (isPayer && isInSplit) return expense.amount - share;
    if (isPayer && !isInSplit) return expense.amount;
    if (!isPayer && isInSplit) return -share;
    return Decimal.zero;
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.bucket});
  final int bucket;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = ledgerCategoryColor(colors, bucket);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.rule, width: 1),
      ),
      alignment: Alignment.center,
      child: Icon(ledgerCategoryIcon(bucket), size: 18, color: fg),
    );
  }
}

/// Distinct settlement row — dashed sage inset, AA-safe sage-text overline.
class LedgerSettleRow extends StatelessWidget {
  const LedgerSettleRow({
    super.key,
    required this.payerName,
    required this.recipientName,
    required this.amount,
    required this.currency,
    this.note,
  });

  final String payerName;
  final String recipientName;
  final Decimal amount;
  final String currency;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sageText = colors.successText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Container(
        decoration: BoxDecoration(
          color: colors.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sageText.withValues(alpha: 0.4),
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _SettleIcon(sageText: sageText),
            SizedBox(width: context.spacing.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$payerName ${context.l10n.ledgerPaidConnector} '
                    '$recipientName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.sans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _Overline(
                      sageText: sageText,
                      note: note,
                      secondary: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: context.spacing.space8),
            RAmount(
              value: amount,
              currency: currency,
              size: 14,
              weight: FontWeight.w600,
              tone: AmountTone.sage,
              showCurrency: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettleIcon extends StatelessWidget {
  const _SettleIcon({required this.sageText});
  final Color sageText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sageText.withValues(alpha: 0.3), width: 1),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.swap_horiz_rounded, size: 18, color: sageText),
    );
  }
}

class _Overline extends StatelessWidget {
  const _Overline({
    required this.sageText,
    required this.note,
    required this.secondary,
  });
  final Color sageText;
  final String? note;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    final base = AppTypography.mono(
      fontSize: 10.5,
      color: sageText,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w700,
    );
    if (note == null || note!.isEmpty) {
      return Text(context.l10n.ledgerSettlementLabel, style: base);
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: context.l10n.ledgerSettlementLabel, style: base),
          TextSpan(
            text: ' · ${note!}',
            style: AppTypography.mono(
              fontSize: 10.5,
              color: secondary,
              letterSpacing: 0.3,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
