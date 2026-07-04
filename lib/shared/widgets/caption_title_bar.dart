import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/services/haptic_service.dart';
import '../../core/theme/tokens/domain_aliases.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import 'directional_icon.dart';

/// Journal-style top bar — small caps caption above an italic display title,
/// with an optional back affordance.
///
/// Layout lifted verbatim from `_TopBar` in `activity_feed_screen.dart`.
/// When [onBack] is null, the back button is omitted entirely (no reserved
/// 44dp gap beyond the bar's natural padding).
class CaptionTitleBar extends StatelessWidget {
  const CaptionTitleBar({
    super.key,
    required this.caption,
    required this.title,
    this.onBack,
    this.backKey,
    this.titleKey,
  });

  final String caption;
  final String title;
  final VoidCallback? onBack;
  final Key? backKey;
  final Key? titleKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onBack != null)
            InkResponse(
              key: backKey,
              onTap: () {
                HapticService.lightClick();
                onBack!();
              },
              radius: 24,
              child: SizedBox(
                width: 44,
                height: 44,
                child: DirectionalIcon(
                  Iconsax.arrow_left,
                  size: 20,
                  color: colors.textPrimary,
                ),
              ),
            ),
          SizedBox(width: context.spacing.space4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    caption,
                    style: AppTypography.caption(
                      context,
                      fontSize: 10,
                      color: colors.textSecondary,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    key: titleKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.displayOf(
                      context,
                      fontSize: 22,
                      color: colors.textPrimary,
                      letterSpacing: -0.3,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
