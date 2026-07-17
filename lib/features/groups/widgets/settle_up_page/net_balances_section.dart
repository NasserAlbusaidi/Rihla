import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../ledger/models/expense_model.dart';
import 'net_balance_row.dart';
import 'section_label.dart';

class NetBalancesSection extends StatelessWidget {
  const NetBalancesSection({
    super.key,
    required this.balances,
    required this.currency,
  });

  final List<UserBalance> balances;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label: context.l10n.settleUpEachPersonNet),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: context.colors.cardSurface,
            borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
            border: Border.all(color: context.colors.rule),
            boxShadow: context.shadows.raised,
          ),
          child: Column(
            children: [
              for (var i = 0; i < balances.length; i++)
                NetBalanceRow(
                  balance: balances[i],
                  currency: currency,
                  showDivider: i < balances.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
