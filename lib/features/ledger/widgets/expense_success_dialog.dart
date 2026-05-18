import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/formatters.dart';
import '../utils/localized_category_name.dart';
import '../models/expense_model.dart';

/// Success dialog shown after saving an expense.
class ExpenseSuccessDialog extends StatelessWidget {
  final Expense expense;
  final String currency;
  final VoidCallback onDone;
  final VoidCallback onAddAnother;

  const ExpenseSuccessDialog({
    super.key,
    required this.expense,
    required this.currency,
    required this.onDone,
    required this.onAddAnother,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.colors.scaffoldBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Close button
              Align(
                alignment: AlignmentDirectional.topEnd,
                child: IconButton(
                  icon: Icon(Icons.close, color: context.colors.textSecondary),
                  onPressed: onDone,
                ),
              ),

              // Success Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: context.colors.selectionFill,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Iconsax.tick_circle5,
                  size: 48,
                  color: context.colors.primary,
                ),
              ).animate().scale(
                delay: 100.ms,
                duration: 300.ms,
                curve: Curves.elasticOut,
              ),

              const SizedBox(height: 16),

              Text(
                context.l10n.expenseSuccessTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),

              const SizedBox(height: 4),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: context.colors.inputFill,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: context.colors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.l10n.expenseSuccessSyncedToCloud,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Summary Card
              _ExpenseSummaryCard(expense: expense, currency: currency),

              const SizedBox(height: 24),

              // Done Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: onDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        context.l10n.expenseSuccessDone,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Iconsax.tick_circle, size: 18),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Add Another
              TextButton(
                onPressed: onAddAnother,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Iconsax.add, size: 18),
                    const SizedBox(width: 8),
                    Text(context.l10n.expenseSuccessAddAnother),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpenseSummaryCard extends StatelessWidget {
  final Expense expense;
  final String currency;

  const _ExpenseSummaryCard({required this.expense, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.shadows.raised,
      ),
      child: Column(
        children: [
          Text(
            context.l10n.expenseSuccessTotalAmount,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          Text(
            AppFormatters.formatCurrency(expense.amount, currency),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Category row
          if (expense.categoryId != null || expense.categoryName != null)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.colors.selectionFill,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Iconsax.category,
                    size: 18,
                    color: context.colors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.expenseSuccessCategory,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      localizedCategoryName(
                        id: expense.categoryId,
                        fallbackName: expense.categoryName,
                        l10n: context.l10n,
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const Spacer(),
                Icon(
                  Iconsax.arrow_right_3,
                  size: 16,
                  color: context.colors.textSecondary,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
