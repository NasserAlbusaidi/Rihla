import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

class ItemizedSectionHeader extends StatelessWidget {
  const ItemizedSectionHeader({
    super.key,
    required this.label,
    this.action,
    this.actionKey,
    this.onAction,
  });

  final String label;
  final String? action;
  final Key? actionKey;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.caption(
              context,
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
              color: colors.textSecondary,
            ),
          ),
        ),
        if (action != null)
          GestureDetector(
            key: actionKey,
            behavior: HitTestBehavior.opaque,
            onTap: onAction,
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: context.spacing.space4,
                horizontal: context.spacing.space4,
              ),
              child: Text(
                action!,
                style: AppTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryDark,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
