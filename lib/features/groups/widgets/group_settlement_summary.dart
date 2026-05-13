import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../keys/group_keys.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// Summary chips displayed below the headline on Group Settle-Up.
///
/// Matches the wireframe: two pills — transfer count and total amount.
class GroupSettlementSummaryCard extends StatelessWidget {
  final Decimal totalPending;
  final String currency;
  final int transferCount;

  const GroupSettlementSummaryCard({
    super.key,
    required this.totalPending,
    required this.currency,
    required this.transferCount,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SettlementChip(
          key: GroupKeys.settleUpGroupTotalLabel,
          dotColor: context.colors.textPrimary,
          label: '$transferCount transfer${transferCount == 1 ? '' : 's'}',
        ),
        _SettlementChip(
          label:
              '${AppFormatters.formatCurrency(totalPending, currency)} total',
          monogram: currency.isNotEmpty ? currency[0] : r'$',
        ),
      ],
    );
  }
}

class _SettlementChip extends StatelessWidget {
  const _SettlementChip({
    super.key,
    required this.label,
    this.dotColor,
    this.monogram,
  });

  final String label;
  final Color? dotColor;
  final String? monogram;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.cardSoft,
        borderRadius: BorderRadius.circular(context.spacing.radiusSmall),
        border: Border.all(color: context.colors.rule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null)
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            )
          else if (monogram != null)
            Text(
              monogram!,
              style: TextStyle(
                color: context.colors.ink2,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: context.colors.ink2,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
