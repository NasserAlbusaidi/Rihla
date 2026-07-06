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

  /// False when the write is queued offline (#412) — the badge then reads
  /// "Saved — will sync" instead of claiming a cloud sync that hasn't happened.
  final bool synced;

  const ExpenseSuccessDialog({
    super.key,
    required this.expense,
    required this.currency,
    required this.onDone,
    required this.onAddAnother,
    this.synced = true,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.colors.scaffoldBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(context.spacing.space24),
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

              SizedBox(height: context.spacing.space16),

              Text(
                context.l10n.expenseSuccessTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),

              SizedBox(height: context.spacing.space4),

              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: context.spacing.space12,
                  vertical: context.spacing.space4,
                ),
                decoration: BoxDecoration(
                  color: context.colors.inputFill,
                  borderRadius: BorderRadius.circular(
                    context.spacing.radiusCard,
                  ),
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
                      synced
                          ? context.l10n.expenseSuccessSyncedToCloud
                          : context.l10n.expenseSuccessWillSync,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: context.spacing.space24),

              // Summary Card
              _ExpenseSummaryCard(expense: expense, currency: currency),

              SizedBox(height: context.spacing.space24),

              // Done Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: onDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.primary,
                    foregroundColor: context.colors.textOnPrimary,
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

              SizedBox(height: context.spacing.space12),

              // Add Another
              TextButton(
                onPressed: onAddAnother,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Iconsax.add, size: 18),
                    SizedBox(width: context.spacing.space8),
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
      padding: EdgeInsets.all(context.spacing.space20),
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
          SizedBox(height: context.spacing.space4),
          Text(
            AppFormatters.formatCurrency(expense.amount, currency),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: context.spacing.space16),

          // Category row
          if (expense.categoryId != null || expense.categoryName != null)
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(context.spacing.space8),
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
                SizedBox(width: context.spacing.space12),
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
              ],
            ),
        ],
      ),
    );
  }
}
