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
          // baseline-aligned Row it would strand at the top when the
          // action's 44dp hit box (#1077) moves the shared baseline down —
          // the WidgetSpan gives it the title's own line metrics so it
          // stays centred on the label wherever the baseline sits.
          Padding(
            key: const Key('section_header_tick'),
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Text.rich(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
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
              style: AppTypography.caption(
                context,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
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
          const Spacer(),
          if (actionLabel != null)
            Semantics(
              button: true,
              label: actionLabel,
              onTap: onActionTap,
              excludeSemantics: true,
              child: GestureDetector(
                key: actionKey,
                onTap: onActionTap,
                behavior: HitTestBehavior.opaque,
                // #1077 §4: the opaque wrapper supplies the 44dp hit floor;
                // Center keeps the rendered link text compact so only the
                // invisible target grows.
                child: SizedBox(
                  height: 44,
                  child: Center(
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
                ),
              ),
            ),
        ],
      ),
    );
  }
}
