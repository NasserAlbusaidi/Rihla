import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

class IdentityChip extends StatelessWidget {
  const IdentityChip({
    super.key,
    required this.leadingIcon,
    required this.label,
    required this.onTap,
  });
  final IconData leadingIcon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space12,
          vertical: 7,
        ),
        decoration: BoxDecoration(
          color: colors.cardSoft,
          borderRadius: BorderRadius.circular(context.spacing.radiusPill),
          border: Border.all(color: colors.rule, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(leadingIcon, size: 12, color: colors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.sans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
