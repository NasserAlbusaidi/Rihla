import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/utils/bidi.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../shared/widgets/directional_icon.dart';
import '../settle_up_page_body.dart';

/// One-gesture "settle all with X" card (#382 PR-5 D2). Shown above the bucket
/// sections for each counterparty owing across ≥2 currency buckets; tapping it
/// drives the per-bucket stepped walk. The caption joins each step's
/// code-first amount so the user sees exactly what the walk will record before
/// they start.
class SteppedSettleCard extends StatelessWidget {
  const SteppedSettleCard({
    super.key,
    required this.otherName,
    required this.steps,
    required this.onTap,
  });

  final String otherName;
  final List<SettleStepRequest> steps;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final amounts = steps
        .map((s) => AppFormatters.formatCurrency(s.suggestedAmount, s.currency))
        .join(' · ');

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
          child: Ink(
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
              border: Border.all(color: context.colors.primary),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: context.spacing.space16,
              vertical: context.spacing.space12,
            ),
            child: Row(
              children: [
                Icon(Iconsax.cards, size: 18, color: context.colors.primary),
                SizedBox(width: context.spacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.settleUpSettleAllWith(
                          bidiIsolate(otherName),
                        ),
                        style: AppTypography.sans(
                          color: context.colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text:
                                  '${context.l10n.settleUpSettleAllWithCount(steps.length)} · ',
                              style: AppTypography.sans(
                                color: context.colors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: amounts,
                              style: AppTypography.mono(
                                fontSize: 12,
                                color: context.colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: context.spacing.space8),
                DirectionalIcon(
                  Iconsax.arrow_right_3,
                  size: 16,
                  color: context.colors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
