import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../models/expense_model.dart';
import '../utils/ledger_categories.dart';

class LedgerCategoryStrip extends StatelessWidget {
  const LedgerCategoryStrip({
    super.key,
    required this.expenses,
    required this.totalCount,
    required this.active,
    required this.onChange,
  });

  final List<Expense> expenses;
  final int totalCount;
  final int? active;
  final ValueChanged<int?> onChange;

  @override
  Widget build(BuildContext context) {
    final present = <int>{};
    for (final e in expenses) {
      present.add(ledgerCategoryBucket(e.categoryId));
    }
    const order = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    final available = order.where(present.contains).toList(growable: false);

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        children: [
          _AllChip(
            count: totalCount,
            active: active == null,
            onTap: () => onChange(null),
          ),
          const SizedBox(width: 8),
          for (final cat in available) ...[
            _CategoryChip(
              bucket: cat,
              active: active == cat,
              onTap: () => onChange(cat),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _AllChip extends StatelessWidget {
  const _AllChip({
    required this.count,
    required this.active,
    required this.onTap,
  });
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: () {
        HapticService.selection();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: context.spacing.space12, vertical: context.spacing.space8),
        decoration: BoxDecoration(
          color: active ? colors.textPrimary : colors.cardSurface,
          borderRadius: BorderRadius.circular(context.spacing.radiusPill),
          border: Border.all(
            color: active ? colors.textPrimary : colors.rule2,
            width: 1,
          ),
        ),
        // Label and count are separate spans; the count is LTR-isolated so the
        // old "label · N" string can't collapse into "All 20" in Arabic (#155).
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.ledgerAllFilter,
              style: AppTypography.sans(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: active ? colors.scaffoldBackground : colors.ink2,
              ),
            ),
            const SizedBox(width: 6),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                '($count)',
                style: AppTypography.sans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: active ? colors.scaffoldBackground : colors.ink2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.bucket,
    required this.active,
    required this.onTap,
  });
  final int bucket;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: () {
        HapticService.selection();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: context.spacing.space12, vertical: context.spacing.space8),
        decoration: BoxDecoration(
          color: active ? colors.textPrimary : colors.cardSurface,
          borderRadius: BorderRadius.circular(context.spacing.radiusPill),
          border: Border.all(
            color: active ? colors.textPrimary : colors.rule2,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: ledgerCategoryColor(colors, bucket),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              ledgerCategoryName(bucket, context.l10n),
              style: AppTypography.sans(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: active ? colors.scaffoldBackground : colors.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Special-case chip rendered when there are no expenses — an "All (0)" pill
/// with an inline italic helper "categories appear as you log them".
class LedgerCategoryStripEmpty extends StatelessWidget {
  const LedgerCategoryStripEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.space12, vertical: context.spacing.space8),
            decoration: BoxDecoration(
              color: colors.cardSurface,
              borderRadius: BorderRadius.circular(context.spacing.radiusPill),
              border: Border.all(color: colors.rule2, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.ledgerAllFilter,
                  style: AppTypography.sans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(width: 6),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    '(0)',
                    style: AppTypography.sans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              context.l10n.ledgerCategoriesAppear,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.display(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
