import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../models/expense_category_model.dart';
import '../providers/category_provider.dart';

/// Bottom-sheet category picker matching Hi_Sheet_Category (tier 6).
///
/// Lists trip categories as RRow-style tiles with a tinted leading square,
/// name, example subtitle, and a saffron checkmark on the selected row.
/// Returns the chosen category id (or null if dismissed).
Future<String?> showCategoryPickerSheet(
  BuildContext context, {
  required String tripId,
  required String? selectedCategoryId,
}) {
  return showModalBottomSheet<String?>(
    context: context,
    backgroundColor: context.colors.scaffoldBackground,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => CategoryPickerSheet(
      tripId: tripId,
      selectedCategoryId: selectedCategoryId,
    ),
  );
}

class CategoryPickerSheet extends ConsumerWidget {
  const CategoryPickerSheet({
    super.key,
    required this.tripId,
    required this.selectedCategoryId,
  });

  final String tripId;
  final String? selectedCategoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final spacing = context.spacing;
    final categoriesAsync = ref.watch(tripCategoriesProvider(tripId));

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: spacing.space12),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.rule2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(height: spacing.space12),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.space24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "What's this for?",
                style: AppTypography.display(
                  fontSize: 26,
                  color: colors.textPrimary,
                  height: 1.15,
                ),
              ),
            ),
          ),
          SizedBox(height: spacing.space16),
          Flexible(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.space24,
                0,
                spacing.space24,
                spacing.space24,
              ),
              child: categoriesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'Could not load categories.\n$e',
                    style: AppTypography.sans(
                      fontSize: 13,
                      color: colors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                data: (categories) => SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: colors.cardSurface,
                          borderRadius: BorderRadius.circular(
                            spacing.radiusLarge,
                          ),
                          boxShadow: context.shadows.raised,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            for (var i = 0; i < categories.length; i++)
                              _CategoryRow(
                                category: categories[i],
                                selected:
                                    selectedCategoryId == categories[i].id,
                                showDivider: i < categories.length - 1,
                                onTap: () {
                                  HapticService.selection();
                                  Navigator.of(context).pop(categories[i].id);
                                },
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.selected,
    required this.showDivider,
    required this.onTap,
  });

  final ExpenseCategory category;
  final bool selected;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = category.resolveColor(colors);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: showDivider ? colors.rule : Colors.transparent,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                category.name.isNotEmpty ? category.name[0].toUpperCase() : '·',
                style: AppTypography.display(fontSize: 18, color: Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    style: AppTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _exampleFor(category.name),
                    style: AppTypography.sans(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, size: 20, color: colors.primary),
          ],
        ),
      ),
    );
  }

  String _exampleFor(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('food') ||
        lower.contains('din') ||
        lower.contains('meal')) {
      return 'Restaurants, bars, cafés';
    }
    if (lower.contains('lodg') ||
        lower.contains('hotel') ||
        lower.contains('stay')) {
      return 'Hotels, rentals';
    }
    if (lower.contains('trans') ||
        lower.contains('taxi') ||
        lower.contains('flight')) {
      return 'Taxi, train, fuel';
    }
    if (lower.contains('groc') || lower.contains('market')) {
      return 'Markets, supplies';
    }
    if (lower.contains('activ') ||
        lower.contains('tour') ||
        lower.contains('ticket')) {
      return 'Tours, tickets';
    }
    if (lower.contains('gas') || lower.contains('fuel')) {
      return 'Petrol, charging';
    }
    if (lower.contains('gear')) {
      return 'Equipment, supplies';
    }
    return 'Anything else';
  }
}
