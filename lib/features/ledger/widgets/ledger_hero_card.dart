import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/animated_currency_text.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';

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
        16,
        16,
        16,
        8,
      ),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColorTokens.light.cardSurface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadowTokens.standard.raised,
        image: const DecorationImage(
          image: AssetImage('assets/textures/grain.png'),
          repeat: ImageRepeat.repeat,
          opacity: 0.035,
          fit: BoxFit.none,
          alignment: Alignment.topLeft,
        ),
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
                    Text(
                      'YOUR BALANCE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppColorTokens.light.textMuted,
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
                  Text(
                    'EVENT TOTAL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColorTokens.light.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$currency $formattedTotal',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColorTokens.light.textPrimary,
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
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColorTokens.light.textSecondary,
                ),
              ),
              Text(
                ' \u00b7 ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColorTokens.light.textSecondary,
                ),
              ),
              Text(
                '$settlementCount settlements',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColorTokens.light.textSecondary,
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
                  height: 52,
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
                  height: 52,
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
