import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/utils/formatters.dart';
import '../models/expense_model.dart';
import '../../../core/theme/tokens/color_tokens.dart';

/// Collapsible section showing the 5 most recent expenses.
class RecentExpensesSection extends StatelessWidget {
  final List<Expense> expenses;
  final String currency;

  const RecentExpensesSection({
    super.key,
    required this.expenses,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final recentExpenses = expenses.take(5).toList();

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          'RECENT EXPENSES',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColorTokens.light.textMuted,
            letterSpacing: 1.0,
          ),
        ),
        trailing: Icon(
          Iconsax.arrow_down_1,
          size: 16,
          color: AppColorTokens.light.textMuted,
        ),
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColorTokens.light.cardSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColorTokens.light.border.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              children: recentExpenses.asMap().entries.map((entry) {
                final index = entry.key;
                final expense = entry.value;
                final isLast = index == recentExpenses.length - 1;
                return _buildExpenseItem(expense, !isLast);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseItem(Expense expense, bool showDivider) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColorTokens.light.scaffoldBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    expense.categoryIcon ?? '💰',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense.description ?? 'Expense',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColorTokens.light.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      expense.categoryName ?? 'General',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColorTokens.light.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                AppFormatters.formatCurrency(expense.amount, currency),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColorTokens.light.textPrimary,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: AppColorTokens.light.border),
      ],
    );
  }
}
