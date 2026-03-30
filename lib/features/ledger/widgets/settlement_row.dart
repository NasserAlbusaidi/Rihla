import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../models/settlement_model.dart';

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
      padding: const EdgeInsets.all(AppColors.space16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppColors.cardShadow,
        border: const Border(
          left: BorderSide(color: AppColors.moduleLedger, width: 3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Iconsax.tick_circle,
            color: AppColors.moduleLedger,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$payerLabel \u2192 $recipientLabel',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '$currency $amountStr',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: AppColors.successText,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textMuted,
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
