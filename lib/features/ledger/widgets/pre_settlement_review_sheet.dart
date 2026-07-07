import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../models/expense_model.dart';
import '../services/pre_settlement_review.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/r_amount.dart';

/// Test/automation hooks for the pre-settlement review sheet (#204).
abstract final class PreSettleReviewKeys {
  static const sheet = Key('pre_settle_review_sheet');
  static const continueButton = Key('pre_settle_review_continue');
  static const reviewButton = Key('pre_settle_review_action_review');
}

/// Shows the non-blocking pre-settlement review sheet (#204). Surfaces the
/// review-worthy expenses (grouped counts + the top items) before the user
/// settles. Returns when dismissed — the caller proceeds regardless (the sheet
/// never blocks). [onReviewAll] fires when "Review expenses" is tapped (the
/// caller routes to the ledger); pass null to hide that CTA — the group-scope
/// caller has no all-expenses surface to route to (#204, #422 deferred).
/// [onTapExpense] fires when a listed item is tapped (the caller deep-links to
/// that expense's editor).
Future<void> showPreSettlementReviewSheet(
  BuildContext context, {
  required List<ReviewFlag> flags,
  required void Function(Expense expense) onTapExpense,
  VoidCallback? onReviewAll,
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
  // Lowest priority: a departed-payer expense that is ALSO exact/large keeps
  // its stronger primary chip. Every ReviewReason MUST appear here or
  // `_primaryReason`'s `firstWhere` throws (no orElse).
  ReviewReason.payerNotInParticipants,
];

String _reasonLabel(BuildContext context, ReviewReason reason) =>
    switch (reason) {
      ReviewReason.exactSplit => context.l10n.preSettleReviewReasonExact,
      ReviewReason.customParticipants =>
        context.l10n.preSettleReviewReasonCustom,
      ReviewReason.personal => context.l10n.preSettleReviewReasonPersonal,
      ReviewReason.largeAmount => context.l10n.preSettleReviewReasonLarge,
      ReviewReason.payerNotInParticipants =>
        context.l10n.preSettleReviewReasonPayerLeft,
    };

String _countLine(BuildContext context, ReviewReason reason, int count) =>
    switch (reason) {
      ReviewReason.exactSplit => context.l10n.preSettleReviewExactCount(count),
      ReviewReason.customParticipants =>
        context.l10n.preSettleReviewCustomCount(count),
      ReviewReason.personal => context.l10n.preSettleReviewPersonalCount(count),
      ReviewReason.largeAmount => context.l10n.preSettleReviewLargeCount(count),
      ReviewReason.payerNotInParticipants =>
        context.l10n.preSettleReviewPayerLeftCount(count),
    };

class _PreSettlementReviewSheet extends StatelessWidget {
  const _PreSettlementReviewSheet({
    required this.flags,
    required this.onTapExpense,
    required this.onReviewAll,
  });

  final List<ReviewFlag> flags;
  final void Function(Expense expense) onTapExpense;
  final VoidCallback? onReviewAll;

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
    // #521: bucket by currency and cap each independently, so a high-value row
    // in one currency is never hidden behind cheaper rows in another.
    final result = reviewItemList(flags);
    final shown = result.shown;
    final overflow = result.overflow;

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
              style: AppTypography.sans(
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
                    style: AppTypography.sans(
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
                  style: AppTypography.sans(
                    fontSize: 12,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            SizedBox(height: spacing.space16),
            Row(
              children: [
                if (onReviewAll case final onReviewAll?) ...[
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
                ],
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
                    style: AppTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    reasonLabel,
                    style: AppTypography.sans(
                      fontSize: 11,
                      color: context.colors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: spacing.space8),
            RAmount(
              value: expense.amount,
              currency: expense.currency,
              size: 13,
              weight: FontWeight.w700,
            ),
          ],
        ),
      ),
    );
  }
}
