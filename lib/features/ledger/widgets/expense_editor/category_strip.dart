import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../events/models/event_model.dart';
import '../../models/expense_category_model.dart';
import '../../utils/ledger_categories.dart';
import '../../utils/localized_category_name.dart';

class CategoryStrip extends StatelessWidget {
  const CategoryStrip({
    super.key,
    required this.categoriesAsync,
    required this.selectedCategoryId,
    required this.onCategorySelected,
    this.eventType,
  });

  final AsyncValue<List<ExpenseCategory>> categoriesAsync;
  final String? selectedCategoryId;
  final ValueChanged<String> onCategorySelected;

  /// #689: when set, reorders the picker so the event type's likely categories
  /// lead (camping → groceries/fuel first). Null (event still loading) → the
  /// neutral catalog order.
  final EventType? eventType;

  @override
  Widget build(BuildContext context) {
    return categoriesAsync.when(
      loading: () => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space24,
          vertical: context.spacing.space12,
        ),
        child: const LinearProgressIndicator(),
      ),
      error: (_, _) => Padding(
        padding: EdgeInsets.symmetric(horizontal: context.spacing.space24),
        child: Text(
          context.l10n.editorCouldNotLoadCategories,
          style: TextStyle(color: context.colors.errorText),
        ),
      ),
      data: (categories) {
        final order = categoryOrderForType(eventType ?? EventType.custom);
        final sorted = [...categories]
          ..sort((a, b) => order.indexOf(a.id).compareTo(order.indexOf(b.id)));
        return SizedBox(
          height: 42,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.space24),
            scrollDirection: Axis.horizontal,
            itemCount: sorted.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final category = sorted[index];
              return _CategoryChip(
                category: category,
                selected: selectedCategoryId == category.id,
                onTap: () => onCategorySelected(category.id),
              );
            },
          ),
        );
      },
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final ExpenseCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = categoryColorForId(context.colors, category.id);
    final displayName = localizedCategoryName(
      id: category.id,
      fallbackName: category.name,
      l10n: context.l10n,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 12, 8),
        decoration: BoxDecoration(
          color: selected
              ? context.colors.textPrimary
              : context.colors.cardSurface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? context.colors.textPrimary : context.colors.rule2,
          ),
          boxShadow: selected ? context.shadows.flat : context.shadows.raised,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: selected
                    ? context.colors.scaffoldBackground.withValues(alpha: 0.18)
                    : context.colors.cardSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                categoryIconForId(category.id),
                size: 11,
                color: selected ? context.colors.scaffoldBackground : color,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              displayName,
              style: AppTypography.sans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected
                    ? context.colors.scaffoldBackground
                    : context.colors.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
