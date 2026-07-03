import 'package:flutter/material.dart';

import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onActionTap,
    this.actionKey,
    this.color,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onActionTap;
  final Key? actionKey;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? context.colors.textSecondary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          title.toUpperCase(),
          style: AppTypography.caption(
            context,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: textColor,
            letterSpacing: 1.5,
          ),
        ),
        const Spacer(),
        if (actionLabel != null)
          GestureDetector(
            key: actionKey,
            onTap: onActionTap,
            behavior: HitTestBehavior.opaque,
            child: Text(
              actionLabel!,
              style: AppTypography.sans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.colors.primaryDark,
              ),
            ),
          ),
      ],
    );
  }
}
