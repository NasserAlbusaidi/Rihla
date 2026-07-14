import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../keys/home_keys.dart';

/// Small saffron-tint pill beside the avatar prompting a first-run name
/// (#818 Wave 4.1). Rendered only while [HomeScreen]'s deviceName is empty.
class SetNameChip extends StatelessWidget {
  const SetNameChip({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      key: HomeKeys.setNameChip,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(10, 4, 10, 4),
        decoration: BoxDecoration(
          color: colors.selectionFill,
          borderRadius: BorderRadius.circular(context.spacing.radiusPill),
          border: Border.all(color: colors.saffronSoft),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Iconsax.edit_2, size: 13, color: colors.primary),
            SizedBox(width: context.spacing.space4),
            Flexible(
              child: Text(
                context.l10n.homeSetNameChip,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.sans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
