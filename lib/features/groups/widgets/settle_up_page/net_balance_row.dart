import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../shared/widgets/r_amount.dart';
import '../../../../shared/widgets/r_avatar.dart';
import '../../../ledger/models/expense_model.dart';

class NetBalanceRow extends StatelessWidget {
  const NetBalanceRow({
    super.key,
    required this.balance,
    required this.currency,
    required this.showDivider,
  });

  final UserBalance balance;
  final String currency;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final name = balance.displayName ?? context.l10n.settleUpUnknown;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: showDivider
              ? BorderSide(color: context.colors.rule)
              : BorderSide.none,
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: context.spacing.space16,
        vertical: context.spacing.space12,
      ),
      child: Row(
        children: [
          RAvatar(name: name, size: 28, colorKey: balance.participantId),
          SizedBox(width: context.spacing.space12),
          Expanded(
            child: Text(
              name,
              style: AppTypography.sans(
                color: context.colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          RAmount(
            value: balance.netBalance,
            currency: currency,
            size: 14,
            sign: true,
            weight: FontWeight
                .w700, // Spline ships 400/500/700 — w800 would synthesize
            tone: balance.netBalance > Decimal.zero
                ? AmountTone.sageText
                : balance.netBalance < Decimal.zero
                ? AmountTone.rustText
                : AmountTone.muted,
          ),
        ],
      ),
    );
  }
}
