import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

/// #1149: pinned explanation banner for the departure-policy mirrors — the R6
/// frozen-expense notice and the roster-trap warning. Same visual language as
/// `SettleScopeNote` (bordered soft card, info icon, secondary text).
class DeparturePolicyNote extends StatelessWidget {
  const DeparturePolicyNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: spacing.space20,
        end: spacing.space20,
        top: spacing.space12,
      ),
      child: Container(
        padding: EdgeInsets.all(spacing.space12),
        decoration: BoxDecoration(
          color: colors.cardSoft,
          borderRadius: BorderRadius.circular(spacing.radiusCard),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Iconsax.info_circle, size: 18, color: colors.primary),
            SizedBox(width: spacing.space12),
            Expanded(
              child: Text(
                text,
                style: AppTypography.sans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
