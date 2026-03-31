import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/error_widgets.dart';
import '../../../core/services/haptic_service.dart';
import '../models/expense_category_model.dart';
import '../../../core/theme/tokens/color_tokens.dart';

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
              color: AppColorTokens.light.textPrimary,
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
                childAspectRatio: 0.85,
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
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => NetworkErrorWidget(),
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
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isSelected ? AppColorTokens.light.primary : AppColorTokens.light.inputFill,
              borderRadius: BorderRadius.circular(20),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppColorTokens.light.primary.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              category.iconData,
              color: isSelected ? Colors.white : AppColorTokens.light.textSecondary,
              size: 26,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            category.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? AppColorTokens.light.textPrimary : AppColorTokens.light.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
