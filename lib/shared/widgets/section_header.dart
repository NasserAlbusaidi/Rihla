import 'package:flutter/material.dart';

import '../../core/theme/tokens/domain_aliases.dart';
import '../../core/theme/tokens/typography_tokens.dart';

/// Small uppercase mono caption with optional action link, used to label
/// home/group sections ("ACTIVE JOURNEYS", "GROUPS", "RECENTLY").
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onActionTap,
    this.actionKey,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  /// Title text — will be rendered uppercase.
  final String title;

  /// Optional action link (e.g. "See all"). Renders in saffron-dark.
  final String? actionLabel;

  /// Tap handler for [actionLabel]. Required if [actionLabel] is set.
  final VoidCallback? onActionTap;

  /// Optional key attached to the action's tap target — lets tests find the
  /// action by key without also picking up the title text.
  final Key? actionKey;

  /// Surrounding padding. Default matches the wireframe's `0 20px` indent.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title.toUpperCase(),
            style: AppTypography.mono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
              letterSpacing: 1.2,
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
                  color: colors.primaryDark,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
