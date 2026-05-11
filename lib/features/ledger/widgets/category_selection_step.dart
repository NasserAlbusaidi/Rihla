import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/error_widgets.dart';
import '../../../core/services/haptic_service.dart';
import '../models/expense_category_model.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../shared/widgets/skeleton_loader.dart';

/// Category grid for expense classification.
///
/// Step 1 in the 3-step Add Expense flow.
class CategorySelectionStep extends StatelessWidget {
  final AsyncValue<List<ExpenseCategory>> categoriesAsync;
  final String? selectedCategoryId;
  final ValueChanged<String> onCategorySelected;

  const CategorySelectionStep({
    super.key,
    required this.categoriesAsync,
    required this.selectedCategoryId,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return categoriesAsync.when(
      data: (categories) => Column(
        children: [
          const SizedBox(height: 44),
          Text(
            'What was this for?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 44),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
                childAspectRatio: 0.75,
              ),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final cat = categories[index];
                final isSelected = selectedCategoryId == cat.id;
                return _CategoryTile(
                  category: cat,
                  isSelected: isSelected,
                  onTap: () => onCategorySelected(cat.id),
                );
              },
            ),
          ),
        ],
      ),
      loading: SkeletonLoader.card,
      error: (e, _) => const NetworkErrorWidget(),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final ExpenseCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticService.lightClick();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isSelected
                  ? context.colors.primary
                  : context.colors.inputFill,
              borderRadius: BorderRadius.circular(16),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: context.colors.primary.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              category.iconData,
              color: isSelected ? Colors.white : context.colors.textSecondary,
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            category.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? context.colors.textPrimary
                  : context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
