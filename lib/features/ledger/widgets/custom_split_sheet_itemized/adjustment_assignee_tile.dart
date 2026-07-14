import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../shared/widgets/r_avatar.dart';
import '../custom_split_sheet.dart';

/// One member row in the assigned-discount picker (#605): checkbox + avatar +
/// name, mirroring the item-assignee tile pattern. Toggles the draft subset.
class AdjustmentAssigneeTile extends StatelessWidget {
  const AdjustmentAssigneeTile({
    super.key,
    required this.participant,
    required this.selected,
    required this.onTap,
  });

  final SplitParticipant participant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return InkWell(
      key: Key('adjustment_assign_tile_${participant.id}'),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.space24,
          vertical: spacing.space8,
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_box : Icons.check_box_outline_blank,
              color: selected ? colors.primary : colors.textSecondary,
              size: 22,
            ),
            SizedBox(width: spacing.space12),
            RAvatar(name: participant.name, size: 32, colorKey: participant.id),
            SizedBox(width: spacing.space12),
            Expanded(
              child: Text(
                participant.name,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
