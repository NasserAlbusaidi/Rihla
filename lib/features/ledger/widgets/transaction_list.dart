import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../models/expense_model.dart';
import '../models/transaction_model.dart';

/// Transaction list showing recent expenses and settlements.
/// Displays empty state with CTA when no transactions exist.
class TransactionList extends StatelessWidget {
  final List<Transaction> transactions;
  final String? currentParticipantId;
  final String currency;
  final void Function(Expense expense) onEditExpense;
  final VoidCallback onAddExpense;

  const TransactionList({
    super.key,
    required this.transactions,
    required this.currency,
    required this.onEditExpense,
    required this.onAddExpense,
    this.currentParticipantId,
  });

  IconData _getCategoryIcon(String? iconName) {
    switch (iconName) {
      case 'gas':
        return Iconsax.gas_station;
      case 'food':
        return Iconsax.coffee;
      case 'gear':
        return Iconsax.bag_2;
      case 'lodging':
        return Iconsax.building;
      case 'transport':
        return Iconsax.car;
      default:
        return Iconsax.receipt;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const Text(
            'RECENT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: AppColors.textMuted,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          if (transactions.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(
                      Iconsax.wallet_3,
                      size: 32,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'No Expenses Yet',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add your first expense to start tracking\ncosts and splitting them with your group.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      HapticService.medium();
                      onAddExpense();
                    },
                    icon: const Icon(Iconsax.add, size: 18),
                    label: const Text('Add Expense'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ...transactions
                .take(15)
                .toList()
                .asMap()
                .entries
                .map(
                  (entry) => TransactionCard(
                    transaction: entry.value,
                    currency: currency,
                    currentParticipantId: currentParticipantId,
                    getCategoryIcon: _getCategoryIcon,
                    onEditExpense: onEditExpense,
                  )
                      .animate()
                      .fadeIn(
                        delay: Duration(milliseconds: (50 * entry.key).clamp(0, 500)),
                        duration: 300.ms,
                      )
                      .slideY(
                        begin: 0.05,
                        end: 0,
                        delay: Duration(milliseconds: (50 * entry.key).clamp(0, 500)),
                      ),
                ),
        ],
      ),
    );
  }
}

/// A single transaction card showing an expense or settlement.
class TransactionCard extends StatelessWidget {
  final Transaction transaction;
  final String currency;
  final String? currentParticipantId;
  final IconData Function(String? iconName) getCategoryIcon;
  final void Function(Expense expense) onEditExpense;

  const TransactionCard({
    super.key,
    required this.transaction,
    required this.currency,
    required this.getCategoryIcon,
    required this.onEditExpense,
    this.currentParticipantId,
  });

  @override
  Widget build(BuildContext context) {
    final isExpense = transaction.type == TransactionType.expense;
    final isSettlement = transaction.type == TransactionType.settlement;

    // For settlements: payer is "from", recipient is "to"
    // For expenses: payer is "paid by"
    final isPayer = transaction.payerId == currentParticipantId;

    Color iconColor;
    IconData iconData;
    String title;
    String subtitle;

    if (isSettlement) {
      iconColor = AppColors.success;
      iconData = Iconsax.money_send;
      title = 'Payment to ${transaction.settlement?.recipientName ?? "Member"}';
      subtitle = isPayer
          ? 'You paid'
          : 'Paid by ${transaction.settlement?.payerName ?? "Member"}';
    } else {
      // Expense
      iconColor = AppColors.primary;
      iconData = getCategoryIcon(transaction.expense?.categoryIcon);
      title = transaction.expense?.description ?? transaction.expense?.categoryName ?? 'Expense';
      subtitle = isPayer
          ? 'You paid full'
          : 'Paid by ${transaction.expense?.payerName ?? 'Member'}';
    }

    return GestureDetector(
      onTap: isExpense && transaction.expense != null
          ? () {
              HapticService.lightClick();
              onEditExpense(transaction.expense!);
            }
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSettlement
                ? AppColors.success.withValues(alpha: 0.3)
                : AppColors.borderLight,
            width: 1.5,
          ),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: isExpense &&
                      (transaction.expense?.receiptUrl != null ||
                          transaction.expense?.receiptPath != null)
                  ? Stack(
                      children: [
                        Icon(
                          iconData,
                          size: 24,
                          color: iconColor,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: AppColors.mint,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: const Icon(Iconsax.camera, size: 9, color: Colors.white),
                          ),
                        ),
                      ],
                    )
                  : Icon(
                      iconData,
                      size: 24,
                      color: iconColor,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              AppFormatters.formatCurrency(transaction.amount, currency),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: isSettlement ? AppColors.success : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
