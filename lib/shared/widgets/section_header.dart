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
          // Leading share-notch tick — brass diamond, the ambient Falaj
          // fork cousin (spec: the only unlimited-use form of the fork).
          // Row order alone puts it on the leading edge under RTL; the
          // diamond is point-symmetric so it never needs a mirror. A
          // rotated Container has no text baseline, so in this
          // baseline-aligned Row it would otherwise sit low against the
          // mono label's cap-height — the bottom nudge below re-centers it.
          Padding(
            key: const Key('section_header_tick'),
            padding: const EdgeInsetsDirectional.only(end: 8, bottom: 2),
            child: Transform.rotate(
              angle: 0.785398, // pi/4
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
          Flexible(
            fit: FlexFit.tight,
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption(
                context,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
          ),
          if (actionLabel != null)
            GestureDetector(
              key: actionKey,
              onTap: onActionTap,
              behavior: HitTestBehavior.opaque,
              child: Text(
                actionLabel!,
                maxLines: 1,
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
