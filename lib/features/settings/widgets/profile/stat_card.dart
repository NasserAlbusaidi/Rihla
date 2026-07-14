import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.statKey,
    required this.keyLabel,
    required this.sub,
    this.value,
    this.valueWidget,
  }) : assert(
         value != null || valueWidget != null,
         'Provide either value or valueWidget',
       );

  final Key statKey;
  final String keyLabel;
  final String sub;
  final String? value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: statKey,
      padding: EdgeInsets.fromLTRB(14, 14, context.spacing.space12, 14),
      // #807: flat card + hairline, not raised — these are static stats with
      // no onTap; the raised treatment is the app's actionable-surface cue
      // (docs/DESIGN.md flat-vs-raised split).
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.rule2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            keyLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption(
              context,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: valueWidget != null
                ? valueWidget!
                : Text(
                    value!,
                    maxLines: 1,
                    softWrap: false,
                    style: AppTypography.display(
                      fontSize: 28,
                      color: colors.textPrimary,
                      height: 1.0,
                    ),
                  ),
          ),
          SizedBox(height: context.spacing.space4),
          Text(
            sub,
            style: AppTypography.sans(
              fontSize: 11,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
