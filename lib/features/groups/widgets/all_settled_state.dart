import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../keys/group_keys.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

/// Empty-state widget displayed when all balances are settled.
///
/// Shows a success circle icon with "All settled up" heading and supporting text.
/// Extracted from [GroupSettleUpScreen._buildAllSettledState] (Phase 36 Plan 01).
class AllSettledState extends StatelessWidget {
  const AllSettledState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(context.spacing.space16),
            decoration: BoxDecoration(
              color: context.colors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Iconsax.tick_circle,
              color: context.colors.success,
              size: 48,
            ),
          ),
          SizedBox(height: context.spacing.space16),
          Text(
            context.l10n.settleUpAllSettledTitle,
            key: GroupKeys.settleUpAllSettledMessage,
            style: AppTypography.sans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: context.spacing.space8),
          Text(
            context.l10n.settleUpAllSettledMessage,
            style: AppTypography.sans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
