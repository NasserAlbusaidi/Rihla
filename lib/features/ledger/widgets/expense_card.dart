import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../models/expense_model.dart';

/// Three-line expense card for the Ledger timeline.
///
/// Line 1: category icon + title + amount (right-aligned)
/// Line 2: payer · date · N people
/// Line 3: color-coded balance status (owed/owes/settled)
///
/// Per D-01, D-02, D-07.
class ExpenseCard extends StatelessWidget {
  final Expense expense;

  /// Positive = owed to user, negative = user owes, zero = settled.
  final Decimal userBalance;
  final String currency;
  final VoidCallback onTap;

  const ExpenseCard({
    super.key,
    required this.expense,
    required this.userBalance,
    required this.currency,
    required this.onTap,
  });

  IconData _categoryIcon(String? category) {
    return switch (category?.toLowerCase()) {
      'food' || 'food & drink' => Iconsax.coffee,
      'transport' || 'transportation' => Iconsax.car,
      'accommodation' || 'hotel' => Iconsax.house,
      'entertainment' => Iconsax.game,
      'shopping' => Iconsax.shopping_bag,
      _ => Iconsax.receipt_item,
    };
  }

  (String, Color) get _balanceStatus {
    final config = AppFormatters.currencyConfig[currency];
    final decimals = config?.decimals ?? 3;
    final absStr = userBalance.abs().toStringAsFixed(decimals);
    final cmp = userBalance.compareTo(Decimal.zero);
    return switch (cmp) {
      > 0 => ('Owed to you $currency $absStr', AppColors.successText),
      < 0 => ('You owe $currency $absStr', AppColors.errorText),
      _ => ('Settled', AppColors.textSecondary),
    };
  }

  @override
  Widget build(BuildContext context) {
    final config = AppFormatters.currencyConfig[currency];
    final decimals = config?.decimals ?? 3;
    final amountStr = expense.amount.toStringAsFixed(decimals);
    final dateStr = AppFormatters.formatRelativeDate(expense.createdAt);
    final payerLabel = expense.payerName ?? 'Unknown';

    // Participant count: customSplitParticipants if custom scope, else 0 means global
    final participantCount = expense.customSplitParticipants?.length ?? 0;
    final peopleStr = participantCount > 0 ? '$participantCount people' : 'group';

    final (statusText, statusColor) = _balanceStatus;
    final icon = _categoryIcon(expense.categoryName);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(AppColors.space16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Line 1: icon + title + amount
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    expense.description ?? 'Expense',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$currency $amountStr',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),

            // Line 2: payer · date · N people
            const SizedBox(height: 4),
            Text(
              '$payerLabel \u00b7 $dateStr \u00b7 $peopleStr',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),

            // Line 3: balance status
            const SizedBox(height: 4),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: statusColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
