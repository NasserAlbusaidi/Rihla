import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/formatters.dart';
import '../models/expense_model.dart';
import '../services/pre_settlement_review.dart';

/// Test/automation hooks for the pre-settlement review sheet (#204).
abstract final class PreSettleReviewKeys {
  static const sheet = Key('pre_settle_review_sheet');
  static const continueButton = Key('pre_settle_review_continue');
  static const reviewButton = Key('pre_settle_review_action_review');
}

/// Max review-worthy expenses listed before collapsing to "+N more" (#204).
const _maxItems = 5;

/// Shows the non-blocking pre-settlement review sheet (#204). Surfaces the
/// review-worthy expenses (grouped counts + the top items) before the user
/// settles. Returns when dismissed — the caller proceeds regardless (the sheet
/// never blocks). [onReviewAll] fires when "Review expenses" is tapped (the
/// caller routes to the ledger); [onTapExpense] fires when a listed item is
/// tapped (the caller deep-links to that expense's editor).
Future<void> showPreSettlementReviewSheet(
  BuildContext context, {
  required List<ReviewFlag> flags,
  required void Function(Expense expense) onTapExpense,
  required VoidCallback onReviewAll,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.cardSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _PreSettlementReviewSheet(
      flags: flags,
      onTapExpense: onTapExpense,
      onReviewAll: onReviewAll,
    ),
  );
}

/// Reasons in display priority order — the per-item chip shows the first reason
/// an expense matches, and the summary lines render in this order too.
const _reasonOrder = [
  ReviewReason.largeAmount,
  ReviewReason.personal,
  ReviewReason.customParticipants,
  ReviewReason.exactSplit,
];

String _reasonLabel(BuildContext context, ReviewReason reason) =>
    switch (reason) {
      ReviewReason.exactSplit => context.l10n.preSettleReviewReasonExact,
      ReviewReason.customParticipants =>
        context.l10n.preSettleReviewReasonCustom,
      ReviewReason.personal => context.l10n.preSettleReviewReasonPersonal,
      ReviewReason.largeAmount => context.l10n.preSettleReviewReasonLarge,
    };

String _countLine(BuildContext context, ReviewReason reason, int count) =>
    switch (reason) {
      ReviewReason.exactSplit => context.l10n.preSettleReviewExactCount(count),
      ReviewReason.customParticipants =>
        context.l10n.preSettleReviewCustomCount(count),
      ReviewReason.personal => context.l10n.preSettleReviewPersonalCount(count),
      ReviewReason.largeAmount => context.l10n.preSettleReviewLargeCount(count),
    };

class _PreSettlementReviewSheet extends StatelessWidget {
  const _PreSettlementReviewSheet({
    required this.flags,
    required this.onTapExpense,
    required this.onReviewAll,
  });

  final List<ReviewFlag> flags;
  final void Function(Expense expense) onTapExpense;
  final VoidCallback onReviewAll;

  ReviewReason _primaryReason(Expense expense) {
    final reasons = flags
        .where((f) => f.expense.id == expense.id)
        .map((f) => f.reason)
        .toSet();
    return _reasonOrder.firstWhere(reasons.contains);
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final counts = reviewReasonCounts(flags);
    final items = distinctReviewExpenses(flags);
    final shown = items.take(_maxItems).toList();
    final overflow = items.length - shown.length;

    return SafeArea(
      key: PreSettleReviewKeys.sheet,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.space20,
          spacing.space16,
          spacing.space20,
          spacing.space16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.preSettleReviewTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: context.colors.textPrimary,
              ),
            ),
            SizedBox(height: spacing.space12),
            for (final reason in _reasonOrder)
              if ((counts[reason] ?? 0) > 0)
                Padding(
                  padding: EdgeInsets.only(bottom: spacing.space4),
                  child: Text(
                    _countLine(context, reason, counts[reason]!),
                    style: TextStyle(
                      fontSize: 13,
                      color: context.colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            SizedBox(height: spacing.space12),
            for (final expense in shown)
              _ReviewItem(
                expense: expense,
                reason: _primaryReason(expense),
                reasonLabel: _reasonLabel(context, _primaryReason(expense)),
                onTap: () {
                  Navigator.of(context).pop();
                  onTapExpense(expense);
                },
              ),
            if (overflow > 0)
              Padding(
                padding: EdgeInsets.only(top: spacing.space4),
                child: Text(
                  context.l10n.preSettleReviewMore(overflow),
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            SizedBox(height: spacing.space16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: PreSettleReviewKeys.reviewButton,
                    onPressed: () {
                      Navigator.of(context).pop();
                      onReviewAll();
                    },
                    child: Text(context.l10n.preSettleReviewReview),
                  ),
                ),
                SizedBox(width: spacing.space12),
                Expanded(
                  child: FilledButton(
                    key: PreSettleReviewKeys.continueButton,
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.l10n.preSettleReviewContinue),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewItem extends StatelessWidget {
  const _ReviewItem({
    required this.expense,
    required this.reason,
    required this.reasonLabel,
    required this.onTap,
  });

  final Expense expense;
  final ReviewReason reason;
  final String reasonLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(spacing.radiusMedium),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: spacing.space8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.description?.trim().isNotEmpty == true
                        ? expense.description!.trim()
                        : reasonLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    reasonLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.colors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: spacing.space8),
            Text(
              AppFormatters.formatCurrency(expense.amount, expense.currency),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
