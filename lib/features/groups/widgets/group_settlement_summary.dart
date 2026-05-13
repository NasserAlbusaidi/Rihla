import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../keys/group_keys.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// Summary card displayed at the top of the Group Settle-Up screen.
///
/// Shows total pending amount across all events in the group.
class GroupSettlementSummaryCard extends StatelessWidget {
  final Decimal totalPending;
  final String currency;
  final int eventCount;
  final int transferCount;

  const GroupSettlementSummaryCard({
    super.key,
    required this.totalPending,
    required this.currency,
    required this.eventCount,
    this.transferCount = 0,
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
        _SettlementChip(
          label: '$eventCount event${eventCount == 1 ? '' : 's'}',
          dotColor: context.colors.primary,
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
