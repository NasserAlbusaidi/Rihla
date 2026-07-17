import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

class SettlementIntro extends StatelessWidget {
  const SettlementIntro({
    super.key,
    required this.transferCount,
    required this.subjectName,
    required this.simplifyDebts,
  });

  final int transferCount;
  final String subjectName;

  /// #363: selects the mode-honest subtitle. Under OFF, "Optimized to reduce
  /// the number of payments" would be factually FALSE over a deliberately
  /// expanded fan-out — a FOUR-way branch across {mode × zero/nonzero}.
  final bool simplifyDebts;

  @override
  Widget build(BuildContext context) {
    final subtitle = transferCount == 0
        ? (simplifyDebts
              ? context.l10n.settleUpNoOptimizedPayments(subjectName)
              : context.l10n.settleUpNoDirectPayments(subjectName))
        : (simplifyDebts
              ? context.l10n.settleUpOptimizedPayments(subjectName)
              : context.l10n.settleUpDirectPayments(subjectName));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (transferCount > 0) ...[
          Text(
            context.l10n.settleUpTransfersHeadline(transferCount),
            style: AppTypography.displayOf(
              context,
              fontSize: 28,
              color: context.colors.textPrimary,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 10),
        ],
        Text(
          subtitle,
          style: AppTypography.sans(
            color: context.colors.textSecondary,
            fontSize: 13,
            height: 1.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
