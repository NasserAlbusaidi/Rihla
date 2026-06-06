import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/formatters.dart';
import '../keys/group_keys.dart';

/// Total-amount pill displayed below the headline on Group Settle-Up.
///
/// The transfer count is intentionally NOT shown here — the `_SettlementIntro`
/// headline already states it ("3 transfers, everyone's even"), so a second
/// count pill was redundant (#158). Only the total survives.
class GroupSettlementSummaryCard extends StatelessWidget {
  final Decimal totalPending;
  final String currency;

  const GroupSettlementSummaryCard({
    super.key,
    required this.totalPending,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SettlementChip(
          key: GroupKeys.settleUpGroupTotalLabel,
          label: context.l10n.settleUpSummaryTotal(
            AppFormatters.formatCurrency(totalPending, currency),
          ),
          icon: Iconsax.wallet_3,
        ),
      ],
    );
  }
}

class _SettlementChip extends StatelessWidget {
  const _SettlementChip({
    super.key,
    required this.label,
    this.icon,
  });

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space12, vertical: context.spacing.space8),
      decoration: BoxDecoration(
        color: context.colors.cardSoft,
        borderRadius: BorderRadius.circular(context.spacing.radiusSmall),
        border: Border.all(color: context.colors.rule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(
              icon,
              size: 12,
              color: context.colors.ink2,
            ),
          SizedBox(width: context.spacing.space8),
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
