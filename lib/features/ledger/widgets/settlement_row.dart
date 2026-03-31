import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/utils/formatters.dart';
import '../models/settlement_model.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';

/// Inline settlement entry for the Ledger timeline.
///
/// Displays a teal checkmark, payer → recipient, amount, and relative date.
/// Has a 3dp teal left accent bar to distinguish settlements from expenses.
///
/// Per D-05.
class SettlementRow extends StatelessWidget {
  final Settlement settlement;
  final String currency;

  const SettlementRow({
    super.key,
    required this.settlement,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final config = AppFormatters.currencyConfig[currency];
    final decimals = config?.decimals ?? 3;
    final amountStr = settlement.amount.toStringAsFixed(decimals);
    final dateStr = AppFormatters.formatRelativeDate(settlement.settledAt);
    final payerLabel = settlement.payerName ?? 'Unknown';
    final recipientLabel = settlement.recipientName ?? 'Unknown';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColorTokens.light.cardSurface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadowTokens.standard.raised,
        border: Border(
          left: BorderSide(color: AppColorTokens.light.moduleLedger, width: 3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Iconsax.tick_circle,
            color: AppColorTokens.light.moduleLedger,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$payerLabel \u2192 $recipientLabel',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColorTokens.light.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '$currency $amountStr',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: AppColorTokens.light.successText,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppColorTokens.light.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
