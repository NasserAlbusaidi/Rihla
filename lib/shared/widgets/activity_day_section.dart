import 'package:flutter/material.dart';

import '../../core/theme/tokens/domain_aliases.dart';
import '../../core/theme/tokens/typography_tokens.dart';

/// A day-grouped card of activity rows — `TODAY · JUL 4` hairline header
/// above a card-wrapped column of children.
///
/// [raised] toggles between two elevation treatments (`docs/DESIGN.md`
/// flat-vs-raised split): actionable rows use the shadowed, borderless card
/// ([raised] true, the default); inert rows use a flat bordered card.
class ActivityDaySection extends StatelessWidget {
  const ActivityDaySection({
    super.key,
    required this.label,
    this.dateSuffix,
    required this.children,
    this.raised = true,
  });

  final String label;
  final String? dateSuffix;
  final List<Widget> children;
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final labelStyle = AppTypography.caption(
      context,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: colors.textSecondary,
      letterSpacing: 2,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label.toUpperCase(), style: labelStyle),
            if (dateSuffix != null)
              Text(' · ${dateSuffix!.toUpperCase()}', style: labelStyle),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 0.5, color: colors.rule2)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(context.spacing.radiusCard),
            boxShadow: raised ? context.shadows.raised : null,
            border: raised ? null : Border.all(color: colors.rule2),
          ),
          padding: EdgeInsets.symmetric(horizontal: context.spacing.space16),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}
