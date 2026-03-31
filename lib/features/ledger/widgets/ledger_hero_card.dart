import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/animated_currency_text.dart';

/// Balance hero card for the Ledger screen.
///
/// Displays the current user's net balance (color-coded), the event total,
/// expense/settlement counts, and two CTAs (Add Expense / Settle Up).
///
/// Per D-03, D-06, D-11: balance is green (successText) when owed, red
/// (errorText) when owing, gray (textSecondary) when settled.
class LedgerHeroCard extends StatelessWidget {
  final Decimal netBalance;
  final Decimal eventTotal;
  final int expenseCount;
  final int settlementCount;
  final String currency;
  final VoidCallback onAddExpense;
  final VoidCallback onSettleUp;

  const LedgerHeroCard({
    super.key,
    required this.netBalance,
    required this.eventTotal,
    required this.expenseCount,
    required this.settlementCount,
    required this.currency,
    required this.onAddExpense,
    required this.onSettleUp,
  });

  @override
  Widget build(BuildContext context) {
    final config = AppFormatters.currencyConfig[currency];
    final decimals = config?.decimals ?? 3;
    final formattedTotal = eventTotal.toStringAsFixed(decimals);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppColors.space16,
        AppColors.space16,
        AppColors.space16,
        AppColors.space8,
      ),
      padding: const EdgeInsets.all(AppColors.space20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: YOUR BALANCE + EVENT TOTAL
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'YOUR BALANCE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedCurrencyText(
                      value: netBalance,
                      currency: currency,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'EVENT TOTAL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$currency $formattedTotal',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Row 2: expense + settlement counts
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '$expenseCount expenses',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
              ),
              const Text(
                ' \u00b7 ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '$settlementCount settlements',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),

          // Row 3: CTA buttons
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: AppColors.buttonHeight,
                  child: ElevatedButton.icon(
                    onPressed: onAddExpense,
                    icon: const Icon(Iconsax.add, size: 18),
                    label: const Text('Add Expense'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: AppColors.buttonHeight,
                  child: OutlinedButton.icon(
                    onPressed: onSettleUp,
                    icon: const Icon(Iconsax.money_send, size: 18),
                    label: const Text('Settle Up'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
